"""Auth feature configuration."""

from dataclasses import dataclass, field


@dataclass
class AuthFeatureConfig:
    """Configuration for the auth feature.

    Attributes:
        name: The feature name (used for routing prefix).
        verbose_name: Human-readable name for the feature.
        description: Description of the feature's functionality.
        prefix: URL prefix for the feature's routes.
        tags: OpenAPI tags for the feature's routes.
    """

    name: str = "auth"
    verbose_name: str = "Authentication"
    description: str = "AWS Cognito user authentication and management"
    prefix: str = "/auth"
    tags: list[str] = field(default_factory=lambda: ["auth"])


feature_config = AuthFeatureConfig()
