# PEP 8 & Python Style Guide

## Table of Contents
1. Naming Conventions
2. Indentation & Whitespace
3. Line Length & Line Breaks
4. Imports
5. Blank Lines
6. Comments & Docstrings
7. String Formatting
8. Expressions & Statements
9. Linting & Formatting Tools
10. Common Violations Quick-Reference

---

## 1. Naming Conventions (PEP 8 §Naming Conventions)

| Entity | Convention | Example |
|---|---|---|
| Variable | `snake_case` | `user_count`, `is_active` |
| Function | `snake_case` | `get_user()`, `calculate_total()` |
| Method | `snake_case` | `self.send_email()` |
| Class | `PascalCase` | `UserAccount`, `HttpClient` |
| Module / File | `snake_case` | `user_service.py`, `db_utils.py` |
| Package | `lowercase` | `mypackage`, `utils` |
| Constant | `UPPER_SNAKE_CASE` | `MAX_RETRIES`, `DEFAULT_TIMEOUT` |
| Private | `_single_leading` | `_internal_cache` |
| Name-mangled | `__double_leading` | `__slot` (use sparingly) |
| Dunder | `__double_both__` | `__init__`, `__str__` |
| Type alias | `PascalCase` | `UserId = int` |

### Good vs. Bad Names
```python
# BAD — opaque intent
def f(x, y):
    d = x - y
    return d

# GOOD — intent is the name
def calculate_age_difference(birth_year: int, target_year: int) -> int:
    return target_year - birth_year
```

### Boolean Variables & Functions
Prefix with `is_`, `has_`, `can_`, `should_`:
```python
is_authenticated = True
has_permission = user.can_access(resource)
def is_valid_email(address: str) -> bool: ...
```

### Verb Vocabulary — Pick the Right Verb

The verb you choose is a contract. Readers make assumptions based on it:

| Verb | Implies | Example |
|---|---|---|
| `get_` | Already computed/cached — cheap, no I/O | `get_current_user()` |
| `fetch_` | Retrieval that may fail or be slow — I/O | `fetch_user_from_api()` |
| `load_` | Reads from disk/DB, transforms to in-memory | `load_config()` |
| `build_` / `create_` | Constructs a new thing | `build_query()`, `create_invoice()` |
| `compute_` / `calculate_` | Non-trivial work to produce a result | `calculate_tax()` |
| `parse_` | Transforms raw input to structured data | `parse_response()` |
| `validate_` | Checks correctness — raises or returns bool | `validate_email()` |
| `send_` / `publish_` | Dispatches to external system | `send_notification()` |
| `format_` | Transforms for display, not storage | `format_currency()` |
| `to_` / `as_` | Converts representation | `to_dict()`, `as_json()` |
| `handle_` | Processes an event/callback | `handle_payment_failed()` |

If you can't find a good verb, the function probably isn't doing one clear thing.

### Name Length Proportional to Scope

```python
# In a tight loop — short is fine, scope is visible
for i, item in enumerate(results):
    totals[i] = item.amount

# In a module-level function — short names are ambiguous
def calc(p, r, t):         # BAD: p? r? t?
    return p * r * t

def calculate_interest(    # GOOD
    principal: float,
    annual_rate: float,
    term_years: int,
) -> float:
    return principal * annual_rate * term_years
```

**Rule**: Name length should scale with the distance between definition and use.
Short scope → short name OK. Long scope or re-exported → be explicit.

### Avoid Type Suffixes — Annotations Handle That

```python
# BAD — type information belongs in the annotation, not the name
user_list: list[User]
config_dict: dict[str, str]
callback_func: Callable

# GOOD — name the ROLE
users: list[User]
config: dict[str, str]
callback: Callable
```

### Domain Vocabulary Consistency

The worst naming sin: multiple words for the same concept.

```python
# BAD — same concept, three words across the codebase
def fetch_user(user_id): ...    # module A
def get_account(account_id): ... # module B — user == account?
def load_member(member_id): ...  # module C — member == user?

# GOOD — one word, everywhere
def get_user(user_id): ...      # consistent across all modules
```

Pick your domain vocabulary early. Document it. Enforce it in reviews.

---

## 2. Indentation & Whitespace

- **4 spaces** per indentation level. Never tabs (PEP 8).
- Spaces around binary operators: `x = a + b`, not `x=a+b`.
- No spaces around keyword argument `=`: `func(key=value)`.
- No spaces inside brackets: `list[0]`, `dict['key']`, `func(arg)`.
- One space after comma: `a, b, c`.

```python
# BAD
def send(to,cc,subject,body,attachments=[]):
    x=to.strip()

# GOOD
def send(
    to: str,
    cc: str,
    subject: str,
    body: str,
    attachments: list[str] | None = None,
) -> None:
    recipient = to.strip()
```

---

## 3. Line Length & Line Breaks

- **88 characters** max (Black default; PEP 8 says 79 but Black's 88 is widely accepted).
- Break long function calls with trailing commas:

```python
# Long function call
result = some_function(
    argument_one,
    argument_two,
    argument_three,
)

# Long import
from some.very.deep.module import (
    ClassOne,
    ClassTwo,
    ClassThree,
)

# Long condition — wrap in parens, align logically
if (
    user.is_authenticated
    and user.has_permission("admin")
    and not user.is_suspended
):
    grant_access()
```

---

## 4. Imports (PEP 8 §Imports + PEP 328)

### Order (enforced by `isort`)
1. Standard library (`os`, `sys`, `pathlib`)
2. Third-party (`requests`, `fastapi`, `pydantic`)
3. Local / project imports

Separate each group with a blank line.

```python
import os
import sys
from pathlib import Path

import httpx
import pydantic
from fastapi import FastAPI

from myapp.models import User
from myapp.utils import format_date
```

### Rules
- One import per line (for `import X` style).
- Prefer explicit `from X import Y` over wildcard `from X import *` — always.
- Absolute imports over relative (PEP 328): `from myapp.utils import X` not `from ..utils import X` unless inside a package.
- Never import unused names — use `__all__` to control public API.

---

## 5. Blank Lines

- 2 blank lines around top-level functions and classes.
- 1 blank line between methods inside a class.
- Use blank lines inside functions sparingly to separate logical sections.

```python
class OrderProcessor:

    def validate(self, order: Order) -> bool:
        ...

    def process(self, order: Order) -> Receipt:
        ...


def standalone_function() -> None:
    ...
```

---

## 6. Comments & Docstrings

### Inline Comments
- Inline comments should be used sparingly — the code should speak for itself.
- At least 2 spaces before `#`, one space after.
- Explain *why*, not *what*:

```python
# BAD — describes what the code does, which is obvious
user_count += 1  # increment user count

# GOOD — explains why
user_count += 1  # include the requesting user in the quota calculation
```

### Docstrings (PEP 257 + Google Style)
Every public module, class, and function should have a docstring.

**Function:**
```python
def calculate_discount(price: float, rate: float) -> float:
    """Calculate discounted price after applying the given rate.

    Args:
        price: Original price in dollars. Must be non-negative.
        rate: Discount rate as a decimal between 0.0 and 1.0.

    Returns:
        Final price after discount applied.

    Raises:
        ValueError: If price is negative or rate is outside [0, 1].

    Example:
        >>> calculate_discount(100.0, 0.2)
        80.0
    """
```

**Class:**
```python
class PaymentProcessor:
    """Handles payment authorization and capture for orders.

    Attributes:
        gateway: The payment gateway client.
        timeout: Request timeout in seconds.
    """
```

**Module (top of file):**
```python
"""User authentication utilities.

Provides JWT encoding/decoding, session management, and
permission checking for the application.
"""
```

---

## 7. String Formatting

Prefer **f-strings** (Python 3.6+) over `%` or `.format()`:

```python
# BAD
msg = "Hello %s, you have %d messages" % (name, count)
msg = "Hello {}, you have {} messages".format(name, count)

# GOOD
msg = f"Hello {name}, you have {count} messages"

# Multi-line f-string
query = (
    f"SELECT * FROM users "
    f"WHERE id = {user_id} "
    f"AND active = {is_active}"
)
```

Use `textwrap.dedent` for multi-line strings in code:
```python
sql = textwrap.dedent("""
    SELECT id, name, email
    FROM users
    WHERE active = TRUE
    ORDER BY created_at DESC
""").strip()
```

---

## 8. Expressions & Statements

### Avoid Redundant Comparisons
```python
# BAD
if is_valid == True:
if items == []:
if value == None:

# GOOD
if is_valid:
if not items:
if value is None:
```

### One Statement Per Line
```python
# BAD
if x: y = 1; z = 2

# GOOD
if x:
    y = 1
    z = 2
```

### Comprehensions — Keep Them Readable
```python
# BAD — too complex for one line
result = [transform(x) for x in items if x.is_valid() and x.category in allowed_categories]

# GOOD — break at logical points
result = [
    transform(item)
    for item in items
    if item.is_valid() and item.category in allowed_categories
]

# RULE: if a comprehension doesn't fit in ~80 chars naturally, expand it
```

---

## 9. Linting & Formatting Tools

### Recommended Toolchain

| Tool | Role | Config File |
|---|---|---|
| **Black** | Opinionated auto-formatter | `pyproject.toml` |
| **isort** | Import sorter (use with `--profile black`) | `pyproject.toml` |
| **Ruff** | Fast linter (replaces flake8 + many plugins) | `pyproject.toml` |
| **mypy** | Static type checker | `pyproject.toml` |
| **pre-commit** | Git hooks to run all of the above | `.pre-commit-config.yaml` |

### `pyproject.toml` Configuration Block
```toml
[tool.black]
line-length = 88
target-version = ["py310"]

[tool.isort]
profile = "black"
line_length = 88

[tool.ruff]
line-length = 88
target-version = "py310"
select = ["E", "W", "F", "I", "B", "C4", "UP"]
ignore = ["E501"]  # Black handles line length

[tool.mypy]
python_version = "3.10"
strict = true
ignore_missing_imports = true
```

### `.pre-commit-config.yaml`
```yaml
repos:
  - repo: https://github.com/psf/black
    rev: 23.12.0
    hooks:
      - id: black
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.1.9
    hooks:
      - id: ruff
        args: [--fix]
  - repo: https://github.com/pycqa/isort
    rev: 5.13.2
    hooks:
      - id: isort
```

---

## 10. Common PEP 8 Violations Quick-Reference

| Violation | Code | Fix |
|---|---|---|
| Missing whitespace around operator | `E225` | `x=1` → `x = 1` |
| Too many blank lines | `E303` | Remove extras |
| Wildcard import | `F403` | Use explicit imports |
| Unused import | `F401` | Remove or add to `__all__` |
| Line too long | `E501` | Wrap or shorten |
| Module level import not at top | `E402` | Move imports up |
| Ambiguous variable name | `E741` | Rename `l`, `O`, `I` |
| Do not compare types, use isinstance | `E721` | `type(x) == int` → `isinstance(x, int)` |
| Missing docstring | `D1xx` | Add docstring |
