# Safe Changes — Refactoring, Cleanup & Regression Prevention

The most dangerous moment in a codebase is when someone "just cleans things up."
Refactoring without discipline creates bugs in code that was working.
This file is the discipline.

## Table of Contents
1. The Change Safety Protocol
2. Before You Touch Anything — The Pre-Flight Checklist
3. Renaming Things Safely
4. Changing Function/Method Signatures
5. Cleanup and Dead Code Removal
6. Consolidating Duplicate Logic
7. The Expand-Contract Pattern for Breaking Changes
8. Managing Growing Files and Modules
9. Regression Prevention
10. The Post-Change Checklist

---

## 1. The Change Safety Protocol

**The Prime Directive: One concern per commit.**

Mixing refactoring and new features in the same commit is how bugs become impossible
to trace. When something breaks, you need to know: was it the refactor or the feature?

```
RULE: Never mix in a single commit:
  ✗ Refactor + new feature
  ✗ Rename + bug fix
  ✗ Cleanup + behavior change
  ✓ Rename only (behavior unchanged)
  ✓ Extract function only (behavior unchanged)
  ✓ Fix bug (nothing else touched)
  ✓ Add feature (no refactoring)
```

### The Three Types of Changes (Keep Them Separate)

**Refactoring** — restructure without changing behavior. Tests pass before and after.
```python
# Before
def get_user_data(uid):
    r = db.query(f"SELECT * FROM users WHERE id={uid}")
    return r

# After (refactored — same behavior, better style)
def get_user(user_id: int) -> User | None:
    return db.execute(select(User).where(User.id == user_id)).scalar_one_or_none()
```

**Feature addition** — new behavior added. Existing tests still pass.

**Bug fix** — incorrect behavior corrected. A NEW test that was failing now passes.

---

## 2. Before You Touch Anything — The Pre-Flight Checklist

```
□ Run the test suite RIGHT NOW — confirm it's green before your first keystroke
  pytest -q
  If it's not green: do NOT proceed until you understand why

□ Understand what the code does
  Read it fully before changing it
  If you don't understand it, you will break it

□ Identify all callers/users of what you're changing
  grep -r "function_name" src/
  grep -r "ClassName" src/ tests/
  Use IDE "Find All References" — do not trust your memory

□ Check for external callers
  Is this in a public API? Does anything outside this codebase call it?
  Is it in a __all__? In docs? In a published package?

□ Scope your change — write it down
  "I will rename X to Y and update all call sites"
  "I will extract lines 40-60 of process_order into validate_order"
  If you can't write it in one sentence, split it into smaller changes

□ Create a safety branch
  git checkout -b refactor/rename-process-order
```

---

## 3. Renaming Things Safely

Renaming is one of the most common refactors and one of the most dangerous when done
casually. "Find and replace" in a text editor is not safe — it hits strings, comments,
and documentation that may or may not need updating.

### The Safe Rename Procedure

```
1. Find ALL usages first — before changing the name
   rg "old_function_name" --type py         # ripgrep
   grep -r "old_function_name" src/ tests/  # grep fallback
   
   Check: .py files, test files, __init__.py exports, type stubs, docs, migrations

2. Use your IDE's "Rename Symbol" (not Find+Replace)
   PyCharm: Shift+F6
   VS Code: F2
   This updates only code references, not every string that happens to match

3. Update non-code references manually
   • Docstrings and comments that refer to the name
   • README and documentation
   • Migration files that reference table/column names
   • Config files with function paths (Celery task names, etc.)

4. If renaming a public API symbol — use a deprecation alias
   (see section 7 — Expand-Contract Pattern)

5. Run the full test suite
   pytest -x  # stop on first failure

6. Run mypy/ruff — they'll catch stale references the tests might not
   mypy src/
   ruff check .
```

### Rename Danger Zones

```python
# DANGER: String-based references don't get caught by "rename symbol"
task_name = "myapp.tasks.send_email"   # if you rename send_email, this breaks silently
route_name = "users.get_user"          # Flask/FastAPI route name
celery_task = app.task(name="old.module.function")

# DANGER: __all__ exports
# myapp/__init__.py
from myapp.services import process_order  # rename this → update __init__.py

# DANGER: Dynamic attribute access
method_name = "calculate_" + suffix
getattr(obj, method_name)()   # grep won't find calculate_total if it's built this way

# DANGER: Config file references
# celery_config.py
CELERY_TASK_ROUTES = {"myapp.tasks.send_email": {"queue": "email"}}
```

---

## 4. Changing Function/Method Signatures

Adding, removing, or reordering parameters breaks all call sites.

### Adding a Parameter Safely

```python
# BEFORE
def create_report(user_id: int) -> Report:
    ...

# Adding a required parameter BREAKS all callers
# WRONG — breaks everything immediately
def create_report(user_id: int, include_drafts: bool) -> Report: ...

# RIGHT — add with a default (backward compatible)
def create_report(user_id: int, *, include_drafts: bool = False) -> Report: ...
# All existing callers still work
# New callers can opt into the new behavior
```

### Removing a Parameter Safely

```python
# BEFORE — parameter exists
def send_email(to: str, subject: str, body: str, legacy_format: bool = False) -> None:
    ...

# WRONG — delete it immediately, breaks callers passing it
def send_email(to: str, subject: str, body: str) -> None: ...

# RIGHT — deprecate first (one release), then remove
import warnings

def send_email(
    to: str,
    subject: str,
    body: str,
    legacy_format: bool | None = None,
) -> None:
    if legacy_format is not None:
        warnings.warn(
            "legacy_format parameter is deprecated and will be removed in v2.0. "
            "It has no effect — remove it from your call site.",
            DeprecationWarning,
            stacklevel=2,
        )
    ...
# In v2.0: remove the parameter
```

### Changing a Parameter Type

```python
# BEFORE — accepts int
def get_user(user_id: int) -> User | None: ...

# Changing to str breaks callers passing int
# RIGHT — accept both, normalize internally, deprecate int path
def get_user(user_id: int | str) -> User | None:
    if isinstance(user_id, int):
        warnings.warn("Pass user_id as str", DeprecationWarning, stacklevel=2)
        user_id = str(user_id)
    ...
```

### Changing a Return Type

This is the most dangerous signature change — it propagates silently through all callers.

```python
# BEFORE — returns list
def get_orders(user_id: int) -> list[Order]: ...

# Changing to generator/tuple breaks callers that assume list methods
# (e.g., caller does len(get_orders(1)), which breaks with a generator)

# PROCEDURE:
# 1. Add new function with new return type
def get_orders_iter(user_id: int) -> Iterator[Order]: ...

# 2. Update callers one by one to use new function
# 3. Deprecate and eventually remove old function
# 4. Run mypy — it will catch callers still expecting the old type
```

---

## 5. Cleanup and Dead Code Removal

Dead code is a liability — it confuses readers and can mask real bugs.
But deleting code that isn't actually dead is even worse.

### Finding Dead Code

```bash
# vulture — static dead code finder
pip install vulture
vulture src/ --min-confidence 80

# coverage — find uncovered code (may be dead)
pytest --cov=src --cov-report=html
# open htmlcov/index.html — red lines are uncovered

# grep for obvious orphans
grep -r "def " src/ | cut -d: -f2 | sort > all_functions.txt
grep -r "function_name(" src/ tests/   # for each function, is it called?
```

### Safe Delete Procedure

```
1. Identify the candidate (function, class, variable, import)

2. Verify it has no callers
   rg "function_name" --type py   # in all .py files
   Check: __all__, string references, dynamic getattr, external packages

3. Comment it out first — don't delete yet
   # DEAD CODE — removing [date]. Delete if tests stay green for 2 weeks.
   # def old_function():
   #     ...

4. Run the full test suite
   pytest -x

5. Run mypy and ruff
   mypy src/   # catches unused imports at minimum
   ruff check --select F401 .  # unused imports

6. Let it sit for a sprint (for production code)
   If nothing breaks in 2 weeks, delete for real

7. Delete
   git commit -m "remove: dead code old_function (unused since [date])"
```

### Import Cleanup

```python
# Find unused imports
ruff check --select F401 .

# Or in code review — these are always safe to remove
from os import path            # unused
from typing import Optional    # replaced by X | None in 3.10+
import json                    # imported but never called
```

---

## 6. Consolidating Duplicate Logic

Duplication is a maintenance liability — but premature consolidation creates
wrong abstractions. The Rule of Three applies: consolidate after the third
occurrence, not the second.

### Identifying True Duplicates

```python
# These look the same but aren't — don't consolidate
def calculate_employee_tax(income: float) -> float:
    return income * 0.22   # US employee tax rate

def calculate_contractor_tax(income: float) -> float:
    return income * 0.22   # same rate NOW, but changes independently

# If rates are set by different regulations, they WILL diverge.
# A single function would require a flag: calculate_tax(income, is_contractor=True)
# That's the flag argument antipattern. Keep them separate.

# These ARE true duplicates — same business concept, same rules
def validate_order_email(email: str) -> bool:
    return "@" in email and "." in email.split("@")[1]

def validate_user_email(email: str) -> bool:
    return "@" in email and "." in email.split("@")[1]

# Extract — same concept, same rules, will always change together
def is_valid_email(email: str) -> bool:
    return "@" in email and "." in email.split("@")[1]
```

### Consolidation Procedure

```
1. Confirm the duplicates are truly the same concept
   Ask: "If business requirements change for this logic, will ALL copies change together?"
   If YES → consolidate
   If NO → keep separate (they only look the same today)

2. Write a test for the existing behavior FIRST
   test_email_validation covers both usages

3. Extract the shared function
   is_valid_email() replaces both

4. Update all call sites to use the new function

5. Run the full test suite — both old test paths now covered by one function

6. Remove the now-unused originals

7. Commit: "refactor: extract is_valid_email from duplicate validators"
```

---

## 7. The Expand-Contract Pattern for Breaking Changes

When you need to make a breaking change to a public API, use expand-contract
(also called parallel change or branch by abstraction).

```
EXPAND — add the new way alongside the old
CONTRACT — migrate all callers to the new way
REMOVE — delete the old way once all callers are migrated
```

### Example: Renaming a Public Method

```python
# PHASE 1: EXPAND — add new name, keep old name as alias with deprecation
class UserRepository:
    def get_by_email(self, email: str) -> User | None:  # NEW name
        return self._session.execute(
            select(User).where(User.email == email)
        ).scalar_one_or_none()

    def find_by_email(self, email: str) -> User | None:  # OLD name
        """Deprecated: use get_by_email() instead."""
        warnings.warn(
            "find_by_email() is deprecated, use get_by_email()",
            DeprecationWarning,
            stacklevel=2,
        )
        return self.get_by_email(email)

# PHASE 2: CONTRACT — update all callers to use get_by_email
# rg "find_by_email" --type py   → find all call sites
# Update them one by one, test after each

# PHASE 3: REMOVE — delete find_by_email (next major version)
# git grep "find_by_email" → must return nothing before removing
```

### Example: Changing a Module's Public API

```python
# myapp/utils.py — old location
def format_currency(amount: float, currency: str) -> str: ...

# myapp/formatting.py — new location (better structure)
def format_currency(amount: float, currency: str) -> str: ...

# EXPAND: re-export from old location with deprecation
# myapp/utils.py
from myapp.formatting import format_currency as _format_currency
import warnings

def format_currency(amount: float, currency: str) -> str:
    warnings.warn(
        "Import format_currency from myapp.formatting, not myapp.utils",
        DeprecationWarning,
        stacklevel=2,
    )
    return _format_currency(amount, currency)

# CONTRACT: migrate imports across codebase
# REMOVE: delete from utils.py
```

---

## 8. Managing Growing Files and Modules

### When a File Is Too Large

A module that needs to be split shows these signs:
- It has multiple clusters of functions that don't interact with each other
- Imports at the top pull in dependencies only needed by half the functions
- Different parts of the file change for completely different reasons

### The Safe Module Split Procedure

```
Scenario: services.py has grown to 600 lines covering users, orders, and billing

1. IDENTIFY the natural seams
   List functions: create_user, update_user, validate_user  ← user cluster
                   create_order, fulfill_order, cancel_order ← order cluster
                   charge_card, issue_refund               ← billing cluster

2. CREATE new modules (don't move yet)
   services/user_service.py    (empty)
   services/order_service.py   (empty)
   services/billing_service.py (empty)

3. MOVE one cluster at a time
   Move user functions to user_service.py
   Add re-exports to services.py (backward compat):
   from services.user_service import create_user, update_user, validate_user

4. RUN TESTS after each cluster move
   pytest -x  ← stop on first failure

5. UPDATE import sites to use new paths
   rg "from services import create_user" --type py → update to user_service

6. REMOVE re-exports from old services.py once all callers are updated

7. DELETE services.py if now empty
```

### Circular Import Prevention

```python
# Circular imports happen when:
# A imports B and B imports A

# DETECTION
python -c "import myapp.moduleA"
# Will show: ImportError: cannot import name 'X' from partially initialized module

# FIXES in order of preference:

# 1. Move the shared thing to a third module that both import
# models.py ← both services.py and repositories.py import from here

# 2. Restructure so the dependency only goes one way
# domain/ ← infrastructure/ ← api/  (domain knows nothing about infra)

# 3. Local import (import inside a function, not at module level)
def get_something():
    from myapp.other import helper   # imported only when function is called
    return helper()
# Use only as a last resort — harder to trace

# 4. TYPE_CHECKING guard for type-only circular imports
from __future__ import annotations  # top of file
from typing import TYPE_CHECKING
if TYPE_CHECKING:
    from myapp.models import User   # only imported during type checking, not runtime
```

---

## 9. Regression Prevention

Regressions — things that worked and then broke — are almost always caused by one of:
- Missing tests for the behavior that broke
- Tests that test implementation, not behavior (so they pass even when behavior breaks)
- A change that touched more than intended

### The Pre-Change Test Requirement

**Before changing any code, there must be a test that covers its current behavior.**

```
If a test exists → run it, confirm it's green, make your change, confirm still green
If no test exists → write one NOW, before changing anything
    • The test documents "this is what it's supposed to do"
    • It becomes your safety net during the change
    • It prevents the same regression twice
```

### Writing Regression Tests After a Bug

```python
# Every bug fix must be accompanied by a test that would have caught it
# BAD: fix the bug, no test added
# GOOD:

# Bug: create_order(items=[]) succeeded when it should have raised
# Regression test:
def test_create_order_rejects_empty_items():
    """Regression: was silently creating empty orders before 2024-03-15"""
    with pytest.raises(ValidationError, match="at least one item"):
        create_order(user_id=1, items=[])
```

### Integration Points Are the Highest Risk

When you change something, the most likely breakage is at the boundaries:

```
Changed: function signature in services.py
At risk: every route in routes.py that calls it
         every test that mocks it
         every place in __init__.py that re-exports it

Changed: database model (added column)
At risk: serializers/schemas that read from it
         migrations (was Alembic updated?)
         test fixtures that create the model

Changed: environment variable name
At risk: Docker Compose, CI config, Kubernetes secrets, README docs, .env.example
```

### Post-Change Checklist for Risky Changes

```bash
# 1. Run the full test suite
pytest -v --tb=short

# 2. Run type checking
mypy src/ --strict

# 3. Run linting
ruff check .

# 4. Check for stale references to what you changed
rg "old_name" --type py

# 5. For API changes — check generated OpenAPI spec changed as expected
# (FastAPI: GET /openapi.json and diff it)

# 6. For DB model changes — verify migration was generated
alembic revision --autogenerate -m "description"
# Review the generated migration — does it match what you changed?

# 7. For public API changes — check __all__ is updated
grep -n "__all__" src/myapp/__init__.py
```

---

## 10. The Post-Change Checklist

Run this before every commit that changes existing behavior:

```
□ Tests pass:              pytest -x
□ No new type errors:      mypy src/
□ No new lint errors:      ruff check .
□ No debug code left:      git diff | grep -E "(print|breakpoint|pdb|ic\()"
□ No commented-out code:   (unless marked with intent and a date)
□ All call sites updated:  rg "old_name" --type py → returns nothing
□ Commit message is clear: "refactor: ..." / "fix: ..." / "feat: ..."
□ One concern per commit:  no mixing of refactor + feature + fix
□ Test covers the change:  if behavior changed, a test reflects it
□ Dependencies updated:    if new imports added, pyproject.toml updated
```

### Commit Message Convention (Enforce This)

```
feat: add bulk import for orders
fix: handle empty items list in create_order
refactor: extract validate_order from process_order
test: add regression test for empty order case
chore: update dependencies, clean dead imports
docs: add docstring to calculate_discount
```

The prefix tells the reader: is this safe to deploy? Does it change behavior?
Can I find it in the git log when something breaks?
