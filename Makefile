.PHONY: dev test lint format typecheck migrate migrate-new docker-build docker-up docker-down help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

dev: ## Run development server with hot reload
	uv run uvicorn main:app --reload

test: ## Run tests
	uv run pytest

lint: ## Run linter and fix issues
	uv run ruff check . --fix

format: ## Format code
	uv run ruff format .

typecheck: ## Run type checker
	uv run mypy .

migrate: ## Run database migrations
	uv run alembic upgrade head

migrate-new: ## Create new migration (usage: make migrate-new msg="Add users table")
	uv run alembic revision --autogenerate -m "$(msg)"

docker-build: ## Build Docker image
	docker build -t paxx_test_app .

docker-up: ## Start services with docker-compose
	docker-compose up -d

docker-down: ## Stop services
	docker-compose down
