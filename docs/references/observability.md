# Python Observability — Logging, Error Handling & Debugging

## Table of Contents
1. Logging Setup (stdlib)
2. Structured Logging with structlog
3. Exception Design
4. Exception Handling Patterns
5. Context Variables in Logs
6. Debugging Techniques
7. Profiling

---

## 1. Logging Setup (stdlib)

### Module-Level Logger (The Right Way)
```python
import logging

# Always get a named logger — never use root logger directly
logger = logging.getLogger(__name__)  # e.g., "myapp.services.user"

def create_user(name: str) -> User:
    logger.debug("Creating user: %s", name)
    try:
        user = User(name=name)
        logger.info("User created successfully", extra={"user_id": user.id})
        return user
    except DatabaseError:
        logger.exception("Failed to create user %s", name)
        raise
```

### Application-Level Configuration
Configure logging **once** at app entry point, never in library code:

```python
# main.py or app/__init__.py
import logging
import logging.config

LOGGING_CONFIG = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "standard": {
            "format": "%(asctime)s [%(levelname)s] %(name)s: %(message)s",
            "datefmt": "%Y-%m-%d %H:%M:%S",
        },
        "json": {
            "()": "pythonjsonlogger.jsonlogger.JsonFormatter",
            "format": "%(asctime)s %(levelname)s %(name)s %(message)s",
        },
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "standard",
            "stream": "ext://sys.stdout",
        },
        "file": {
            "class": "logging.handlers.RotatingFileHandler",
            "formatter": "json",
            "filename": "app.log",
            "maxBytes": 10_485_760,   # 10 MB
            "backupCount": 5,
        },
    },
    "root": {
        "level": "INFO",
        "handlers": ["console", "file"],
    },
    "loggers": {
        "myapp": {"level": "DEBUG", "propagate": True},
        "sqlalchemy.engine": {"level": "WARNING", "propagate": True},
    },
}

logging.config.dictConfig(LOGGING_CONFIG)
```

### Log Levels — When to Use Which
| Level | Use For |
|---|---|
| `DEBUG` | Fine-grained detail for diagnosing issues — only in dev |
| `INFO` | Significant events: startup, shutdown, key user actions |
| `WARNING` | Something unexpected but not fatal — app still works |
| `ERROR` | A specific operation failed — requires attention |
| `CRITICAL` | System-level failure — app may not recover |

### Lazy Formatting
```python
# BAD — string formatted even if log level filtered out
logger.debug("Processing %s items: %s" % (len(items), items))

# GOOD — deferred, only formatted if level is active
logger.debug("Processing %d items: %s", len(items), items)
```

---

## 2. Structured Logging with structlog

For production systems, structured (JSON) logs are far more searchable:

```bash
pip install structlog
```

```python
import structlog

logger = structlog.get_logger()

def process_order(order_id: int, user_id: int) -> None:
    log = logger.bind(order_id=order_id, user_id=user_id)
    log.info("order.processing_started")
    try:
        result = fulfill(order_id)
        log.info("order.fulfilled", total=result.total)
    except PaymentError as e:
        log.error("order.payment_failed", error=str(e), code=e.code)
        raise
```

Output:
```json
{"event": "order.processing_started", "order_id": 42, "user_id": 7, "timestamp": "..."}
{"event": "order.payment_failed", "order_id": 42, "code": "insufficient_funds", "..."}
```

---

## 3. Exception Design

### Custom Exception Hierarchy
```python
class AppError(Exception):
    """Root exception for all application-level errors.
    
    All exceptions the app raises intentionally should inherit from this.
    """
    def __init__(self, message: str, code: str | None = None) -> None:
        super().__init__(message)
        self.code = code


class ValidationError(AppError):
    """Input failed validation rules."""
    def __init__(self, field: str, message: str) -> None:
        super().__init__(f"{field}: {message}", code="VALIDATION_ERROR")
        self.field = field


class NotFoundError(AppError):
    """Requested resource does not exist."""
    def __init__(self, resource: str, identifier: str | int) -> None:
        super().__init__(
            f"{resource} with id={identifier!r} not found",
            code="NOT_FOUND",
        )
        self.resource = resource
        self.identifier = identifier


class ConflictError(AppError):
    """Operation conflicts with current state."""


class UnauthorizedError(AppError):
    """Caller lacks permission for this operation."""
```

### Exception Message Guidelines
- Be specific: `"User with id=42 not found"` not `"Not found"`
- Include context: `"Payment of $50.00 failed: card declined (code: insufficient_funds)"`
- Don't expose internal state: no stack traces or DB errors to end users
- Use codes for machine-readable error handling

---

## 4. Exception Handling Patterns

### Catch Specific Exceptions
```python
# BAD — catches everything including KeyboardInterrupt, SystemExit
try:
    result = risky_operation()
except:
    log("Something failed")

# BAD — still too broad
try:
    result = risky_operation()
except Exception:
    log("Something failed")

# GOOD — catch what you can handle
try:
    result = fetch_data(url)
except httpx.TimeoutException:
    logger.warning("Request timed out, retrying...")
    result = fetch_data(url, timeout=60)
except httpx.HTTPStatusError as e:
    logger.error("HTTP %d from %s", e.response.status_code, url)
    raise ServiceError(f"Upstream error: {e.response.status_code}") from e
```

### Exception Chaining (`raise X from Y`)
```python
try:
    conn = db.connect()
except psycopg2.OperationalError as e:
    raise DatabaseUnavailableError("Could not connect to primary DB") from e
    # The original traceback is preserved as __cause__
```

### `finally` for Cleanup
```python
resource = acquire_resource()
try:
    use(resource)
except ProcessingError:
    logger.exception("Processing failed")
    raise
finally:
    resource.release()  # always runs — success or failure
```

### Reraise Without Losing Traceback
```python
try:
    do_work()
except ValueError:
    logger.exception("Caught unexpected value error")
    raise  # bare raise — re-raises with original traceback intact
```

### Exception Groups (Python 3.11+)
```python
try:
    async with asyncio.TaskGroup() as tg:
        tg.create_task(fetch_users())
        tg.create_task(fetch_orders())
except* httpx.TimeoutException as eg:
    for exc in eg.exceptions:
        logger.error("Timeout: %s", exc)
```

---

## 5. Context Variables in Logs

Attach request/transaction IDs across call stack using `contextvars`:

```python
import logging
import uuid
from contextvars import ContextVar

request_id_var: ContextVar[str] = ContextVar("request_id", default="")

class RequestIdFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = request_id_var.get("")
        return True

# In middleware / request handler:
def handle_request(request):
    token = request_id_var.set(str(uuid.uuid4()))
    try:
        return process(request)
    finally:
        request_id_var.reset(token)
```

---

## 6. Debugging Techniques

### `breakpoint()` — Built-in Debugger (Python 3.7+)
```python
def buggy_function(data):
    breakpoint()   # drops into pdb; set PYTHONBREAKPOINT=0 to disable
    process(data)
```

### `pdb` Commands
| Command | Action |
|---|---|
| `n` | next line |
| `s` | step into |
| `c` | continue |
| `p expr` | print expression |
| `pp expr` | pretty-print |
| `l` | list source around current line |
| `u` / `d` | move up/down the call stack |
| `q` | quit |

### `icecream` for Quick Debug Printing
```bash
pip install icecream
```
```python
from icecream import ic

result = transform(data)
ic(result)  # prints: ic| result: {'key': 'value'}
```

### `rich.inspect` for Exploring Objects
```python
from rich import inspect
inspect(some_object, methods=True)
```

### Logging as Debugging
```python
logger.debug("State at checkpoint: items=%d, total=%.2f", len(items), total)
```

---

## 7. Profiling

### `cProfile` — Which Functions Are Slow
```bash
python -m cProfile -s cumulative myscript.py
python -m cProfile -o profile.stats myscript.py
```

```python
import cProfile
import pstats

with cProfile.Profile() as pr:
    result = expensive_function()

stats = pstats.Stats(pr)
stats.sort_stats("cumulative")
stats.print_stats(20)   # top 20 functions by cumulative time
```

### `line_profiler` — Line-Level Timing
```bash
pip install line_profiler
kernprof -l -v myscript.py
```
```python
@profile   # decorator added by kernprof
def slow_function():
    ...
```

### `memory_profiler` — Memory Usage
```bash
pip install memory-profiler
python -m memory_profiler myscript.py
```

### `py-spy` — Zero-Overhead Live Profiling
```bash
pip install py-spy
py-spy top --pid <PID>          # live top-style view
py-spy record -o profile.svg -- python myscript.py
```

### Rule: Profile Before Optimizing
Don't guess where bottlenecks are. Measure, then fix the top offenders.
