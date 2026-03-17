# Python Testing — pytest, Mocking, TDD, Coverage

## Table of Contents
1. Testing Philosophy
2. pytest Fundamentals
3. Fixtures — Design & Scope
4. Parametrize
5. Mocking with `unittest.mock`
6. Testing Patterns by Layer
7. Test-Driven Development (TDD)
8. Code Coverage
9. Testing Async Code
10. Test Organization & Naming

---

## 1. Testing Philosophy

### What to Test
- **Behavior, not implementation.** Test what the function does, not how it does it.
- **Public interfaces.** If users can't call it, it's probably not worth testing directly.
- **Edge cases.** Empty input, None, zero, negatives, boundaries, max values.
- **Error paths.** What happens when things go wrong — are the right exceptions raised?

### What NOT to Test
- `__repr__` / `__str__` unless critical to your app.
- Third-party library behavior.
- Private implementation details that may change.
- Trivial getters/setters with zero logic.

### The Testing Pyramid
```
         /\
        /E2E\         ← few, slow, expensive (Selenium, Playwright)
       /------\
      /Integr. \      ← moderate (DB, API, filesystem)
     /----------\
    /   Unit     \    ← many, fast, isolated (mock everything external)
   /--------------\
```

---

## 2. pytest Fundamentals

### Basic Test Structure
```python
# tests/test_calculator.py

def test_add_positive_numbers():
    assert add(2, 3) == 5

def test_add_with_zero():
    assert add(5, 0) == 5

def test_add_negative_numbers():
    assert add(-1, -2) == -3
```

### Running Tests
```bash
pytest                          # run all
pytest tests/test_calculator.py # specific file
pytest -k "add"                 # match name pattern
pytest -v                       # verbose output
pytest -x                       # stop after first failure
pytest --tb=short               # shorter tracebacks
pytest -s                       # show print() output
pytest --lf                     # rerun last failures only
```

### Testing Exceptions
```python
import pytest

def test_divide_by_zero_raises():
    with pytest.raises(ZeroDivisionError):
        divide(10, 0)

def test_divide_by_zero_message():
    with pytest.raises(ZeroDivisionError, match="division by zero"):
        divide(10, 0)

def test_invalid_user_raises_validation_error():
    with pytest.raises(ValidationError) as exc_info:
        create_user(name="", email="bad")
    assert "name" in str(exc_info.value)
```

### Testing Approximate Floats
```python
def test_float_result():
    assert calculate_average([1, 2, 3]) == pytest.approx(2.0)
    assert calculate_average([1, 2, 3]) == pytest.approx(2.0, rel=1e-3)
```

---

## 3. Fixtures — Design & Scope

Fixtures are pytest's dependency injection system. They replace `setUp`/`tearDown`.

### Basic Fixture
```python
import pytest
from myapp.models import User

@pytest.fixture
def basic_user() -> User:
    return User(name="Pat Taylor", email="pat@example.com", role="viewer")

@pytest.fixture
def admin_user() -> User:
    return User(name="Admin", email="admin@example.com", role="admin")

def test_user_can_view(basic_user: User):
    assert basic_user.can_access("view_dashboard")

def test_admin_can_delete(admin_user: User):
    assert admin_user.can_access("delete_records")
```

### Fixture Scope
```python
@pytest.fixture(scope="function")   # default — new instance per test
@pytest.fixture(scope="class")      # shared within a test class
@pytest.fixture(scope="module")     # shared within a test module
@pytest.fixture(scope="session")    # shared across the whole test suite
```

Use `scope="session"` for expensive resources (DB connections, server startup).

### Fixtures with Teardown (yield)
```python
@pytest.fixture
def temp_database():
    db = create_test_database()
    db.migrate()
    yield db                # test runs here
    db.drop_all_tables()    # teardown
    db.disconnect()

def test_save_user(temp_database):
    user = User(name="Test")
    temp_database.save(user)
    assert temp_database.get_by_name("Test") == user
```

### `conftest.py` — Shared Fixtures
Put shared fixtures in `conftest.py` at the root of `tests/` — pytest discovers them automatically:
```python
# tests/conftest.py
import pytest
from myapp import create_app

@pytest.fixture(scope="session")
def app():
    return create_app(config="testing")

@pytest.fixture(scope="session")
def client(app):
    return app.test_client()
```

---

## 4. Parametrize

Avoid copy-paste tests — parametrize instead:

```python
import pytest

@pytest.mark.parametrize("input_val, expected", [
    (0,   "zero"),
    (1,   "positive"),
    (-1,  "negative"),
    (100, "positive"),
])
def test_classify_number(input_val: int, expected: str):
    assert classify_number(input_val) == expected
```

### Parametrize with IDs for Clarity
```python
@pytest.mark.parametrize("email", [
    pytest.param("user@example.com", id="valid_email"),
    pytest.param("not-an-email",     id="missing_at"),
    pytest.param("@nodomain",        id="missing_local"),
    pytest.param("",                 id="empty_string"),
])
def test_invalid_email_raises(email: str):
    with pytest.raises(ValidationError):
        validate_email(email)
```

### Matrix Parametrize
```python
@pytest.mark.parametrize("role", ["admin", "editor", "viewer"])
@pytest.mark.parametrize("resource", ["report", "dashboard", "settings"])
def test_permission_matrix(role: str, resource: str):
    result = check_permission(role, resource)
    assert isinstance(result, bool)
```

---

## 5. Mocking with `unittest.mock`

### `MagicMock` vs `Mock`
- `MagicMock` supports magic methods (`__len__`, `__iter__`, etc.) — usually the right choice.
- `Mock` for simpler stubs where you don't need magic method support.

### `patch` as Decorator
```python
from unittest.mock import patch, MagicMock

@patch("myapp.services.send_email")
def test_notify_user_sends_email(mock_send: MagicMock):
    notify_user(user_id=1)
    mock_send.assert_called_once()
    mock_send.assert_called_with(to="user@example.com", subject="Welcome")
```

### `patch` as Context Manager
```python
def test_payment_calls_gateway():
    with patch("myapp.payments.StripeGateway") as MockGateway:
        instance = MockGateway.return_value
        instance.charge.return_value = {"status": "success"}

        result = process_payment(amount=100)

        instance.charge.assert_called_once_with(amount=100, currency="USD")
        assert result.status == "success"
```

### `patch.object` — Patching a Method on an Instance
```python
from unittest.mock import patch

def test_order_notifies_on_completion(order: Order):
    with patch.object(order, "send_confirmation") as mock_confirm:
        order.complete()
        mock_confirm.assert_called_once()
```

### `side_effect` — Simulate Errors
```python
@patch("myapp.db.get_user")
def test_handles_database_error(mock_get: MagicMock):
    mock_get.side_effect = DatabaseConnectionError("timeout")
    with pytest.raises(ServiceUnavailableError):
        get_user_profile(user_id=42)
```

### `side_effect` as a Function (Dynamic Return Values)
```python
def response_factory(url: str):
    responses = {
        "/users/1": {"name": "Pat"},
        "/users/2": {"name": "Alex"},
    }
    return responses.get(url, {})

mock_client.get.side_effect = response_factory
```

### Asserting Call History
```python
mock_fn.assert_called()                    # called at least once
mock_fn.assert_called_once()               # called exactly once
mock_fn.assert_called_with(arg1, key=val)  # last call args
mock_fn.assert_any_call(arg)               # any call matched
mock_fn.assert_not_called()                # never called
print(mock_fn.call_args_list)              # full call history
```

---

## 6. Testing Patterns by Layer

### Unit Test — Pure Function
```python
def test_calculate_tax_us():
    assert calculate_tax(100.0, region="US") == pytest.approx(8.25)

def test_calculate_tax_zero_for_exempt():
    assert calculate_tax(100.0, region="US", exempt=True) == 0.0
```

### Unit Test — Class with Injected Dependency
```python
def test_order_service_saves_to_repo():
    mock_repo = MagicMock(spec=OrderRepository)
    service = OrderService(repository=mock_repo)

    order = Order(items=[Item("Widget", 9.99)])
    service.place(order)

    mock_repo.save.assert_called_once_with(order)
```

### Integration Test — Database
```python
def test_save_and_retrieve_user(db_session):
    user = User(name="Integration Test", email="int@test.com")
    db_session.add(user)
    db_session.commit()

    retrieved = db_session.get(User, user.id)
    assert retrieved.name == "Integration Test"
```

### Integration Test — HTTP Client (httpx + respx)
```python
import respx
import httpx

@respx.mock
def test_fetch_weather():
    respx.get("https://api.weather.com/v1/current").mock(
        return_value=httpx.Response(200, json={"temp": 72, "unit": "F"})
    )
    result = fetch_weather(city="Nashville")
    assert result.temperature == 72
```

---

## 7. Test-Driven Development (TDD)

### Red → Green → Refactor
1. **Red**: Write a failing test for the behavior you want.
2. **Green**: Write the minimal code to make it pass.
3. **Refactor**: Improve code quality without changing behavior.

### TDD Example Walkthrough
```python
# STEP 1: Red — write the test first
def test_password_must_be_8_chars():
    with pytest.raises(ValidationError, match="8 characters"):
        validate_password("short")

# STEP 2: Green — minimal implementation
def validate_password(password: str) -> None:
    if len(password) < 8:
        raise ValidationError("Password must be at least 8 characters")

# STEP 3: Red — add next requirement
def test_password_must_have_digit():
    with pytest.raises(ValidationError, match="digit"):
        validate_password("nodigits!")

# STEP 4: Green — extend
def validate_password(password: str) -> None:
    if len(password) < 8:
        raise ValidationError("Password must be at least 8 characters")
    if not any(c.isdigit() for c in password):
        raise ValidationError("Password must contain at least one digit")

# STEP 5: Refactor — extract rules
_RULES: list[tuple[Callable, str]] = [
    (lambda p: len(p) >= 8,          "Password must be at least 8 characters"),
    (lambda p: any(c.isdigit() for c in p), "Password must contain at least one digit"),
]

def validate_password(password: str) -> None:
    for rule, message in _RULES:
        if not rule(password):
            raise ValidationError(message)
```

---

## 8. Code Coverage

### Setup
```bash
pip install pytest-cov
pytest --cov=myapp --cov-report=term-missing --cov-report=html
```

### `pyproject.toml` Config
```toml
[tool.pytest.ini_options]
addopts = "--cov=myapp --cov-report=term-missing"

[tool.coverage.run]
branch = true
omit = ["*/migrations/*", "*/tests/*", "setup.py"]

[tool.coverage.report]
fail_under = 80
show_missing = true
```

### Coverage Annotations
```python
def complex_function(x):
    if x > 0:       # pragma: no cover — exclude from coverage
        ...
```

### What Coverage Doesn't Tell You
Coverage shows **which lines ran**, not whether they were tested **correctly**.
80% coverage with bad assertions is worse than 60% with strong ones. Coverage
is a floor, not a ceiling.

---

## 9. Testing Async Code

```python
import pytest
import pytest_asyncio

@pytest.mark.asyncio
async def test_async_fetch_returns_data():
    result = await fetch_data("https://api.example.com/items")
    assert len(result) > 0

# Async fixture
@pytest_asyncio.fixture
async def async_client():
    async with httpx.AsyncClient(base_url="http://test") as client:
        yield client
```

Install: `pip install pytest-asyncio`

Configure in `pyproject.toml`:
```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
```

---

## 10. Test Organization & Naming

### Directory Structure
```
project/
├── src/
│   └── myapp/
│       ├── __init__.py
│       ├── models.py
│       └── services.py
└── tests/
    ├── conftest.py
    ├── unit/
    │   ├── test_models.py
    │   └── test_services.py
    └── integration/
        ├── test_db.py
        └── test_api.py
```

### Naming Conventions
- Test files: `test_<module>.py`
- Test functions: `test_<what>_<scenario>_<expected>`
- Examples:
  - `test_calculate_discount_zero_rate_returns_full_price`
  - `test_create_user_duplicate_email_raises_conflict_error`
  - `test_fetch_orders_empty_list_returns_empty_response`

### Grouping with Classes
```python
class TestUserValidation:
    """Tests for user input validation logic."""

    def test_valid_email_passes(self): ...
    def test_missing_email_raises(self): ...
    def test_duplicate_email_raises(self): ...

class TestUserPermissions:
    """Tests for role-based permission checks."""

    def test_admin_can_delete(self): ...
    def test_viewer_cannot_delete(self): ...
```

### pytest Marks
```python
@pytest.mark.slow          # skip in fast runs: pytest -m "not slow"
@pytest.mark.integration   # skip in unit-only runs
@pytest.mark.smoke         # always run: pytest -m smoke
```

Register marks in `pyproject.toml`:
```toml
[tool.pytest.ini_options]
markers = [
    "slow: marks tests as slow",
    "integration: marks tests requiring external services",
    "smoke: critical path tests always run",
]
```
