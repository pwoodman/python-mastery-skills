# Senior Python Judgment — Decision Frameworks

This file captures the meta-level thinking that separates readable, maintainable code
from technically-correct-but-painful code. These are the things you can't get from PEP 8.

## Table of Contents
1. The Fundamental Readability Tests
2. Naming as Communication (the craft, not the rules)
3. When to Use a Class vs. Function vs. Module
4. Function Design — Size, Shape, and Composition
5. When to Split Things Up
6. Modularity vs. Monolith — The Real Tradeoff
7. Abstraction Cost — Is This Earning Its Keep?
8. The Maintenance Mindset

---

## 1. The Fundamental Readability Tests

Run these mentally on any code you write or review:

**The Stranger Test**: Could a competent Python developer who has never seen this codebase
understand this function/class/module in under 2 minutes? If not, it's too clever or too dense.

**The Newspaper Test**: Code should read like an article — headline first (what it does),
details below (how it does it). The most important thing should be visible without scrolling.

**The "WTF per minute" test**: Every time a reader thinks "what is this doing?", that's a WTF.
Good code has a low WTF rate. Measure it during reviews.

**The Change Test**: If requirements change slightly, does the change require touching
one place or many? Scattered changes are a design smell.

---

## 2. Naming as Communication (the craft, not the rules)

PEP 8 tells you *how* to format names. This tells you *what* to name things.

### Verb Vocabulary for Functions

The verb you choose is a contract. Be intentional:

| Verb | Implies | Example |
|---|---|---|
| `get_` | Returns something already computed/cached — cheap, no I/O | `get_current_user()` |
| `fetch_` | Goes and gets it — likely I/O, may fail | `fetch_user_from_api()` |
| `load_` | Reads from disk / DB — transforms storage format to in-memory | `load_config_from_file()` |
| `build_` / `create_` | Constructs something new — factory-like | `build_query()`, `create_invoice()` |
| `compute_` / `calculate_` | Does non-trivial work to produce a result | `calculate_tax()` |
| `parse_` | Transforms raw input to structured data | `parse_response()` |
| `validate_` / `check_` | Verifies correctness — returns bool or raises | `validate_email()` |
| `send_` / `publish_` | Dispatches to external system — side effect | `send_notification()` |
| `update_` / `set_` | Mutates existing state | `update_user_role()` |
| `format_` | Transforms data for display/output, not storage | `format_currency()` |
| `to_` / `as_` | Converts between representations | `to_dict()`, `as_json()` |
| `handle_` | Processes an event — usually in handlers/callbacks | `handle_payment_failed()` |

If you can't find a good verb, the function probably isn't doing one clear thing.

### Name Length Proportional to Scope

```python
# In a 3-line loop: `i`, `x`, `k` are fine — scope is obvious
for i, item in enumerate(results):
    totals[i] = item.amount

# In a module-level function: short names kill understanding
def calc(p, r, t):           # BAD: p? r? t?
    return p * r * t

def calculate_interest(principal: float, rate: float, term_years: int) -> float:
    return principal * rate * term_years   # GOOD
```

**Rule**: Name length should be proportional to the distance between definition and use.
Local variable in a 5-line function? Short is fine. Module-level constant? Be explicit.

### Avoid Type Suffixes in Names — That's What Annotations Are For

```python
# BAD — the type is in the name, redundantly
user_list: list[User]
config_dict: dict[str, str]
item_count_int: int
callback_func: Callable

# GOOD — name the ROLE, annotation gives the type
users: list[User]
config: dict[str, str]
item_count: int
callback: Callable
```

### Domain Vocabulary Consistency — Pick One Word and Own It

The worst naming sin is using 3 words for the same concept across a codebase:

```python
# BAD — same concept, different words everywhere
def fetch_user(user_id): ...      # module A
def get_account(account_id): ... # module B  (user == account?)
def load_member(member_id): ...  # module C  (member == user?)

# GOOD — one word, used consistently
def get_user(user_id): ...        # everywhere
```

Pick your domain vocabulary up front. Document it. Enforce it in reviews.

### The Redundancy Trap

```python
# BAD — redundant context in names
class User:
    def get_user_name(self):  # "user" is already implied by self
        ...
    user_email: str           # "user" prefix is noise inside User

# GOOD
class User:
    def get_name(self):
        ...
    email: str
```

---

## 3. When to Use a Class vs. Function vs. Module

This is the most misjudged decision in Python. Most beginner-to-intermediate code
has **too many classes**. Most very junior code has **none**.

### The Decision Tree

```
Do you need multiple instances of this thing?
  YES → Class (almost certainly)
  NO  ↓

Does it have meaningful mutable state that lives across multiple operations?
  YES → Class
  NO  ↓

Are you implementing a protocol/interface?
  YES → Class
  NO  ↓

Is it a group of related utilities with no shared state?
  YES → Module (just a .py file with functions)
  NO  ↓

Is it a single transformation or operation?
  YES → Function
```

### Classes Are NOT Just Namespaces

```python
# BAD — a class used as a namespace (just use a module)
class StringUtils:
    @staticmethod
    def slugify(text: str) -> str: ...
    @staticmethod
    def truncate(text: str, max_len: int) -> str: ...

# GOOD — just put these in string_utils.py and import them
def slugify(text: str) -> str: ...
def truncate(text: str, max_len: int) -> str: ...
```

### The "One Sentence" Class Test

You should be able to describe a class in one sentence without "and":

- `User` → "Represents a registered user in the system." ✅
- `OrderProcessor` → "Validates, persists, and notifies on order creation." ❌ — 3 things

If you need "and", you probably have two classes.

### Service Class Warning

`UserService`, `DataService`, `PaymentService` are common but often become God classes.
Ask: is this class modeling a *thing* or just grouping functions?

```python
# Signs your "service" is actually just a function namespace:
# - Most methods take different inputs, return different outputs
# - Methods don't share state (only share self.db or self.logger)
# - You could call any method without calling the others first

# Instead of:
class UserService:
    def __init__(self, db, cache, emailer):
        ...
    def create_user(self, data): ...
    def update_user(self, user_id, data): ...
    def delete_user(self, user_id): ...

# Consider module-level functions with explicit deps:
def create_user(data: UserCreate, *, db: Database) -> User: ...
def update_user(user_id: int, data: UserUpdate, *, db: Database) -> User: ...
```

### When Classes Are Exactly Right

- Domain entities with identity: `Order`, `Invoice`, `User`
- Stateful things: `Connection`, `Cache`, `Queue`
- Protocol implementations: `CsvExporter(Exporter)`
- Context managers: things that open/close
- When you genuinely need multiple instances with different state

---

## 4. Function Design — Size, Shape, and Composition

### The Abstraction Level Rule

**The most important function design principle most people miss:**
A function should operate at ONE level of abstraction.

```python
# BAD — mixes high-level orchestration with low-level string work
def process_order(order_id: int) -> Receipt:
    order = db.query(f"SELECT * FROM orders WHERE id = {order_id}")  # low-level
    if order["status"] != "pending":                                  # low-level
        return None
    charge_customer(order)                                            # high-level
    send_confirmation_email(order["customer_email"])                  # high-level

# GOOD — consistent level of abstraction throughout
def process_order(order_id: int) -> Receipt:
    order = get_pending_order(order_id)     # same level of detail throughout
    receipt = charge_customer(order)
    send_confirmation(order, receipt)
    return receipt

def get_pending_order(order_id: int) -> Order:
    """The low-level details live here, isolated."""
    row = db.query("SELECT * FROM orders WHERE id = %s", order_id)
    if row["status"] != "pending":
        raise OrderNotPendingError(order_id)
    return Order.from_row(row)
```

### The Right Size

There is no magic line count. The rule is: **a function should do one thing at one abstraction level**.

That said, experience shows:
- **< 5 lines**: Often fine. But if it has a name longer than its body, ask if it adds clarity.
- **5-20 lines**: The sweet spot for most business logic.
- **20-50 lines**: Legitimate for complex algorithms, orchestration. Watch for nested logic.
- **> 50 lines**: High smell. Either it's doing too much or it has too many abstraction levels.
- **> 100 lines**: Almost always wrong. Extract.

### The Over-Extraction Trap

Over-extraction is just as harmful as under-extraction:

```python
# Over-extracted — the name adds nothing over reading the code
def _get_first_item(items: list) -> Any:
    return items[0]

# Better — just inline it, unless it's used in 3+ places
result = items[0]

# Over-abstracted wrapper that masks errors
def safe_get(d: dict, key: str) -> Any:
    return d.get(key)   # just use d.get(key) directly
```

**The extraction test**: An extracted function earns its existence if it:
1. Has a name that reveals intent beyond what the code shows, AND/OR
2. Is reused in 2+ places, AND/OR
3. Can be independently tested

### Argument Order Convention

```python
# Subject → action target → options
def send_email(
    to: str,            # primary subject
    subject: str,       # what the action acts on
    body: str,
    *,                  # keyword-only after here
    cc: list[str] | None = None,    # options
    bcc: list[str] | None = None,
    retry: bool = True,
) -> None: ...
```

Most important things come first. Optional/configuration things come last, as keyword-only.

### Command-Query Separation

Functions either DO something (command) or RETURN something (query). Not both.

```python
# BAD — does something AND returns something (hidden side effect)
def pop_and_log(stack: list[str]) -> str:
    item = stack.pop()
    logger.info("Popped: %s", item)
    return item

# GOOD — separate concerns
item = stack.pop()
logger.info("Popped: %s", item)
```

Exception: context managers, generators, and I/O-heavy pipelines sometimes must violate this.

---

## 5. When to Split Things Up

### When to Extract a Function

Extract when ANY of these are true:
- You wrote a comment above a block of code (that comment = the function's name)
- The block is reused 2+ times
- The block can be tested independently and is non-trivial
- The block operates at a different abstraction level from the surrounding code

Do NOT extract just because a block is "long" — cohesive long blocks are better than
artificial tiny functions.

### When to Split a Class

Split a class when it has **two distinct reasons to change**:
```
Does changing the data model require changes here?  +
Does changing the notification logic require changes here?
→ Split into two classes.
```

Or when a class has multiple clusters of methods that only use a subset of attributes:
```python
class User:
    # Cluster 1: identity/auth methods — use name, email, password_hash
    def authenticate(self, password): ...
    def change_email(self, email): ...
    
    # Cluster 2: billing methods — use payment_method, billing_address
    def charge(self, amount): ...
    def update_payment_method(self, method): ...

# → Split into User and UserBillingProfile
```

### When to Split a Module (file)

Split a module when:
- It has more than ~300-400 lines AND covers more than one topic
- Imports from it are always partial (`from user import User` — never need OrderHistory?)
- It's become a catch-all (`utils.py` with 50 unrelated functions)
- Different functions change for different reasons (auth logic vs. formatting logic)

Do NOT split just for line count — a focused 600-line module is fine.

### When to Split a Package

Create a sub-package when:
- A module group has its own internal API distinct from the public API
- A set of modules needs its own `__init__.py` to curate a clean public interface
- You find yourself writing `from myapp.billing.processors.stripe import X` — that depth is a hint

### When to Keep Things Together

Sometimes the urge to "clean up" by splitting makes things worse:
- If two things are **always changed together**, splitting them creates shotgun surgery
- If callers **always import both**, the split is artificial
- If the "two classes" would have a lot of shared private logic, keep them together

---

## 6. Modularity vs. Monolith — The Real Tradeoff

### Start Monolith, Extract With Purpose

The default answer is: **don't split**. Let the pain tell you when to split.

The monolith is not the enemy. An under-structured monolith is. You can have:
- A monolith with clear package boundaries (best for most projects)
- A monolith with clear module contracts (better than a ball of mud)

The signals that tell you it's time to modularize:
1. Different parts of the code change for completely different reasons and at different rates
2. Different teams need to work independently without stepping on each other
3. You have genuine separation of deployment/scaling needs
4. Circular imports keep appearing despite correct design attempts

### Internal Modularity — The Right First Step

Before splitting into packages, get your internal structure right:

```
myapp/
├── domain/        ← business rules, no framework imports
│   ├── models.py
│   ├── services.py
│   └── exceptions.py
├── infrastructure/  ← DB, cache, external APIs
│   ├── database.py
│   └── email_client.py
├── api/           ← HTTP layer
│   ├── routes.py
│   └── schemas.py
└── config.py
```

**Dependency direction rule**: domain knows nothing about infrastructure.
Infrastructure knows about domain. API knows about both. Never reverse this.

### The Cost of Premature Extraction

Every package boundary you create is a contract you have to maintain:
- Changes that used to be in one file now require coordinating two packages
- You now need to think about versioning, public APIs, backward compatibility
- Import paths get longer and more brittle

Extract when the **pain of coupling exceeds the pain of indirection**.

---

## 7. Abstraction Cost — Is This Earning Its Keep?

Every abstraction has a cost: a name to remember, a layer to navigate, a place bugs hide.

### The Rule of Three

Don't abstract until you've written the thing three times:
- First time: write it inline
- Second time: write it inline again (maybe copy-paste — that's fine)
- Third time: now you understand it well enough to abstract correctly

Abstracting after one use creates leaky abstractions. You don't know what it really needs yet.

### Indirection Layers — Each One Costs

```python
# 3 layers of indirection for what is essentially: db.execute(sql)
result = repo.get_user(user_id)         # calls...
    → session.query(UserModel)           # calls...
        → db.execute("SELECT...")        # finally, the work

# Ask: does the repo layer pay for itself?
# YES if: different storage backends are realistic, OR you need to mock storage in tests
# NO if: you only ever use one DB and test with it directly
```

### Configuration Object Overengineering

```python
# OVER-ENGINEERED for a 3-parameter function
@dataclass
class EmailConfig:
    to: str
    subject: str
    body: str

def send_email(config: EmailConfig) -> None:
    ...

# APPROPRIATE — just take the parameters
def send_email(to: str, subject: str, body: str) -> None:
    ...

# Configuration objects make sense when:
# - 5+ parameters with non-obvious order
# - Configuration is reused across multiple calls
# - You need to serialize/deserialize it
```

---

## 8. The Maintenance Mindset

### Comments as a Last Resort

Comments have a maintenance cost — they go stale and become lies.
Prefer self-documenting code. When you can't:
- Comment the WHY, never the WHAT
- Comments near tricky algorithms: cite sources (StackOverflow URL, paper reference)
- TODO comments: include a ticket number or date

```python
# BAD — stale comment waiting to happen
# Loop through users and update their status
for user in users:
    user.status = compute_status(user)

# GOOD — code says what, doc says why
for user in users:
    # Status must be recomputed nightly because external billing system
    # does not push webhook events — see ticket BILL-447
    user.status = compute_status(user)
```

### Boring Code is a Virtue

Choose the boring, obvious solution over the clever one. Every time.

```python
# Clever — shows off generator chaining knowledge, harder to debug
result = list(filter(None, map(transform, chain.from_iterable(groups))))

# Boring — a new team member understands it in 5 seconds
items = []
for group in groups:
    for item in group:
        transformed = transform(item)
        if transformed is not None:
            items.append(transformed)
```

The boring code will be maintained by your teammates, your future self, and possibly
someone who learned Python 6 months ago. Optimize for them.

### The Shotgun Surgery Smell

If adding a new feature means editing 5 different files, your boundaries are wrong.
A well-designed system lets you add a new entity type by adding one new file and
touching one registration point.

### The Bus Factor Principle

Write code as if you'll be hit by a bus tomorrow. Not because you might be, but because
it forces you to make things understandable to others. If only one person understands a
module, it's a liability.

### The Four Questions Before Every Decision

1. **Will this be obvious to someone else in 6 months?**
2. **Does this make testing easier or harder?**
3. **If requirements change slightly, how much changes?**
4. **Am I solving a problem I actually have, or one I'm imagining?**

If you can't answer #4 with confidence — don't abstract yet.
