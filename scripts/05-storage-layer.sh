#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATABASE_DIR="${PROJECT_ROOT}/data/db"
DATABASE_FILE="${DATABASE_DIR}/shaheen_ys.db"
SCHEMA_FILE="${DATABASE_DIR}/schema.sql"

log() {
    printf '[05-storage] %s\n' "$1"
}

fail() {
    printf '[05-storage][ERROR] %s\n' "$1" >&2
    exit 1
}

command -v python3 >/dev/null 2>&1 || fail "Python 3 غير مثبت."
command -v sqlite3 >/dev/null 2>&1 || fail "SQLite3 غير مثبت."

mkdir -p "${DATABASE_DIR}"

cat << 'SQL_EOF' > "${SCHEMA_FILE}"
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    email TEXT UNIQUE,
    password_hash TEXT,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
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
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS system_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT NOT NULL,
    service_name TEXT NOT NULL,
    payload TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS service_health (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    service_name TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'unknown',
    latency_ms REAL,
    details TEXT,
    checked_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_username
ON users(username);

CREATE INDEX IF NOT EXISTS idx_api_keys_prefix
ON api_keys(key_prefix);

CREATE INDEX IF NOT EXISTS idx_sessions_session_id
ON sessions(session_id);

CREATE INDEX IF NOT EXISTS idx_events_service_name
ON system_events(service_name);

CREATE INDEX IF NOT EXISTS idx_health_service_name
ON service_health(service_name);
SQL_EOF

sqlite3 "${DATABASE_FILE}" < "${SCHEMA_FILE}"

chmod 700 "${DATABASE_DIR}"
chmod 600 "${DATABASE_FILE}"

cat << 'PY_EOF' > "${PROJECT_ROOT}/app/database.py"
from __future__ import annotations

import os
import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Generator


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DATABASE_PATH = PROJECT_ROOT / "data" / "db" / "shaheen_ys.db"

DATABASE_PATH = Path(
    os.getenv("SHAHEEN_DATABASE_PATH", str(DEFAULT_DATABASE_PATH))
).expanduser().resolve()


def ensure_database_directory() -> None:
    """إنشاء مجلد قاعدة البيانات إذا لم يكن موجوداً."""
    DATABASE_PATH.parent.mkdir(parents=True, exist_ok=True)


def get_connection() -> sqlite3.Connection:
    """إنشاء اتصال SQLite آمن ومهيأ للاستخدام."""
    ensure_database_directory()

    connection = sqlite3.connect(
        DATABASE_PATH,
        timeout=30,
        check_same_thread=False,
    )

    connection.row_factory = sqlite3.Row

    connection.execute("PRAGMA foreign_keys = ON")
    connection.execute("PRAGMA journal_mode = WAL")
    connection.execute("PRAGMA synchronous = NORMAL")
    connection.execute("PRAGMA busy_timeout = 30000")

    return connection


@contextmanager
def database_connection() -> Generator[sqlite3.Connection, None, None]:
    """إدارة دورة حياة الاتصال والمعاملات بأمان."""
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
    """إنشاء الجداول الأساسية عند بدء النظام."""
    schema_path = DATABASE_PATH.parent / "schema.sql"

    if not schema_path.exists():
        raise FileNotFoundError(
            f"ملف مخطط قاعدة البيانات غير موجود: {schema_path}"
        )

    with database_connection() as connection:
        schema_sql = schema_path.read_text(encoding="utf-8")
        connection.executescript(schema_sql)


def database_health_check() -> dict[str, object]:
    """فحص حقيقي لاتصال SQLite وقابلية القراءة والكتابة."""
    try:
        with database_connection() as connection:
            result = connection.execute("SELECT 1 AS health").fetchone()

            if result is None or result["health"] != 1:
                return {
                    "status": "unhealthy",
                    "database": "sqlite",
                    "reason": "Database query returned an invalid result",
                }

        return {
            "status": "healthy",
            "database": "sqlite",
            "path": str(DATABASE_PATH),
        }

    except Exception as error:
        return {
            "status": "unhealthy",
            "database": "sqlite",
            "error": str(error),
        }


if __name__ == "__main__":
    initialize_database()
    print(database_health_check())
PY_EOF

mkdir -p "${PROJECT_ROOT}/app"

touch "${PROJECT_ROOT}/app/__init__.py"

python3 -c "from app.database import initialize_database; initialize_database(); print('Database initialized successfully.')"

log "تم إنشاء طبقة التخزين وقاعدة البيانات بنجاح."
log "Database: ${DATABASE_FILE}"
log "Schema: ${SCHEMA_FILE}"
