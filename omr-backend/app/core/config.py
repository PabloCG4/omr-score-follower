"""Application settings for the stateless OMR FastAPI service."""

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration loaded from environment variables when present."""

    model_config = SettingsConfigDict(
        env_prefix="OMR_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "Score Follower OMR API"
    max_upload_bytes: int = Field(default=50 * 1024 * 1024, ge=1024)
    mock_inference_delay_seconds: float = Field(default=2.0, ge=0.0)
    cors_allow_origins: list[str] = Field(
        default_factory=lambda: [
            "*",
        ]
    )
    log_level: str = "INFO"


@lru_cache
def get_settings() -> Settings:
    """Return a process-wide cached settings instance."""
    return Settings()
