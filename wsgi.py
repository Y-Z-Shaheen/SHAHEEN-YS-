from __future__ import annotations

from app.config import initialize_config
from app.database import initialize_database
from app.dashboard.app import app

# Initialise configuration and database schema on every worker startup.
# This runs once per Gunicorn worker process when the module is imported,
# which is the correct place for production bootstrapping (pre-fork or
# post-fork depending on preload_app setting in gunicorn.conf.py).
initialize_config()
initialize_database()

application = app

__all__ = [
    "app",
    "application",
]
