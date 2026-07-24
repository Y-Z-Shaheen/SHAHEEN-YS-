from __future__ import annotations

import os

import requests


class GitHubClient:
    """
    عميل GitHub API.

    لا يتم تخزين التوكن داخل الكود.
    """

    def __init__(
        self,
        token: str | None = None,
    ) -> None:
        self.token = token or os.getenv(
            "GITHUB_TOKEN",
        )

        self.api_url = os.getenv(
            "GITHUB_API_URL",
            "https://api.github.com",
        )

    def get_repository(
        self,
        owner: str,
        repository: str,
    ) -> dict:
        if not self.token:
            raise RuntimeError(
                "GITHUB_TOKEN غير موجود."
            )

        response = requests.get(
            f"{self.api_url}/repos/"
            f"{owner}/{repository}",
            headers={
                "Authorization": (
                    f"Bearer {self.token}"
                ),
                "Accept": (
                    "application/vnd.github+json"
                ),
            },
            timeout=30,
        )

        response.raise_for_status()

        return response.json()
