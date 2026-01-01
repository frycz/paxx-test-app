# paxx-test-app

A FastAPI application built with paxx conventions

## Getting Started

### Option 1: Docker (Recommended)

```bash
# Start the app with PostgreSQL
docker compose up

# The API is available at http://localhost:8000
# PostgreSQL is available at localhost:5432
```

### Option 2: Local Development with Dockerized Postgres

```bash
# Start just the database
docker compose up db -d

# Install dependencies
uv sync --all-extras

# Run the development server
uv run paxx start
```

### Option 3: Local Development with External Database

```bash
# Install dependencies
uv sync --all-extras

# Set your database URL in settings.py or via environment variable
export DATABASE_URL="postgresql://user:password@host:5432/dbname"

# Run the development server
uv run paxx start
```

### Database Migrations

```bash
# Create a new migration
uv run paxx db migrate "description"

# Apply migrations
uv run paxx db upgrade

# Revert last migration
uv run paxx db downgrade
```

### Creating Features

```bash
# Create a new domain feature
uv run paxx feature create users
```

## Project Structure

```
paxx-test-app/
├── main.py              # Application entry point
├── settings.py          # Configuration
├── conftest.py          # Pytest fixtures
├── alembic.ini          # Alembic configuration
├── core/                # Core utilities
│   ├── exceptions.py    # Custom exceptions
│   ├── middleware.py    # Custom middleware
│   ├── dependencies.py  # FastAPI dependencies
│   └── schemas.py       # Pydantic schemas
├── db/                  # Database
│   ├── database.py      # Database setup
│   └── migrations/      # Alembic migrations
└── features/            # Domain features
    └── <feature_name>/
        ├── models.py    # SQLAlchemy models
        ├── schemas.py   # Pydantic schemas
        ├── services.py  # Business logic
        └── routes.py    # API endpoints
```

## License

MIT
