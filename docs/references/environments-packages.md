# Environments & Package Management

## Table of Contents
1. Python Version Management (pyenv)
2. Virtual Environments
3. Dependency Management Tools
4. Dependency Security
5. Private Packages & Indexes
6. Environment Troubleshooting

---

## 1. Python Version Management (pyenv)

Never use the system Python for projects. Always use pyenv to manage versions.

```bash
# Install pyenv (macOS/Linux)
curl https://pyenv.run | bash

# Install a Python version
pyenv install 3.12.3
pyenv install 3.11.9

# Set version for a project directory
cd myproject
pyenv local 3.12.3    # creates .python-version file — commit this

# Set global default
pyenv global 3.12.3

# See installed versions
pyenv versions

# See available versions
pyenv install --list | grep "3.1"
```

### Windows: Use `py` launcher

```powershell
# Install from python.org or winget
winget install Python.Python.3.12

# Use specific version
py -3.12 -m venv .venv
py -3.11 script.py
```

---

## 2. Virtual Environments

**Always use a virtual environment. Never install into the system or global Python.**

### With venv (built-in, always available)

```bash
# Create
python -m venv .venv

# Activate
source .venv/bin/activate          # macOS/Linux
.venv\Scripts\activate              # Windows cmd
.venv\Scripts\Activate.ps1          # Windows PowerShell

# Verify
which python                        # should show .venv/bin/python

# Deactivate
deactivate

# Delete and recreate (clean slate)
rm -rf .venv && python -m venv .venv
```

### With uv (modern, fast — recommended)

```bash
# Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh   # macOS/Linux
powershell -c "irm https://astral.sh/uv/install.ps1 | iex"   # Windows

# Create + sync from pyproject.toml in one step
uv sync                  # creates .venv automatically

# Add packages
uv add fastapi pydantic
uv add --dev pytest ruff mypy

# Run in venv without activating
uv run pytest
uv run python -m myapp

# Lockfile
uv lock                  # update uv.lock from pyproject.toml
uv sync --frozen         # install exactly from lockfile (CI)
```

### .gitignore essentials

```gitignore
.venv/
venv/
env/
__pycache__/
*.pyc
.python-version        # only if you don't want to share the version
```

---

## 3. Dependency Management Tools

### Tool Comparison

| Tool | Use Case | Lockfile |
|---|---|---|
| **uv** | Fast, modern, everything in one | `uv.lock` |
| **Poetry** | Full-featured, publishing | `poetry.lock` |
| **pip-tools** | Deterministic deps, minimal | `requirements.txt` (pinned) |
| **pip + requirements.txt** | Simple scripts, legacy | manual |

### uv Workflow (Recommended)

```bash
# New project
uv init myproject
cd myproject

# Add runtime deps
uv add httpx "fastapi>=0.110" "pydantic>=2"

# Add dev deps (not in dist)
uv add --dev pytest pytest-cov ruff mypy black

# Optional dep groups
uv add --group docs sphinx sphinx-autodoc

# Remove
uv remove requests

# Upgrade all
uv lock --upgrade

# Upgrade specific package
uv lock --upgrade-package httpx

# Show dependency tree
uv tree
```

### pip-tools Workflow (Stable Alternative)

```bash
pip install pip-tools

# requirements.in — abstract deps (commit this)
fastapi>=0.110
pydantic>=2
httpx

# Compile to pinned requirements.txt
pip-compile requirements.in             # creates requirements.txt
pip-compile requirements-dev.in         # creates requirements-dev.txt

# Sync environment to lockfile
pip-sync requirements.txt requirements-dev.txt

# Upgrade all
pip-compile --upgrade requirements.in
```

### Minimal requirements.txt (scripts/small projects)

```text
fastapi==0.111.0
pydantic==2.7.1
httpx==0.27.0
uvicorn==0.29.0
```

---

## 4. Dependency Security

### Audit for Vulnerabilities

```bash
# pip-audit — scan installed packages for CVEs
pip install pip-audit
pip-audit

# Scan requirements file without installing
pip-audit -r requirements.txt

# uv audit (built-in)
uv audit

# Safety — another scanner
pip install safety
safety check
```

### Pinning Strategy

```python
# pyproject.toml — abstract constraints for libraries (allow upgrades)
dependencies = [
    "httpx>=0.27,<1.0",      # lower bound + upper bound to avoid breaking changes
    "pydantic>=2.0",
]

# For applications (deploy a specific version) — pin in lockfile
# uv.lock / poetry.lock pins exact versions
# requirements.txt pins exact versions (pip-compile output)
```

### Supply Chain Hygiene

```bash
# Verify package integrity with hashes (pip-compile --generate-hashes)
pip install --require-hashes -r requirements.txt

# Only install from trusted index
pip install --index-url https://pypi.org/simple/ fastapi

# Scan before adding new deps
pip-audit --package fastapi     # check a single package before adding

# Check license compatibility
pip install pip-licenses
pip-licenses --format=table
```

---

## 5. Private Packages & Indexes

```bash
# Install from private PyPI
pip install --extra-index-url https://pypi.company.com/simple/ mypackage

# In pyproject.toml (uv/poetry)
[[tool.uv.index]]
name = "company"
url = "https://pypi.company.com/simple/"
```

```toml
# pyproject.toml - publishing to PyPI or private index
[tool.hatch.publish.index]
url = "https://upload.pypi.org/legacy/"

# Or for TestPyPI
[tool.hatch.publish.test]
url = "https://test.pypi.org/legacy/"
```

### Install From Git

```bash
# Latest commit on main
pip install git+https://github.com/org/repo.git

# Specific tag
pip install git+https://github.com/org/repo.git@v1.2.3

# Specific commit
pip install git+https://github.com/org/repo.git@abc1234

# In pyproject.toml (uv)
uv add "mypackage @ git+https://github.com/org/repo.git@v1.2.3"
```

---

## 6. Environment Troubleshooting

```bash
# "module not found" — wrong Python
which python
python -c "import sys; print(sys.executable)"
# Should point to .venv — if not, activate the venv

# Find where a package is installed
python -c "import fastapi; print(fastapi.__file__)"

# List all installed packages
pip list
uv pip list

# Show package info including deps
pip show fastapi

# Why is this version installed?
pip-tree | grep httpx     # pip install pipdeptree
uv tree | grep httpx

# Clean up broken environment
rm -rf .venv
uv sync    # recreate from lockfile

# Check for conflicting requirements
pip check

# Find import errors early
python -c "import myapp"   # before running the full app
```
