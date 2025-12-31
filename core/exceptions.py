"""Exception handlers and custom exceptions.

This module provides:
- Custom exception classes for common error scenarios
- Exception handlers that format errors consistently
"""

from fastapi import FastAPI, Request, status
from fastapi.responses import JSONResponse


class AppException(Exception):
    """Base exception for application errors.

    Provides consistent error response format.
    """

    def __init__(
        self,
        message: str,
        status_code: int = status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail: str | None = None,
    ) -> None:
        self.message = message
        self.status_code = status_code
        self.detail = detail
        super().__init__(message)


class NotFoundError(AppException):
    """Resource not found error.

    Example:
        raise NotFoundError("User not found", detail="User with id 123 does not exist")
    """

    def __init__(self, message: str = "Not found", detail: str | None = None) -> None:
        super().__init__(message, status.HTTP_404_NOT_FOUND, detail)


class BadRequestError(AppException):
    """Bad request error.

    Example:
        raise BadRequestError("Invalid input", detail="Email format is invalid")
    """

    def __init__(
        self, message: str = "Bad request", detail: str | None = None
    ) -> None:
        super().__init__(message, status.HTTP_400_BAD_REQUEST, detail)


class UnauthorizedError(AppException):
    """Unauthorized access error.

    Example:
        raise UnauthorizedError("Invalid credentials")
    """

    def __init__(
        self, message: str = "Unauthorized", detail: str | None = None
    ) -> None:
        super().__init__(message, status.HTTP_401_UNAUTHORIZED, detail)


class ForbiddenError(AppException):
    """Forbidden access error.

    Example:
        raise ForbiddenError("Insufficient permissions")
    """

    def __init__(self, message: str = "Forbidden", detail: str | None = None) -> None:
        super().__init__(message, status.HTTP_403_FORBIDDEN, detail)


class ConflictError(AppException):
    """Conflict error (e.g., duplicate resource).

    Example:
        raise ConflictError("User already exists", detail="Email already registered")
    """

    def __init__(self, message: str = "Conflict", detail: str | None = None) -> None:
        super().__init__(message, status.HTTP_409_CONFLICT, detail)


async def app_exception_handler(request: Request, exc: AppException) -> JSONResponse:
    """Handle AppException and subclasses.

    Returns a consistent JSON error response.
    """
    content = {"message": exc.message}
    if exc.detail:
        content["detail"] = exc.detail

    return JSONResponse(status_code=exc.status_code, content=content)


async def unhandled_exception_handler(
    request: Request, exc: Exception
) -> JSONResponse:
    """Handle unhandled exceptions.

    In production, this returns a generic error message.
    In development, additional details may be logged.
    """
    # Log the exception here if needed
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"message": "Internal server error"},
    )


def register_exception_handlers(app: FastAPI) -> None:
    """Register exception handlers with the FastAPI app.

    Args:
        app: FastAPI application instance
    """
    app.add_exception_handler(AppException, app_exception_handler)
    # Optionally add handler for unhandled exceptions
    # app.add_exception_handler(Exception, unhandled_exception_handler)
