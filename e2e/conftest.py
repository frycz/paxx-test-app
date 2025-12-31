"""E2E test fixtures.

These tests run against a live API server. Set APP_URL environment
variable to point to the server (defaults to http://localhost:8000).
"""

import os

import httpx
import pytest


@pytest.fixture
def app_url() -> str:
    """Get the application URL from environment."""
    return os.environ.get("APP_URL", "http://localhost:8000")


@pytest.fixture
def client(app_url: str):
    """HTTP client for making requests to the API."""
    with httpx.Client(base_url=app_url) as c:
        yield c
