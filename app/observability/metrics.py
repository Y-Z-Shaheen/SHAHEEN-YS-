from __future__ import annotations

from collections import Counter
from threading import Lock
from time import monotonic


class ApplicationMetrics:
    """Metrics بسيطة وخفيفة بدون الاعتماد على خدمة خارجية."""

    def __init__(self) -> None:
        self._lock = Lock()

        self._started_at = monotonic()

        self._total_requests = 0

        self._total_errors = 0

        self._status_codes: Counter[int] = Counter()

    def record_request(
        self,
        status_code: int,
    ) -> None:
        with self._lock:
            self._total_requests += 1

            self._status_codes[
                status_code
            ] += 1

            if status_code >= 500:
                self._total_errors += 1

    def snapshot(self) -> dict[str, object]:
        with self._lock:
            return {
                "total_requests": self._total_requests,

                "total_errors": self._total_errors,

                "status_codes": dict(
                    self._status_codes
                ),

                "uptime_seconds": round(
                    monotonic()
                    - self._started_at,
                    2,
                ),
            }


metrics = ApplicationMetrics()
