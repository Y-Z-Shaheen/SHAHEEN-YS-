from __future__ import annotations

import os
import shlex
import subprocess
from pathlib import Path


PROJECT_ROOT = Path(
    os.getenv(
        "SHAHEEN_YS_PROJECT_ROOT",
        Path.cwd(),
    )
).resolve()


def execute_command(
    command: str,
) -> dict[str, object]:
    """
    تنفيذ أوامر Terminal بشكل مضبوط.

    لا يستخدم shell=True لتقليل مخاطر
    Shell Injection.
    """

    if not command.strip():
        return {
            "success": False,
            "stdout": "",
            "stderr": "الأمر فارغ.",
            "return_code": 1,
        }

    try:
        arguments = shlex.split(
            command,
        )

        result = subprocess.run(
            arguments,
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )

        return {
            "success": result.returncode == 0,
            "stdout": result.stdout,
            "stderr": result.stderr,
            "return_code": result.returncode,
        }

    except subprocess.TimeoutExpired:
        return {
            "success": False,
            "stdout": "",
            "stderr": "انتهت مهلة تنفيذ الأمر.",
            "return_code": 124,
        }

    except Exception as error:
        return {
            "success": False,
            "stdout": "",
            "stderr": str(error),
            "return_code": 1,
        }
