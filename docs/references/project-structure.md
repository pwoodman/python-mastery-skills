# Python Project Structure, Packaging & Tooling

## Table of Contents
1. Project Layout
2. pyproject.toml (The Modern Standard)
3. Dependency Management
4. Virtual Environments
5. Package Building & Distribution
6. CI/CD Pipeline Setup
7. Environment & Secrets Management
8. Makefile / Task Runner

---

## 1. Project Layout

### Standard `src` Layout (Recommended)

```
my-project/
├── src/
│   └── myapp/
│       ├── __init__.py
│       ├── main.py
│       ├── models/
│       │   ├── __init__.py
│       │   ├── user.py
│       │   └── order.py
│       ├── services/
│       │   ├── __init__.py
│       │   ├── user_service.py
│       │   └── payment_service.py
│       ├── repositories/
│       │   ├── __init__.py
│       │   └── user_repository.py
│       └── utils/
│           ├── __init__.py
│           └── date_utils.py
├── tests/
│   ├── conftest.py
│   ├── unit/
│   └── integration/
├── docs/
├── scripts/
├── .github/
│   └── workflows/
│       └── ci.yml
├── pyproject.toml
├── README.md
├── .env.example
├── .gitignore
└── Makefile
```

### Why `src/` Layout?
- Prevents accidental imports of uninstalled package from working directory.
- Forces proper install (`pip install -e .`) before running.
- Cleaner separation of source from tests/scripts.

### `__init__.py` Strategy
```python
# myapp/__init__.py — expose clean public API
from myapp.models.user import User
from myapp.models.order import Order

__version__ = "1.0.0"
__all__ = ["User", "Order"]
```

---

## 2. pyproject.toml (The Modern Standard)

`pyproject.toml` is the single config file for everything Python (PEP 517/518/621).

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "myapp"
version = "1.0.0"
description = "Short description of what this does"
readme = "README.md"
requires-python = ">=3.10"
license = { text = "MIT" }
authors = [
  { name = "Your Name", email = "you@example.com" }
]
dependencies = [
  "httpx>=0.27",
  "pydantic>=2.0",
  "fastapi>=0.110",
]

[project.optional-dependencies]
dev = [
  "pytest>=8.0",
  "pytest-cov>=4.0",
  "pytest-asyncio>=0.23",
  "black>=24.0",
  "ruff>=0.3",
  "mypy>=1.9",
  "pre-commit>=3.6",
]

[project.scripts]
myapp = "myapp.main:cli"   # exposes `myapp` as a CLI command

[tool.hatch.build.targets.wheel]
packages = ["src/myapp"]

# --- Tool Configuration ---

[tool.black]
line-length = 88
target-version = ["py310"]

[tool.ruff]
line-length = 88
target-version = "py310"
select = ["E", "W", "F", "I", "B", "C4", "UP", "SIM"]

[tool.mypy]
python_version = "3.10"
strict = true
ignore_missing_imports = true

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "--cov=myapp --cov-report=term-missing -v"
asyncio_mode = "auto"

[tool.coverage.run]
branch = true
source = ["src/myapp"]

[tool.coverage.report]
fail_under = 80
show_missing = true
```

---

## 3. Dependency Management

### Option A: **uv** (Recommended — Fast, Modern)
```bash
# Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh

# Create project
uv init myapp
cd myapp
uv add httpx pydantic fastapi
uv add --dev pytest ruff black mypy

# Run commands
uv run pytest
uv run python -m myapp
uv sync             # sync venv from lockfile
uv lock             # update lockfile
```

### Option B: **Poetry** (Full Feature Set)
```bash
poetry new myapp
cd myapp
poetry add httpx pydantic
poetry add --group dev pytest ruff
poetry install
poetry run pytest
poetry build        # build wheel
poetry publish      # publish to PyPI
```

### Option C: **pip + requirements files** (Simple / Legacy)
```bash
# requirements.txt — production
httpx>=0.27
pydantic>=2.0

# requirements-dev.txt — development
-r requirements.txt
pytest>=8.0
black>=24.0
ruff>=0.3
```

### Pinning Strategy
- Production deps: pin **minimum** version (`httpx>=0.27`).
- Lockfiles pin **exact** versions for reproducibility.
- Never commit `*.egg-info/`, `dist/`, `.venv/` to git.

---

## 4. Virtual Environments

```bash
# Create
python -m venv .venv

# Activate
source .venv/bin/activate       # Linux/macOS
.venv\Scripts\activate           # Windows

# Deactivate
deactivate
```

### `.gitignore` Essentials
```gitignore
.venv/
__pycache__/
*.pyc
*.pyo
.pytest_cache/
.mypy_cache/
.ruff_cache/
htmlcov/
.coverage
dist/
build/
*.egg-info/
.env
```

---

## 5. Package Building & Distribution

```bash
# Build
pip install build
python -m build       # creates dist/*.whl and dist/*.tar.gz

# Check distribution
pip install twine
twine check dist/*

# Publish to PyPI
twine upload dist/*

# Publish to TestPyPI first
twine upload --repository testpypi dist/*
```

---

## 6. CI/CD Pipeline — GitHub Actions

### `.github/workflows/ci.yml`
```yaml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ["3.10", "3.11", "3.12"]

    steps:
      - uses: actions/checkout@v4

      - name: Install uv
        uses: astral-sh/setup-uv@v3

      - name: Set up Python ${{ matrix.python-version }}
        run: uv python install ${{ matrix.python-version }}

      - name: Install dependencies
        run: uv sync --all-extras --dev

      - name: Lint (Ruff)
        run: uv run ruff check .

      - name: Format check (Black)
        run: uv run black --check .

      - name: Type check (mypy)
        run: uv run mypy src/

      - name: Run tests
        run: uv run pytest --cov-report=xml

      - name: Upload coverage
        uses: codecov/codecov-action@v4
        with:
          file: ./coverage.xml
```

---

## 7. Environment & Secrets Management

### `.env` Pattern with `python-dotenv`
```python
# .env.example (committed — template only, no real values)
DATABASE_URL=postgresql://localhost:5432/myapp
SECRET_KEY=change-me-in-production
STRIPE_API_KEY=sk_test_...

# .env (gitignored — real values)
DATABASE_URL=postgresql://user:pass@prod-host/myapp
SECRET_KEY=super-secret-value
```

```python
# config.py
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str
    secret_key: str
    stripe_api_key: str
    debug: bool = False

    model_config = {"env_file": ".env"}

settings = Settings()
```

Use `pydantic-settings` for typed, validated environment configuration.

---

## 8. Makefile / Task Runner

```makefile
.PHONY: install lint format test coverage clean

install:
	uv sync --all-extras --dev
	uv run pre-commit install

lint:
	uv run ruff check .
	uv run mypy src/

format:
	uv run black .
	uv run ruff check . --fix

test:
	uv run pytest -v

coverage:
	uv run pytest --cov-report=html
	open htmlcov/index.html

clean:
	rm -rf .venv dist build __pycache__ .pytest_cache .mypy_cache htmlcov .coverage
```

Usage: `make install`, `make test`, `make lint`
