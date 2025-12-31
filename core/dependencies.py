"""Shared FastAPI dependencies.

This module provides reusable dependencies for common patterns:
- Pagination parameters
"""

from typing import Annotated

from fastapi import Query
from pydantic import BaseModel


class PaginationParams(BaseModel):
    """Pagination parameters.

    Attributes:
        page: Current page number (1-indexed).
        page_size: Number of items per page.
    """

    page: int
    page_size: int

    @property
    def offset(self) -> int:
        """Calculate the offset for database queries."""
        return (self.page - 1) * self.page_size

    @property
    def limit(self) -> int:
        """Alias for page_size for database queries."""
        return self.page_size


def get_pagination(
    page: Annotated[int, Query(ge=1, description="Page number (1-indexed)")] = 1,
    page_size: Annotated[
        int, Query(ge=1, le=100, description="Number of items per page")
    ] = 20,
) -> PaginationParams:
    """Dependency for pagination parameters.

    Example:
        @router.get("/items")
        async def list_items(
            pagination: Annotated[PaginationParams, Depends(get_pagination)]
        ):
            items = await db.execute(
                select(Item)
                .offset(pagination.offset)
                .limit(pagination.limit)
            )
            return items.scalars().all()

    Args:
        page: Page number (1-indexed, default: 1).
        page_size: Number of items per page (default: 20, max: 100).

    Returns:
        PaginationParams with calculated offset and limit.
    """
    return PaginationParams(page=page, page_size=page_size)
