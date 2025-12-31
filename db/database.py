"""Database configuration and session management.

Uses SQLAlchemy 2.0 async API with connection pooling.
"""

from collections.abc import AsyncGenerator
from datetime import datetime
from typing import Annotated

from sqlalchemy import MetaData, func, text
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from settings import settings

# Naming convention for database constraints
# This ensures consistent naming across all databases
NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}

# Create async engine
engine = create_async_engine(
    settings.database_url,
    echo=settings.debug,
    pool_pre_ping=True,
)

# Create async session factory
async_session_factory = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


class Base(DeclarativeBase):
    """Base class for all SQLAlchemy models.

    Provides common metadata configuration with naming conventions.
    """

    metadata = MetaData(naming_convention=NAMING_CONVENTION)


# Type alias for primary key
IntPK = Annotated[int, mapped_column(primary_key=True)]


class TimestampMixin:
    """Mixin that adds created_at and updated_at timestamps to models."""

    created_at: Mapped[datetime] = mapped_column(
        server_default=func.now(),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )


class BaseModel(TimestampMixin, Base):
    """Base model with id and timestamps.

    All models should inherit from this class to get:
    - Auto-incrementing integer primary key (id)
    - created_at timestamp (set on insert)
    - updated_at timestamp (set on insert and update)

    Example:
        class User(BaseModel):
            __tablename__ = "users"

            email: Mapped[str] = mapped_column(unique=True)
            name: Mapped[str]
    """

    __abstract__ = True

    id: Mapped[IntPK]


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """FastAPI dependency that provides a database session.

    Usage:
        @router.get("/users")
        async def get_users(db: Annotated[AsyncSession, Depends(get_db)]):
            result = await db.execute(select(User))
            return result.scalars().all()

    The session is automatically closed after the request completes.
    """
    async with async_session_factory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise


async def init_db() -> None:
    """Initialize the database by creating all tables.

    This is useful for testing or initial development.
    For production, use Alembic migrations instead.
    """
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def close_db() -> None:
    """Close database connections.

    Call this during application shutdown.
    """
    await engine.dispose()


async def verify_database_connection() -> bool:
    """Verify database connectivity.

    Returns:
        True if database is reachable, False otherwise.
    """
    try:
        async with async_session_factory() as session:
            await session.execute(text("SELECT 1"))
        return True
    except Exception:
        return False
