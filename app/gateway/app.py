from __future__ import annotations

import logging
import time
from datetime import datetime, timezone

from flask import (
    Flask,
    g,
    jsonify,
    request,
)
from werkzeug.exceptions import RequestEntityTooLarge

from app.database import (
    check_database_health,
)
from app.identity.service import (
    identity_service,
)
from app.identity.security import (
    generate_request_id,
)
from app.gateway.config import (
    ALLOWED_ORIGINS,
    ENVIRONMENT,
    HOST,
    MAX_BODY_SIZE_BYTES,
    PORT,
    RATE_LIMIT_REQUESTS,
    RATE_LIMIT_WINDOW_SECONDS,
)
from app.gateway.rate_limiter import (
    InMemoryRateLimiter,
)
from app.gateway.security import (
    apply_security_headers,
)


logging.basicConfig(
    level=logging.INFO,
    format=(
        "%(asctime)s "
        "%(levelname)s "
        "%(name)s "
        "%(message)s"
    ),
)

logger = logging.getLogger(
    "shaheen-ys.api-gateway"
)


app = Flask(
    "shaheen-ys-api-gateway"
)

app.config["MAX_CONTENT_LENGTH"] = (
    MAX_BODY_SIZE_BYTES
)


rate_limiter = InMemoryRateLimiter(
    max_requests=RATE_LIMIT_REQUESTS,
    window_seconds=RATE_LIMIT_WINDOW_SECONDS,
)


@app.before_request
def before_request() -> None:
    g.request_id = generate_request_id()

    g.request_started_at = time.monotonic()

    client_ip = (
        request.headers.get(
            "X-Forwarded-For",
            request.remote_addr
            or "unknown",
        )
        .split(",")[0]
        .strip()
    )

    g.client_ip = client_ip

    if not rate_limiter.allow(client_ip):
        return jsonify(
            {
                "success": False,
                "error": "rate_limit_exceeded",
                "message": (
                    "Too many requests."
                ),
                "request_id": g.request_id,
            }
        ), 429


@app.after_request
def after_request(response):
    response.headers["X-Request-ID"] = (
        g.get(
            "request_id",
            "unknown",
        )
    )

    apply_security_headers(
        response
    )

    origin = request.headers.get(
        "Origin"
    )

    if origin and origin in ALLOWED_ORIGINS:
        response.headers[
            "Access-Control-Allow-Origin"
        ] = origin

        response.headers[
            "Vary"
        ] = "Origin"

    elapsed_ms = (
        time.monotonic()
        - g.get(
            "request_started_at",
            time.monotonic(),
        )
    ) * 1000

    logger.info(
        "%s %s %s %.2fms",
        request.method,
        request.path,
        response.status_code,
        elapsed_ms,
    )

    return response


@app.errorhandler(
    RequestEntityTooLarge
)
def handle_payload_too_large(
    error,
):
    return jsonify(
        {
            "success": False,
            "error": "payload_too_large",
            "message": (
                "Request payload exceeds "
                "the configured limit."
            ),
            "request_id": g.get(
                "request_id",
                "unknown",
            ),
        }
    ), 413


@app.errorhandler(
    404
)
def handle_not_found(
    error,
):
    return jsonify(
        {
            "success": False,
            "error": "not_found",
            "message": (
                "The requested resource "
                "does not exist."
            ),
            "request_id": g.get(
                "request_id",
                "unknown",
            ),
        }
    ), 404


@app.errorhandler(
    405
)
def handle_method_not_allowed(
    error,
):
    return jsonify(
        {
            "success": False,
            "error": "method_not_allowed",
            "message": (
                "HTTP method is not allowed."
            ),
            "request_id": g.get(
                "request_id",
                "unknown",
            ),
        }
    ), 405


@app.errorhandler(
    Exception
)
def handle_unexpected_error(
    error,
):
    logger.exception(
        "Unhandled exception"
    )

    return jsonify(
        {
            "success": False,
            "error": "internal_server_error",
            "message": (
                "An internal server error occurred."
            ),
            "request_id": g.get(
                "request_id",
                "unknown",
            ),
        }
    ), 500


@app.get(
    "/"
)
def root():
    return jsonify(
        {
            "name": "SHAHEEN-YS",
            "service": "API Gateway",
            "version": "0.1.0",
            "environment": ENVIRONMENT,
            "status": "running",
            "timestamp": datetime.now(
                timezone.utc
            ).isoformat(),
        }
    )


@app.get(
    "/api/v1/health"
)
def health():
    database_health = (
        check_database_health()
    )

    identity_health = (
        identity_service.health_check()
    )

    database_healthy = (
        database_health.get(
            "status"
        ) == "healthy"
    )

    identity_healthy = (
        identity_health.get(
            "status"
        ) == "healthy"
    )

    overall_status = (
        "healthy"
        if database_healthy
        and identity_healthy
        else "unhealthy"
    )

    status_code = (
        200
        if overall_status == "healthy"
        else 503
    )

    return jsonify(
        {
            "status": overall_status,
            "service": "api-gateway",
            "timestamp": datetime.now(
                timezone.utc
            ).isoformat(),
            "components": {
                "database": database_health,
                "identity": identity_health,
            },
            "request_id": g.request_id,
        }
    ), status_code


@app.get(
    "/api/v1/identity/health"
)
def identity_health():
    result = (
        identity_service.health_check()
    )

    status_code = (
        200
        if result.get(
            "status"
        ) == "healthy"
        else 503
    )

    return jsonify(
        result
    ), status_code


@app.post(
    "/api/v1/admin/keys"
)
def create_api_key():
    api_key = request.headers.get(
        "X-Admin-API-Key"
    )

    if not api_key:
        return jsonify(
            {
                "success": False,
                "error": "missing_admin_key",
                "message": (
                    "X-Admin-API-Key header "
                    "is required."
                ),
                "request_id": g.request_id,
            }
        ), 401

    verified_key = (
        identity_service.verify_api_key(
            api_key
        )
    )

    if verified_key is None:
        return jsonify(
            {
                "success": False,
                "error": "invalid_admin_key",
                "message": (
                    "The supplied API key "
                    "is invalid or inactive."
                ),
                "request_id": g.request_id,
            }
        ), 403

    payload = request.get_json(
        silent=True
    )

    if not isinstance(
        payload,
        dict,
    ):
        return jsonify(
            {
                "success": False,
                "error": "invalid_json",
                "message": (
                    "A valid JSON object is required."
                ),
                "request_id": g.request_id,
            }
        ), 400

    owner_name = payload.get(
        "owner_name"
    )

    if not isinstance(
        owner_name,
        str,
    ):
        return jsonify(
            {
                "success": False,
                "error": "invalid_owner_name",
                "message": (
                    "owner_name must be a string."
                ),
                "request_id": g.request_id,
            }
        ), 400

    try:
        result = (
            identity_service.create_api_key(
                owner_name
            )
        )

        return jsonify(
            {
                "success": True,
                "data": result,
                "request_id": g.request_id,
            }
        ), 201

    except ValueError as error:
        return jsonify(
            {
                "success": False,
                "error": "validation_error",
                "message": str(error),
                "request_id": g.request_id,
            }
        ), 400


@app.get(
    "/api/v1/identity/verify"
)
def verify_identity():
    api_key = request.headers.get(
        "X-API-Key"
    )

    if not api_key:
        return jsonify(
            {
                "authenticated": False,
                "error": "missing_api_key",
                "request_id": g.request_id,
            }
        ), 401

    identity = (
        identity_service.verify_api_key(
            api_key
        )
    )

    if identity is None:
        return jsonify(
            {
                "authenticated": False,
                "error": "invalid_api_key",
                "request_id": g.request_id,
            }
        ), 403

    return jsonify(
        {
            "authenticated": True,
            "identity": identity,
            "request_id": g.request_id,
        }
    )


@app.get(
    "/api/v1/system/info"
)
def system_info():
    return jsonify(
        {
            "name": "SHAHEEN-YS",
            "architecture": {
                "phase": 1,
                "component": "API Gateway",
                "identity": "active",
                "database": "SQLite",
                "dashboard": "planned",
            },
            "security": {
                "request_ids": True,
                "rate_limiting": True,
                "security_headers": True,
                "api_key_hashing": True,
            },
            "request_id": g.request_id,
        }
    )


def create_app() -> Flask:
    return app


if __name__ == "__main__":
    logger.info(
        "Starting SHAHEEN-YS API Gateway"
    )

    logger.info(
        "Listening on %s:%s",
        HOST,
        PORT,
    )

    app.run(
        host=HOST,
        port=PORT,
        debug=False,
        threaded=True,
    )
