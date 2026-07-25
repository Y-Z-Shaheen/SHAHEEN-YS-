"""
Tests for SHAHEEN-YS health endpoints.
Tests: /health, /health/live, /health/ready, /metrics
"""

from __future__ import annotations

import importlib
import os

import pytest


@pytest.fixture(scope="module")
def client(tmp_path_factory):
    """
    Flask test client with a fresh SQLite database.
    module-scoped for speed (one DB per test module).
    """
    db_path = str(tmp_path_factory.mktemp("db") / "health_test.db")

    # Set env vars directly (no monkeypatch — incompatible with module scope)
    os.environ.pop("DATABASE_URL", None)
    os.environ["SHAHEEN_YS_DATABASE_PATH"] = db_path
    os.environ["SHAHEEN_YS_ENV"] = "development"

    # Reload db module so new path takes effect
    import app.database as db_mod
    importlib.reload(db_mod)
    db_mod.initialize_database()

    # Reload dashboard app so it picks up the fresh db module
    import app.dashboard.app as dash_mod
    importlib.reload(dash_mod)

    with dash_mod.app.test_client() as c:
        yield c

    # Cleanup
    os.environ.pop("SHAHEEN_YS_DATABASE_PATH", None)


class TestLivenessEndpoint:
    def test_returns_200(self, client):
        resp = client.get("/health/live")
        assert resp.status_code == 200

    def test_returns_alive_status(self, client):
        data = client.get("/health/live").get_json()
        assert data["status"] == "alive"

    def test_service_field(self, client):
        data = client.get("/health/live").get_json()
        assert "service" in data
        assert data["service"] == "SHAHEEN-YS"

    def test_no_auth_required(self, client):
        resp = client.get("/health/live")
        assert resp.status_code != 401
        assert resp.status_code != 403


class TestReadinessEndpoint:
    def test_returns_200_when_db_healthy(self, client):
        resp = client.get("/health/ready")
        assert resp.status_code == 200

    def test_returns_ready_status(self, client):
        data = client.get("/health/ready").get_json()
        assert data["status"] == "ready"

    def test_includes_database_field(self, client):
        data = client.get("/health/ready").get_json()
        assert "database" in data
        assert isinstance(data["database"], dict)

    def test_no_auth_required(self, client):
        resp = client.get("/health/ready")
        assert resp.status_code != 401


class TestHealthEndpoint:
    def test_returns_200_when_healthy(self, client):
        resp = client.get("/health")
        assert resp.status_code == 200

    def test_returns_healthy_status(self, client):
        data = client.get("/health").get_json()
        assert data["status"] == "healthy"

    def test_includes_database_field(self, client):
        data = client.get("/health").get_json()
        assert "database" in data
        db = data["database"]
        assert db["status"] == "healthy"
        assert "backend" in db


class TestMetricsEndpoint:
    def test_returns_200(self, client):
        resp = client.get("/metrics")
        assert resp.status_code == 200

    def test_returns_json(self, client):
        resp = client.get("/metrics")
        data = resp.get_json()
        assert isinstance(data, dict)
        assert "metrics" in data
        assert data["service"] == "SHAHEEN-YS"
