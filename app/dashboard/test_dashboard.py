from __future__ import annotations

from app.dashboard.app import create_dashboard_app


def main() -> None:
    application = create_dashboard_app()

    application.testing = True

    client = application.test_client()

    dashboard_response = client.get("/")

    if dashboard_response.status_code != 200:
        raise RuntimeError(
            f"Dashboard returned HTTP {dashboard_response.status_code}"
        )

    health_response = client.get("/health")

    if health_response.status_code not in (200, 503):
        raise RuntimeError(
            f"Health endpoint returned HTTP {health_response.status_code}"
        )

    status_response = client.get("/api/dashboard/status")

    if status_response.status_code != 200:
        raise RuntimeError(
            "Dashboard status endpoint is not responding correctly"
        )

    print("[09-dashboard] Dashboard tests passed successfully.")


if __name__ == "__main__":
    main()
