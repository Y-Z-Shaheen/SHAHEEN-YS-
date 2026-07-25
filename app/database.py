"""
Production-grade database layer for SHAHEEN-YS.

Backend selection (automatic):
  - DATABASE_URL set   → PostgreSQL  (production, Railway)
  - DATABASE_URL unset → SQLite      (development fallback only)

PostgreSQL features:
  - Connection pooling via SQLAlchemy QueuePool
  - pool_pre_ping=True for automatic reconnection on stale connections
  - pool_recycle to avoid idle-connection timeouts
  - Idempotent schema initialisation (CREATE TABLE IF NOT EXISTS)

Public API (unchanged from original):
  - database_connection()   → context manager yielding a connection
  - initialize_database()   → idempotent schema creation
  - check_database_health() → dict with status/database keys
  - insert_and_get_id()     → cross-backend INSERT helper

All callers use SQLAlchemy text() with named params (:name style).
Row results support dict-like access via .mappings().
"""

from __future__ import annotations

import logging
import os
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator

from sqlalchemy import create_engine, event, text
from sqlalchemy.engine import Connection, Engine
from sqlalchemy.exc import OperationalError, SQLAlchemyError
from sqlalchemy.pool import QueuePool, StaticPool

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Database URL resolution
# ---------------------------------------------------------------------------

_PROJECT_ROOT = Path(__file__).resolve().parent.parent


def _resolve_database_url() -> tuple[str, str]:
    """
    Return (url, backend) where backend is "postgresql" or "sqlite".

    Railway / production: DATABASE_URL environment variable must be set.
    Development: falls back to SQLite at SHAHEEN_YS_DATABASE_PATH.

    Handles the common Railway quirk where DATABASE_URL starts with
    "postgres://" (without 'ql') — SQLAlchemy 1.4+ requires "postgresql://".
    """
    raw_url = os.environ.get("DATABASE_URL", "").strip()

    if raw_url:
        # Normalise legacy postgres:// → postgresql://
        if raw_url.startswith("postgres://"):
            raw_url = "postgresql://" + raw_url[len("postgres://"):]
        logger.info("Database backend: PostgreSQL (DATABASE_URL is set)")
        return raw_url, "postgresql"

    # Development fallback: SQLite
    sqlite_path = os.environ.get(
        "SHAHEEN_YS_DATABASE_PATH",
        str(_PROJECT_ROOT / "data" / "db" / "shaheen_ys.db"),
    )
    db_path = Path(sqlite_path).expanduser().resolve()
    db_path.parent.mkdir(parents=True, exist_ok=True)

    url = f"sqlite:///{db_path}"
    logger.info("Database backend: SQLite (development fallback) at %s", db_path)
    return url, "sqlite"


# ---------------------------------------------------------------------------
# Engine creation
# ---------------------------------------------------------------------------

def _create_engine(url: str, backend: str) -> Engine:
    """Create a SQLAlchemy engine with appropriate pooling settings."""
    if backend == "postgresql":
        engine = create_engine(
            url,
            poolclass=QueuePool,
            pool_size=int(os.environ.get("DB_POOL_SIZE", "10")),
            max_overflow=int(os.environ.get("DB_MAX_OVERFLOW", "20")),
            pool_timeout=int(os.environ.get("DB_POOL_TIMEOUT", "30")),
            pool_recycle=int(os.environ.get("DB_POOL_RECYCLE", "300")),
            pool_pre_ping=True,          # detect stale connections automatically
            echo=False,
        )
    else:
        # SQLite: use StaticPool so the same connection is reused across threads,
        # which is safe with check_same_thread=False in a single-process dev env.
        engine = create_engine(
            url,
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
            echo=False,
        )

        # Enable WAL mode and foreign keys for every new SQLite connection
        @event.listens_for(engine, "connect")
        def _sqlite_pragmas(dbapi_conn, _connection_record):
            cursor = dbapi_conn.cursor()
            cursor.execute("PRAGMA journal_mode=WAL")
            cursor.execute("PRAGMA foreign_keys=ON")
            cursor.execute("PRAGMA busy_timeout=30000")
            cursor.close()

    return engine


_DATABASE_URL, DB_BACKEND = _resolve_database_url()
_engine: Engine = _create_engine(_DATABASE_URL, DB_BACKEND)

IS_POSTGRES = DB_BACKEND == "postgresql"

#: Backwards-compatibility export — used by app/compute/service.py (raw sqlite3).
#: Points to the SQLite database file path regardless of production backend.
DATABASE_PATH: str = str(
    Path(
        os.environ.get(
            "SHAHEEN_YS_DATABASE_PATH",
            str(_PROJECT_ROOT / "data" / "db" / "shaheen_ys.db"),
        )
    ).expanduser().resolve()
)


# ---------------------------------------------------------------------------
# Schema SQL (database-specific)
# ---------------------------------------------------------------------------

_SQLITE_SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id          INTEGER PRIMARY KEY,
    username    TEXT    NOT NULL UNIQUE,
    email       TEXT    UNIQUE,
    password_hash TEXT,
    is_active   INTEGER NOT NULL DEFAULT 1,
    created_at  TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS api_keys (
    id          INTEGER PRIMARY KEY,
    owner_name  TEXT    NOT NULL,
    key_hash    TEXT    NOT NULL UNIQUE,
    key_prefix  TEXT    NOT NULL,
    is_active   INTEGER NOT NULL DEFAULT 1,
    created_at  TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_used_at TEXT
);

CREATE TABLE IF NOT EXISTS sessions (
    id          INTEGER PRIMARY KEY,
    session_id  TEXT    NOT NULL UNIQUE,
    user_id     INTEGER,
    expires_at  TEXT    NOT NULL,
    created_at  TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS system_events (
    id          INTEGER PRIMARY KEY,
    event_type  TEXT    NOT NULL,
    service_name TEXT   NOT NULL,
    payload     TEXT,
    created_at  TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS compute_instances (
    id          TEXT    PRIMARY KEY,
    name        TEXT    NOT NULL UNIQUE,
    image       TEXT    NOT NULL,
    cpu         INTEGER NOT NULL,
    memory_mb   INTEGER NOT NULL,
    status      TEXT    NOT NULL,
    created_at  TEXT    NOT NULL,
    updated_at  TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_api_keys_hash          ON api_keys(key_hash);
CREATE INDEX IF NOT EXISTS idx_api_keys_active        ON api_keys(is_active);
CREATE INDEX IF NOT EXISTS idx_sessions_id            ON sessions(session_id);
CREATE INDEX IF NOT EXISTS idx_sessions_expires       ON sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_events_type            ON system_events(event_type);
CREATE INDEX IF NOT EXISTS idx_compute_instances_name ON compute_instances(name);
"""

_POSTGRES_SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id            SERIAL PRIMARY KEY,
    username      TEXT   NOT NULL UNIQUE,
    email         TEXT   UNIQUE,
    password_hash TEXT,
    is_active     INTEGER NOT NULL DEFAULT 1,
    created_at    TEXT    NOT NULL DEFAULT (NOW() AT TIME ZONE 'UTC')
);

CREATE TABLE IF NOT EXISTS api_keys (
    id           SERIAL PRIMARY KEY,
    owner_name   TEXT    NOT NULL,
    key_hash     TEXT    NOT NULL UNIQUE,
    key_prefix   TEXT    NOT NULL,
    is_active    INTEGER NOT NULL DEFAULT 1,
    created_at   TEXT    NOT NULL DEFAULT (NOW() AT TIME ZONE 'UTC'),
    last_used_at TEXT
);

CREATE TABLE IF NOT EXISTS sessions (
    id          SERIAL PRIMARY KEY,
    session_id  TEXT    NOT NULL UNIQUE,
    user_id     INTEGER,
    expires_at  TEXT    NOT NULL,
    created_at  TEXT    NOT NULL DEFAULT (NOW() AT TIME ZONE 'UTC'),
    CONSTRAINT fk_sessions_user
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS system_events (
    id           SERIAL PRIMARY KEY,
    event_type   TEXT   NOT NULL,
    service_name TEXT   NOT NULL,
    payload      TEXT,
    created_at   TEXT   NOT NULL DEFAULT (NOW() AT TIME ZONE 'UTC')
);

CREATE TABLE IF NOT EXISTS compute_instances (
    id          TEXT    PRIMARY KEY,
    name        TEXT    NOT NULL UNIQUE,
    image       TEXT    NOT NULL,
    cpu         INTEGER NOT NULL,
    memory_mb   INTEGER NOT NULL,
    status      TEXT    NOT NULL,
    created_at  TEXT    NOT NULL,
    updated_at  TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_api_keys_hash          ON api_keys(key_hash);
CREATE INDEX IF NOT EXISTS idx_api_keys_active        ON api_keys(is_active);
CREATE INDEX IF NOT EXISTS idx_sessions_id            ON sessions(session_id);
CREATE INDEX IF NOT EXISTS idx_sessions_expires       ON sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_events_type            ON system_events(event_type);
CREATE INDEX IF NOT EXISTS idx_compute_instances_name ON compute_instances(name);
"""


# ---------------------------------------------------------------------------
# Public context manager
# ---------------------------------------------------------------------------

@contextmanager
def database_connection() -> Iterator[Connection]:
    """
    Context manager that yields a SQLAlchemy Connection.

    Commits on clean exit, rolls back on exception, and always closes.
    Rows from execute().mappings().fetchone() / .all() support dict access.

    Usage::

        from sqlalchemy import text
        with database_connection() as conn:
            row = conn.execute(text("SELECT id FROM users WHERE username = :u"),
                               {"u": username}).mappings().fetchone()
    """
    conn = _engine.connect()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# INSERT helper (cross-backend)
# ---------------------------------------------------------------------------

def insert_and_get_id(conn: Connection, sql: str, params: dict[str, Any]) -> int:
    """
    Execute an INSERT statement and return the new row's primary key.

    For PostgreSQL: automatically appends RETURNING id to the SQL.
    For SQLite:     uses result.lastrowid.

    The ``sql`` argument must NOT already contain a RETURNING clause.

    Example::

        key_id = insert_and_get_id(conn,
            "INSERT INTO api_keys (owner_name, key_hash, key_prefix, is_active)"
            " VALUES (:owner_name, :key_hash, :key_prefix, 1)",
            {"owner_name": name, "key_hash": h, "key_prefix": p})
    """
    if IS_POSTGRES:
        result = conn.execute(text(f"{sql} RETURNING id"), params)
        row = result.fetchone()
        return int(row[0])
    else:
        result = conn.execute(text(sql), params)
        return int(result.lastrowid)


# ---------------------------------------------------------------------------
# Schema initialisation
# ---------------------------------------------------------------------------

def initialize_database() -> None:
    """
    Initialise the database schema idempotently.

    Uses CREATE TABLE IF NOT EXISTS — safe to run on every startup.
    Selects the appropriate DDL based on the detected backend.
    """
    schema = _POSTGRES_SCHEMA if IS_POSTGRES else _SQLITE_SCHEMA

    with _engine.begin() as conn:
        # Split on semicolons and execute each statement individually,
        # because SQLAlchemy does not support multi-statement text() execution
        # on all backends.
        for statement in schema.split(";"):
            stmt = statement.strip()
            if stmt:
                conn.execute(text(stmt))

    logger.info(
        "Database schema initialised (backend=%s)",
        DB_BACKEND,
    )


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------

def check_database_health() -> dict[str, str]:
    """
    Check database connectivity.

    Returns a dict with at minimum:
      {"status": "healthy"|"unhealthy", "database": "<detail>", "backend": "..."}
    """
    try:
        with database_connection() as conn:
            conn.execute(text("SELECT 1"))
        return {
            "status": "healthy",
            "database": "connected",
            "backend": DB_BACKEND,
        }
    except (OperationalError, SQLAlchemyError) as exc:
        logger.error("Database health check failed: %s", exc)
        return {
            "status": "unhealthy",
            "database": "connection failed",
            "backend": DB_BACKEND,
            "detail": str(exc),
        }


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    initialize_database()
    print(check_database_health())
