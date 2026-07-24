from __future__ import annotations

import os

from fastapi import FastAPI
from fastapi.responses import HTMLResponse


app = FastAPI(
    title="SHAHEEN-YS",
    description="منصة SHAHEEN-YS",
    version="1.0.0",
)


@app.get(
    "/",
    response_class=HTMLResponse,
)
async def dashboard() -> str:
    return """
    <!DOCTYPE html>
    <html lang="ar" dir="rtl">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport"
              content="width=device-width, initial-scale=1.0">
        <title>SHAHEEN-YS</title>
    </head>
    <body>
        <main>
            <h1>SHAHEEN-YS</h1>
            <p>منصة الذكاء الاصطناعي وإدارة الإضافات</p>
            <p>الحالة: تعمل</p>
        </main>
    </body>
    </html>
    """
