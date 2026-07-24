from __future__ import annotations

from app.database import initialize_database
from app.identity.service import IdentityService
from app.identity.security import (
    hash_secret,
    verify_secret,
)


def main() -> int:
    initialize_database()

    service = IdentityService()

    result = service.create_api_key(
        owner_name="SHAHEEN-YS Test Client"
    )

    generated_key = result["api_key"]

    if not generated_key.startswith("sk_shaheen_"):
        print("FAIL: Invalid API key prefix.")
        return 1

    stored_hash = hash_secret(generated_key)

    if not verify_secret(
        generated_key,
        stored_hash,
    ):
        print("FAIL: Secret verification failed.")
        return 1

    if verify_secret(
        "invalid-api-key",
        stored_hash,
    ):
        print("FAIL: Invalid secret was accepted.")
        return 1

    verified = service.verify_api_key(
        generated_key
    )

    if verified is None:
        print("FAIL: API key lookup failed.")
        return 1

    revoked = service.revoke_api_key(
        result["id"]
    )

    if not revoked:
        print("FAIL: API key revocation failed.")
        return 1

    if service.verify_api_key(
        generated_key
    ) is not None:
        print("FAIL: Revoked API key still works.")
        return 1

    session = service.create_session(
        lifetime_minutes=5
    )

    if not service.verify_session(
        session["session_id"]
    ):
        print("FAIL: Session verification failed.")
        return 1

    print("Identity tests passed.")
    print("API key generation: OK")
    print("Hash verification: OK")
    print("Invalid key rejection: OK")
    print("API key revocation: OK")
    print("Session creation: OK")
    print("Session verification: OK")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
