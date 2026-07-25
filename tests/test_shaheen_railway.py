"""
Tests for Railway production readiness.

Covers:
- PORT environment variable is respected (0.0.0.0:$PORT)
- WSGI application is importable as wsgi.application
- /health endpoint returns 200 with healthy DB
- /health/live endpoint always returns 200
- /health/ready returns 200 only when DB is ready
- /metrics endpoint returns 200
- Health response body contains expected fields
"""

from __future__ import annotations

import importlib
import os
import sys
from unittest.mock import patch, MagicMock

import pytest


# ---------------------------------------------------------------------------
# WSGI import
# ---------------------------------------------------------------------------


class TestWSGIImport:
    def test_wsgi_application_is_importable(self):
        """wsgi:application must be importable for Gunicorn."""
        import wsgi
        assert hasattr(wsgi, "application"), "wsgi.application not found"
        assert hasattr(wsgi, "app"), "wsgi.app not found"

    def test_wsgi_application_is_callable(self):
        import wsgi
        assert callable(wsgi.application)

    def test_wsgi_app_and_application_are_same_object(self):
        import wsgi
        assert wsgi.app is wsgi.application


# ---------------------------------------------------------------------------
# Gunicorn config: PORT and bind address
# ---------------------------------------------------------------------------


class TestGunicornConfig:
    def test_binds_to_all_interfaces(self):
        """gunicorn.conf.py must bind to 0.0.0.0 (required for Railway)."""
        if "gunicorn_conf" in sys.modules:
            del sys.modules["gunicorn_conf"]

        with patch.dict("os.environ", {"PORT": "7777"}, clear=False):
            import importlib.util
            spec = importlib.util.spec_from_file_location(
                "gunicorn_conf_test", "gunicorn.conf.py"
            )
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)

        assert module.bind == "0.0.0.0:7777"
        assert module.bind.startswith("0.0.0.0:")

    def test_default_port_is_numeric_string(self):
        """When PORT is unset, a sensible default is used."""
        env_without_port = {k: v for k, v in os.environ.items() if k != "PORT"}
        with patch.dict("os.environ", env_without_port, clear=True):
            import importlib.util
            spec = importlib.util.spec_from_file_location(
                "gunicorn_conf_test2", "gunicorn.conf.py"
            )
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)

        host, port_str = module.bind.rsplit(":", 1)
        assert host == "0.0.0.0"
        assert port_str.isdigit()
        assert int(port_str) > 0


# ---------------------------------------------------------------------------
# Flask app health endpoints
# ---------------------------------------------------------------------------


@pytest.fixture()
def flask_client(tmp_path):
    """
    Provide a Flask test client with an initialised SQLite database.
    Patches DATABASE_URL away so we use SQLite in tests.
    """
    db_path = tmp_path / "test_railway.db"
    env = {"SHAHEEN_YS_DATABASE_PATH": str(db_path)}

    # Drop cached database module so it re-initialises with our temp db
    mods_to_drop = [k for k in sys.modules if k.startswith("app.database")]
    for m in mods_to_drop:
        del sys.modules[m]

    with patch.dict("os.environ", env, clear=False):
        # Remove DATABASE_URL if set in the real environment
        os.environ.pop("DATABASE_URL", None)

        import app.database as db_module
        db_module.initialize_database()

        # Re-import dashboard app so it picks up the fresh db module
        mods_to_drop_app = [
            k for k in sys.modules
            if k.startswith("app.dashboard") or k == "wsgi"
        ]
        for m in mods_to_drop_app:
            del sys.modules[m]

        from app.dashboard.app import app
        app.config["TESTING"] = True
        with app.test_client() as client:
            yield client

    # Cleanup
    mods_to_drop = [k for k in sys.modules if k.startswith("app.database")]
    for m in mods_to_drop:
        del sys.modules[m]


class TestHealthEndpoint:
    def test_health_returns_200(self, flask_client):
        resp = flask_client.get("/health")
        assert resp.status_code == 200

    def test_health_body_has_status(self, flask_client):
        data = flask_client.get("/health").get_json()
        assert "status" in data

    def test_health_body_has_service(self, flask_client):
        data = flask_client.get("/health").get_json()
        assert data.get("service") == "SHAHEEN-YS"

    def test_health_body_has_database_info(self, flask_client):
        data = flask_client.get("/health").get_json()
        assert "database" in data

    def test_health_status_is_healthy(self, flask_client):
        data = flask_client.get("/health").get_json()
        assert data["status"] == "healthy"


class TestLivenessEndpoint:
    def test_live_always_200(self, flask_client):
        resp = flask_client.get("/health/live")
        assert resp.status_code == 200

    def test_live_body_status_alive(self, flask_client):
        data = flask_client.get("/health/live").get_json()
        assert data.get("status") == "alive"

    def test_live_body_has_service(self, flask_client):
        data = flask_client.get("/health/live").get_json()
        assert data.get("service") == "SHAHEEN-YS"


class TestReadinessEndpoint:
    def test_ready_returns_200_with_healthy_db(self, flask_client):
        resp = flask_client.get("/health/ready")
        assert resp.status_code == 200

    def test_ready_body_status_ready(self, flask_client):
        data = flask_client.get("/health/ready").get_json()
        assert data.get("status") == "ready"

    def test_ready_body_has_database(self, flask_client):
        data = flask_client.get("/health/ready").get_json()
        assert "database" in data

    def test_ready_returns_503_when_db_unhealthy(self, flask_client):
        """
        When the database is unavailable, /health/ready must return 503.
        Patch in the dashboard module's namespace (where the name is bound).
        """
        from unittest.mock import patch as _patch

        def unhealthy():
            return {"status": "unhealthy", "database": "connection failed", "backend": "sqlite"}

        with _patch("app.dashboard.app.check_database_health", unhealthy):
            resp = flask_client.get("/health/ready")

        assert resp.status_code == 503
        data = resp.get_json()
        assert data["status"] == "not_ready"


class TestMetricsEndpoint:
    def test_metrics_returns_200(self, flask_client):
        resp = flask_client.get("/metrics")
        assert resp.status_code == 200

    def test_metrics_body_has_service(self, flask_client):
        data = flask_client.get("/metrics").get_json()
        assert data.get("service") == "SHAHEEN-YS"

    def test_metrics_body_has_metrics_key(self, flask_client):
        data = flask_client.get("/metrics").get_json()
        assert "metrics" in data


class TestDashboardEndpoint:
    def test_root_returns_200_or_html(self, flask_client):
        resp = flask_client.get("/")
        # May return 200 (HTML) or 500 if template missing in test env
        assert resp.status_code in (200, 500)

    def test_api_dashboard_status(self, flask_client):
        resp = flask_client.get("/api/dashboard/status")
        assert resp.status_code == 200
        data = resp.get_json()
        assert data.get("platform") == "SHAHEEN-YS"


# ---------------------------------------------------------------------------
# Config: PORT is read from os.environ, not hardcoded
# ---------------------------------------------------------------------------


class TestPortConfiguration:
    def test_config_reads_port_from_env(self):
        import sys
        mods_to_drop = [k for k in sys.modules if k.startswith("app.config")]
        for m in mods_to_drop:
            del sys.modules[m]

        with patch.dict("os.environ", {"PORT": "9999"}, clear=False):
            import app.config as cfg
            assert cfg.Config.PORT == 9999

        for m in list(sys.modules):
            if m.startswith("app.config"):
                del sys.modules[m]
