# Deployment & Security

## Table of Contents
1. Docker — Containerizing Python Apps
2. Production Configuration
3. Health Checks & Readiness
4. Security — Input & Injection
5. Secrets Management
6. OWASP Top Issues for Python APIs
7. Rate Limiting & Abuse Protection

---

## 1. Docker — Containerizing Python Apps

### Multi-Stage Dockerfile (Production Pattern)

```dockerfile
# syntax=docker/dockerfile:1

# Stage 1: Build / dependency install
FROM python:3.12-slim AS builder

WORKDIR /app

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Copy dependency files first (cache layer)
COPY pyproject.toml uv.lock ./

# Install deps into /app/.venv
RUN uv sync --frozen --no-install-project --no-dev

# Stage 2: Runtime image
FROM python:3.12-slim AS runtime

# Security: don't run as root
RUN groupadd --system appgroup && useradd --system --gid appgroup appuser

WORKDIR /app

# Copy venv from builder
COPY --from=builder /app/.venv /app/.venv

# Copy application code
COPY src/ ./src/

# Set PATH to use venv
ENV PATH="/app/.venv/bin:$PATH"
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

USER appuser

EXPOSE 8000

CMD ["uvicorn", "myapp.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]
```

### .dockerignore

```
.venv/
__pycache__/
*.pyc
.git/
.env
.pytest_cache/
htmlcov/
dist/
.mypy_cache/
tests/
```

### docker-compose.yml (local development)

```yaml
version: "3.9"

services:
  app:
    build: .
    ports:
      - "8000:8000"
    environment:
      DATABASE_URL: postgresql+asyncpg://dev:dev@db/myapp
      SECRET_KEY: dev-secret-not-for-production
    depends_on:
      db:
        condition: service_healthy
    volumes:
      - ./src:/app/src   # hot reload in dev

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: dev
      POSTGRES_PASSWORD: dev
      POSTGRES_DB: myapp
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dev -d myapp"]
      interval: 5s
      retries: 5

volumes:
  postgres_data:
```

### Production-Ready Startup Command

```bash
# With Gunicorn + Uvicorn workers (production)
gunicorn myapp.main:app \
    --workers 4 \
    --worker-class uvicorn.workers.UvicornWorker \
    --bind 0.0.0.0:8000 \
    --timeout 30 \
    --graceful-timeout 30 \
    --keep-alive 5 \
    --access-logfile -

# Pure Uvicorn (simpler, single process or behind nginx)
uvicorn myapp.main:app --host 0.0.0.0 --port 8000 --workers 4
```

---

## 2. Production Configuration

```python
# config.py — pydantic-settings with environment validation
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # Required in production — pydantic raises if missing
    database_url: str
    secret_key: str

    # App
    environment: str = "development"
    log_level: str = "INFO"
    debug: bool = False

    # Performance
    db_pool_size: int = 10
    db_max_overflow: int = 20
    workers: int = 4

    @property
    def is_production(self) -> bool:
        return self.environment == "production"

    def validate_production(self) -> None:
        """Call at startup to catch misconfigurations early."""
        if self.is_production:
            assert len(self.secret_key) >= 32, "SECRET_KEY must be >= 32 chars"
            assert not self.debug, "DEBUG must be False in production"
            assert "localhost" not in self.database_url, "Cannot use localhost DB in production"
```

### 12-Factor Config Checklist

- All secrets and URLs come from environment variables — never hardcoded
- Different `.env` per environment (`.env.dev`, `.env.staging`, `.env.prod`)
- No `.env` files in Docker images — inject at runtime
- `DEBUG=False` in production
- `LOG_LEVEL=INFO` (or WARNING) in production — DEBUG fills disks fast

---

## 3. Health Checks & Readiness

```python
# FastAPI health endpoints
from fastapi import APIRouter
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_session

router = APIRouter(tags=["health"])

@router.get("/health")
async def health() -> dict:
    """Liveness probe — is the process alive?"""
    return {"status": "ok"}

@router.get("/ready")
async def ready(session: AsyncSession = Depends(get_session)) -> dict:
    """Readiness probe — can we handle traffic?"""
    try:
        await session.execute(text("SELECT 1"))
        return {"status": "ready", "database": "ok"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Database unavailable: {e}")
```

---

## 4. Security — Input & Injection

### SQL Injection — Parameterize Everything

```python
# VULNERABLE
user_input = request.args["search"]
db.execute(f"SELECT * FROM users WHERE name LIKE '%{user_input}%'")

# SAFE — SQLAlchemy ORM (always parameterized)
db.execute(select(User).where(User.name.ilike(f"%{search_term}%")))

# SAFE — raw SQL with params
db.execute(text("SELECT * FROM users WHERE name ILIKE :q"), {"q": f"%{search_term}%"})
```

### Command Injection — Never shell=True with User Input

```python
# VULNERABLE
filename = request.json()["filename"]
subprocess.run(f"convert {filename} output.png", shell=True)   # NEVER

# SAFE — list form, shell=False (default)
subprocess.run(["convert", filename, "output.png"])

# SAFE — sanitize path
from pathlib import Path
safe_path = Path(filename).name   # strip directory traversal
if not safe_path.endswith(".jpg"):
    raise ValidationError("Only JPG files allowed")
```

### Path Traversal

```python
# VULNERABLE
file_path = Path(settings.upload_dir) / user_provided_path
content = file_path.read_text()   # ../../../../etc/passwd

# SAFE — resolve and verify prefix
base = Path(settings.upload_dir).resolve()
target = (base / user_provided_path).resolve()
if not str(target).startswith(str(base)):
    raise SecurityError("Path traversal attempt")
content = target.read_text()
```

### Template Injection

```python
# VULNERABLE — Jinja2 with user-controlled template strings
template = jinja2.Template(user_input)   # can execute arbitrary code

# SAFE — render only trusted templates, user data as context vars
template = env.get_template("email/welcome.html")
rendered = template.render(user_name=user.name)   # never render user input as template
```

---

## 5. Secrets Management

### Never Hardcode Secrets

```python
# NEVER
API_KEY = "sk-real-key-1234567890"
DATABASE_URL = "postgresql://user:realpassword@host/db"

# ALWAYS
from app.config import settings
api_key = settings.stripe_api_key
db_url = settings.database_url
```

### Secrets in Production

```bash
# Docker secrets / environment injection
docker run -e SECRET_KEY="$(openssl rand -hex 32)" myapp

# AWS Secrets Manager (boto3)
import boto3, json
client = boto3.client("secretsmanager", region_name="us-east-1")
secret = json.loads(client.get_secret_value(SecretId="myapp/prod")["SecretString"])

# HashiCorp Vault
import hvac
vault = hvac.Client(url="https://vault.company.com", token=os.environ["VAULT_TOKEN"])
secret = vault.secrets.kv.v2.read_secret_version(path="myapp/prod")
```

### Rotating Secrets Safely

- Store secrets with a version identifier so you can rotate without downtime
- Use a grace period where both old and new secrets are valid
- Never log secrets — mask in error messages with `***`

---

## 6. OWASP Top Issues for Python APIs

| Issue | Python Manifestation | Fix |
|---|---|---|
| **Broken Auth** | Short/predictable tokens, no expiry | JWT with expiry, bcrypt passwords |
| **Injection** | `f"SELECT...{user_input}"` | Parameterized queries always |
| **Sensitive Data Exposure** | Passwords/keys in logs, responses | Pydantic `exclude=True`, mask in logs |
| **XML External Entity** | `etree.parse()` with user XML | `defusedxml` library |
| **Broken Access Control** | No per-object ownership check | Verify resource ownership in every endpoint |
| **Security Misconfiguration** | Debug mode in prod, broad CORS | Environment validation at startup |
| **XSS** | Returning HTML with user input unescaped | Jinja2 auto-escape on, `markupsafe.escape()` |
| **Insecure Deserialization** | `pickle.loads(user_data)` | Never pickle user data — use JSON/Pydantic |
| **Vulnerable Dependencies** | Unpatched packages | `pip-audit` in CI, update regularly |
| **Insufficient Logging** | No request logging, no audit trail | Structured logs with request IDs |

---

## 7. Rate Limiting & Abuse Protection

```python
# slowapi — rate limiting for FastAPI
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

@router.post("/auth/login")
@limiter.limit("5/minute")   # 5 login attempts per minute per IP
async def login(request: Request, credentials: LoginRequest) -> TokenResponse:
    ...

@router.get("/api/data")
@limiter.limit("100/minute")
async def get_data(request: Request) -> list[dict]:
    ...
```

### Input Size Limits

```python
# FastAPI — limit request body size
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

class RequestSizeLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, max_body_size: int = 10 * 1024 * 1024) -> None:  # 10 MB
        super().__init__(app)
        self.max_body_size = max_body_size

    async def dispatch(self, request: Request, call_next):
        if request.headers.get("content-length"):
            if int(request.headers["content-length"]) > self.max_body_size:
                return JSONResponse({"detail": "Request too large"}, status_code=413)
        return await call_next(request)
```
