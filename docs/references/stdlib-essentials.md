# Python Stdlib Essentials

The standard library is underused. Before reaching for a package, check here.

## Table of Contents
1. pathlib — File System
2. datetime — Dates and Times (and the timezone trap)
3. collections — Smarter Data Structures
4. functools — Functional Tooling
5. itertools — Iteration Superpowers
6. contextlib — Context Manager Utilities
7. re — Regular Expressions
8. subprocess — Running System Commands
9. json / csv / tomllib — Data Formats
10. os / sys / shutil — System Integration

---

## 1. pathlib — File System

**Always use `pathlib.Path` over string concatenation for paths.**

```python
from pathlib import Path

# Building paths — use / operator
base = Path("/data/projects")
config_file = base / "config" / "settings.toml"   # never os.path.join

# Common operations
path = Path("reports/q3_summary.csv")
path.stem        # "q3_summary"
path.suffix      # ".csv"
path.name        # "q3_summary.csv"
path.parent      # Path("reports")
path.resolve()   # absolute path

# File I/O
text = path.read_text(encoding="utf-8")
path.write_text("content", encoding="utf-8")
data = path.read_bytes()

# Existence and type checks
path.exists()
path.is_file()
path.is_dir()

# Create directories
output = Path("output/charts")
output.mkdir(parents=True, exist_ok=True)   # never fails if already exists

# Glob
for csv_file in Path("data").glob("**/*.csv"):   # recursive
    process(csv_file)

for log in Path("/var/log").glob("app_*.log"):
    rotate(log)

# Iterate directory contents
for item in Path("src").iterdir():
    if item.is_file():
        lint(item)

# Rename / move / delete
path.rename(path.with_suffix(".bak"))
path.unlink(missing_ok=True)     # delete, no error if missing (3.8+)

# Temp files
from tempfile import TemporaryDirectory
with TemporaryDirectory() as tmp:
    work_dir = Path(tmp)
    process_in(work_dir)
    # cleaned up automatically
```

---

## 2. datetime — Dates and Times

### The Timezone Trap — The #1 datetime mistake

**Always use timezone-aware datetimes.** Naive datetimes (no tz) cause subtle bugs when you cross DST boundaries, compare timestamps, or deploy to different regions.

```python
from datetime import datetime, timezone, timedelta
from zoneinfo import ZoneInfo   # Python 3.9+

# WRONG — naive datetime, no timezone
now = datetime.now()              # What timezone? Unknown. Bug waiting.

# RIGHT — always UTC for storage/comparison
now_utc = datetime.now(timezone.utc)   # explicit UTC
now_utc = datetime.now(tz=timezone.utc)

# For user-facing display, convert to their timezone
user_tz = ZoneInfo("America/Chicago")
local_time = now_utc.astimezone(user_tz)

# Creating specific times
dt = datetime(2024, 3, 15, 14, 30, tzinfo=timezone.utc)

# Arithmetic
deadline = now_utc + timedelta(days=30, hours=6)
age = datetime.now(timezone.utc) - user.created_at  # timedelta
age.days          # int
age.total_seconds()  # float

# Parsing and formatting
dt = datetime.fromisoformat("2024-03-15T14:30:00+00:00")  # ISO 8601
dt = datetime.strptime("March 15, 2024", "%B %d, %Y")
formatted = dt.strftime("%Y-%m-%d %H:%M")
iso_str = dt.isoformat()   # "2024-03-15T14:30:00+00:00"

# Comparing
if event.starts_at > datetime.now(timezone.utc):   # both must be tz-aware
    send_reminder(event)
```

### Common Date Patterns

```python
from datetime import date, timedelta

today = date.today()
yesterday = today - timedelta(days=1)
first_of_month = today.replace(day=1)

# Date range
from dateutil.relativedelta import relativedelta  # pip install python-dateutil
next_month = today + relativedelta(months=1)
```

### Rule: Store UTC, Display Local

- **Database**: store as UTC timestamp or ISO 8601 string with `+00:00`
- **API responses**: return UTC ISO 8601, let clients convert
- **UI display**: convert to user's local timezone at display time only

---

## 3. collections — Smarter Data Structures

```python
from collections import defaultdict, Counter, deque, OrderedDict, namedtuple, ChainMap

# defaultdict — no KeyError on missing keys
inventory: dict[str, list] = defaultdict(list)
inventory["fruits"].append("apple")   # no need to check if key exists first

word_counts: dict[str, int] = defaultdict(int)
for word in text.split():
    word_counts[word] += 1

# Counter — frequency counting
from collections import Counter
words = Counter("the quick brown fox the quick".split())
words.most_common(3)        # [('the', 2), ('quick', 2), ('brown', 1)]
words["the"]                # 2
words["missing"]            # 0 — no KeyError

# Two counters can add/subtract
page_views = Counter({"home": 100, "about": 50})
new_views   = Counter({"home": 25, "contact": 10})
total = page_views + new_views   # Counter({'home': 125, 'about': 50, 'contact': 10})

# deque — double-ended queue, O(1) on both ends
from collections import deque
queue = deque(maxlen=100)     # fixed-size sliding window
queue.appendleft(item)        # O(1) — unlike list.insert(0, ...)
queue.popleft()               # O(1) — unlike list.pop(0) which is O(n)

# namedtuple — lightweight immutable record (prefer dataclass for methods)
Point = namedtuple("Point", ["x", "y"])
p = Point(1.0, 2.0)
p.x, p.y                      # attribute access AND positional unpacking

# ChainMap — overlay multiple dicts, first match wins
from collections import ChainMap
config = ChainMap(cli_args, env_vars, defaults)   # CLI overrides env overrides defaults
config["timeout"]             # finds first dict that has it
```

---

## 4. functools — Functional Tooling

```python
from functools import lru_cache, cache, partial, reduce, wraps, total_ordering

# lru_cache — memoize with size limit
@lru_cache(maxsize=256)
def fetch_exchange_rate(from_currency: str, to_currency: str) -> float: ...

# cache — unbounded memoization (3.9+)
@cache
def fibonacci(n: int) -> int:
    if n < 2: return n
    return fibonacci(n-1) + fibonacci(n-2)

# partial — pre-fill arguments
from functools import partial
multiply = lambda x, y: x * y
double = partial(multiply, 2)
triple = partial(multiply, 3)
double(5)   # 10

# Useful for callbacks and event handlers
import json
compact_json = partial(json.dumps, separators=(",", ":"))

# reduce — fold over a sequence (prefer explicit loops for readability)
from functools import reduce
product = reduce(lambda acc, x: acc * x, [1, 2, 3, 4, 5], 1)   # 120

# total_ordering — define __eq__ + one of lt/le/gt/ge, get the rest
@total_ordering
class Version:
    def __init__(self, major: int, minor: int) -> None:
        self.major, self.minor = major, minor

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, Version): return NotImplemented
        return (self.major, self.minor) == (other.major, other.minor)

    def __lt__(self, other: "Version") -> bool:
        if not isinstance(other, Version): return NotImplemented
        return (self.major, self.minor) < (other.major, other.minor)
    # __le__, __gt__, __ge__ are generated automatically

# wraps — preserve metadata when writing decorators (see decorators.md)
def log_calls(func):
    @wraps(func)                    # copies __name__, __doc__, __annotations__
    def wrapper(*args, **kwargs):
        print(f"Calling {func.__name__}")
        return func(*args, **kwargs)
    return wrapper
```

---

## 5. itertools — Iteration Superpowers

```python
from itertools import (
    chain, chain_from_iterable,
    islice, takewhile, dropwhile,
    groupby,
    product, combinations, permutations,
    cycle, repeat, count,
    batched,           # 3.12+
    pairwise,          # 3.10+
    accumulate,
    zip_longest,
)

# chain — flatten multiple iterables
all_items = list(chain(list_a, list_b, list_c))
all_items = list(chain.from_iterable([list_a, list_b, list_c]))

# islice — slice a generator/iterator
first_10 = list(islice(huge_generator(), 10))

# takewhile / dropwhile — conditional slicing
from itertools import takewhile, dropwhile
small = list(takewhile(lambda x: x < 10, sorted_numbers))

# groupby — group consecutive items by key (INPUT MUST BE SORTED BY KEY)
from itertools import groupby
events_sorted = sorted(events, key=lambda e: e.category)
for category, group in groupby(events_sorted, key=lambda e: e.category):
    items = list(group)

# pairwise — sliding window of 2 (3.10+)
from itertools import pairwise
for prev, curr in pairwise([1, 2, 3, 4]):
    delta = curr - prev   # [(1,2),(2,3),(3,4)]

# batched — split into fixed-size chunks (3.12+)
from itertools import batched
for chunk in batched(range(100), 10):
    process_batch(chunk)   # 10 items at a time

# Pre-3.12 batched equivalent:
def chunk(it, size):
    it = iter(it)
    return iter(lambda: list(islice(it, size)), [])

# product — cartesian product (nested loops replaced)
from itertools import product
for color, size in product(["red", "blue"], ["S", "M", "L"]):
    create_variant(color, size)

# zip_longest — zip with fill value instead of stopping at shortest
from itertools import zip_longest
for a, b in zip_longest(list1, list2, fillvalue=None):
    compare(a, b)
```

---

## 6. contextlib — Context Manager Utilities

```python
from contextlib import (
    contextmanager, asynccontextmanager,
    suppress, nullcontext,
    ExitStack,
)

# suppress — ignore specific exceptions
from contextlib import suppress
with suppress(FileNotFoundError):
    path.unlink()    # no need for try/except

# nullcontext — conditional context manager (avoids if/else around with)
with (context_manager if condition else nullcontext()):
    do_work()

# ExitStack — dynamic set of context managers
from contextlib import ExitStack
with ExitStack() as stack:
    files = [stack.enter_context(open(p)) for p in file_paths]
    process(files)   # all files closed on exit, even if one fails

# asynccontextmanager
from contextlib import asynccontextmanager

@asynccontextmanager
async def managed_connection(url: str):
    conn = await create_connection(url)
    try:
        yield conn
    finally:
        await conn.close()
```

---

## 7. re — Regular Expressions

```python
import re

# Compile for reuse (significant speedup in loops)
EMAIL_RE = re.compile(r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}")
PHONE_RE = re.compile(r"\+?1?\s*\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}")

# match vs search vs fullmatch
re.match(r"\d+", "123abc")    # matches at START only → Match
re.search(r"\d+", "abc123")   # matches ANYWHERE → Match
re.fullmatch(r"\d+", "123")   # must match ENTIRE string → Match

# Find all
emails = EMAIL_RE.findall(text)                      # list of strings
for m in EMAIL_RE.finditer(text):                    # iterator of Match objects
    print(m.group(), m.start(), m.end())

# Groups
m = re.match(r"(\d{4})-(\d{2})-(\d{2})", "2024-03-15")
m.groups()        # ('2024', '03', '15')
m.group(1)        # '2024'

# Named groups — much clearer than positional
m = re.match(r"(?P<year>\d{4})-(?P<month>\d{2})-(?P<day>\d{2})", "2024-03-15")
m.group("year")   # '2024'
m.groupdict()     # {'year': '2024', 'month': '03', 'day': '15'}

# Substitution
cleaned = re.sub(r"\s+", " ", text.strip())         # collapse whitespace
masked  = EMAIL_RE.sub("[email]", text)             # replace with literal

# Flags
re.compile(r"hello", re.IGNORECASE | re.MULTILINE)

# Rule: Don't use regex for HTML/XML — use a parser (BeautifulSoup, lxml)
# Rule: Don't validate emails with regex — use a library (email-validator)
# Rule: Complex regex needs a comment above it explaining what it matches
```

---

## 8. subprocess — Running System Commands

```python
import subprocess

# Run a command and get output (preferred modern API)
result = subprocess.run(
    ["git", "log", "--oneline", "-10"],
    capture_output=True,   # stdout + stderr captured
    text=True,             # decode bytes to str
    check=True,            # raises CalledProcessError on non-zero exit
)
print(result.stdout)

# With input
result = subprocess.run(
    ["grep", "error"],
    input="this line has error\nthis one does not\n",
    capture_output=True,
    text=True,
)

# Shell=True is a SECURITY RISK with user input — never do this:
subprocess.run(f"grep {user_input} logfile", shell=True)   # DANGEROUS
# Always use list form with shell=False (default):
subprocess.run(["grep", user_input, "logfile"])            # SAFE

# Check return code without raising
result = subprocess.run(["test", "-f", str(path)])
if result.returncode == 0:
    print("file exists")

# Streaming output (long-running commands)
with subprocess.Popen(["tail", "-f", "app.log"], stdout=subprocess.PIPE, text=True) as proc:
    for line in proc.stdout:
        process_log_line(line.rstrip())
```

---

## 9. json / csv / tomllib — Data Formats

### JSON

```python
import json

# Serialize / deserialize
data = json.loads(json_string)
json_string = json.dumps(data, indent=2, sort_keys=True)

# File I/O
with open("data.json") as f:
    config = json.load(f)

with open("output.json", "w") as f:
    json.dump(results, f, indent=2, default=str)   # default=str handles dates

# Custom serialization
class DateTimeEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, datetime):
            return obj.isoformat()
        return super().default(obj)

json.dumps(data, cls=DateTimeEncoder)

# Tip: Use Pydantic or dataclasses for structured JSON — see pydantic-validation.md
```

### CSV

```python
import csv

# Reading — use DictReader for named columns
with open("sales.csv", newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        process(row["customer_id"], float(row["amount"]))

# Writing
with open("output.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=["id", "name", "score"])
    writer.writeheader()
    for record in records:
        writer.writerow({"id": record.id, "name": record.name, "score": record.score})

# For large files / complex transforms — use pandas (see data-and-ml.md)
```

### TOML (Python 3.11+)

```python
import tomllib   # read-only in stdlib
with open("pyproject.toml", "rb") as f:   # must be binary mode
    config = tomllib.load(f)

# Write TOML — use tomli-w package
import tomli_w
with open("config.toml", "wb") as f:
    tomli_w.dump(data, f)
```

### YAML

```python
import yaml   # pip install pyyaml

with open("config.yaml") as f:
    config = yaml.safe_load(f)   # ALWAYS safe_load, never yaml.load

with open("output.yaml", "w") as f:
    yaml.dump(data, f, default_flow_style=False, sort_keys=False)
```

---

## 10. os / sys / shutil — System Integration

```python
import os, sys, shutil

# Environment variables
db_url = os.environ.get("DATABASE_URL", "sqlite:///dev.db")
# Better: use pydantic-settings — see pydantic-validation.md

# sys
sys.argv[1:]         # command-line args (prefer argparse/Click/Typer)
sys.exit(1)          # exit with code
sys.path.append(...)  # add to import path (avoid if possible)
sys.platform         # 'linux', 'darwin', 'win32'

# shutil — high-level file operations
shutil.copy2("src.txt", "dst.txt")          # copy with metadata
shutil.copytree("src_dir/", "dst_dir/")     # copy directory
shutil.rmtree("old_build/")                 # delete directory
shutil.move("old_path", "new_path")         # rename/move

shutil.make_archive("backup", "zip", "src/")   # create zip
shutil.unpack_archive("backup.zip", "dest/")

# Disk space
total, used, free = shutil.disk_usage("/")

# Find executable
python_path = shutil.which("python3")    # like `which` in bash
```
