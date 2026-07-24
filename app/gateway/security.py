from __future__ import annotations

from flask import Response


def apply_security_headers(
    response: Response,
) -> Response:
    """
    إضافة Security Headers أساسية.
    """

    response.headers["X-Content-Type-Options"] = (
        "nosniff"
    )

    response.headers["X-Frame-Options"] = (
        "DENY"
    )

    response.headers["Referrer-Policy"] = (
        "no-referrer"
    )

    response.headers["Permissions-Policy"] = (
        "camera=(), microphone=(), geolocation=()"
    )

    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; "
        "style-src 'self' 'unsafe-inline'; "
        "script-src 'self'; "
        "img-src 'self' data:;"
    )

    return response
