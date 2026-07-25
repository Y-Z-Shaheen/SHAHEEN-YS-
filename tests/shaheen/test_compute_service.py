"""
Tests for app/compute/service.py — uses SQLAlchemy layer, not raw sqlite3.
"""

from __future__ import annotations

import importlib
import os

import pytest


@pytest.fixture(autouse=True)
def fresh_compute_db(tmp_path, monkeypatch):
    """
    Reset DB and compute service modules for each test with a fresh SQLite DB.
    """
    db_path = str(tmp_path / "compute_test.db")
    monkeypatch.setenv("SHAHEEN_YS_DATABASE_PATH", db_path)
    monkeypatch.delenv("DATABASE_URL", raising=False)

    import app.database as db_mod
    importlib.reload(db_mod)
    db_mod.initialize_database()

    import app.compute.service as svc_mod
    importlib.reload(svc_mod)

    yield svc_mod


class TestComputeServiceHealth:
    def test_healthy_after_init(self, fresh_compute_db):
        result = fresh_compute_db.get_compute_health()
        assert result["status"] == "healthy"
        assert result["service"] == "compute"

    def test_uses_sqlalchemy_not_sqlite3(self, fresh_compute_db):
        """Verify the module does NOT import sqlite3 directly."""
        import inspect
        import app.compute.service as svc_mod
        source = inspect.getsource(svc_mod)
        assert "import sqlite3" not in source
        assert "sqlite3.connect" not in source


class TestListInstances:
    def test_empty_list_initially(self, fresh_compute_db):
        result = fresh_compute_db.list_instances()
        assert result == []

    def test_returns_created_instance(self, fresh_compute_db):
        fresh_compute_db.create_instance("web-1", "nginx:latest", 2, 512)
        instances = fresh_compute_db.list_instances()
        assert len(instances) == 1
        assert instances[0]["name"] == "web-1"


class TestCreateInstance:
    def test_creates_and_returns_instance(self, fresh_compute_db):
        inst = fresh_compute_db.create_instance("db-1", "postgres:15", 4, 2048)
        assert inst["name"] == "db-1"
        assert inst["image"] == "postgres:15"
        assert inst["cpu"] == 4
        assert inst["memory_mb"] == 2048
        assert inst["status"] == "created"
        assert inst["id"].startswith("shaheen-")

    def test_id_is_unique(self, fresh_compute_db):
        i1 = fresh_compute_db.create_instance("svc-1", "redis:7", 1, 256)
        i2 = fresh_compute_db.create_instance("svc-2", "redis:7", 1, 256)
        assert i1["id"] != i2["id"]

    def test_duplicate_name_raises(self, fresh_compute_db):
        fresh_compute_db.create_instance("unique-name", "alpine", 1, 128)
        with pytest.raises(ValueError, match="already exists"):
            fresh_compute_db.create_instance("unique-name", "alpine", 1, 128)

    def test_timestamps_present(self, fresh_compute_db):
        inst = fresh_compute_db.create_instance("ts-test", "busybox", 1, 64)
        assert "created_at" in inst
        assert "updated_at" in inst
        assert inst["created_at"]
        assert inst["updated_at"]


class TestGetInstance:
    def test_get_existing_instance(self, fresh_compute_db):
        created = fresh_compute_db.create_instance("lookup-1", "ubuntu", 2, 1024)
        found = fresh_compute_db.get_instance(created["id"])
        assert found is not None
        assert found["id"] == created["id"]
        assert found["name"] == "lookup-1"

    def test_get_nonexistent_returns_none(self, fresh_compute_db):
        result = fresh_compute_db.get_instance("shaheen-doesnotexist")
        assert result is None
