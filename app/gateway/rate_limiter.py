from __future__ import annotations

import threading
import time
from collections import defaultdict, deque


class InMemoryRateLimiter:
    """
    Rate limiter بسيط داخل الذاكرة.

    مناسب للنسخة Single-Node.
    عند الانتقال إلى Multi-Node يجب استبداله
    بمخزن مركزي مثل Redis.
    """

    def __init__(
        self,
        max_requests: int,
        window_seconds: int,
    ) -> None:
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._requests: dict[str, deque[float]] = defaultdict(
            deque
        )
        self._lock = threading.Lock()

    def allow(
        self,
        client_key: str,
    ) -> bool:
        now = time.monotonic()

        with self._lock:
            requests = self._requests[client_key]

            cutoff = (
                now
                - self.window_seconds
            )

            while requests and requests[0] <= cutoff:
                requests.popleft()

            if len(requests) >= self.max_requests:
                return False

            requests.append(now)

            return True

    def cleanup(
        self,
    ) -> None:
        now = time.monotonic()

        cutoff = (
            now
            - self.window_seconds
        )

        with self._lock:
            expired_keys = []

            for key, requests in self._requests.items():
                while requests and requests[0] <= cutoff:
                    requests.popleft()

                if not requests:
                    expired_keys.append(key)

            for key in expired_keys:
                del self._requests[key]
