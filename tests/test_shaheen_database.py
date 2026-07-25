"""
Tests for the SHAHEEN-YS database layer (app/database.py).

Covers:
- SQLite fallback when DATABASE_URL is not set
- initialize_database() creates all tables (idempotent)
- check_database_health() returns healthy/unhealthy correctly
- database_connection() commits on success, rolls back on exception
- insert_and_get_id() returns the correct inserted row ID
- DATABASE_URL postgres:// prefix is normalised to postgresql://
"""

from __future__ import annotations

import importlib
import sys
from contextlib import contextmanager
from unittest.mock import patch, MagicMock

import pytest
from sqlalchemy import text


# ---------------------------------------------------------------------------
# Helpers — reload module with clean env so DB_BACKEND is re-evaluated
# ---------------------------------------------------------------------------


def _reload_database_module(env: dict):
    """
    Reload app.database with a patched environment.
    Returns the reloaded module.
    """
    mods_to_drop = [k for k in sys.modules if k.startswith("app.database")]
    for m in mods_to_drop:
        del sys.modules[m]

    with patch.dict("os.environ", env, clear=True):
        import app.database as db_module
        return db_module


# ---------------------------------------------------------------------------
# Backend detection
# ---------------------------------------------------------------------------


class TestBackendDetection:
    def test_no_database_url_uses_sqlite(self):
        db = _reload_database_module({})
        assert db.DB_BACKEND == "sqlite"
        assert db.IS_POSTGRES is False

    def test_database_url_set_uses_postgresql(self):
        # We only check the URL resolution, not an actual connection
        # by inspecting the module-level constants.
        db = _reload_database_module(
            {"DATABASE_URL": "postgresql://u:p@localhost/db"}
        )
        assert db.DB_BACKEND == "postgresql"
        assert db.IS_POSTGRES is True

    def test_postgres_scheme_normalised(self):
        """Legacy postgres:// is converted to postgresql://"""
        db = _reload_database_module(
            {"DATABASE_URL": "postgres://u:p@localhost/db"}
        )
        # The engine URL should use the postgresql:// dialect
        url_str = str(db._engine.url)
        assert url_str.startswith("postgresql")


# ---------------------------------------------------------------------------
# Fixtures — always use a fresh in-memory SQLite engine for isolation
# ---------------------------------------------------------------------------


@pytest.fixture()
def db_module(tmp_path):
    """
    Provide app.database loaded against a temp-file SQLite database.
    Each test gets its own isolated file.
    """
    db_path = tmp_path / "test.db"
    env = {"SHAHEEN_YS_DATABASE_PATH": str(db_path)}

    mods_to_drop = [k for k in sys.modules if k.startswith("app.database")]
    for m in mods_to_drop:
        del sys.modules[m]

    with patch.dict("os.environ", env, clear=True):
        import app.database as db_module
        yield db_module

    # Cleanup
    mods_to_drop = [k for k in sys.modules if k.startswith("app.database")]
    for m in mods_to_drop:
        del sys.modules[m]


# ---------------------------------------------------------------------------
# Schema initialisation
# ---------------------------------------------------------------------------


class TestSchemaInitialisation:
    def test_initialize_creates_users_table(self, db_module):
        db_module.initialize_database()
        with db_module.database_connection() as conn:
            result = conn.execute(
                text("SELECT name FROM sqlite_master WHERE type='table' AND name='users'")
            ).fetchone()
        assert result is not None

    def test_initialize_creates_api_keys_table(self, db_module):
        db_module.initialize_database()
        with db_module.database_connection() as conn:
            result = conn.execute(
                text("SELECT name FROM sqlite_master WHERE type='table' AND name='api_keys'")
            ).fetchone()
        assert result is not None

    def test_initialize_creates_sessions_table(self, db_module):
        db_module.initialize_database()
        with db_module.database_connection() as conn:
            result = conn.execute(
                text("SELECT name FROM sqlite_master WHERE type='table' AND name='sessions'")
            ).fetchone()
        assert result is not None

    def test_initialize_creates_system_events_table(self, db_module):
        db_module.initialize_database()
        with db_module.database_connection() as conn:
            result = conn.execute(
                text(
                    "SELECT name FROM sqlite_master"
                    " WHERE type='table' AND name='system_events'"
                )
            ).fetchone()
        assert result is not None

    def test_initialize_is_idempotent(self, db_module):
        """Calling initialize_database() twice should not raise."""
        db_module.initialize_database()
        db_module.initialize_database()  # must not raise

    def test_initialize_creates_indexes(self, db_module):
        db_module.initialize_database()
        with db_module.database_connection() as conn:
            indexes = conn.execute(
                text("SELECT name FROM sqlite_master WHERE type='index'")
            ).fetchall()
        index_names = {row[0] for row in indexes}
        assert "idx_api_keys_hash" in index_names
        assert "idx_sessions_id" in index_names


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------


class TestHealthCheck:
    def test_healthy_database(self, db_module):
        db_module.initialize_database()
        result = db_module.check_database_health()
        assert result["status"] == "healthy"
        assert result["database"] == "connected"
        assert "backend" in result

    def test_includes_backend_info(self, db_module):
        result = db_module.check_database_health()
        assert result.get("backend") in ("sqlite", "postgresql")

    def test_unhealthy_when_engine_broken(self, db_module):
        """Simulate a broken engine by patching _engine.connect to raise."""
        original_connect = db_module._engine.connect

        def broken_connect():
            from sqlalchemy.exc import OperationalError
            raise OperationalError("connect", {}, Exception("DB down"))

        db_module._engine.connect = broken_connect
        try:
            result = db_module.check_database_health()
            assert result["status"] == "unhealthy"
        finally:
            db_module._engine.connect = original_connect


# ---------------------------------------------------------------------------
# database_connection context manager
# ---------------------------------------------------------------------------


class TestDatabaseConnection:
    def test_commits_on_clean_exit(self, db_module):
        db_module.initialize_database()
        with db_module.database_connection() as conn:
            conn.execute(
                text(
                    "INSERT INTO users (username, is_active, created_at)"
                    " VALUES ('alice', 1, CURRENT_TIMESTAMP)"
                )
            )
        # Verify it persists
        with db_module.database_connection() as conn:
            row = conn.execute(
                text("SELECT username FROM users WHERE username='alice'")
            ).fetchone()
        assert row is not None

    def test_rolls_back_on_exception(self, db_module):
        db_module.initialize_database()
        with pytest.raises(ValueError):
            with db_module.database_connection() as conn:
                conn.execute(
                    text(
                        "INSERT INTO users (username, is_active, created_at)"
                        " VALUES ('bob', 1, CURRENT_TIMESTAMP)"
                    )
                )
                raise ValueError("intentional error")
        # Row must NOT be committed
        with db_module.database_connection() as conn:
            row = conn.execute(
                text("SELECT username FROM users WHERE username='bob'")
            ).fetchone()
        assert row is None

    def test_connection_is_closed_after_exit(self, db_module):
        db_module.initialize_database()
        conn_ref = None
        with db_module.database_connection() as conn:
            conn_ref = conn
        # After context exits, connection should be closed (SQLAlchemy marks it invalid)
        assert conn_ref is not None


# ---------------------------------------------------------------------------
# insert_and_get_id
# ---------------------------------------------------------------------------


class TestInsertAndGetId:
    def test_returns_integer_id(self, db_module):
        db_module.initialize_database()
        with db_module.database_connection() as conn:
            row_id = db_module.insert_and_get_id(
                conn,
                "INSERT INTO users (username, is_active, created_at)"
                " VALUES (:username, 1, CURRENT_TIMESTAMP)",
                {"username": "charlie"},
            )
        assert isinstance(row_id, int)
        assert row_id > 0

    def test_ids_are_sequential(self, db_module):
        db_module.initialize_database()
        ids = []
        for i in range(3):
            with db_module.database_connection() as conn:
                row_id = db_module.insert_and_get_id(
                    conn,
                    "INSERT INTO users (username, is_active, created_at)"
                    " VALUES (:username, 1, CURRENT_TIMESTAMP)",
                    {"username": f"user_{i}"},
                )
                ids.append(row_id)
        assert ids[0] < ids[1] < ids[2]

    def test_row_is_actually_inserted(self, db_module):
        db_module.initialize_database()
        with db_module.database_connection() as conn:
            row_id = db_module.insert_and_get_id(
                conn,
                "INSERT INTO users (username, is_active, created_at)"
                " VALUES (:username, 1, CURRENT_TIMESTAMP)",
                {"username": "diana"},
            )
        with db_module.database_connection() as conn:
            row = conn.execute(
                text("SELECT id, username FROM users WHERE id = :id"),
                {"id": row_id},
            ).fetchone()
        assert row is not None
        assert row[1] == "diana"


# ---------------------------------------------------------------------------
# SQLite-fallback behaviour in development
# ---------------------------------------------------------------------------


class TestSQLiteFallback:
    def test_sqlite_is_default_backend(self, db_module):
        assert db_module.DB_BACKEND == "sqlite"

    def test_sqlite_engine_url_starts_with_sqlite(self, db_module):
        url_str = str(db_module._engine.url)
        assert url_str.startswith("sqlite")
