# Web APIs — FastAPI, Flask, REST Design

## Table of Contents
1. FastAPI — Modern API Development
2. Flask — Lightweight APIs
3. REST Design Principles
4. Authentication Patterns
5. Request Validation & Error Responses
6. Middleware & Lifecycle
7. Testing APIs

---

## 1. FastAPI — Modern API Development

FastAPI is the default choice for new Python APIs: async-native, Pydantic-based,
auto-docs, type-safe.

### Project Structure

```
app/
├── main.py           ← app factory + include routers
├── routers/
│   ├── users.py
│   └── orders.py
├── models/           ← domain models (dataclasses / SQLAlchemy)
│   └── user.py
├── schemas/          ← Pydantic request/response shapes
│   └── user.py
├── services/         ← business logic
│   └── user_service.py
├── dependencies.py   ← FastAPI Depends() definitions
└── config.py         ← pydantic-settings
```

### Application Factory

```python
# main.py
from fastapi import FastAPI
from app.routers import users, orders
from app.middleware import add_middleware

def create_app() -> FastAPI:
    app = FastAPI(title="My API", version="1.0.0")
    add_middleware(app)
    app.include_router(users.router, prefix="/users", tags=["users"])
    app.include_router(orders.router, prefix="/orders", tags=["orders"])
    return app

app = create_app()
```

### Router Definition

```python
# routers/users.py
from fastapi import APIRouter, Depends, HTTPException, status
from app.schemas.user import UserCreate, UserResponse, UserUpdate
from app.services.user_service import UserService
from app.dependencies import get_user_service, get_current_user

router = APIRouter()

@router.post("/", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def create_user(
    payload: UserCreate,
    service: UserService = Depends(get_user_service),
) -> UserResponse:
    return await service.create(payload)

@router.get("/{user_id}", response_model=UserResponse)
async def get_user(
    user_id: int,
    service: UserService = Depends(get_user_service),
    current_user: User = Depends(get_current_user),
) -> UserResponse:
    user = await service.get(user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return user

@router.patch("/{user_id}", response_model=UserResponse)
async def update_user(
    user_id: int,
    payload: UserUpdate,
    service: UserService = Depends(get_user_service),
) -> UserResponse:
    return await service.update(user_id, payload)

@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_user(
    user_id: int,
    service: UserService = Depends(get_user_service),
) -> None:
    await service.delete(user_id)
```

### Pydantic Schemas

```python
# schemas/user.py
from pydantic import BaseModel, EmailStr, Field
from datetime import datetime

class UserBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    email: EmailStr

class UserCreate(UserBase):
    password: str = Field(..., min_length=8)

class UserUpdate(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=100)
    email: EmailStr | None = None
    # All fields optional — partial update (PATCH semantics)

class UserResponse(UserBase):
    id: int
    created_at: datetime
    is_active: bool

    model_config = {"from_attributes": True}  # read from ORM objects
```

### Dependency Injection

```python
# dependencies.py
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_session
from app.services.user_service import UserService

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/token")

async def get_db_session() -> AsyncSession:
    async with get_session() as session:
        yield session

def get_user_service(session: AsyncSession = Depends(get_db_session)) -> UserService:
    return UserService(session)

async def get_current_user(
    token: str = Depends(oauth2_scheme),
    service: UserService = Depends(get_user_service),
) -> User:
    user = await service.get_from_token(token)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user
```

### Background Tasks

```python
from fastapi import BackgroundTasks

@router.post("/orders/")
async def create_order(
    payload: OrderCreate,
    background_tasks: BackgroundTasks,
    service: OrderService = Depends(get_order_service),
) -> OrderResponse:
    order = await service.create(payload)
    background_tasks.add_task(send_confirmation_email, order)  # runs after response
    return order
```

---

## 2. Flask — Lightweight APIs

For simpler APIs, scripts that serve HTTP, or when FastAPI is overkill.

```python
from flask import Flask, request, jsonify, abort
from http import HTTPStatus

def create_app(config: dict | None = None) -> Flask:
    app = Flask(__name__)
    if config:
        app.config.update(config)

    from app.routes import users_bp
    app.register_blueprint(users_bp, url_prefix="/users")

    @app.errorhandler(404)
    def not_found(e):
        return jsonify(error="Not found"), HTTPStatus.NOT_FOUND

    @app.errorhandler(422)
    def unprocessable(e):
        return jsonify(error=str(e)), HTTPStatus.UNPROCESSABLE_ENTITY

    return app

# routes/users.py
from flask import Blueprint, request, jsonify

users_bp = Blueprint("users", __name__)

@users_bp.get("/<int:user_id>")
def get_user(user_id: int):
    user = user_service.get(user_id)
    if user is None:
        abort(404)
    return jsonify(user.to_dict())

@users_bp.post("/")
def create_user():
    data = request.get_json(force=True)
    # Validate manually or use marshmallow/flask-pydantic
    user = user_service.create(data)
    return jsonify(user.to_dict()), 201
```

---

## 3. REST Design Principles

### URL Design

```
# Nouns, not verbs. Actions are the HTTP methods.
GET    /users              → list users
POST   /users              → create user
GET    /users/42           → get user 42
PATCH  /users/42           → partial update
PUT    /users/42           → full replace
DELETE /users/42           → delete

# Nested resources for relationships
GET    /users/42/orders    → orders belonging to user 42
POST   /users/42/orders    → create order for user 42

# Use query params for filtering, sorting, pagination
GET    /orders?status=pending&sort=created_at&page=2&per_page=20
```

### HTTP Status Codes — Use Them Correctly

| Code | Meaning | When |
|---|---|---|
| 200 | OK | Successful GET, PATCH, PUT |
| 201 | Created | Successful POST |
| 204 | No Content | Successful DELETE |
| 400 | Bad Request | Invalid input, malformed JSON |
| 401 | Unauthorized | No/invalid credentials |
| 403 | Forbidden | Valid credentials, insufficient permissions |
| 404 | Not Found | Resource doesn't exist |
| 409 | Conflict | Duplicate, state conflict |
| 422 | Unprocessable Entity | Validation failed (FastAPI default) |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Internal Server Error | Unexpected server error |

### Response Shape

```python
# Consistent error format
{
    "detail": "User with email 'x@y.com' already exists",
    "code": "DUPLICATE_EMAIL",
    "field": "email"       # optional, for field-level errors
}

# List response with pagination
{
    "items": [...],
    "total": 247,
    "page": 2,
    "per_page": 20,
    "pages": 13
}
```

---

## 4. Authentication Patterns

### JWT Bearer Tokens

```python
from datetime import datetime, timedelta, timezone
import jwt   # pip install pyjwt

SECRET_KEY = settings.secret_key
ALGORITHM = "HS256"
TOKEN_EXPIRY = timedelta(hours=24)

def create_access_token(user_id: int) -> str:
    payload = {
        "sub": str(user_id),
        "iat": datetime.now(timezone.utc),
        "exp": datetime.now(timezone.utc) + TOKEN_EXPIRY,
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)

def decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except jwt.ExpiredSignatureError:
        raise UnauthorizedError("Token has expired")
    except jwt.InvalidTokenError:
        raise UnauthorizedError("Invalid token")
```

### API Key Auth

```python
from fastapi.security import APIKeyHeader

api_key_header = APIKeyHeader(name="X-API-Key")

async def verify_api_key(
    api_key: str = Depends(api_key_header),
) -> APIClient:
    client = await api_key_service.get_client(api_key)
    if client is None:
        raise HTTPException(status_code=401, detail="Invalid API key")
    return client
```

### Password Hashing

```python
import bcrypt   # pip install bcrypt

def hash_password(plain: str) -> str:
    return bcrypt.hashpw(plain.encode(), bcrypt.gensalt()).decode()

def verify_password(plain: str, hashed: str) -> bool:
    return bcrypt.checkpw(plain.encode(), hashed.encode())
```

---

## 5. Request Validation & Error Responses

### FastAPI Global Exception Handler

```python
from fastapi import Request
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from app.exceptions import AppError, NotFoundError, ValidationError as AppValidationError

def add_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(RequestValidationError)
    async def validation_handler(request: Request, exc: RequestValidationError):
        return JSONResponse(
            status_code=422,
            content={
                "detail": "Validation failed",
                "errors": exc.errors(),
            },
        )

    @app.exception_handler(NotFoundError)
    async def not_found_handler(request: Request, exc: NotFoundError):
        return JSONResponse(status_code=404, content={"detail": str(exc)})

    @app.exception_handler(AppError)
    async def app_error_handler(request: Request, exc: AppError):
        return JSONResponse(status_code=400, content={"detail": str(exc), "code": exc.code})
```

---

## 6. Middleware & Lifecycle

```python
from fastapi import FastAPI
from starlette.middleware.cors import CORSMiddleware
from starlette.middleware.gzip import GZipMiddleware
import time, uuid

def add_middleware(app: FastAPI) -> None:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.add_middleware(GZipMiddleware, minimum_size=1000)

# Custom middleware — request ID + timing
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

class RequestLoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        request_id = str(uuid.uuid4())[:8]
        start = time.perf_counter()
        response = await call_next(request)
        duration_ms = (time.perf_counter() - start) * 1000
        logger.info(
            "request completed",
            extra={
                "request_id": request_id,
                "method": request.method,
                "path": request.url.path,
                "status": response.status_code,
                "duration_ms": round(duration_ms, 2),
            }
        )
        response.headers["X-Request-ID"] = request_id
        return response

# Lifespan — startup/shutdown (replaces on_event, FastAPI 0.95+)
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    await database.connect()
    await cache.ping()
    yield                   # app runs here
    await database.disconnect()
    await cache.close()

app = FastAPI(lifespan=lifespan)
```

---

## 7. Testing APIs

```python
# With FastAPI — use TestClient (sync) or AsyncClient (async)
from fastapi.testclient import TestClient
import pytest

@pytest.fixture
def client(app: FastAPI) -> TestClient:
    return TestClient(app)

def test_create_user_returns_201(client: TestClient):
    response = client.post("/users/", json={"name": "Pat", "email": "pat@x.com", "password": "secure123"})
    assert response.status_code == 201
    assert response.json()["email"] == "pat@x.com"

def test_get_missing_user_returns_404(client: TestClient):
    response = client.get("/users/99999")
    assert response.status_code == 404

# Async test client
import pytest_asyncio
from httpx import AsyncClient

@pytest.mark.asyncio
async def test_create_user_async(app: FastAPI):
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.post("/users/", json={...})
    assert response.status_code == 201
```
