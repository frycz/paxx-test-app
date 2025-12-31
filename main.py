"""paxx-test-app Application Entry Point.

This module provides the application factory and FastAPI app instance.
"""

import sys
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from core.exceptions import register_exception_handlers
from core.logging import configure_logging, get_logger
from core.middleware import register_middleware
from db.database import close_db, verify_database_connection
from features.health.routes import router as health_router
from settings import settings

# Configure logging before anything else
configure_logging(level=settings.log_level, format=settings.log_format)
logger = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Manage application lifespan events.

    Startup:
        - Validates database connectivity (fails fast if unreachable)

    Shutdown:
        - Closes all database connections gracefully
    """
    # Startup
    logger.info(
        "Application starting",
        app_name=settings.app_name,
        environment=settings.environment,
    )

    # Validate database connection (fail fast)
    if not await verify_database_connection():
        logger.critical("Failed to connect to database - shutting down")
        sys.exit(1)

    logger.info("Database connection verified")

    yield

    # Shutdown
    logger.info("Application shutting down - closing database connections")
    await close_db()
    logger.info("Shutdown complete")


def create_app() -> FastAPI:
    """Create and configure the FastAPI application.

    Returns:
        Configured FastAPI application instance.
    """
    app = FastAPI(
        title=settings.app_name,
        debug=settings.debug,
        lifespan=lifespan,
    )

    # Register exception handlers
    register_exception_handlers(app)

    # Register custom middleware
    register_middleware(app)

    # Configure CORS
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Register routers
    app.include_router(health_router, tags=["health"])

    return app


# Create application instance
app = create_app()
