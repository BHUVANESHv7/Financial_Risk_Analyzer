"""
security.py
───────────
Small, dependency-free protections:
  • RateLimiter — sliding-window limiter (e.g. failed logins per email + IP)
  • security_headers — sensible HTTP response headers
  • csv_safe — neutralise spreadsheet formula injection in CSV exports

The limiter is in-memory, which is right for a single server process.
Behind several workers, move it to Redis or the reverse proxy.
"""

import threading
import time
from collections import defaultdict, deque


class RateLimiter:
    def __init__(self, max_events: int, window_seconds: int):
        self.max_events = max_events
        self.window = window_seconds
        self._events: dict[str, deque] = defaultdict(deque)
        self._lock = threading.Lock()

    def _prune(self, q: deque, now: float):
        while q and now - q[0] > self.window:
            q.popleft()

    def retry_after(self, key: str) -> int:
        """Seconds until `key` may try again (0 = allowed now)."""
        now = time.monotonic()
        with self._lock:
            q = self._events.get(key)
            if not q:
                return 0
            self._prune(q, now)
            if len(q) < self.max_events:
                return 0
            return max(1, int(self.window - (now - q[0])) + 1)

    def hit(self, key: str):
        now = time.monotonic()
        with self._lock:
            q = self._events[key]
            self._prune(q, now)
            q.append(now)
            if len(self._events) > 10_000:  # bound memory under abuse
                for k in [k for k, v in self._events.items() if not v][:5_000]:
                    del self._events[k]

    def reset(self, key: str):
        with self._lock:
            self._events.pop(key, None)


# 5 wrong passwords per email+IP per 15 minutes; 10 sign-ups per IP per hour.
login_limiter = RateLimiter(max_events=5, window_seconds=15 * 60)
register_limiter = RateLimiter(max_events=10, window_seconds=60 * 60)

SECURITY_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
    "Cache-Control": "no-store",
}


def csv_safe(value) -> str:
    """Prefix cells that a spreadsheet would run as a formula."""
    text = "" if value is None else str(value)
    return "'" + text if text[:1] in ("=", "+", "-", "@", "\t", "\r") else text
