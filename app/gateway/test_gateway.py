from __future__ import annotations

from app.database import (
    initialize_database,
)
from app.gateway.app import (
    app,
)


def main() -> int:
    initialize_database()

    client = app.test_client()

    root_response = client.get(
        "/"
    )

    if root_response.status_code != 200:
        print(
            "FAIL: Root endpoint."
        )

        return 1

    health_response = client.get(
        "/api/v1/health"
    )

    if health_response.status_code != 200:
        print(
            "FAIL: Health endpoint."
        )

        print(
            health_response.get_json()
        )

        return 1

    missing_response = client.get(
        "/does-not-exist"
    )

    if missing_response.status_code != 404:
        print(
            "FAIL: 404 handling."
        )

        return 1

    invalid_auth_response = client.get(
        "/api/v1/identity/verify"
    )

    if invalid_auth_response.status_code != 401:
        print(
            "FAIL: Missing API key handling."
        )

        return 1

    print(
        "API Gateway tests passed."
    )

    print(
        "Root endpoint: OK"
    )

    print(
        "Health endpoint: OK"
    )

    print(
        "404 handling: OK"
    )

    print(
        "Authentication validation: OK"
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(
        main()
    )
