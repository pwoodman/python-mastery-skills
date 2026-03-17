# Troubleshooting, Debugging & Unknown Tasks

The difference between a 2-hour bug and a 2-week bug is usually methodology, not skill.
Most debugging time is wasted by guessing. This file replaces guessing with process.

## Table of Contents
1. The Systematic Debugging Protocol
2. Reading Errors Correctly
3. The Break/Fix Loop — Recognition and Escape
4. Approaching an Unfamiliar Problem or Library
5. The Minimal Reproducible Example
6. Common Python Error Patterns and Real Causes
7. Debugging Tools in Practice
8. When to Ask for Help (and How)

---

## 1. The Systematic Debugging Protocol

**The core rule: one hypothesis, one change, one observation. Never two at once.**

If you change two things and the bug disappears, you don't know which one fixed it.
Next time it comes back (and it will), you're back to zero.

### The Five-Step Protocol

```
STEP 1 — STOP AND READ
  Before changing anything:
  • Read the full traceback from TOP to BOTTOM (not just the last line)
  • Identify the EXACT line the error originates from (often not the bottom)
  • Read the error message word by word — it is usually precise
  • Ask: "What does Python think is happening here?"

STEP 2 — LOCATE
  Find the actual source of the problem:
  • Is the error WHERE Python reports it, or UPSTREAM where bad data was created?
  • Trace the data backwards — where did this value come from?
  • Is this a symptom or the root cause?

STEP 3 — HYPOTHESIZE
  Form ONE specific hypothesis:
  • "I think X is None because Y"
  • "I think the function is receiving a str but expects an int"
  • Do NOT form vague hypotheses: "maybe it's the database" is not a hypothesis
  • A hypothesis must be FALSIFIABLE — you can prove it wrong

STEP 4 — OBSERVE
  Add ONE observation to test your hypothesis:
  • print() / logger.debug() at the exact decision point
  • Use the debugger (breakpoint()) to inspect state
  • Add an assertion: assert isinstance(x, int), f"Expected int, got {type(x)}"
  • Run ONE test that should fail if your hypothesis is correct

STEP 5 — CONCLUDE
  Based on what you observed:
  • Hypothesis confirmed → fix the actual cause (not just the symptom)
  • Hypothesis wrong → form a new hypothesis and go back to step 3
  • Still unclear → narrow the scope (step down to minimal reproduction)
```

### The Golden Rules

**Fix the cause, not the symptom.**
```python
# Symptom fix — will break again elsewhere
result = some_function() or "default"   # silently hides that some_function returned None

# Cause fix — understand WHY it returned None and fix that
def some_function() -> str:
    # The real bug was here — missing a return statement in one branch
    if condition:
        return compute_value()
    return fallback_value()   # was missing — that's the actual fix
```

**State is the enemy.** Most bugs live in state — a value that was set somewhere
unexpected, a list that was mutated, a global that was changed. When stuck, ask:
"What is the actual value of X at this point, and where was it last set?"

**Trust nothing, verify everything.**
```python
# Don't assume the data is what you think it is
def process_order(order_id: int) -> Receipt:
    # When debugging, add checkpoints to verify your assumptions
    order = repository.get(order_id)
    assert order is not None, f"Order {order_id} not found"
    assert order.status == "pending", f"Expected pending, got {order.status!r}"
    return fulfill(order)
```

---

## 2. Reading Errors Correctly

### Anatomy of a Python Traceback

```
Traceback (most recent call last):          ← read this direction ↓
  File "app/main.py", line 42, in run
    result = process_orders(pending)        ← caller
  File "app/services.py", line 17, in process_orders
    for order in orders:                    ← the intermediate
  File "app/services.py", line 23, in fulfill
    total = order.items[0].price * qty      ← THE ACTUAL LINE
TypeError: unsupported operand type(s) for *: 'str' and 'int'
                                            ← THE ACTUAL ERROR
```

The bottom of the traceback is where Python crashed. But the **root cause** is often
several frames up — where bad data was created and passed down.

### Error Message Vocabulary

| Error | What It Actually Means |
|---|---|
| `AttributeError: 'NoneType' object has no attribute 'X'` | Something returned `None` when you expected an object. Find where it was supposed to be set. |
| `KeyError: 'X'` | Dict doesn't have that key. Check spelling, check if it was ever set. |
| `TypeError: X() takes 2 arguments but 3 were given` | Signature mismatch — caller and definition disagree. Check both. |
| `ImportError: cannot import name 'X' from 'Y'` | Name doesn't exist in that module. Check spelling, check the module's `__all__`, check if it moved. |
| `RecursionError: maximum recursion depth exceeded` | Function calls itself without a base case, or two functions call each other. Draw the call graph. |
| `ValueError: not enough values to unpack` | Unpacking `a, b = func()` but `func()` returned 1 or 3 values. Print the return value first. |
| `IndentationError` | Mixed tabs and spaces, or wrong indentation level. Run `python -t file.py` to find tabs. |
| `RuntimeError: coroutine was never awaited` | Called an `async` function without `await`. |
| `StopIteration` inside a generator | `return` or `raise StopIteration` in a nested call. Use `yield from` correctly. |
| `PermissionError` | File system permissions. Check the path and ownership. |

### The "Wrong File" Trap

One of the most common debugging time-wasters: you're editing the right file
but Python is importing a different one.

```python
# Verify you're running what you think you're running
import mymodule
print(mymodule.__file__)    # prints the actual path being loaded

# Or at the top of the file being debugged
print(f"LOADED: {__file__}")
```

---

## 3. The Break/Fix Loop — Recognition and Escape

A break/fix loop is when every fix creates a new problem, or the same bug keeps
coming back in slightly different form. It's one of the most demoralizing states
in development — and it's almost always caused by fixing symptoms, not causes.

### Signs You're In a Break/Fix Loop

- You've changed the same code more than 3 times for the "same" bug
- You're not sure what the last change actually did
- Each fix works briefly, then something else breaks
- You're adding `try/except` around things to "silence" errors
- You're not sure what state your code is currently in
- You've lost track of what the original behavior was supposed to be

### Escape Protocol — Stop and Reset

```
STOP CODING.

1. REVERT to the last known-good state
   git stash         # save current work
   git log --oneline # find last green commit
   git checkout <hash> -- path/to/file.py

2. CHARACTERIZE the actual bug
   Write down in one sentence what the observed behavior is:
   "When I call process_order(id=42), it raises AttributeError on line 17"
   If you can't write it in one sentence, you don't understand it yet.

3. WRITE A FAILING TEST first
   def test_process_order_with_valid_id():
       result = process_order(42)
       assert result.status == "completed"
   Run it. It should fail. Now you have a target.

4. FIX ONLY WHAT MAKES THAT TEST PASS
   Nothing else. Don't "also clean this up" while you're in there.

5. RUN THE FULL TEST SUITE
   Make sure you didn't break anything else.

6. COMMIT
   Even a small commit. It gives you a checkpoint to return to.
```

### The Symptom Suppression Trap

These patterns hide bugs instead of fixing them:

```python
# TRAP — silences the error, root cause still there
try:
    result = process(data)
except Exception:
    result = None   # error swallowed, None propagates silently

# TRAP — defensive None-checking without understanding why it's None
if user and user.profile and user.profile.address:
    city = user.profile.address.city
# Why would any of these be None? That's the real question.

# TRAP — default values that mask missing data
name = user.get("name", "Unknown")   # "Unknown" appearing in prod = data bug

# FIX — understand and fix the source
# Ask: when is this None/missing? Should it ever be? If not, raise early.
```

### The Expanding Patch Problem

```python
# Original bug: division by zero when quantity is 0
def unit_price(total: float, quantity: int) -> float:
    return total / quantity

# Patch 1: guard it
def unit_price(total: float, quantity: int) -> float:
    if quantity == 0:
        return 0.0   # but now callers get 0.0 and treat it as a valid price

# Patch 2: silence the caller
price = unit_price(total, qty) or DEFAULT_PRICE  # no, this is worse

# RIGHT FIX: ask why quantity is ever 0, fix it at the source
# If it's valid (empty order), model it explicitly
# If it's a bug (should never happen), raise early and loudly
def unit_price(total: float, quantity: int) -> float:
    if quantity <= 0:
        raise ValueError(f"quantity must be positive, got {quantity}")
    return total / quantity
```

---

## 4. Approaching an Unfamiliar Problem or Library

When you don't know how to do something, the temptation is to jump straight to code.
That's how you end up 4 hours in, deep in the wrong abstraction.

### The Unknown Task Protocol

```
STEP 1 — DEFINE SUCCESS FIRST (before any code)
  Write down:
  • What is the INPUT?
  • What is the expected OUTPUT?
  • What are the edge cases?
  • How will I know when it's working?

  If you can't answer these precisely, you're not ready to code.

STEP 2 — FIND THE SMALLEST WORKING EXAMPLE
  Before building the real thing:
  • Find an official example or docs example that does something similar
  • Run it exactly as-is first — don't modify it yet
  • Verify it works, then understand WHY it works
  • Now start adapting it to your case, one change at a time

STEP 3 — SPIKE FIRST (for genuinely unknown territory)
  A spike is a throwaway experiment:
  • Create a scratch file (spike.py) — not in your main codebase
  • Explore the library/API/approach in isolation
  • Don't write production code until you understand the mechanics
  • Delete the spike when done — don't let it creep into production
  • The spike is a learning exercise. The real code is written after.

STEP 4 — BUILD VERTICALLY, NOT HORIZONTALLY
  Get ONE path working end-to-end before going wide:
  BAD: build all models → build all routes → add auth → add tests
  GOOD: build one route with one model, with auth, with a test → then repeat

STEP 5 — INSTRUMENT EARLY
  Add logging before the code is "done":
  • Log inputs to each function during development
  • Log what branches are taken
  • Log return values
  Easier to add during development than to retrofit when debugging.
```

### When the Docs Fail You

In order of effectiveness:

1. **Read the source code** — `inspect.getsource(library.function)` or find it on GitHub
2. **Read the tests** — official library tests show exactly how it's meant to be used
3. **Check the changelog** — the behavior you expect may have changed between versions
4. **Search GitHub issues** — your exact error has probably been hit before
5. **Search with the full error message** in quotes — often finds the one StackOverflow answer
6. **Check the version** — `import library; print(library.__version__)` — you may be on the wrong version

### Verifying Library Behavior

```python
# When you're not sure what a library does, test it in isolation
# Create a scratch file, do NOT put this in production code

# Example: not sure how SQLAlchemy handles None in a WHERE clause
import sqlalchemy as sa
engine = sa.create_engine("sqlite:///:memory:")
with engine.connect() as conn:
    result = conn.execute(sa.text("SELECT :val IS NULL"), {"val": None})
    print(result.fetchone())   # verify before assuming
```

---

## 5. The Minimal Reproducible Example

If you can't reproduce the bug in isolation, you don't understand it well enough to fix it.

### How to Build One

```python
# Step 1: Strip away everything that isn't the bug
# Remove: database calls, HTTP calls, auth, logging
# Replace with: hardcoded data, in-memory state

# BEFORE — complex reproduction
def test_reproduce():
    client = create_test_client()
    client.post("/auth/login", json={"email": "...", "password": "..."})
    client.post("/orders/", json={"items": [...]})
    response = client.get("/orders/42/total")
    assert response.json()["total"] == 99.99

# AFTER — minimal reproduction
def test_total_calculation():
    order = Order(items=[Item(price=49.99, qty=2)])
    assert order.total == 99.98   # found it — floating point issue
```

### Properties of a Good MRE

- Runs in under 1 second
- Has no external dependencies (no DB, no network, no files)
- Fails immediately and clearly
- Contains the minimum code needed to show the problem
- Can be shared with someone else and reproduce on their machine

---

## 6. Common Python Error Patterns and Real Causes

### "It works locally but not in production"

Usually one of:
- Different Python version → check `python --version` on both
- Missing environment variable → add startup validation
- Different package version → pin your dependencies
- File path assumptions → use `Path(__file__).parent` not relative paths
- Timezone differences → always store UTC

```python
# Startup validation — catch config errors at boot, not at 3am
def validate_settings(settings: Settings) -> None:
    required = ["database_url", "secret_key", "redis_url"]
    missing = [f for f in required if not getattr(settings, f, None)]
    if missing:
        raise RuntimeError(f"Missing required settings: {missing}")
```

### "It works the first time but fails on the second call"

Mutable state carried between calls:

```python
# BUG — result list is shared across all calls
def get_results(item, cache=[]):   # mutable default argument
    cache.append(item)
    return cache

# BUG — class-level mutable state
class Processor:
    results = []   # shared across ALL instances

    def process(self, item):
        self.results.append(item)   # mutates the class variable
```

### "Random failures in test suite"

Usually one of:
- **Test order dependency** — test B depends on state left by test A
- **Shared mutable fixtures** — fixture scope too broad, state leaks between tests
- **Time-sensitive tests** — `datetime.now()` in assertions, or `time.sleep()` races
- **Port conflicts** — multiple tests starting servers on the same port

```python
# Find order-dependent tests
pytest --randomly-seed=1234    # pip install pytest-randomly
pytest --randomly-seed=last    # rerun with same order that failed
```

### "Memory grows unboundedly"

```python
# Common causes:
# 1. Accumulating results without clearing
results = []
for item in stream:
    results.append(transform(item))   # grows forever for infinite streams
    # Fix: process in chunks, yield results, or use a fixed-size deque

# 2. lru_cache on a function with unbounded inputs
@lru_cache(maxsize=None)   # grows forever — set a maxsize
def process(item_id: int) -> Result: ...

# 3. Event listeners that hold references
listeners = []
def on_event(handler):
    listeners.append(handler)   # handler keeps referencing its closure
# Fix: use weakref.WeakSet for listener collections
```

---

## 7. Debugging Tools in Practice

### `breakpoint()` — Built-in Debugger

```python
def tricky_function(data: list[dict]) -> float:
    total = 0
    for item in data:
        breakpoint()       # drops into pdb here
        total += item["amount"]
    return total
```

**Essential pdb commands:**
```
n          next line (don't step into calls)
s          step into a function call
c          continue to next breakpoint
p expr     print expression value
pp expr    pretty-print (dicts, lists)
l          list source around current line
u / d      up / down the call stack
w          where am I? (show full stack)
b 42       set breakpoint at line 42
q          quit
```

### Strategic `print()` Placement

When pdb feels heavy:

```python
# Before you debug, add checkpoints at every decision point
def process(order: Order) -> Receipt:
    print(f"DEBUG process: order.id={order.id}, status={order.status!r}")
    
    items = validate_items(order.items)
    print(f"DEBUG validate_items returned: {len(items)} items")
    
    charge = calculate_charge(items)
    print(f"DEBUG charge: {charge}")
    
    return finalize(charge)
```

Remove ALL debug prints before committing. Use `git diff` to catch them.

### `assert` as a Debugging Aid

```python
# Add assertions where your assumptions might be wrong
def calculate_discount(price: float, rate: float) -> float:
    assert 0 <= rate <= 1, f"rate must be 0-1, got {rate}"
    assert price >= 0, f"price must be non-negative, got {price}"
    return price * (1 - rate)
```

Assertions are disabled with `python -O`. For production validation, use explicit
`if` + `raise`. Use `assert` only during development to catch bugs.

### `icecream` for Less Painful Print Debugging

```bash
pip install icecream
```

```python
from icecream import ic

# Instead of: print(f"result = {result}")
ic(result)            # ic| result: {'key': 'value', 'count': 42}
ic(user.id, status)   # ic| user.id: 7, status: 'pending'
```

---

## 8. When to Ask for Help (and How)

### Before Asking

1. You have a minimal reproducible example (section 5)
2. You have read the full error message and traceback
3. You have formed and tested at least 2 hypotheses
4. You have searched for the exact error message online

### How to Ask Effectively

```
BAD:  "My code is broken, can you fix it?"
BAD:  "It gives an error on line 47"
GOOD: "I'm getting [exact error] when I call [exact function] with [exact inputs].
       I expected [X]. I've verified that [observation A] and [observation B].
       Here's the minimal code that reproduces it: [MRE]"
```

### Time Limits for Self-Debugging

This is a professional judgment call, not a weakness:
- **20 minutes** without progress → take a break, come back fresh
- **2 hours** without progress → ask someone (rubber duck first, then a person)
- **1 day** without progress → you are missing context — get it from somewhere
- **Rubber ducking**: explain the problem out loud to an inanimate object.
  The act of explaining it often reveals the answer.
