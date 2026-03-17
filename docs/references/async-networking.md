# Async & Networking — asyncio, httpx, WebSockets

## Table of Contents
1. asyncio Fundamentals
2. async/await Patterns
3. httpx — Async HTTP Client
4. WebSockets
5. Concurrency Primitives
6. Common Mistakes

---

## 1. asyncio Fundamentals

### The Mental Model

asyncio is single-threaded cooperative concurrency. While one coroutine waits for I/O,
the event loop runs another. It is NOT parallel — only I/O-bound work benefits.

```
Event Loop
├── Task A awaits db.query()    ← suspended, waiting for I/O
├── Task B runs (event loop switches here)
├── Task B awaits http.get()    ← suspended
├── Task A resumes (db responded)
└── ...
```

### Running asyncio

```python
import asyncio

async def main() -> None:
    result = await do_work()
    print(result)

if __name__ == "__main__":
    asyncio.run(main())   # creates event loop, runs, closes
```

---

## 2. async/await Patterns

### Sequential vs Concurrent

```python
import asyncio

# SEQUENTIAL — awaits one at a time, doesn't benefit from async
async def fetch_sequential(user_ids: list[int]) -> list[User]:
    results = []
    for uid in user_ids:
        user = await fetch_user(uid)   # waits for each before starting next
        results.append(user)
    return results

# CONCURRENT — all requests in flight simultaneously
async def fetch_concurrent(user_ids: list[int]) -> list[User]:
    return await asyncio.gather(*(fetch_user(uid) for uid in user_ids))

# CONCURRENT with error handling per-task
results = await asyncio.gather(
    *tasks,
    return_exceptions=True,   # don't cancel all if one fails
)
users = [r for r in results if isinstance(r, User)]
errors = [r for r in results if isinstance(r, Exception)]
```

### asyncio.gather vs asyncio.TaskGroup (3.11+)

```python
# gather — fire and forget, best for simple fan-out
users, orders = await asyncio.gather(
    get_users(user_ids),
    get_orders(order_ids),
)

# TaskGroup (3.11+) — structured concurrency, cancels all if one fails
async with asyncio.TaskGroup() as tg:
    user_task  = tg.create_task(get_user(user_id))
    order_task = tg.create_task(get_orders(user_id))

users = user_task.result()    # access after the group exits
orders = order_task.result()
```

### Timeouts

```python
import asyncio

# Per-operation timeout
try:
    result = await asyncio.wait_for(fetch_data(), timeout=5.0)
except asyncio.TimeoutError:
    logger.warning("fetch_data timed out after 5s")

# Timeout on a group (3.11+)
async with asyncio.timeout(10.0):
    await process_all_items(items)   # entire block has 10s budget
```

### Semaphore — Limit Concurrency

```python
async def fetch_all_limited(urls: list[str]) -> list[str]:
    semaphore = asyncio.Semaphore(10)   # max 10 concurrent requests

    async def fetch_one(url: str) -> str:
        async with semaphore:
            return await fetch(url)

    return await asyncio.gather(*(fetch_one(url) for url in urls))
```

### asyncio.Queue — Producer/Consumer

```python
async def producer(queue: asyncio.Queue, items: list) -> None:
    for item in items:
        await queue.put(item)
    await queue.put(None)   # sentinel to signal completion

async def consumer(queue: asyncio.Queue) -> list:
    results = []
    while True:
        item = await queue.get()
        if item is None:
            break
        results.append(await process(item))
        queue.task_done()
    return results

async def pipeline(items: list) -> list:
    queue: asyncio.Queue = asyncio.Queue(maxsize=50)
    producer_task = asyncio.create_task(producer(queue, items))
    consumer_task = asyncio.create_task(consumer(queue))
    await producer_task
    return await consumer_task
```

---

## 3. httpx — Async HTTP Client

`httpx` is the modern replacement for `requests` — sync and async, type-safe.

### Async Client (recommended for async code)

```python
import httpx

async def fetch_user(user_id: int) -> dict:
    async with httpx.AsyncClient(
        base_url="https://api.example.com",
        timeout=httpx.Timeout(10.0, connect=3.0),
        headers={"Authorization": f"Bearer {settings.api_token}"},
    ) as client:
        response = await client.get(f"/users/{user_id}")
        response.raise_for_status()   # raises HTTPStatusError on 4xx/5xx
        return response.json()
```

### Shared Client (don't recreate per request)

```python
# Create once at app startup, close at shutdown
class ApiClient:
    def __init__(self) -> None:
        self._client: httpx.AsyncClient | None = None

    async def __aenter__(self) -> "ApiClient":
        self._client = httpx.AsyncClient(
            base_url=settings.api_base_url,
            timeout=10.0,
        )
        return self

    async def __aexit__(self, *args) -> None:
        if self._client:
            await self._client.aclose()

    async def get_user(self, user_id: int) -> dict:
        assert self._client is not None
        r = await self._client.get(f"/users/{user_id}")
        r.raise_for_status()
        return r.json()
```

### Retry Logic

```python
import httpx
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception

@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=1, max=10),
    retry=retry_if_exception(lambda e: isinstance(e, httpx.TransportError)),
)
async def resilient_fetch(url: str) -> dict:
    async with httpx.AsyncClient() as client:
        response = await client.get(url, timeout=5.0)
        response.raise_for_status()
        return response.json()
```

### Handling Errors

```python
try:
    response = await client.get("/resource")
    response.raise_for_status()
except httpx.TimeoutException:
    raise ServiceUnavailableError("Request timed out")
except httpx.HTTPStatusError as e:
    if e.response.status_code == 404:
        raise NotFoundError("resource", id)
    if e.response.status_code == 429:
        raise RateLimitedError()
    raise UpstreamError(f"HTTP {e.response.status_code}") from e
except httpx.RequestError as e:
    raise NetworkError(f"Connection failed: {e}") from e
```

### Sync httpx (scripts and tests)

```python
# Drop-in replacement for requests in sync code
import httpx

response = httpx.get("https://api.example.com/data", timeout=10.0)
response.raise_for_status()
data = response.json()
```

---

## 4. WebSockets

```python
# FastAPI WebSocket endpoint
from fastapi import WebSocket, WebSocketDisconnect

class ConnectionManager:
    def __init__(self) -> None:
        self._connections: list[WebSocket] = []

    async def connect(self, ws: WebSocket) -> None:
        await ws.accept()
        self._connections.append(ws)

    def disconnect(self, ws: WebSocket) -> None:
        self._connections.remove(ws)

    async def broadcast(self, message: str) -> None:
        for connection in self._connections:
            await connection.send_text(message)

manager = ConnectionManager()

@router.websocket("/ws/{client_id}")
async def websocket_endpoint(ws: WebSocket, client_id: str) -> None:
    await manager.connect(ws)
    try:
        while True:
            data = await ws.receive_text()
            await manager.broadcast(f"{client_id}: {data}")
    except WebSocketDisconnect:
        manager.disconnect(ws)
        await manager.broadcast(f"{client_id} left")
```

---

## 5. Concurrency Primitives

### Event Loop — Don't Block It

```python
import asyncio
from concurrent.futures import ThreadPoolExecutor

# WRONG — blocks the event loop for everyone
async def process_image(path: str) -> bytes:
    return heavy_cpu_operation(path)   # blocks! nothing else can run

# RIGHT — offload CPU work to thread/process pool
async def process_image(path: str) -> bytes:
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, heavy_cpu_operation, path)

# Or for CPU-bound with ProcessPoolExecutor
executor = ProcessPoolExecutor(max_workers=4)
result = await loop.run_in_executor(executor, cpu_heavy_function, data)
```

### asyncio.Lock, Event, Condition

```python
# Lock — mutual exclusion
lock = asyncio.Lock()
async def safe_update(resource):
    async with lock:
        await resource.update()

# Event — signal between coroutines
ready = asyncio.Event()
async def producer():
    await initialize()
    ready.set()

async def consumer():
    await ready.wait()   # blocks until set()
    await start_consuming()
```

---

## 6. Common Mistakes

| Mistake | Fix |
|---|---|
| `requests` in async code | Use `httpx.AsyncClient` |
| Sequential `await` in a loop when order doesn't matter | `asyncio.gather()` |
| Creating new `httpx.AsyncClient` per request | Share a client, create once |
| Blocking CPU work in async function | `run_in_executor` |
| Forgetting `async with asyncio.TaskGroup()` exits before reading results | Read `.result()` after the `async with` block |
| `asyncio.run()` inside another running loop (Jupyter) | Use `await coro()` directly or `nest_asyncio` |
| Thread-shared mutable state in async code | Use `asyncio.Queue` or `asyncio.Lock` |
| `time.sleep()` in async function | `await asyncio.sleep()` |
