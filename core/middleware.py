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


async def security_headers_middleware(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    """Add security headers to all responses.

    Headers added:
    - X-Content-Type-Options: nosniff - Prevents MIME type sniffing
    - X-Frame-Options: DENY - Prevents clickjacking via iframes
    - X-XSS-Protection: 1; mode=block - Legacy XSS filter (for older browsers)
    - Strict-Transport-Security - Forces HTTPS (only added on HTTPS requests)
    """
    response = await call_next(request)

    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"

    # Only add HSTS on HTTPS connections (browsers remember this)
    if request.url.scheme == "https":
        response.headers["Strict-Transport-Security"] = (
            "max-age=31536000; includeSubDomains"
        )

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

    # Add security headers middleware
    app.middleware("http")(security_headers_middleware)

    # Add request ID middleware (runs first)
    app.middleware("http")(request_id_middleware)
