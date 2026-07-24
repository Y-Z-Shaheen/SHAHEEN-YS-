from __future__ import annotations

import multiprocessing
import os


bind = f"0.0.0.0:{os.getenv('PORT', '8080')}"

workers = int(
    os.getenv(
        "WEB_CONCURRENCY",
        str(max(2, multiprocessing.cpu_count() * 2 + 1)),
    )
)

threads = int(
    os.getenv(
        "GUNICORN_THREADS",
        "2",
    )
)

worker_class = "gthread"

timeout = int(
    os.getenv(
        "GUNICORN_TIMEOUT",
        "120",
    )
)

graceful_timeout = int(
    os.getenv(
        "GUNICORN_GRACEFUL_TIMEOUT",
        "30",
    )
)

keepalive = int(
    os.getenv(
        "GUNICORN_KEEPALIVE",
        "5",
    )
)

max_requests = int(
    os.getenv(
        "GUNICORN_MAX_REQUESTS",
        "1000",
    )
)

max_requests_jitter = int(
    os.getenv(
        "GUNICORN_MAX_REQUESTS_JITTER",
        "100",
    )
)

accesslog = "-"

errorlog = "-"

loglevel = os.getenv(
    "SHAHEEN_YS_LOG_LEVEL",
    "info",
)

capture_output = True

preload_app = False

forwarded_allow_ips = "*"

secure_scheme_headers = {
    "X-FORWARDED-PROTO": "https",
}
