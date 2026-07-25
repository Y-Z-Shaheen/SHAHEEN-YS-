"""
Shared pytest fixtures for SHAHEEN-YS tests only.
Isolated in tests/shaheen/ to avoid conflicting with the root AstrBot conftest.
"""

from __future__ import annotations

import os

import pytest


@pytest.fixture(autouse=True)
def clean_env(monkeypatch):
    """
    Ensure DATABASE_URL is not set during SHAHEEN-YS tests so the
    SQLite fallback is used. Individual tests that need PostgreSQL
    can override this fixture.
    """
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.setenv("SHAHEEN_YS_ENV", "development")
    yield
