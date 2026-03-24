.DEFAULT_GOAL := help
SHELL := /bin/bash

# Project settings
PROJECT := crs
PYTHON := python3.12
PIP := pip
VENV := .venv
VENV_PYTHON := $(VENV)/bin/python
VENV_PIP := $(VENV)/bin/pip

# Colors for output
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RESET := \033[0m

.PHONY: help
help: ## Show this help message
	@echo ""
	@echo "  Constitutional Reflective System"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""

# ------------------------------------------------------------
# Setup
# ------------------------------------------------------------

.PHONY: install
install: ## Install all dependencies into virtualenv
	$(PYTHON) -m venv $(VENV)
	$(VENV_PIP) install --upgrade pip
	$(VENV_PIP) install -e ".[dev]"
	@echo "$(GREEN)Installation complete. Activate with: source $(VENV)/bin/activate$(RESET)"

.PHONY: install-ci
install-ci: ## Install dependencies for CI (no venv)
	$(PIP) install -e ".[dev]"

# ------------------------------------------------------------
# Development
# ------------------------------------------------------------

.PHONY: dev
dev: ## Start development server with hot reload
	$(VENV_PYTHON) -m uvicorn crs.server.app:app --reload --host 0.0.0.0 --port 8000

.PHONY: server
server: ## Start production server
	$(VENV_PYTHON) -m uvicorn crs.server.app:app --host 0.0.0.0 --port 8000 --workers 4

.PHONY: worker
worker: ## Start background worker
	$(VENV_PYTHON) -m crs.worker.main

.PHONY: cli
cli: ## Show CLI help
	$(VENV_PYTHON) -m crs.cli --help

# ------------------------------------------------------------
# Database
# ------------------------------------------------------------

.PHONY: migrate
migrate: ## Run pending Alembic migrations
	$(VENV_PYTHON) -m alembic -c infrastructure/migrations/alembic.ini upgrade head

.PHONY: migrate-auto
migrate-auto: ## Auto-generate a new migration (usage: make migrate-auto MSG="description")
	$(VENV_PYTHON) -m alembic -c infrastructure/migrations/alembic.ini revision --autogenerate -m "$(MSG)"

.PHONY: migrate-down
migrate-down: ## Rollback one migration
	$(VENV_PYTHON) -m alembic -c infrastructure/migrations/alembic.ini downgrade -1

.PHONY: migrate-history
migrate-history: ## Show migration history
	$(VENV_PYTHON) -m alembic -c infrastructure/migrations/alembic.ini history --verbose

.PHONY: db-reset
db-reset: ## Drop and recreate database (DESTRUCTIVE)
	@echo "$(YELLOW)WARNING: This will destroy all data!$(RESET)"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	$(VENV_PYTHON) -m alembic -c infrastructure/migrations/alembic.ini downgrade base
	$(MAKE) migrate

# ------------------------------------------------------------
# Testing
# ------------------------------------------------------------

.PHONY: test
test: ## Run all tests
	$(VENV_PYTHON) -m pytest tests/ -v --tb=short

.PHONY: test-unit
test-unit: ## Run unit tests only
	$(VENV_PYTHON) -m pytest tests/unit/ -v --tb=short

.PHONY: test-integration
test-integration: ## Run integration tests (requires running postgres)
	$(VENV_PYTHON) -m pytest tests/integration/ -v --tb=short

.PHONY: test-cov
test-cov: ## Run tests with coverage report
	$(VENV_PYTHON) -m pytest tests/ --cov=packages --cov-report=term-missing --cov-report=html

# ------------------------------------------------------------
# Code Quality
# ------------------------------------------------------------

.PHONY: lint
lint: ## Run ruff linter
	$(VENV_PYTHON) -m ruff check packages/ tests/

.PHONY: lint-fix
lint-fix: ## Run ruff linter with auto-fix
	$(VENV_PYTHON) -m ruff check --fix packages/ tests/

.PHONY: format
format: ## Format code with ruff
	$(VENV_PYTHON) -m ruff format packages/ tests/

.PHONY: format-check
format-check: ## Check formatting without modifying files
	$(VENV_PYTHON) -m ruff format --check packages/ tests/

.PHONY: typecheck
typecheck: ## Run mypy type checker
	$(VENV_PYTHON) -m mypy packages/ --ignore-missing-imports

.PHONY: check
check: lint format-check typecheck ## Run all checks (lint + format + types)

# ------------------------------------------------------------
# API
# ------------------------------------------------------------

.PHONY: openapi-export
openapi-export: ## Export OpenAPI schema to docs/api/openapi.json
	$(VENV_PYTHON) -c "
import json
from crs.server.app import app
schema = app.openapi()
with open('docs/api/openapi.json', 'w') as f:
    json.dump(schema, f, indent=2)
print('Exported docs/api/openapi.json')
"

# ------------------------------------------------------------
# Docker
# ------------------------------------------------------------

.PHONY: docker-up
docker-up: ## Start all Docker services
	docker compose up -d

.PHONY: docker-up-redis
docker-up-redis: ## Start all Docker services including Redis
	docker compose --profile redis up -d

.PHONY: docker-up-dev
docker-up-dev: ## Start all Docker services including dev tools
	docker compose --profile dev up -d

.PHONY: docker-down
docker-down: ## Stop all Docker services
	docker compose down

.PHONY: docker-down-v
docker-down-v: ## Stop all Docker services and remove volumes (DESTRUCTIVE)
	docker compose down -v

.PHONY: docker-logs
docker-logs: ## Follow Docker service logs
	docker compose logs -f

.PHONY: docker-build
docker-build: ## Build Docker images
	docker compose build

.PHONY: docker-ps
docker-ps: ## Show Docker service status
	docker compose ps

# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------

.PHONY: clean
clean: ## Remove build artifacts and cache files
	find . -type f -name "*.pyc" -delete
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".mypy_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".ruff_cache" -exec rm -rf {} + 2>/dev/null || true
	rm -rf dist/ build/ htmlcov/ .coverage coverage.xml

.PHONY: clean-all
clean-all: clean ## Remove build artifacts and virtualenv
	rm -rf $(VENV)
