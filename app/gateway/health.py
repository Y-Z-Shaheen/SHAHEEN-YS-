from __future__ import annotations

import sys

from app.gateway.app import (
    app,
)


def main() -> int:
    client = app.test_client()

    response = client.get(
        "/api/v1/health"
    )

    print(
        "HTTP Status:",
        response.status_code,
    )

    print(
        response.get_json()
    )

    if response.status_code == 200:
        print(
            "API Gateway health check passed."
        )

        return 0

    print(
        "API Gateway health check failed."
    )

    return 1


if __name__ == "__main__":
    sys.exit(
        main()
    )
