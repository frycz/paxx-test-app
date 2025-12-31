# Production Dockerfile for paxx-test-app
# Multi-stage build for minimal image size

# Build stage
FROM python:3.12-slim AS builder

WORKDIR /app

# Install uv for fast dependency management
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Install dependencies first (cached layer)
COPY pyproject.toml uv.lock* ./
RUN uv sync --frozen --no-dev --no-install-project 2>/dev/null || uv sync --no-dev --no-install-project

# Copy source code and install project
COPY . .
RUN uv sync --frozen --no-dev 2>/dev/null || uv sync --no-dev

# Runtime stage
FROM python:3.12-slim

WORKDIR /app

# Copy only the virtual environment and application code
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app .

ENV PATH="/app/.venv/bin:$PATH"

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--workers", "4"]
