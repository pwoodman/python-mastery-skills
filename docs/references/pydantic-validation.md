# Pydantic v2 & Validation

Pydantic is the foundation of modern Python data validation. Used in FastAPI, settings
management, data pipelines, and anywhere you need type-safe parsing of external data.

## Table of Contents
1. BaseModel — Core Patterns
2. Field Definitions
3. Validators — Custom Logic
4. Model Config
5. pydantic-settings — Environment Configuration
6. Common Patterns

---

## 1. BaseModel — Core Patterns

```python
from pydantic import BaseModel, Field, EmailStr
from datetime import datetime
from decimal import Decimal

class UserProfile(BaseModel):
    id: int
    name: str
    email: EmailStr           # validated email string
    score: float = 0.0        # default value
    tags: list[str] = []      # mutable defaults are safe in Pydantic
    metadata: dict[str, str] = {}
    created_at: datetime | None = None

# Parsing — Pydantic coerces types automatically
user = UserProfile(id="42", name="Pat", email="pat@example.com")
user.id            # int 42 (coerced from "42")
user.score         # float 0.0
user.model_dump()  # dict
user.model_dump_json()  # JSON string

# Parse from dict
data = {"id": 1, "name": "Alex", "email": "alex@x.com"}
user = UserProfile.model_validate(data)

# Parse from JSON string
user = UserProfile.model_validate_json('{"id": 1, "name": "Alex", "email": "alex@x.com"}')

# Strict mode — no coercion
user = UserProfile.model_validate(data, strict=True)
```

### Inheritance & Composition

```python
class UserBase(BaseModel):
    name: str
    email: EmailStr

class UserCreate(UserBase):
    password: str = Field(min_length=8)

class UserUpdate(BaseModel):
    # All optional for PATCH endpoints
    name: str | None = None
    email: EmailStr | None = None

class UserInDB(UserBase):
    id: int
    password_hash: str
    created_at: datetime

class UserResponse(UserBase):
    id: int
    created_at: datetime

    model_config = {"from_attributes": True}  # ORM compatibility
```

---

## 2. Field Definitions

```python
from pydantic import BaseModel, Field

class Product(BaseModel):
    id: int
    name: str = Field(
        ...,                    # required (no default)
        min_length=1,
        max_length=200,
        description="Product display name",
    )
    price: Decimal = Field(
        ...,
        gt=0,                   # greater than zero
        decimal_places=2,
    )
    discount: float = Field(
        default=0.0,
        ge=0.0,                 # >= 0
        le=1.0,                 # <= 1
    )
    sku: str = Field(
        ...,
        pattern=r"^[A-Z]{3}-\d{6}$",   # regex validation
        examples=["ABC-123456"],
    )
    quantity: int = Field(default=0, ge=0)
    tags: list[str] = Field(default_factory=list)
    internal_code: str = Field(
        ...,
        exclude=True,           # excluded from model_dump() / serialization
    )
    alias_field: str = Field(..., alias="externalFieldName")  # JSON key mapping
```

---

## 3. Validators — Custom Logic

```python
from pydantic import BaseModel, field_validator, model_validator, Field

class OrderCreate(BaseModel):
    item_ids: list[int]
    coupon_code: str | None = None
    subtotal: float
    discount: float = 0.0
    total: float

    @field_validator("item_ids")
    @classmethod
    def items_not_empty(cls, v: list[int]) -> list[int]:
        if not v:
            raise ValueError("Order must contain at least one item")
        return v

    @field_validator("coupon_code")
    @classmethod
    def normalize_coupon(cls, v: str | None) -> str | None:
        return v.upper().strip() if v else None

    @model_validator(mode="after")
    def validate_total(self) -> "OrderCreate":
        expected = self.subtotal - self.discount
        if abs(self.total - expected) > 0.01:
            raise ValueError(
                f"Total {self.total} doesn't match subtotal {self.subtotal}"
                f" minus discount {self.discount}"
            )
        return self
```

### Annotated Validators (reusable across models)

```python
from typing import Annotated
from pydantic import BeforeValidator, AfterValidator

def strip_and_lower(v: str) -> str:
    return v.strip().lower()

def must_be_nonempty(v: str) -> str:
    if not v:
        raise ValueError("Must not be empty")
    return v

# Compose validators with Annotated
NormalizedEmail = Annotated[str, BeforeValidator(strip_and_lower), AfterValidator(must_be_nonempty)]

class LoginRequest(BaseModel):
    email: NormalizedEmail
    password: str
```

---

## 4. Model Config

```python
from pydantic import BaseModel, ConfigDict

class ApiResponse(BaseModel):
    model_config = ConfigDict(
        from_attributes=True,    # parse from ORM objects (formerly orm_mode)
        populate_by_name=True,   # allow both alias and field name
        str_strip_whitespace=True, # strip whitespace from all str fields
        use_enum_values=True,    # serialize enums as their values
        validate_default=True,   # run validators on default values too
        frozen=True,             # immutable (like frozen dataclass)
        extra="ignore",          # silently drop unknown fields (vs "forbid" or "allow")
    )
```

### Serialization Control

```python
from pydantic import model_serializer, field_serializer

class User(BaseModel):
    name: str
    password_hash: str
    created_at: datetime

    @field_serializer("created_at")
    def serialize_dt(self, dt: datetime) -> str:
        return dt.isoformat()

    @field_serializer("password_hash")
    def hide_password(self, v: str) -> str:
        return "***"    # never expose in serialized form
```

---

## 5. pydantic-settings — Environment Configuration

The right way to handle configuration. Reads from `.env` files and environment variables.

```bash
pip install pydantic-settings python-dotenv
```

```python
# config.py
from pydantic import AnyUrl, Field
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # Database
    database_url: str = Field(..., description="PostgreSQL connection string")

    # Security
    secret_key: str = Field(..., min_length=32)
    access_token_expire_minutes: int = 1440  # 24 hours
    allowed_origins: list[str] = ["http://localhost:3000"]

    # App
    environment: str = "development"
    debug: bool = False
    log_level: str = "INFO"

    # External services
    stripe_api_key: str | None = None
    redis_url: str = "redis://localhost:6379/0"

    @property
    def is_production(self) -> bool:
        return self.environment == "production"


# Singleton — load once
settings = Settings()
```

```python
# .env.example (commit this)
DATABASE_URL=postgresql+asyncpg://user:pass@localhost/myapp
SECRET_KEY=change-me-to-a-32-character-random-string
ENVIRONMENT=development

# .env (gitignore this)
DATABASE_URL=postgresql+asyncpg://prod_user:real_pass@prod-host/myapp
SECRET_KEY=actually-random-secret-here
```

---

## 6. Common Patterns

### Discriminated Union (polymorphic payloads)

```python
from typing import Literal
from pydantic import BaseModel

class EmailNotification(BaseModel):
    type: Literal["email"]
    to: str
    subject: str

class SmsNotification(BaseModel):
    type: Literal["sms"]
    phone: str
    message: str

class WebhookNotification(BaseModel):
    type: Literal["webhook"]
    url: str
    payload: dict

Notification = EmailNotification | SmsNotification | WebhookNotification

class SendRequest(BaseModel):
    notifications: list[Notification]   # Pydantic picks the right class by `type`
```

### Partial Update (PATCH semantics)

```python
# Don't use Optional everywhere — use a sentinel
from pydantic import BaseModel
from typing import Any

_MISSING = object()   # sentinel for "not provided"

class UserUpdate(BaseModel):
    name: str | None = None
    email: str | None = None

    def to_update_dict(self) -> dict[str, Any]:
        """Only return fields that were explicitly set."""
        return self.model_dump(exclude_none=True)   # or exclude_unset=True
```

### Response Model with Computed Fields

```python
from pydantic import computed_field, BaseModel

class ProductResponse(BaseModel):
    id: int
    name: str
    price: float
    discount_rate: float

    @computed_field
    @property
    def final_price(self) -> float:
        return round(self.price * (1 - self.discount_rate), 2)
```
