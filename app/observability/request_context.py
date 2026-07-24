from __future__ import annotations

import uuid
from contextvars import ContextVar


_request_id: ContextVar[str | None] = ContextVar(
    "shaheen_ys_request_id",
    default=None,
)


def generate_request_id() -> str:
    return uuid.uuid4().hex


def set_request_id(
    request_id: str,
) -> None:
    _request_id.set(request_id)


def get_request_id() -> str | None:
    return _request_id.get()


def clear_request_id() -> None:
    _request_id.set(None)
