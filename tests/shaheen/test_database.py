"""
Tests for app/database.py — SQLite fallback, schema init, health, insert helper.
"""

from __future__ import annotations

import os
import importlib

import pytest
from sqlalchemy import text


@pytest.fixture()
def fresh_db(tmp_path, monkeypatch):
    """
    Provide a fresh SQLite database for each test by pointing
    SHAHEEN_YS_DATABASE_PATH at a temp directory and reloading the module.
    DATABASE_URL is already cleared by conftest.
    """
    db_path = str(tmp_path / "test.db")
    monkeypatch.setenv("SHAHEEN_YS_DATABASE_PATH", db_path)
    monkeypatch.delenv("DATABASE_URL", raising=False)

    # Force module reload so the new env vars take effect
    import app.database as db_module
    importlib.reload(db_module)

    db_module.initialize_database()
    yield db_module

    # Reload back to a clean state after the test
    importlib.reload(db_module)


class TestDatabaseBackendSelection:
    def test_sqlite_fallback_when_no_database_url(self, fresh_db):
        assert fresh_db.DB_BACKEND == "sqlite"
        assert fresh_db.IS_POSTGRES is False

    def test_postgresql_backend_selected_when_url_set(self, monkeypatch):
        """Only verify URL normalization — no actual PG connection."""
        import app.database as db_module

        # Call the resolver directly without a real PG server
        monkeypatch.setenv("DATABASE_URL", "postgres://user:pass@localhost/mydb")
        url, backend = db_module._resolve_database_url()
        assert backend == "postgresql"
        assert url.startswith("postgresql://"), "postgres:// must be normalised"

    def test_postgresql_plus_dialect_preserved(self, monkeypatch):
        import app.database as db_module

        monkeypatch.setenv("DATABASE_URL", "postgresql+psycopg://user:pass@host/db")
        url, backend = db_module._resolve_database_url()
        assert backend == "postgresql"
        # Should NOT double-prefix
        assert url.startswith("postgresql+psycopg://")

    def test_postgres_url_normalised(self, monkeypatch):
        import app.database as db_module

        monkeypatch.setenv("DATABASE_URL", "postgres://u:p@localhost:5432/testdb")
        url, backend = db_module._resolve_database_url()
        assert url == "postgresql://u:p@localhost:5432/testdb"


class TestSchemaInitialization:
    def test_all_tables_created(self, fresh_db):
        with fresh_db.database_connection() as conn:
            for table in ("users", "api_keys", "sessions", "system_events", "compute_instances"):
                result = conn.execute(
                    text(f"SELECT name FROM sqlite_master WHERE type='table' AND name='{table}'")
                ).fetchone()
                assert result is not None, f"Table '{table}' was not created"

    def test_idempotent_initialization(self, fresh_db):
        """Running initialize_database twice should not raise."""
        fresh_db.initialize_database()
        fresh_db.initialize_database()


class TestDatabaseConnection:
    def test_basic_query(self, fresh_db):
        with fresh_db.database_connection() as conn:
            result = conn.execute(text("SELECT 1")).fetchone()
        assert result[0] == 1

    def test_rollback_on_exception(self, fresh_db):
        """Connection rolls back on exception without propagating DB state."""
        try:
            with fresh_db.database_connection() as conn:
                conn.execute(
                    text("INSERT INTO users (username) VALUES (:u)"),
                    {"u": "rollback_test"},
                )
                raise RuntimeError("intentional failure")
        except RuntimeError:
            pass

        # Row must not persist after rollback
        with fresh_db.database_connection() as conn:
            row = conn.execute(
                text("SELECT id FROM users WHERE username = :u"),
                {"u": "rollback_test"},
            ).fetchone()
        assert row is None


class TestInsertAndGetId:
    def test_returns_integer_id(self, fresh_db):
        with fresh_db.database_connection() as conn:
            row_id = fresh_db.insert_and_get_id(
                conn,
                "INSERT INTO users (username) VALUES (:username)",
                {"username": "testuser"},
            )
        assert isinstance(row_id, int)
        assert row_id > 0


class TestDatabaseHealth:
    def test_healthy_when_db_accessible(self, fresh_db):
        result = fresh_db.check_database_health()
        assert result["status"] == "healthy"
        assert result["database"] == "connected"
        assert result["backend"] == "sqlite"

    def test_backend_key_present(self, fresh_db):
        result = fresh_db.check_database_health()
        assert "backend" in result


class TestSQLiteDevFallback:
    def test_sqlite_path_used_when_no_database_url(self, fresh_db):
        """DATABASE_PATH must point to a real file (SQLite dev fallback)."""
        from pathlib import Path
        path = Path(fresh_db.DATABASE_PATH)
        # File might not exist until first write, but parent must exist
        assert path.parent.exists()
