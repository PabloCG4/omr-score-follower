"""Structured logging configuration for the OMR API process."""

from __future__ import annotations

import logging
import sys


def configure_logging(level: str = "INFO") -> None:
    """Configure root logging once for uvicorn and application modules."""
    root_logger = logging.getLogger()
    if root_logger.handlers:
        root_logger.setLevel(level.upper())
        return

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(
        logging.Formatter(
            fmt="%(asctime)s %(levelname)s [%(name)s] %(message)s",
            datefmt="%Y-%m-%dT%H:%M:%S",
        )
    )
    root_logger.addHandler(handler)
    root_logger.setLevel(level.upper())
