"""Health check API routes.

This module provides health check endpoints for monitoring application status.
"""

from fastapi import APIRouter, Response

from db.database import verify_database_connection

router = APIRouter()


@router.get("/health")
async def health_check(response: Response) -> dict[str, str]:
    """Health check endpoint.

    Verifies database connectivity and returns appropriate status.

    Returns:
        200: {"status": "healthy"} - All systems operational
        503: {"status": "unhealthy", "detail": "..."} - Database unreachable
    """
    if await verify_database_connection():
        return {"status": "healthy"}

    response.status_code = 503
    return {"status": "unhealthy", "detail": "Database connection failed"}
