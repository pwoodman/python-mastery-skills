# Python Type System — Annotations, Hints, Protocols, Generics

## Table of Contents
1. Type Annotation Basics
2. Built-in Type Hints (Python 3.10+)
3. Optional, Union, and Literal
4. Collections
5. Callable, TypeVar, Generics
6. Protocols (Structural Subtyping)
7. TypedDict & NamedTuple
8. TypeAlias & NewType
9. Overload
10. Running mypy

---

## 1. Type Annotation Basics

```python
# Variables
name: str = "Patrick"
count: int = 0
ratio: float = 0.75
active: bool = True
raw: bytes = b"data"

# Functions
def greet(name: str) -> str:
    return f"Hello, {name}"

def process(items: list[str]) -> None:
    for item in items:
        print(item)
```

Always annotate:
- Public function parameters and return types
- Class attributes
- Module-level variables that aren't obvious

Type annotations are **enforced by mypy**, not by Python at runtime.

---

## 2. Built-in Type Hints (Python 3.10+)

Python 3.9+ allows using built-in generics directly:

```python
# Python 3.10+ (no `from typing import ...` needed for basics)
def process(items: list[str]) -> dict[str, int]: ...
def lookup(mapping: dict[str, list[int]]) -> set[str]: ...
def pipe(fn: tuple[int, ...]) -> None: ...
```

Before 3.9, you needed `from typing import List, Dict, Set, Tuple`.

---

## 3. Optional, Union, and Literal

```python
from typing import Literal

# Optional (value or None)
def find_user(user_id: int) -> User | None:  # Python 3.10+
    ...

# Union of types
def parse(value: str | int | float) -> float:
    return float(value)

# Literal — constrain to specific values
def set_log_level(level: Literal["DEBUG", "INFO", "WARNING", "ERROR"]) -> None:
    ...

# Use | None over Optional[T] — cleaner in Python 3.10+
```

---

## 4. Collections

```python
from collections.abc import Sequence, Mapping, Iterator, Generator, Iterable

# Prefer abstract types in function signatures — more flexible
def total(values: Sequence[float]) -> float:  # accepts list, tuple, etc.
    return sum(values)

def lookup(config: Mapping[str, str]) -> str:  # accepts dict, OrderedDict, etc.
    return config.get("key", "")

# Generators
def count_up(n: int) -> Generator[int, None, None]:
    for i in range(n):
        yield i

# Iterator
def first(it: Iterator[int]) -> int | None:
    return next(it, None)
```

---

## 5. Callable, TypeVar, Generics

### Callable
```python
from collections.abc import Callable

# Callable[[arg_types], return_type]
def apply(fn: Callable[[int], str], value: int) -> str:
    return fn(value)

# Callable with no args
def run(task: Callable[[], None]) -> None:
    task()
```

### TypeVar — Generic Functions
```python
from typing import TypeVar

T = TypeVar("T")

def first(items: list[T]) -> T | None:
    return items[0] if items else None

# Constrained TypeVar
Numeric = TypeVar("Numeric", int, float)

def double(value: Numeric) -> Numeric:
    return value * 2
```

### Generic Classes (Python 3.12+ syntax)
```python
# Python 3.12+
class Stack[T]:
    def __init__(self) -> None:
        self._items: list[T] = []

    def push(self, item: T) -> None:
        self._items.append(item)

    def pop(self) -> T:
        return self._items.pop()

# Pre-3.12
from typing import Generic, TypeVar
T = TypeVar("T")

class Stack(Generic[T]):
    ...
```

---

## 6. Protocols (Structural Subtyping)

Protocols define interfaces without inheritance (duck typing + type safety):

```python
from typing import Protocol, runtime_checkable

class Drawable(Protocol):
    def draw(self) -> None: ...

class Circle:
    def draw(self) -> None:
        print("○")

class Square:
    def draw(self) -> None:
        print("□")

def render_all(shapes: list[Drawable]) -> None:
    for shape in shapes:
        shape.draw()

# Both Circle and Square satisfy Drawable without inheriting from it
render_all([Circle(), Square()])

# @runtime_checkable allows isinstance() checks
@runtime_checkable
class Closeable(Protocol):
    def close(self) -> None: ...

assert isinstance(open("f"), Closeable)
```

**Prefer Protocols over ABCs** when you want structural typing without coupling.

---

## 7. TypedDict & NamedTuple

### TypedDict — Typed Dict Structures
```python
from typing import TypedDict, NotRequired

class UserRecord(TypedDict):
    id: int
    name: str
    email: str
    role: NotRequired[str]  # optional key

def process_user(record: UserRecord) -> str:
    return f"{record['name']} <{record['email']}>"
```

### NamedTuple — Immutable Records with Names
```python
from typing import NamedTuple

class Point(NamedTuple):
    x: float
    y: float
    label: str = ""

p = Point(1.0, 2.0)
print(p.x, p.y)       # attribute access
x, y = p               # still unpackable
```

Use `@dataclass(frozen=True)` when you need methods; `NamedTuple` for simple value objects.

---

## 8. TypeAlias & NewType

### TypeAlias
```python
from typing import TypeAlias

UserId: TypeAlias = int
Matrix: TypeAlias = list[list[float]]
JsonValue: TypeAlias = str | int | float | bool | None | dict | list
```

### NewType — Distinct Types (Compile-Time Only)
```python
from typing import NewType

UserId = NewType("UserId", int)
OrderId = NewType("OrderId", int)

def get_user(user_id: UserId) -> User: ...

# mypy will catch this — they're different types even though both are int
order_id = OrderId(42)
get_user(order_id)  # ERROR: Argument of type OrderId not expected UserId
```

---

## 9. Overload

Define multiple signatures for a single function:

```python
from typing import overload

@overload
def parse_value(value: str) -> str: ...
@overload
def parse_value(value: int) -> int: ...
@overload
def parse_value(value: bytes) -> str: ...

def parse_value(value: str | int | bytes) -> str | int:
    if isinstance(value, bytes):
        return value.decode()
    return value
```

---

## 10. Running mypy

```bash
# Basic check
mypy src/

# Strict mode (recommended)
mypy --strict src/

# Check a single file
mypy src/myapp/services.py
```

### `pyproject.toml` mypy config
```toml
[tool.mypy]
python_version = "3.10"
strict = true
ignore_missing_imports = true  # for third-party without stubs
disallow_untyped_defs = true
disallow_incomplete_defs = true
warn_unused_ignores = true
warn_return_any = true
```

### Suppressing Errors (Use Sparingly)
```python
result = some_untyped_library()  # type: ignore[no-any-return]
```

### Installing Type Stubs
```bash
pip install types-requests   # for requests
pip install pandas-stubs     # for pandas
```
