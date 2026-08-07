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

    # Vision inference (Phase 5.5.3.C.2)
    vision_raster_dpi: float = Field(default=200.0, gt=0.0)
    vision_max_pages: int = Field(default=50, ge=1)
    vision_slice_height: int = Field(default=512, ge=64)
    vision_slice_width: int = Field(default=512, ge=64)
    vision_overlap_ratio: float = Field(default=0.2, ge=0.0, lt=1.0)
    vision_confidence_threshold: float = Field(default=0.25, ge=0.0, le=1.0)
    vision_device: str = "cpu"
    vision_weights_path: str | None = None
    vision_input_size: int = Field(default=518, ge=64)


@lru_cache
def get_settings() -> Settings:
    """Return a process-wide cached settings instance."""
    return Settings()
