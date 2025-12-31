"""Custom middleware for the application.

This module provides middleware that can be added to the FastAPI app.
Common middleware patterns are included here.
"""

import time
import uuid
from collections.abc import Awaitable, Callable

from fastapi import FastAPI, Request, Response


async def request_id_middleware(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    """Add a unique request ID to each request.

    The request ID is:
    - Generated as a UUID4 if not provided in X-Request-ID header
    - Stored in request.state.request_id for access in handlers
    - Returned in X-Request-ID response header

    Usage in routes:
        @router.get("/example")
        async def example(request: Request):
            request_id = request.state.request_id
            return {"request_id": request_id}
    """
    request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
    request.state.request_id = request_id

    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id

    return response


async def timing_middleware(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    """Add request timing information to responses.

    Adds X-Process-Time header with the request processing time in seconds.
    """
    start_time = time.perf_counter()

    response = await call_next(request)

    process_time = time.perf_counter() - start_time
    response.headers["X-Process-Time"] = f"{process_time:.4f}"

    return response


def register_middleware(app: FastAPI) -> None:
    """Register custom middleware with the FastAPI app.

    Middleware is executed in reverse order of registration
    (last registered runs first).

    Args:
        app: FastAPI application instance
    """
    # Add timing middleware (runs last, measures total time)
    app.middleware("http")(timing_middleware)

    # Add request ID middleware (runs first)
    app.middleware("http")(request_id_middleware)
