#!/usr/bin/env bash

set -Eeuo pipefail

============================================================

SHAHEEN-YS - PASH4

Secure Web Terminal Foundation

============================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WEBUI_DIR="${PROJECT_ROOT}/shaheen_ys/webui"
TERMINAL_DIR="${WEBUI_DIR}/terminal"
STATIC_DIR="${WEBUI_DIR}/static"
CONFIG_DIR="${PROJECT_ROOT}/config"
LOG_DIR="${PROJECT_ROOT}/logs"

TERMINAL_SERVER="${TERMINAL_DIR}/server.py"
TERMINAL_CONFIG="${CONFIG_DIR}/terminal.yml"
TERMINAL_CSS="${STATIC_DIR}/terminal.css"
TERMINAL_JS="${STATIC_DIR}/terminal.js"
TERMINAL_LOG="${LOG_DIR}/terminal.log"

log() {
local message="$1"

mkdir -p "${LOG_DIR}"

printf '[%s] %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" \
    "${message}" | tee -a "${TERMINAL_LOG}"

}

fail() {
log "ERROR: $1"
exit 1
}

require_command() {
local command_name="$1"

if ! command -v "${command_name}" >/dev/null 2>&1; then
    fail "الأداة المطلوبة غير مثبتة: ${command_name}"
fi

}

validate_project() {
if [[ ! -d "${PROJECT_ROOT}/shaheen_ys" ]]; then
fail "مجلد shaheen_ys غير موجود. نفذ PASH1 أولاً."
fi
}

prepare_directories() {
mkdir -p 
"${WEBUI_DIR}" 
"${TERMINAL_DIR}" 
"${STATIC_DIR}" 
"${CONFIG_DIR}" 
"${LOG_DIR}"
}

create_terminal_configuration() {
cat > "${TERMINAL_CONFIG}" << 'YAML'
terminal:
enabled: true
host: 127.0.0.1
port: 8090

security:
shell_mode: false
shell_execution: false
command_timeout_seconds: 30
maximum_command_length: 4096
maximum_sessions: 5
working_directory: project_root

logging:
enabled: true
log_commands: true

blocked_commands:

- rm

- mkfs

- dd

- shutdown

- reboot

- poweroff

- halt

- passwd

- useradd

- userdel

- groupadd

- groupdel

- mount

- umount

- iptables

- nft

- systemctl

- service

- docker

- podman

- kubectl

- terraform

- tofu

- ssh

- scp

- sftp
  YAML
  
  log "تم إنشاء إعدادات Terminal الآمنة."
  }

create_terminal_backend() {
cat > "${TERMINAL_SERVER}" << 'PYTHON'
from future import annotations

import asyncio
import json
import logging
import os
import shlex
import time
from pathlib import Path
from typing import Final

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles

PROJECT_ROOT: Final[Path] = Path(
os.getenv(
"SHAHEEN_YS_PROJECT_ROOT",
Path(file).resolve().parents[3],
)
).resolve()

TERMINAL_HOST: Final[str] = os.getenv(
"SHAHEEN_YS_TERMINAL_HOST",
"127.0.0.1",
)

TERMINAL_PORT: Final[int] = int(
os.getenv(
"SHAHEEN_YS_TERMINAL_PORT",
"8090",
)
)

MAX_COMMAND_LENGTH: Final[int] = int(
os.getenv(
"SHAHEEN_YS_MAX_COMMAND_LENGTH",
"4096",
)
)

COMMAND_TIMEOUT_SECONDS: Final[int] = int(
os.getenv(
"SHAHEEN_YS_COMMAND_TIMEOUT",
"30",
)
)

MAX_SESSIONS: Final[int] = int(
os.getenv(
"SHAHEEN_YS_MAX_SESSIONS",
"5",
)
)

LOG_DIR: Final[Path] = PROJECT_ROOT / "logs"

LOG_DIR.mkdir(
parents=True,
exist_ok=True,
)

logging.basicConfig(
level=logging.INFO,
format="%(asctime)s %(levelname)s %(name)s %(message)s",
handlers=[
logging.FileHandler(
LOG_DIR / "terminal.log",
encoding="utf-8",
),
logging.StreamHandler(),
],
)

logger = logging.getLogger("shaheen_ys.terminal")

app = FastAPI(
title="SHAHEEN-YS Terminal",
version="1.0.0",
)

STATIC_DIR: Final[Path] = Path(file).resolve().parent.parent / "static"

if STATIC_DIR.exists():
app.mount(
"/static",
StaticFiles(directory=str(STATIC_DIR)),
name="static",
)

ACTIVE_SESSIONS: set[str] = set()

BLOCKED_COMMANDS: Final[set[str]] = {
"rm",
"mkfs",
"dd",
"shutdown",
"reboot",
"poweroff",
"halt",
"passwd",
"useradd",
"userdel",
"groupadd",
"groupdel",
"mount",
"umount",
"iptables",
"nft",
"systemctl",
"service",
"docker",
"podman",
"kubectl",
"terraform",
"tofu",
"ssh",
"scp",
"sftp",
}

ALLOWED_COMMANDS: Final[set[str]] = {
"pwd",
"ls",
"find",
"cat",
"head",
"tail",
"grep",
"printf",
"echo",
"whoami",
"id",
"date",
"uname",
"python",
"python3",
"pip",
"pip3",
"git",
}

def normalize_command(command: str) -> str:
return command.strip()

def validate_command(command: str) -> list[str]:
normalized_command = normalize_command(command)

if not normalized_command:
    raise HTTPException(
        status_code=400,
        detail="الأمر فارغ.",
    )

if len(normalized_command) > MAX_COMMAND_LENGTH:
    raise HTTPException(
        status_code=413,
        detail="الأمر يتجاوز الحد الأقصى المسموح.",
    )

if "\x00" in normalized_command:
    raise HTTPException(
        status_code=400,
        detail="الأمر يحتوي على محرف غير صالح.",
    )

try:
    arguments = shlex.split(normalized_command)
except ValueError as error:
    raise HTTPException(
        status_code=400,
        detail="صيغة الأمر غير صحيحة.",
    ) from error

if not arguments:
    raise HTTPException(
        status_code=400,
        detail="تعذر تحليل الأمر.",
    )

executable = Path(arguments[0]).name.lower()

if executable in BLOCKED_COMMANDS:
    raise HTTPException(
        status_code=403,
        detail=f"الأمر '{executable}' محظور.",
    )

if executable not in ALLOWED_COMMANDS:
    raise HTTPException(
        status_code=403,
        detail=f"الأمر '{executable}' غير موجود في قائمة الأوامر المسموحة.",
    )

dangerous_tokens = {
    "&&",
    "||",
    ";",
    "|",
    ">",
    ">>",
    "<",
    "$(",
    "`",
}

for token in arguments:
    if token in dangerous_tokens:
        raise HTTPException(
            status_code=403,
            detail="Shell operators غير مسموحة.",
        )

return arguments

def safe_working_directory() -> Path:
return PROJECT_ROOT

async def execute_command(
command: str,
) -> dict[str, object]:
arguments = validate_command(command)

started_at = time.monotonic()

logger.info(
    "Terminal command requested: %s",
    " ".join(arguments),
)

try:
    process = await asyncio.create_subprocess_exec(
        *arguments,
        cwd=str(safe_working_directory()),
        stdin=asyncio.subprocess.DEVNULL,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env={
            "PATH": os.getenv(
                "PATH",
                "/usr/local/bin:/usr/bin:/bin",
            ),
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
        },
    )

    try:
        stdout, stderr = await asyncio.wait_for(
            process.communicate(),
            timeout=COMMAND_TIMEOUT_SECONDS,
        )
    except asyncio.TimeoutError:
        process.kill()

        await process.wait()

        logger.warning(
            "Terminal command timeout: %s",
            " ".join(arguments),
        )

        return {
            "success": False,
            "exit_code": -1,
            "stdout": "",
            "stderr": "انتهى وقت تنفيذ الأمر.",
        }

    duration_ms = round(
        (time.monotonic() - started_at) * 1000,
        2,
    )

    return {
        "success": process.returncode == 0,
        "exit_code": process.returncode,
        "stdout": stdout.decode(
            "utf-8",
            errors="replace",
        ),
        "stderr": stderr.decode(
            "utf-8",
            errors="replace",
        ),
        "duration_ms": duration_ms,
    }

except FileNotFoundError:
    return {
        "success": False,
        "exit_code": 127,
        "stdout": "",
        "stderr": "الأمر غير موجود في البيئة.",
    }

except OSError as error:
    logger.exception(
        "Operating system error while executing command.",
    )

    return {
        "success": False,
        "exit_code": 1,
        "stdout": "",
        "stderr": f"خطأ في نظام التشغيل: {error}",
    }

@app.get(
"/",
response_class=HTMLResponse,
)
async def terminal_page() -> str:
return """

<!DOCTYPE html><html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta
        name="viewport"
        content="width=device-width, initial-scale=1.0"
    >
    <title>SHAHEEN-YS Terminal</title><link
    rel="stylesheet"
    href="/static/terminal.css"
>

</head><body>
    <main class="terminal-page">
        <section class="terminal-card">
            <header class="terminal-header">
                <div>
                    <h1>SHAHEEN-YS Terminal</h1>
                    <p>طرفية التحكم المحلية</p>
                </div>            <span class="status-badge">
                متصل
            </span>
        </header>

        <div
            id="terminal-output"
            class="terminal-output"
            aria-live="polite"
        >
            <div class="terminal-line system">
                SHAHEEN-YS Terminal جاهز.
            </div>

            <div class="terminal-line system">
                اكتب help لمعرفة الأوامر الأساسية.
            </div>
        </div>

        <form
            id="terminal-form"
            class="terminal-form"
        >
            <span class="prompt">
                SHAHEEN-YS $
            </span>

            <input
                id="terminal-input"
                type="text"
                autocomplete="off"
                spellcheck="false"
                maxlength="4096"
                placeholder="اكتب الأمر..."
            >

            <button
                type="submit"
            >
                تنفيذ
            </button>
        </form>
    </section>
</main>

<script src="/static/terminal.js"></script>

</body>
</html>
"""@app.get("/health")
async def health() -> dict[str, object]:
return {
"status": "healthy",
"service": "terminal",
"project": "SHAHEEN-YS",
"working_directory": str(PROJECT_ROOT),
"active_sessions": len(ACTIVE_SESSIONS),
"max_sessions": MAX_SESSIONS,
}

@app.websocket("/ws")
async def terminal_websocket(
websocket: WebSocket,
) -> None:
if len(ACTIVE_SESSIONS) >= MAX_SESSIONS:
await websocket.close(
code=1013,
reason="Maximum terminal sessions reached.",
)

    return

await websocket.accept()

session_id = f"{id(websocket)}"

ACTIVE_SESSIONS.add(session_id)

logger.info(
    "Terminal session opened: %s",
    session_id,
)

try:
    while True:
        payload = await websocket.receive_text()

        try:
            data = json.loads(payload)
        except json.JSONDecodeError:
            await websocket.send_json(
                {
                    "success": False,
                    "error": "بيانات الطلب غير صالحة.",
                }
            )

            continue

        command = data.get("command")

        if not isinstance(command, str):
            await websocket.send_json(
                {
                    "success": False,
                    "error": "الأمر يجب أن يكون نصاً.",
                }
            )

            continue

        if command.strip() == "help":
            await websocket.send_json(
                {
                    "success": True,
                    "stdout": (
                        "الأوامر المسموحة:\n"
                        "pwd\n"
                        "ls\n"
                        "find\n"
                        "cat\n"
                        "head\n"
                        "tail\n"
                        "grep\n"
                        "echo\n"
                        "printf\n"
                        "whoami\n"
                        "id\n"
                        "date\n"
                        "uname\n"
                        "python\n"
                        "python3\n"
                        "pip\n"
                        "pip3\n"
                        "git\n"
                    ),
                    "stderr": "",
                }
            )

            continue

        result = await execute_command(command)

        await websocket.send_json(result)

except WebSocketDisconnect:
    logger.info(
        "Terminal session disconnected: %s",
        session_id,
    )

except Exception:
    logger.exception(
        "Unexpected terminal WebSocket error.",
    )

finally:
    ACTIVE_SESSIONS.discard(session_id)

PYTHON

log "تم إنشاء Backend الخاص بالـ Terminal."

}

create_terminal_javascript() {
cat > "${TERMINAL_JS}" << 'JAVASCRIPT'
(() => {
"use strict";

const outputElement = document.getElementById(
    "terminal-output",
);

const formElement = document.getElementById(
    "terminal-form",
);

const inputElement = document.getElementById(
    "terminal-input",
);

const protocol = window.location.protocol === "https:"
    ? "wss:"
    : "ws:";

const websocketUrl =
    `${protocol}//${window.location.host}/ws`;

let socket = null;

function appendOutput(
    text,
    className = "command-output",
) {
    const line = document.createElement("pre");

    line.className = `terminal-line ${className}`;

    line.textContent = text;

    outputElement.appendChild(line);

    outputElement.scrollTop =
        outputElement.scrollHeight;
}

function connect() {
    socket = new WebSocket(
        websocketUrl,
    );

    socket.addEventListener(
        "open",
        () => {
            appendOutput(
                "تم الاتصال بالـ Terminal.",
                "system",
            );
        },
    );

    socket.addEventListener(
        "message",
        (event) => {
            try {
                const response = JSON.parse(
                    event.data,
                );

                if (response.stdout) {
                    appendOutput(
                        response.stdout,
                        "stdout",
                    );
                }

                if (response.stderr) {
                    appendOutput(
                        response.stderr,
                        "stderr",
                    );
                }

                if (response.error) {
                    appendOutput(
                        response.error,
                        "stderr",
                    );
                }

            } catch (error) {
                appendOutput(
                    "تعذر قراءة استجابة الخادم.",
                    "stderr",
                );
            }
        },
    );

    socket.addEventListener(
        "close",
        () => {
            appendOutput(
                "تم إغلاق اتصال Terminal.",
                "stderr",
            );
        },
    );

    socket.addEventListener(
        "error",
        () => {
            appendOutput(
                "حدث خطأ في اتصال Terminal.",
                "stderr",
            );
        },
    );
}

formElement.addEventListener(
    "submit",
    (event) => {
        event.preventDefault();

        const command =
            inputElement.value.trim();

        if (!command) {
            return;
        }

        appendOutput(
            `SHAHEEN-YS $ ${command}`,
            "command",
        );

        if (
            !socket ||
            socket.readyState !== WebSocket.OPEN
        ) {
            appendOutput(
                "الاتصال غير متاح.",
                "stderr",
            );

            return;
        }

        socket.send(
            JSON.stringify({
                command,
            }),
        );

        inputElement.value = "";

        inputElement.focus();
    },
);

connect();

inputElement.focus();

})();
JAVASCRIPT

log "تم إنشاء JavaScript الخاص بالـ Terminal."

}

create_terminal_css() {
cat > "${TERMINAL_CSS}" << 'CSS'
:root {
color-scheme: dark;
font-family:
"Noto Sans Arabic",
"Segoe UI",
Arial,
sans-serif;
}

* {
  box-sizing: border-box;
  }

body {
margin: 0;
min-height: 100vh;
background: #0d1117;
color: #e6edf3;
}

.terminal-page {
min-height: 100vh;
padding: 24px;
display: flex;
align-items: center;
justify-content: center;
}

.terminal-card {
width: min(1100px, 100%);
overflow: hidden;
border: 1px solid #30363d;
border-radius: 14px;
background: #161b22;
box-shadow: 0 20px 50px rgba(0, 0, 0, 0.35);
}

.terminal-header {
min-height: 90px;
padding: 20px 24px;
display: flex;
align-items: center;
justify-content: space-between;
gap: 20px;
border-bottom: 1px solid #30363d;
}

.terminal-header h1 {
margin: 0;
font-size: 22px;
}

.terminal-header p {
margin: 6px 0 0;
color: #8b949e;
}

.status-badge {
padding: 7px 14px;
border-radius: 999px;
background: #238636;
color: #ffffff;
font-size: 13px;
}

.terminal-output {
height: 520px;
overflow-y: auto;
padding: 20px;
direction: ltr;
text-align: left;
background: #010409;
font-family:
"JetBrains Mono",
"Fira Code",
monospace;
}

.terminal-line {
margin: 0 0 10px;
white-space: pre-wrap;
word-break: break-word;
}

.system {
color: #79c0ff;
}

.command {
color: #e6edf3;
}

.stdout {
color: #7ee787;
}

.stderr {
color: #ff7b72;
}

.terminal-form {
min-height: 68px;
padding: 12px 16px;
display: flex;
align-items: center;
gap: 12px;
direction: ltr;
border-top: 1px solid #30363d;
}

.prompt {
color: #7ee787;
white-space: nowrap;
font-family: monospace;
}

#terminal-input {
flex: 1;
min-width: 0;
padding: 12px;
border: 1px solid #30363d;
border-radius: 8px;
outline: none;
background: #0d1117;
color: #e6edf3;
font-family: monospace;
}

#terminal-input:focus {
border-color: #58a6ff;
}

.terminal-form button {
padding: 12px 20px;
border: 0;
border-radius: 8px;
cursor: pointer;
background: #238636;
color: #ffffff;
font-weight: 700;
}

.terminal-form button:hover {
opacity: 0.9;
}

@media (max-width: 768px) {
.terminal-page {
padding: 10px;
}

.terminal-header {
    align-items: flex-start;
    flex-direction: column;
}

.terminal-form {
    align-items: stretch;
    flex-direction: column;
}

.prompt {
    display: none;
}

.terminal-form button {
    width: 100%;
}

}
CSS

log "تم إنشاء CSS الخاص بالـ Terminal."

}

create_terminal_documentation() {
local documentation_file="${TERMINAL_DIR}/README.md"

cat > "${documentation_file}" << 'MD'

SHAHEEN-YS Terminal

الوظيفة

واجهة Terminal عبر المتصفح للتعامل مع المشروع.

الأمان

يستخدم النظام:

- "asyncio.create_subprocess_exec"
- عدم استخدام "shell=True"
- قائمة أوامر مسموحة
- قائمة أوامر محظورة
- حد أقصى لطول الأمر
- مهلة تنفيذ
- حد أقصى للجلسات
- Working Directory محدد
- بيئة تشغيل محدودة
- تسجيل العمليات

تشغيل السيرفر

python3 shaheen_ys/webui/terminal/server.py

افتراضياً:

http://127.0.0.1:8090

تحذير

لا تعرض هذا السيرفر للإنترنت العام بدون:

- Authentication

- Authorization

- Rate Limiting

- CSRF Protection

- Audit Logging

- Container Isolation

- Network Policy
  MD
  
  log "تم إنشاء توثيق Terminal."
  }

update_requirements() {
local requirements_file="${PROJECT_ROOT}/requirements.txt"

touch "${requirements_file}"

if ! grep -q '^fastapi' "${requirements_file}"; then
    printf 'fastapi>=0.115,<1\n' >> "${requirements_file}"
fi

if ! grep -q '^uvicorn' "${requirements_file}"; then
    printf 'uvicorn[standard]>=0.34,<1\n' >> "${requirements_file}"
fi

log "تم تحديث requirements.txt."

}

create_terminal_launcher() {
local launcher="${PROJECT_ROOT}/run-terminal.sh"

cat > "${launcher}" << 'BASH'

#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export SHAHEEN_YS_PROJECT_ROOT="${PROJECT_ROOT}"
export SHAHEEN_YS_TERMINAL_HOST="${SHAHEEN_YS_TERMINAL_HOST:-127.0.0.1}"
export SHAHEEN_YS_TERMINAL_PORT="${SHAHEEN_YS_TERMINAL_PORT:-8090}"

exec python3 
-m uvicorn 
shaheen_ys.webui.terminal.server:app 
--host "${SHAHEEN_YS_TERMINAL_HOST}" 
--port "${SHAHEEN_YS_TERMINAL_PORT}"
BASH

chmod +x "${launcher}"

log "تم إنشاء مشغل Terminal."

}

create_python_init_files() {
touch 
"${PROJECT_ROOT}/shaheen_ys/init.py" 
"${PROJECT_ROOT}/shaheen_ys/webui/init.py" 
"${PROJECT_ROOT}/shaheen_ys/webui/terminal/init.py"

log "تم إنشاء ملفات Python package."

}

show_summary() {
printf '\n'

log "=============================================="
log "تم تنفيذ PASH4 بنجاح."
log "=============================================="

printf '\n'
printf '🖥️ Terminal Backend:\n'
printf '%s\n' "${TERMINAL_SERVER}"

printf '\n'
printf '🌐 Terminal URL محلياً:\n'
printf 'http://127.0.0.1:8090\n'

printf '\n'
printf '▶️ التشغيل:\n'
printf './run-terminal.sh\n'

printf '\n'
printf '❤️ Health:\n'
printf 'http://127.0.0.1:8090/health\n'

printf '\n'
printf '⚠️ الأوامر غير المسموحة لا يتم ت
