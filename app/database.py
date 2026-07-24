from __future__ import annotations

import os
import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator


PROJECT_ROOT = Path(
    __file__
).resolve().parent.parent

DATABASE_PATH = Path(
    os.getenv(
        "SHAHEEN_DATABASE_PATH",
        str(
            PROJECT_ROOT
            / "data"
            / "db"
            / "shaheen_ys.db"
        ),
    )
).expanduser().resolve()


DATABASE_PATH.parent.mkdir(
    parents=True,
    exist_ok=True,
)


SCHEMA_SQL = """
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    email TEXT UNIQUE,
    password_hash TEXT,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS api_keys (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    owner_name TEXT NOT NULL,
    key_hash TEXT NOT NULL UNIQUE,
    key_prefix TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_used_at TEXT
);

CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL UNIQUE,
    user_id INTEGER,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS system_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT NOT NULL,
    service_name TEXT NOT NULL,
    payload TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_api_keys_hash
ON api_keys(key_hash);

CREATE INDEX IF NOT EXISTS idx_api_keys_active
ON api_keys(is_active);

CREATE INDEX IF NOT EXISTS idx_sessions_session_id
ON sessions(session_id);

CREATE INDEX IF NOT EXISTS idx_sessions_expires_at
ON sessions(expires_at);

CREATE INDEX IF NOT EXISTS idx_system_events_type
ON system_events(event_type);
"""


def get_connection() -> sqlite3.Connection:
    connection = sqlite3.connect(
        DATABASE_PATH,
        timeout=30,
    )

    connection.row_factory = sqlite3.Row

    connection.execute(
        "PRAGMA foreign_keys = ON"
    )

    connection.execute(
        "PRAGMA journal_mode = WAL"
    )

    connection.execute(
        "PRAGMA busy_timeout = 30000"
    )

    return connection


@contextmanager
def database_connection() -> Iterator[
    sqlite3.Connection
]:
    connection = get_connection()

    try:
        yield connection

        connection.commit()

    except Exception:
        connection.rollback()
        raise

    finally:
        connection.close()


def initialize_database() -> None:
    with database_connection() as connection:
        connection.executescript(
            SCHEMA_SQL
        )

    print(
        f"Database initialized: {DATABASE_PATH}"
    )


def check_database_health() -> dict[str, str]:
    try:
        with database_connection() as connection:
            result = connection.execute(
                "SELECT 1 AS health"
            ).fetchone()

            if result is None:
                return {
                    "status": "unhealthy",
                    "database": "no response",
                }

            return {
                "status": "healthy",
                "database": "connected",
            }

    except sqlite3.Error as error:
        return {
            "status": "unhealthy",
            "database": str(error),
        }


if __name__ == "__main__":
    initialize_database()

    print(
        check_database_health()
    )
