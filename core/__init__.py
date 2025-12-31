"""Core utilities module.

This module provides reusable components for the application:
- dependencies: Common FastAPI dependencies (pagination, etc.)
- logging: Structured logging with structlog
- schemas: Standard response schemas (success, error, list)

Usage:
    from core.dependencies import get_pagination, PaginationParams
    from core.logging import get_logger
    from core.schemas import SuccessResponse, ErrorResponse, ListResponse
"""

from core.dependencies import PaginationParams, get_pagination
from core.logging import configure_logging, get_logger
from core.schemas import (
    ErrorResponse,
    ListResponse,
    PaginationMeta,
    SuccessResponse,
)

__all__ = [
    "PaginationParams",
    "get_pagination",
    "configure_logging",
    "get_logger",
    "SuccessResponse",
    "ErrorResponse",
    "ListResponse",
    "PaginationMeta",
]
