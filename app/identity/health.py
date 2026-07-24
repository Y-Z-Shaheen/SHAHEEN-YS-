from __future__ import annotations

from app.identity.service import identity_service


def main() -> int:
    result = identity_service.health_check()

    print(result)

    if result.get("status") == "healthy":
        return 0

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
