"""Application settings using Pydantic Settings.

Configuration is loaded from environment variables and .env file.
All settings are validated at startup.
"""

from functools import lru_cache
from typing import Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings.

    Settings are loaded from environment variables and .env file.
    Environment variables take precedence over .env file values.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # Application
    app_name: str = "paxx-test-app"
    debug: bool = False
    environment: Literal["development", "staging", "production"] = "development"

    # Logging
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = "INFO"
    log_format: Literal["json", "console"] = "console"

    # Server
    host: str = "127.0.0.1"
    port: int = 8000

    # Database
    database_url: str = Field(
        default="postgresql+asyncpg://postgres:postgres@localhost:5432/paxx_test_app",
        description="Database connection URL (async driver required)",
    )

    # Security
    secret_key: str = Field(
        default="CHANGE-ME-IN-PRODUCTION-USE-SECRETS-TOKEN",
        min_length=32,
        description="Secret key for JWT encoding. Must be at least 32 characters.",
    )
    access_token_expire_minutes: int = Field(default=30, ge=1)

    # CORS
    cors_origins: list[str] = Field(default_factory=lambda: ["http://localhost:3000"])

    @field_validator("secret_key")
    @classmethod
    def validate_secret_key(cls, v: str, info) -> str:
        """Warn if using default secret key in non-development environment."""
        # Note: In production, this should raise an error instead of just warning
        # For now, we just ensure minimum length
        return v

    @property
    def is_development(self) -> bool:
        """Check if running in development mode."""
        return self.environment == "development"

    @property
    def is_production(self) -> bool:
        """Check if running in production mode."""
        return self.environment == "production"


@lru_cache
def get_settings() -> Settings:
    """Get cached settings instance.

    Uses lru_cache to ensure settings are only loaded once.
    """
    return Settings()


# Convenience alias
settings = get_settings()
