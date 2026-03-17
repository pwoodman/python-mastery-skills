# Databases — SQLAlchemy, Alembic & Patterns

## Table of Contents
1. SQLAlchemy ORM — Models & Relationships
2. Async SQLAlchemy (2.x style)
3. Querying Patterns
4. Alembic — Migrations
5. Connection Pooling
6. Repository Pattern in Practice
7. Raw SQL Safety
8. Common Pitfalls

---

## 1. SQLAlchemy ORM — Models & Relationships

### Base Setup

```python
# database.py
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

class Base(DeclarativeBase):
    pass

engine = create_engine(settings.database_url, echo=False)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)
```

### Model Definition (SQLAlchemy 2.x mapped_column style)

```python
# models/user.py
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy import String, Boolean, ForeignKey, func
from datetime import datetime
from app.database import Base

class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100))
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        server_default=func.now(), nullable=False
    )

    orders: Mapped[list["Order"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",   # delete orders when user deleted
        lazy="select",                   # explicit: no auto-loading surprises
    )

    def __repr__(self) -> str:
        return f"User(id={self.id!r}, email={self.email!r})"


class Order(Base):
    __tablename__ = "orders"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    status: Mapped[str] = mapped_column(String(50), default="pending")
    total: Mapped[float] = mapped_column(default=0.0)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())

    user: Mapped["User"] = relationship(back_populates="orders")
    items: Mapped[list["OrderItem"]] = relationship(back_populates="order")
```

---

## 2. Async SQLAlchemy (FastAPI / async context)

```python
# database.py (async version)
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from contextlib import asynccontextmanager

engine = create_async_engine(
    settings.database_url,  # postgresql+asyncpg://user:pass@host/db
    pool_size=10,
    max_overflow=20,
    echo=False,
)
AsyncSessionFactory = async_sessionmaker(engine, expire_on_commit=False)

@asynccontextmanager
async def get_session() -> AsyncSession:
    async with AsyncSessionFactory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise

# FastAPI dependency
async def db_session() -> AsyncSession:
    async with get_session() as session:
        yield session
```

---

## 3. Querying Patterns

```python
from sqlalchemy import select, update, delete, func, and_, or_, text
from sqlalchemy.orm import selectinload, joinedload

# Select
async def get_user(session: AsyncSession, user_id: int) -> User | None:
    result = await session.execute(select(User).where(User.id == user_id))
    return result.scalar_one_or_none()

# Eager loading — avoid N+1 queries
async def get_user_with_orders(session: AsyncSession, user_id: int) -> User | None:
    stmt = (
        select(User)
        .where(User.id == user_id)
        .options(selectinload(User.orders))   # single extra query, not N
    )
    result = await session.execute(stmt)
    return result.scalar_one_or_none()

# Filter, order, paginate
async def list_orders(
    session: AsyncSession,
    *,
    user_id: int | None = None,
    status: str | None = None,
    page: int = 1,
    per_page: int = 20,
) -> tuple[list[Order], int]:
    stmt = select(Order)
    count_stmt = select(func.count()).select_from(Order)

    if user_id is not None:
        stmt = stmt.where(Order.user_id == user_id)
        count_stmt = count_stmt.where(Order.user_id == user_id)
    if status is not None:
        stmt = stmt.where(Order.status == status)
        count_stmt = count_stmt.where(Order.status == status)

    stmt = stmt.order_by(Order.created_at.desc())
    stmt = stmt.offset((page - 1) * per_page).limit(per_page)

    items = (await session.execute(stmt)).scalars().all()
    total = (await session.execute(count_stmt)).scalar_one()
    return list(items), total

# Upsert pattern
async def upsert_user(session: AsyncSession, data: dict) -> User:
    user = await get_user_by_email(session, data["email"])
    if user is None:
        user = User(**data)
        session.add(user)
    else:
        for key, value in data.items():
            setattr(user, key, value)
    await session.flush()   # get generated ID without committing
    return user

# Bulk insert (efficient)
from sqlalchemy.dialects.postgresql import insert as pg_insert

async def bulk_create_records(session: AsyncSession, rows: list[dict]) -> None:
    await session.execute(insert(Record), rows)  # SQLAlchemy bulk insert
```

### The N+1 Problem

```python
# PROBLEM — this runs 1 + N queries (one per user)
users = session.scalars(select(User)).all()
for user in users:
    print(user.orders)   # each access fires a new SELECT

# FIX — eager load with selectinload (2 queries total)
users = session.scalars(
    select(User).options(selectinload(User.orders))
).all()
for user in users:
    print(user.orders)   # no extra queries — already loaded
```

---

## 4. Alembic — Migrations

```bash
# Setup
alembic init alembic

# Generate migration from model changes (auto-detect)
alembic revision --autogenerate -m "add users table"

# Run migrations
alembic upgrade head

# Rollback one step
alembic downgrade -1

# Show history
alembic history --verbose

# Show current version
alembic current
```

### alembic.ini

```ini
sqlalchemy.url = %(DATABASE_URL)s  # use env var
```

### Migration File Pattern

```python
# alembic/versions/abc123_add_users_table.py
"""add users table"""
from alembic import op
import sqlalchemy as sa

def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("email", sa.String(255), unique=True, nullable=False),
        sa.Column("created_at", sa.DateTime, server_default=sa.func.now()),
    )
    op.create_index("ix_users_email", "users", ["email"])

def downgrade() -> None:
    op.drop_index("ix_users_email", "users")
    op.drop_table("users")
```

---

## 5. Connection Pooling

```python
# Sync engine
engine = create_engine(
    DATABASE_URL,
    pool_size=5,          # persistent connections
    max_overflow=10,      # burst capacity
    pool_timeout=30,      # seconds to wait for connection
    pool_recycle=1800,    # recycle connections every 30 min (avoids stale)
    pool_pre_ping=True,   # test connection before use (handles dropped connections)
)

# Async engine (production recommended settings)
engine = create_async_engine(
    DATABASE_URL,         # postgresql+asyncpg://...
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True,
    pool_recycle=3600,
)
```

**Rule**: `pool_pre_ping=True` is almost always worth it — prevents `OperationalError` after network interruptions or database restarts.

---

## 6. Repository Pattern in Practice

```python
# repositories/user_repository.py
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.models import User

class UserRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def get(self, user_id: int) -> User | None:
        return await self._session.get(User, user_id)

    async def get_by_email(self, email: str) -> User | None:
        result = await self._session.execute(
            select(User).where(User.email == email)
        )
        return result.scalar_one_or_none()

    async def save(self, user: User) -> User:
        self._session.add(user)
        await self._session.flush()   # assigns ID, within transaction
        return user

    async def delete(self, user: User) -> None:
        await self._session.delete(user)

    async def exists_email(self, email: str) -> bool:
        result = await self._session.execute(
            select(func.count()).where(User.email == email)
        )
        return result.scalar_one() > 0
```

---

## 7. Raw SQL Safety

**Never format user input into SQL strings.** Always parameterize.

```python
# DANGEROUS — SQL injection vulnerability
user_id = request.args["id"]
db.execute(f"SELECT * FROM users WHERE id = {user_id}")   # NEVER

# SAFE — parameterized
db.execute(text("SELECT * FROM users WHERE id = :user_id"), {"user_id": user_id})
db.execute(select(User).where(User.id == user_id))   # ORM is safe by default
```

---

## 8. Common Pitfalls

| Pitfall | Fix |
|---|---|
| `expire_on_commit=True` (default) causes LazyLoadError after commit | `expire_on_commit=False` in async, or eager load before commit |
| `lazy="dynamic"` on relationships | Use `lazy="select"` + `selectinload` in queries |
| No `pool_pre_ping` → stale connection errors | Always set `pool_pre_ping=True` in production |
| Missing index on FK columns | Add `index=True` to all ForeignKey columns |
| Loading ORM objects then calling `len()` or `in` | Use SQL `COUNT` and `EXISTS` queries |
| Auto-migration in production | Run `alembic upgrade head` as deployment step, never on startup |
| Forgetting `async with session.begin()` | Use the context manager — rollback is automatic on exception |
