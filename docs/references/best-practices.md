# Python Best Practices, Idioms & Design

**See also**: `senior-judgment.md` for when to use a class vs function vs module,
when to split, modularity decisions. This file covers the *how*; that file covers the *when*.

## Table of Contents
1. Pythonic Idioms
2. Functions — Design & Contracts
3. Classes — OOP Done Right
4. SOLID in Practice
5. Design Patterns Worth Knowing
6. Error Handling Design
7. Performance Patterns
8. Concurrency
9. Anti-Patterns Reference

---

## 1. Pythonic Idioms

### Unpacking
```python
a, b = b, a                          # swap
first, *rest = items                 # head/tail
head, *middle, tail = items          # split ends

for name, score in zip(names, scores):     # parallel iteration
    grade(name, score)

for i, item in enumerate(items, start=1):  # indexed iteration
    print(f"{i}. {item.title}")
```

### Dictionary
```python
value = config.get("timeout", 30)          # default, never KeyError
merged = base_config | overrides           # merge (3.9+)
grouped: dict[str, list] = defaultdict(list)
inverted = {v: k for k, v in mapping.items()}
```

### Iteration & Generators
```python
# Use itertools — don't hand-roll
from itertools import chain, groupby, islice, batched  # batched: 3.12+

# Generators — lazy, memory-efficient
def read_chunks(path: Path) -> Iterator[str]:
    with open(path) as f:
        while chunk := f.read(8192):
            yield chunk

# Walrus operator — avoid re-reading
while line := file.readline():
    process(line)
```

### Context Managers
```python
with open("data.csv") as f:
    data = f.read()

# Custom — @contextmanager for simple cases
from contextlib import contextmanager

@contextmanager
def database_transaction(session: Session) -> Iterator[Session]:
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
```

### Truthy/Falsy — Write It Directly
```python
if is_valid:         # not: if is_valid == True:
if not items:        # not: if items == []:
if value is None:    # not: if value == None:
label = "active" if user.is_active else "inactive"  # ternary for simple only
```

---

## 2. Functions — Design & Contracts

### One Level of Abstraction

The most violated rule. A function should operate at one "altitude" — don't mix
high-level orchestration with low-level string ops or SQL in the same function.

```python
# BAD — SQL + business logic + orchestration all mixed together
def process_order(order_id: int):
    row = db.execute(f"SELECT * FROM orders WHERE id={order_id}").fetchone()
    if row[3] != "pending": return
    charge_stripe(row[5], row[6])
    db.execute(f"UPDATE orders SET status='done' WHERE id={order_id}")

# GOOD — reads like a story, each call at the same zoom level
def process_order(order_id: int) -> Receipt:
    order = get_pending_order(order_id)
    receipt = charge_customer(order)
    mark_order_complete(order_id, receipt)
    return receipt
```

### Guard Clauses — Fail Fast, Keep Happy Path Unindented

```python
# BAD — actual work buried under nesting
def fulfill(order):
    if order is not None:
        if order.is_valid():
            if order.payment_method:
                return charge_and_ship(order)

# GOOD — guard up front, logic at top level
def fulfill(order: Order) -> Shipment:
    if order is None:
        raise ValueError("Order is required")
    if not order.is_valid():
        raise OrderValidationError(order.errors)
    if not order.payment_method:
        raise MissingPaymentMethodError(order.id)
    return charge_and_ship(order)
```

### Argument Design

```python
# Keyword-only after `*` — prevents positional confusion
def create_user(
    name: str,
    email: str,
    *,
    role: str = "viewer",
    send_welcome: bool = True,
) -> User: ...

# Self-documenting at call site:
create_user("Pat", "pat@x.com", role="admin", send_welcome=False)
# vs: create_user("Pat", "pat@x.com", "admin", False)  ← what is False?

# Flag arguments are a design smell — they hide two functions as one
def export(data, as_csv=False): ...   # BAD — does two different things
def export_as_json(data): ...         # GOOD — clear intent
def export_as_csv(data): ...
```

### Return Values

```python
# Return ONE type. Never str | None | list depending on mood.
def find_user(user_id: int) -> User | None: ...  # explicit: caller must handle None
def get_user(user_id: int) -> User: ...          # raises NotFoundError if missing

# Multiple return values → named container
@dataclass(frozen=True)
class ParseResult:
    value: Any
    warnings: list[str]
    source_line: int

def parse_record(line: str) -> ParseResult: ...
```

### Mutable Default Arguments — Classic Trap

```python
# BAD — `tags` list is shared across ALL calls
def create_product(name: str, tags: list[str] = []) -> Product:
    tags.append("unreviewed")    # mutates the shared default!

# GOOD
def create_product(name: str, tags: list[str] | None = None) -> Product:
    effective_tags = list(tags) if tags else ["unreviewed"]
```

### Command-Query Separation

Functions either DO something (command) or RETURN something (query). Not both.

```python
# BAD — action and return value mixed, side effect is hidden
def pop_and_notify(stack: list) -> str:
    item = stack.pop()
    notify_removed(item)
    return item

# GOOD
item = stack.pop()
notify_removed(item)
```

---

## 3. Classes — OOP Done Right

### Dataclasses for Data Containers

```python
from dataclasses import dataclass, field

@dataclass
class Invoice:
    customer_id: int
    line_items: list[LineItem] = field(default_factory=list)
    notes: str = ""

    @property
    def total(self) -> Decimal:
        return sum(item.amount for item in self.line_items)

# Use frozen=True for value objects that must be immutable
@dataclass(frozen=True)
class Money:
    amount: Decimal
    currency: str = "USD"

    def __add__(self, other: "Money") -> "Money":
        if self.currency != other.currency:
            raise CurrencyMismatchError(self.currency, other.currency)
        return Money(self.amount + other.amount, self.currency)
```

### Properties for Validation

```python
class Temperature:
    def __init__(self, celsius: float) -> None:
        self.celsius = celsius          # calls setter on init

    @property
    def celsius(self) -> float:
        return self._celsius

    @celsius.setter
    def celsius(self, value: float) -> None:
        if value < -273.15:
            raise ValueError(f"{value}°C is below absolute zero")
        self._celsius = value

    @property
    def fahrenheit(self) -> float:
        return self._celsius * 9/5 + 32
```

### Class, Static, and Instance Methods — Use the Right One

```python
class Report:
    def render(self) -> str:                          # instance: uses self
        return format_table(self.data)

    @classmethod
    def from_csv(cls, path: Path) -> "Report":        # factory: creates instances
        return cls(parse_csv(path))

    @staticmethod
    def validate_schema(row: dict) -> bool:           # utility: no self needed
        return all(k in row for k in ("id", "name", "amount"))
```

### Composition Over Inheritance

Inheritance is tight coupling. Prefer composition unless there's a genuine IS-A.

```python
# Inheritance — brittle, PremiumUser is locked to User's internals
class PremiumUser(User):
    def get_discount(self) -> float: ...

# Composition — loose coupling, individually testable
@dataclass
class User:
    profile: UserProfile
    subscription: Subscription | None = None

    @property
    def discount_rate(self) -> float:
        return self.subscription.discount if self.subscription else 0.0
```

Use inheritance when: implementing a Protocol/ABC, or a true IS-A that respects LSP.

---

## 4. SOLID in Practice

### Single Responsibility — One Reason to Change

```python
# BAD — one class does data + formatting + persistence
class Report:
    def build(self): ...
    def format_as_pdf(self): ...
    def save_to_disk(self): ...

# GOOD — each class has one reason to change
class ReportBuilder:    def build(self, filters: ReportFilters) -> ReportData: ...
class ReportFormatter:  def to_pdf(self, report: ReportData) -> bytes: ...
class ReportStore:      def save(self, report: ReportData, path: Path) -> None: ...
```

### Open/Closed — Extend, Don't Modify

```python
class NotificationChannel(Protocol):
    def send(self, message: str, recipient: str) -> None: ...

# Add channels by adding classes — never touch NotificationService
class EmailChannel:
    def send(self, message: str, recipient: str) -> None: ...

class SlackChannel:
    def send(self, message: str, recipient: str) -> None: ...

class NotificationService:
    def __init__(self, channels: list[NotificationChannel]) -> None:
        self._channels = channels

    def notify(self, message: str, recipient: str) -> None:
        for channel in self._channels:
            channel.send(message, recipient)
```

### Dependency Inversion — Inject, Don't Instantiate

```python
# BAD — can't test, can't swap implementations
class OrderService:
    def __init__(self):
        self.db = PostgresDatabase()   # hard-wired
        self.emailer = SmtpEmailer()   # hard-wired

# GOOD — injected Protocols, testable with mocks
class OrderService:
    def __init__(self, repository: OrderRepository, notifier: Notifier) -> None:
        self._repo = repository
        self._notifier = notifier
```

---

## 5. Design Patterns Worth Knowing

### Registry / Factory (Kills if/elif chains)

```python
_PARSERS: dict[str, type[Parser]] = {}

def register_parser(fmt: str):
    def decorator(cls: type[Parser]) -> type[Parser]:
        _PARSERS[fmt] = cls
        return cls
    return decorator

@register_parser("csv")
class CsvParser(Parser): ...

@register_parser("json")
class JsonParser(Parser): ...

def get_parser(fmt: str) -> Parser:
    cls = _PARSERS.get(fmt)
    if cls is None:
        raise ValueError(f"No parser for {fmt!r}")
    return cls()
```

### Repository Pattern

```python
class OrderRepository(Protocol):
    def get(self, order_id: int) -> Order | None: ...
    def save(self, order: Order) -> None: ...
    def find_by_customer(self, customer_id: int) -> list[Order]: ...

class SqlOrderRepository:
    def __init__(self, session: Session) -> None:
        self._session = session

    def get(self, order_id: int) -> Order | None:
        return self._session.get(Order, order_id)

    def save(self, order: Order) -> None:
        self._session.merge(order)
        self._session.flush()
```

### Strategy Pattern

```python
class PricingStrategy(Protocol):
    def calculate(self, base: Decimal, qty: int) -> Decimal: ...

class StandardPricing:
    def calculate(self, base: Decimal, qty: int) -> Decimal:
        return base * qty

class BulkPricing:
    def __init__(self, threshold: int, discount: float) -> None:
        self.threshold = threshold
        self.discount = Decimal(str(discount))

    def calculate(self, base: Decimal, qty: int) -> Decimal:
        multiplier = (1 - self.discount) if qty >= self.threshold else Decimal(1)
        return base * qty * multiplier
```

---

## 6. Error Handling Design

### Meaningful Exception Hierarchy

```python
class AppError(Exception):
    """All intentional errors. Unexpected ones should propagate."""
    def __init__(self, message: str, *, code: str | None = None) -> None:
        super().__init__(message)
        self.code = code

class ValidationError(AppError):
    def __init__(self, field: str, reason: str) -> None:
        super().__init__(f"{field}: {reason}", code="VALIDATION_FAILED")
        self.field = field

class NotFoundError(AppError):
    def __init__(self, resource: str, identifier: int | str) -> None:
        super().__init__(f"{resource} {identifier!r} not found", code="NOT_FOUND")
```

### Catch What You Can Handle — Nothing Else

```python
# BAD — hides real bugs, returns None silently
try:
    result = process(data)
except Exception:
    logger.error("Something failed")
    return None

# GOOD — specific, intentional
try:
    result = fetch_from_api(url)
except httpx.TimeoutException:
    logger.warning("API timeout, using cache")
    result = get_cached(url)
except httpx.HTTPStatusError as e:
    logger.error("HTTP %d from upstream", e.response.status_code)
    raise ServiceUnavailableError("upstream") from e
```

### Preserve Cause

```python
try:
    connect(host, port)
except OSError as e:
    raise DatabaseConnectionError(f"Cannot connect to {host}:{port}") from e
```

---

## 7. Performance Patterns

- Generators over lists when you don't need all values in memory
- `set`/`dict` for membership checks: O(1) vs `list`'s O(n)
- `lru_cache` for pure functions with repeated identical inputs
- `__slots__` for thousands of small instances
- `deque` for queues; `list` for stacks (right-end only)
- **Profile before optimizing** — `cProfile`, `py-spy`. Don't guess.

```python
from functools import lru_cache

@lru_cache(maxsize=512)
def get_tax_rate(region: str, year: int) -> float:
    return lookup_tax_config(region, year)
```

---

## 8. Concurrency

| Workload | Tool |
|---|---|
| I/O-bound (high concurrency) | `asyncio` + `async/await` |
| I/O-bound (simpler) | `ThreadPoolExecutor` |
| CPU-bound | `ProcessPoolExecutor` |

```python
async def fetch_all(urls: list[str]) -> list[dict]:
    async with httpx.AsyncClient(timeout=10) as client:
        responses = await asyncio.gather(
            *(client.get(url) for url in urls),
            return_exceptions=True,
        )
    return [r.json() for r in responses if not isinstance(r, Exception)]
```

**Never share mutable state across threads.** Use queues or message-passing.

---

## 9. Anti-Patterns Reference

| Anti-Pattern | Fix |
|---|---|
| `def f(lst=[])` mutable default | `def f(lst=None): lst = lst or []` |
| Bare `except:` | Catch specific exceptions |
| Flag argument `process(x, validate=True)` | Two functions with clear names |
| God class (20 unrelated methods) | Split by responsibility |
| Magic number `if status == 3:` | `PENDING = 3` or `Enum` |
| `import *` | Always explicit imports |
| `eval()` / `exec()` | `ast.literal_eval`, `json.loads` |
| Type suffix: `user_list: list[User]` | `users: list[User]` |
| Over-extracted 2-line helper used once | Inline it |
| Abstracting after first use | Rule of three — wait |
| `class Utils: @staticmethod...` namespace | Module with functions |
