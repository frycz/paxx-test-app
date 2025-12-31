"""Shared Pydantic schemas for standard API responses.

This module provides consistent response schemas:
- SuccessResponse: For successful operations without data
- ErrorResponse: For error responses
- ListResponse: For paginated list responses
"""

from typing import Generic, TypeVar

from pydantic import BaseModel, Field

T = TypeVar("T")


class SuccessResponse(BaseModel):
    """Standard response for successful operations.

    Example:
        return SuccessResponse(message="User created successfully")
    """

    message: str = Field(description="Success message")


class ErrorResponse(BaseModel):
    """Standard response for errors.

    Matches the format used by exception handlers in core/exceptions.py.

    Example:
        return JSONResponse(
            status_code=400,
            content=ErrorResponse(
                message="Validation failed",
                detail="Email format is invalid"
            ).model_dump()
        )
    """

    message: str = Field(description="Error message")
    detail: str | None = Field(default=None, description="Additional error details")


class PaginationMeta(BaseModel):
    """Pagination metadata for list responses.

    Attributes:
        page: Current page number (1-indexed).
        page_size: Number of items per page.
        total_items: Total number of items across all pages.
        total_pages: Total number of pages.
    """

    page: int = Field(ge=1, description="Current page number")
    page_size: int = Field(ge=1, description="Items per page")
    total_items: int = Field(ge=0, description="Total number of items")
    total_pages: int = Field(ge=0, description="Total number of pages")


class ListResponse(BaseModel, Generic[T]):
    """Generic paginated list response.

    Example:
        class UserPublic(BaseModel):
            id: int
            email: str

        @router.get("/users", response_model=ListResponse[UserPublic])
        async def list_users(
            pagination: Annotated[PaginationParams, Depends(get_pagination)],
            db: Annotated[AsyncSession, Depends(get_db)],
        ):
            # Get total count
            total = await db.scalar(select(func.count(User.id)))

            # Get paginated items
            result = await db.execute(
                select(User)
                .offset(pagination.offset)
                .limit(pagination.limit)
            )
            items = result.scalars().all()

            return ListResponse(
                items=items,
                meta=PaginationMeta(
                    page=pagination.page,
                    page_size=pagination.page_size,
                    total_items=total,
                    total_pages=(total + pagination.page_size - 1) // pagination.page_size,
                )
            )

    Attributes:
        items: List of items for the current page.
        meta: Pagination metadata.
    """

    items: list[T] = Field(description="List of items")
    meta: PaginationMeta = Field(description="Pagination metadata")
