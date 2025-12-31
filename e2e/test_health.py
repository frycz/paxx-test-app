"""E2E tests for health check endpoint."""

import httpx


def test_health_returns_200(client: httpx.Client):
    """Health endpoint should return 200 when app is healthy."""
    response = client.get("/health")

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
