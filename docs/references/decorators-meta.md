# Decorators & Metaprogramming

## Table of Contents
1. Writing Decorators Correctly
2. Parameterized Decorators
3. Class Decorators
4. functools.wraps — Always Use It
5. Descriptors
6. __slots__, __init_subclass__, __class_getitem__
7. When (Not) to Use Metaprogramming

---

## 1. Writing Decorators Correctly

A decorator is a function that takes a function and returns a (usually enhanced) function.

### Minimal Correct Pattern

```python
from functools import wraps
from typing import TypeVar, Callable, Any

F = TypeVar("F", bound=Callable[..., Any])

def log_calls(func: F) -> F:
    @wraps(func)          # ALWAYS use @wraps — preserves __name__, __doc__, etc.
    def wrapper(*args: Any, **kwargs: Any) -> Any:
        logger.debug("Calling %s", func.__name__)
        result = func(*args, **kwargs)
        logger.debug("%s returned %s", func.__name__, result)
        return result
    return wrapper  # type: ignore[return-value]

@log_calls
def calculate_total(items: list[Item]) -> float:
    return sum(i.price for i in items)
```

### Preserving Type Signatures (Python 3.12+ / ParamSpec)

```python
from typing import ParamSpec, TypeVar, Callable
from functools import wraps
import time

P = ParamSpec("P")
R = TypeVar("R")

def timer(func: Callable[P, R]) -> Callable[P, R]:
    @wraps(func)
    def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
        start = time.perf_counter()
        result = func(*args, **kwargs)
        elapsed = time.perf_counter() - start
        logger.info("%s took %.3fs", func.__name__, elapsed)
        return result
    return wrapper

@timer
def fetch_report(user_id: int, *, include_drafts: bool = False) -> Report:
    ...
# Mypy still knows: fetch_report(42, include_drafts=True) -> Report
```

### Async Decorators

```python
def retry_on_error(max_attempts: int = 3):
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            for attempt in range(1, max_attempts + 1):
                try:
                    return await func(*args, **kwargs)
                except TransientError as e:
                    if attempt == max_attempts:
                        raise
                    await asyncio.sleep(2 ** attempt)   # exponential backoff
        return wrapper
    return decorator

@retry_on_error(max_attempts=3)
async def fetch_data(url: str) -> dict: ...
```

---

## 2. Parameterized Decorators

A parameterized decorator is a function that returns a decorator.

```python
def require_role(*roles: str):
    """Usage: @require_role("admin", "editor")"""
    def decorator(func):
        @wraps(func)
        async def wrapper(request: Request, *args, **kwargs):
            if request.user.role not in roles:
                raise PermissionDeniedError(f"Requires one of: {roles}")
            return await func(request, *args, **kwargs)
        return wrapper
    return decorator

@require_role("admin")
async def delete_user(request: Request, user_id: int): ...

@require_role("admin", "editor")
async def update_content(request: Request, content_id: int): ...
```

### Decorator That Works With or Without Arguments

```python
def cache(func=None, *, maxsize: int = 128, ttl: float | None = None):
    """
    Can be used as @cache or @cache(maxsize=256, ttl=60)
    """
    if func is None:
        # Called with arguments: @cache(maxsize=256)
        return lambda f: cache(f, maxsize=maxsize, ttl=ttl)

    _store: dict = {}

    @wraps(func)
    def wrapper(*args, **kwargs):
        key = (args, tuple(sorted(kwargs.items())))
        if key in _store:
            return _store[key]
        result = func(*args, **kwargs)
        _store[key] = result
        return result

    wrapper.cache_clear = lambda: _store.clear()
    return wrapper

@cache
def get_config(key: str) -> str: ...

@cache(maxsize=50, ttl=300)
def fetch_remote(url: str) -> dict: ...
```

---

## 3. Class Decorators

```python
def singleton(cls):
    """Make a class a singleton — only one instance ever created."""
    instances = {}
    @wraps(cls)
    def get_instance(*args, **kwargs):
        if cls not in instances:
            instances[cls] = cls(*args, **kwargs)
        return instances[cls]
    return get_instance

@singleton
class AppCache:
    def __init__(self) -> None:
        self._store: dict = {}

# Prefer dependency injection over singleton for testability.
# Singletons make testing harder — use this sparingly.
```

---

## 4. functools.wraps — Always Use It

Without `@wraps`, your decorator destroys the function's identity:

```python
def bad_decorator(func):
    def wrapper(*args, **kwargs):
        return func(*args, **kwargs)
    return wrapper   # wrapper.__name__ = "wrapper", __doc__ = None

@bad_decorator
def calculate_tax(amount: float) -> float:
    """Calculate applicable tax."""
    ...

calculate_tax.__name__   # "wrapper"   ← WRONG
calculate_tax.__doc__    # None         ← lost
# Sphinx, pytest, debuggers all break

# With @wraps:
def good_decorator(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        return func(*args, **kwargs)
    return wrapper

@good_decorator
def calculate_tax(amount: float) -> float:
    """Calculate applicable tax."""
    ...

calculate_tax.__name__   # "calculate_tax"   ← correct
calculate_tax.__doc__    # "Calculate applicable tax."
```

---

## 5. Descriptors

Descriptors are objects that implement `__get__`, `__set__`, or `__delete__`.
They're the mechanism behind `@property`, `@classmethod`, and ORM fields.

```python
class ValidatedAttribute:
    """A descriptor that validates on assignment."""

    def __init__(self, min_val: float, max_val: float) -> None:
        self.min_val = min_val
        self.max_val = max_val
        self.name = ""   # set by __set_name__

    def __set_name__(self, owner: type, name: str) -> None:
        self.name = f"_{name}"   # use private backing attribute

    def __get__(self, obj: object, objtype: type | None = None) -> float:
        if obj is None:
            return self   # accessed on class, not instance
        return getattr(obj, self.name, 0.0)

    def __set__(self, obj: object, value: float) -> None:
        if not (self.min_val <= value <= self.max_val):
            raise ValueError(
                f"{self.name[1:]} must be between {self.min_val} and {self.max_val}, got {value}"
            )
        setattr(obj, self.name, value)


class Sensor:
    temperature = ValidatedAttribute(-50.0, 150.0)
    humidity    = ValidatedAttribute(0.0, 100.0)

    def __init__(self, temp: float, humidity: float) -> None:
        self.temperature = temp    # triggers __set__ — validated
        self.humidity = humidity

s = Sensor(25.0, 60.0)
s.temperature = 200.0    # raises ValueError: temperature must be between -50 and 150
```

---

## 6. __slots__, __init_subclass__, __class_getitem__

### `__slots__`

```python
class Point:
    __slots__ = ("x", "y")   # no __dict__ — saves ~200 bytes per instance

    def __init__(self, x: float, y: float) -> None:
        self.x, self.y = x, y

# Use when: creating millions of small objects (e.g., records, game entities)
# Do NOT use on base classes if subclasses add attributes
```

### `__init_subclass__` — Hook into Subclassing

```python
class Plugin:
    _registry: dict[str, type] = {}

    def __init_subclass__(cls, *, name: str, **kwargs) -> None:
        super().__init_subclass__(**kwargs)
        Plugin._registry[name] = cls

class EmailPlugin(Plugin, name="email"):
    def run(self) -> None: ...

class SlackPlugin(Plugin, name="slack"):
    def run(self) -> None: ...

# Plugin._registry == {"email": EmailPlugin, "slack": SlackPlugin}
# No explicit registration needed — happens at class definition time
```

### `__class_getitem__` — Custom Generics

```python
class TypedQueue:
    def __class_getitem__(cls, item_type: type) -> type:
        # Enables Queue[int] syntax for type hints
        return type(f"Queue[{item_type.__name__}]", (cls,), {"_type": item_type})
```

---

## 7. When (Not) to Use Metaprogramming

### Use decorators for:
- Cross-cutting concerns: logging, timing, retry, auth checking, caching
- Marking/tagging: `@router.get("/path")`, `@register_parser("csv")`
- Transforming classes: `@dataclass`, `@total_ordering`

### Use descriptors for:
- Attribute validation that's reused across many classes
- Computed attributes with complex get/set logic
- ORM column definitions

### Avoid metaprogramming when:
- A regular function or class would be simpler to read
- The "magic" would confuse someone who hasn't seen this pattern before
- You're 2+ levels of meta (decorators returning decorators returning decorators)

**The Metaprogramming Test**: If you have to write more than one paragraph to explain
what it does in a code review, reconsider. Good metaprogramming should make the
*call sites* simpler, not the implementation.
