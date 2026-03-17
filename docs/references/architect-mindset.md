# Senior Architect & Developer — The Unified Mindset

A senior architect who can't write code makes bad decisions in the abstract.
A senior developer who can't think architecturally builds things that work today
and cripple the team in 18 months. The goal is to hold both at once.

This file is the thinking framework — not a list of patterns to copy, but the
mental operating system that determines which patterns apply and when.

## Table of Contents
1. The Architect's Mindset
2. System Design Decisions — The Real Tradeoffs
3. Technical Debt as a Managed Resource
4. The Non-Functional Requirements That Actually Kill Systems
5. Integration & Communication Patterns
6. Data Architecture Decisions
7. Evolutionary Architecture — Growing Without Rewriting
8. Building for the 3am Pager (Operability)
9. Technology Selection Framework
10. Architecture Decision Records (ADRs)
11. The Architect-Developer Duality in Practice

---

## 1. The Architect's Mindset

Architecture is not about diagrams. It is about **decisions with long-term consequences
under conditions of incomplete information**. Every architectural choice is a bet on
what will and won't change.

### The Three Questions Before Any Design Decision

```
1. What is the cost of getting this wrong?
   Low cost → decide fast, iterate
   High cost → slow down, get more information

2. How reversible is this?
   Easy to reverse → lean toward simpler, decide now
   Hard to reverse → treat as high-stakes, validate first
   Irreversible → treat as extremely high-stakes (data schemas, public APIs, contracts)

3. Who is making this decision?
   Close to the work → best positioned to decide
   Far from the work → should inform, not decide
```

### The Reversibility Matrix

```
              EASY TO REVERSE     HARD TO REVERSE
LOW STAKES    Decide now,         Decide now, document
              don't document      why you chose it

HIGH STAKES   Spike, decide,      This is architecture.
              document            Slow down. Get data.
                                  ADR required.
```

Most day-to-day development is top-left. Most architecture is bottom-right.
The mistake is treating bottom-right decisions like top-left ones.

### What Architects Actually Do

The job is not "draw boxes and lines." It is:

- **Make the implicit explicit.** Name the forces, tradeoffs, and constraints that
  are currently living in people's heads or not being discussed at all.
- **Create the conditions for good decisions.** Not make all the decisions yourself.
- **Set constraints, not implementations.** "We will not couple services through shared
  databases" is architecture. "Use Redis for the cache" may or may not be architecture
  depending on context.
- **Take responsibility for the things that are hard to change later.** Everything else
  can be someone else's call.
- **Stay in the code.** An architect who doesn't code loses touch with the friction
  their decisions create. The best architectural decisions come from developers who
  have felt the pain of the previous ones.

---

## 2. System Design Decisions — The Real Tradeoffs

### Monolith vs. Microservices

The hype cycle has swung both ways. Here is what experience actually teaches:

**Start monolith. Almost always.**

Microservices solve an organizational scaling problem — multiple teams deploying
independently without stepping on each other. If you don't have that problem yet,
you are paying the cost of distributed systems without getting the benefit.

The cost of distributed systems is severe and underestimated:
- Network calls fail in ways that local calls don't
- Distributed transactions are extremely hard to get right
- Debugging a request that spans 5 services is 10x harder
- Deploying and versioning multiple services multiplies operational complexity
- Data consistency across services is a constant source of bugs

```
Signs you're ready for service extraction (need ALL of these):
□ A specific part of the system has genuinely different scaling needs
□ Multiple teams need to deploy that part independently
□ The boundary is stable and well-understood
□ You have strong observability (distributed tracing, correlation IDs)
□ You have operational maturity (CI/CD per service, on-call rotation)

Signs you are NOT ready:
□ "It feels like it's getting big"
□ Someone read a blog post about Netflix
□ A consultant suggested it
□ You haven't had the monolith in production yet
```

**The Modular Monolith** is the underrated middle path:
- Single deployable unit (operational simplicity of a monolith)
- Clear internal module boundaries with explicit public interfaces
- No cross-module direct database access — each module owns its data
- Extractable later if you genuinely need to, without a full rewrite

```python
# Modular monolith structure — modules with explicit contracts
myapp/
├── orders/           # owns orders table, never touches users table directly
│   ├── __init__.py   # public interface: create_order, get_order, etc.
│   ├── models.py
│   ├── service.py
│   └── repository.py
├── users/            # owns users table
│   ├── __init__.py   # public interface: get_user, authenticate, etc.
│   └── ...
├── notifications/    # no database, calls orders and users via their public APIs
│   └── ...
```

### Synchronous vs. Asynchronous Communication

```
USE SYNC (HTTP/RPC) WHEN:
  • Caller needs the result before proceeding
  • Operation completes in < 5 seconds reliably
  • Failure should propagate immediately to the caller
  • You need the simplicity

USE ASYNC (queue/message) WHEN:
  • Caller can proceed without the result
  • Operation is slow or unreliable (emails, external APIs, PDF generation)
  • You need to decouple the sender's availability from the receiver's availability
  • You need retry with backoff without blocking the caller
  • Multiple downstream systems need to react to the same event

THE TEST:
  "If the worker processing this message goes down for 10 minutes,
   what happens to the user experience?"
  • Acceptable delay → async is fine
  • Unacceptable → sync or show a pending state
```

### Caching Strategy

Every caching decision has a companion question: **what is the cache invalidation strategy?**
Getting data in is easy. Getting stale data out is where systems fail.

```python
# Cache-aside (most common Python pattern)
async def get_user(user_id: int) -> User:
    cached = await cache.get(f"user:{user_id}")
    if cached:
        return User.model_validate_json(cached)
    user = await db.get_user(user_id)
    await cache.setex(f"user:{user_id}", 300, user.model_dump_json())
    return user

# Invalidation on write
async def update_user(user_id: int, data: UserUpdate) -> User:
    user = await db.update_user(user_id, data)
    await cache.delete(f"user:{user_id}")   # invalidate, don't update
    return user
```

**Cache invalidation strategies in order of safety:**
1. **TTL-based expiry** — simplest, accepts some staleness. Right for most cases.
2. **Invalidate on write** — invalidate the key when data changes. Right for user-facing data.
3. **Write-through** — update cache on every write. Adds complexity, use for hot paths.
4. **Event-based invalidation** — listen for change events, invalidate. Complex, use when multiple services share a cache.

**Cache levels — each is a different tool:**
```
In-process (dict / functools.cache):
  • Fastest (nanoseconds), zero network
  • Per-process — doesn't help with multiple workers
  • Use for: computed values, config, reference data

Redis (shared cache):
  • Fast (microseconds), shared across processes
  • Requires network call
  • Use for: session data, rate limiting, pub/sub, hot DB rows

CDN (edge cache):
  • Fastest for static/semi-static HTTP responses
  • Geographic distribution
  • Use for: public API responses, static assets
```

---

## 3. Technical Debt as a Managed Resource

Technical debt is not inherently bad. **Unmanaged** technical debt is what kills teams.

### The Debt Taxonomy

```
DELIBERATE DEBT — chosen consciously, documented
  "We hardcoded the tax rate to ship by Friday. JIRA-447 to fix before Q2."
  This is fine. This is how software ships on time.

ACCIDENTAL DEBT — created unconsciously, often not recognized
  "Nobody knows why this module is structured this way."
  This is the dangerous kind. It compounds silently.

OUTDATED DEBT — was correct, now isn't
  "This was the right pattern in 2019. Python 3.10 makes this unnecessary."
  Normal lifecycle. Schedule it.

RECKLESS DEBT — created knowingly without acknowledgment
  "I know this is wrong but I'll just leave it."
  Stop. This one poisons teams.
```

### The Debt Register

Treat debt like a real financial obligation. Track it:

```markdown
## Technical Debt Register

| ID | Description | Type | Impact | Effort | Owner | Target |
|----|-------------|------|--------|--------|-------|--------|
| TD-01 | order_service.py mixes HTTP + business logic | Accidental | High | Medium | Pat | Q2 |
| TD-02 | No connection pooling in legacy db module | Accidental | High | Low | — | Sprint 12 |
| TD-03 | Tax rate hardcoded (JIRA-447) | Deliberate | Medium | Low | Alex | Before Q2 |
```

**The 20% Rule:** Allocate 20% of every sprint to debt reduction. Not as "bonus work"
but as a first-class sprint commitment. Teams that don't do this end up spending 80%
of their time on debt in 18 months.

### When Debt Becomes a Crisis

Warning signs that debt has reached critical mass:
- New features take 3x longer than estimated — every change ripples unexpectedly
- Developers are afraid to touch certain parts of the codebase
- Onboarding a new developer takes months, not days
- "We'd have to rewrite X to do Y" is said more than once a month
- Bug count is rising faster than it's falling

When here: **stop adding features, declare a debt sprint, fix the highest-impact items first.**
The business argument: shipping on a rotten foundation accelerates decay.

---

## 4. The Non-Functional Requirements That Actually Kill Systems

These are the things that aren't in the user story but determine whether the system
survives contact with production.

### The Six That Matter Most

```
RELIABILITY — does it do the right thing even when things go wrong?
  • What happens when the database is slow?
  • What happens when a downstream API returns 500?
  • What happens when the disk is full?
  • What happens when you deploy a bad version?
  → Circuit breakers, graceful degradation, health checks, rollback strategy

SCALABILITY — can it handle 10x the current load?
  • Where are the bottlenecks? (profile before assuming)
  • Is state shared across instances? (must be external: Redis, DB)
  • Are background jobs consuming unbounded resources?
  → Stateless services, horizontal scaling, queue-based load leveling

OBSERVABILITY — when something goes wrong at 3am, can you find it?
  • Structured logs with correlation IDs
  • Metrics for the four golden signals (latency, traffic, errors, saturation)
  • Distributed traces for request flows across services
  → If you can't measure it, you can't debug it and you can't improve it

OPERABILITY — how hard is it to run this thing in production?
  • Zero-downtime deploys (rolling, blue-green, canary)
  • Feature flags for gradual rollouts
  • Clear runbooks for common failure modes
  → The best code is code that operators understand without waking up the dev

SECURITY — who can do what, and can you prove it?
  • Auth and authz on every endpoint (not bolted on later)
  • Audit log for sensitive operations
  • Secrets rotation without downtime
  → Security is not a phase. It's a continuous practice.

MAINTAINABILITY — can the team evolve this without fear?
  • Test coverage that gives confidence
  • Low coupling, high cohesion
  • Clear ownership of each component
  → Code that can't be safely changed is a liability, not an asset
```

### The Four Golden Signals (Observability)

```python
# What to instrument on every service — derived from Google SRE book

# 1. LATENCY — how long does it take?
histogram_request_duration.labels(endpoint="/orders", status="200").observe(elapsed)

# 2. TRAFFIC — how much demand?
counter_requests_total.labels(endpoint="/orders", method="POST").inc()

# 3. ERRORS — how often does it fail?
counter_errors_total.labels(endpoint="/orders", error_type="ValidationError").inc()

# 4. SATURATION — how full is the system?
gauge_queue_depth.labels(queue="order_processing").set(queue.qsize())
gauge_db_pool_used.set(pool.checked_out)
```

---

## 5. Integration & Communication Patterns

### Message Queue Patterns

```python
# Task queue (Celery/arq) — fire and forget with retry
# Use when: you need background work with retry, scheduling, prioritization
@celery.task(bind=True, max_retries=3, default_retry_delay=60)
def send_order_confirmation(self, order_id: int) -> None:
    try:
        order = Order.objects.get(id=order_id)
        email_service.send_confirmation(order)
    except EmailServiceError as e:
        raise self.retry(exc=e, countdown=60 * (2 ** self.request.retries))

# Event-driven (publish/subscribe) — decouple producers from consumers
# Use when: multiple systems react to the same event independently
async def handle_order_placed(event: OrderPlacedEvent) -> None:
    await event_bus.publish("order.placed", {
        "order_id": event.order_id,
        "customer_id": event.customer_id,
        "total": float(event.total),
        "timestamp": event.placed_at.isoformat(),
    })
# Subscribers: inventory service, notification service, analytics service
# Each reacts independently, neither knows about the others
```

### Circuit Breaker Pattern

Prevent cascading failures when a downstream service is degraded:

```python
from circuitbreaker import circuit   # pip install circuitbreaker

@circuit(failure_threshold=5, recovery_timeout=30, expected_exception=ServiceError)
async def call_payment_gateway(order: Order) -> PaymentResult:
    """
    If this fails 5 times in a row, the circuit opens.
    For the next 30 seconds, calls immediately raise CircuitBreakerError.
    After 30s, one call is allowed through (half-open state).
    If it succeeds, circuit closes. If not, opens again.
    """
    return await payment_gateway.charge(order)

# In the caller — handle the open circuit gracefully
async def process_order(order: Order) -> ProcessingResult:
    try:
        result = await call_payment_gateway(order)
        return ProcessingResult(status="charged", receipt=result)
    except CircuitBreakerError:
        # Circuit is open — fail fast, don't queue the user
        return ProcessingResult(status="payment_unavailable", retry_after=30)
```

### Saga Pattern — Distributed Transactions

When a business transaction spans multiple services and each step can fail:

```python
# Choreography saga — each service emits events, others react
# Simpler, but harder to trace the overall flow

# Orchestration saga — a coordinator drives the steps
class OrderFulfillmentSaga:
    """
    Steps: reserve_inventory → charge_payment → schedule_shipping
    Compensations (on failure): release_inventory, refund_payment
    """
    async def execute(self, order: Order) -> SagaResult:
        completed_steps: list[str] = []
        try:
            await self.reserve_inventory(order)
            completed_steps.append("inventory")

            await self.charge_payment(order)
            completed_steps.append("payment")

            await self.schedule_shipping(order)
            return SagaResult(success=True)

        except Exception as e:
            await self.compensate(order, completed_steps)
            raise OrderFulfillmentError(str(e)) from e

    async def compensate(self, order: Order, completed: list[str]) -> None:
        if "payment" in completed:
            await self.refund_payment(order)        # undo in reverse order
        if "inventory" in completed:
            await self.release_inventory(order)
```

---

## 6. Data Architecture Decisions

### Choose Your Data Model Before Your Database

```
Questions to answer BEFORE picking a database:

1. What are your access patterns?
   "I need to look up orders by customer_id, date range, and status"
   → Relational fits, index on those columns

2. What are your write vs. read ratios?
   Heavy writes → optimize for writes, accept denormalization
   Heavy reads → optimize for reads, use caching, read replicas

3. Do you need transactions across entities?
   YES → relational database (PostgreSQL)
   NO  → you have more options, but default to relational anyway

4. What is the shape of your data?
   Highly relational (users → orders → items → products) → RDBMS
   Document-oriented (each record is a self-contained blob) → consider document store
   Time series (metrics, events) → TimescaleDB, InfluxDB
   Graph traversals (social networks, recommendation) → Neo4j

5. What scale are you actually at?
   < 10M rows → PostgreSQL handles this trivially. Don't over-engineer.
   > 100M rows → NOW think about partitioning, read replicas, sharding
```

**Default to PostgreSQL.** It handles relational, JSON documents, full-text search,
time series (with TimescaleDB), and geospatial data. You are not Google. Start here.

### When to Normalize vs. Denormalize

```
NORMALIZE (3NF) BY DEFAULT
  • Data integrity — one place to update
  • Less storage
  • Easier to query flexibly
  • Right for OLTP (transactional systems)

DENORMALIZE DELIBERATELY
  • Read-heavy paths where joins are a proven bottleneck (measure first)
  • Read models in CQRS
  • Analytics / reporting (OLAP)
  • When the data truly "belongs together" and is always accessed together

THE RULE: Normalize first. Denormalize with evidence and intent.
```

### Event Sourcing — When It's Worth It

Event sourcing stores every state change as an immutable event, not just current state.

```python
# Traditional: store current state
class Order:
    status: str = "pending"  # overwritten on each change

# Event sourced: store what happened
class OrderCreated:
    order_id: int
    customer_id: int
    timestamp: datetime

class OrderConfirmed:
    order_id: int
    timestamp: datetime

class OrderShipped:
    order_id: int
    tracking_number: str
    timestamp: datetime

# State is derived by replaying events
def rebuild_order(events: list[Event]) -> OrderState:
    state = OrderState()
    for event in events:
        state = state.apply(event)
    return state
```

**Event sourcing is worth the complexity when:**
- You need a full audit trail that can never be altered
- You need to replay history to debug production issues
- You need temporal queries ("what did this look like on March 15?")
- You're doing CQRS and need to rebuild read models from scratch

**Event sourcing is NOT worth it when:**
- You just need a created_at / updated_at timestamp
- Your team hasn't shipped a working monolith first
- You read about it and it sounds cool

---

## 7. Evolutionary Architecture — Growing Without Rewriting

The goal is architecture that bends, not breaks, as requirements change.

### The Strangler Fig Pattern

Gradually replace legacy code without a big-bang rewrite:

```
Legacy system still serves traffic
        ↓
New system built alongside, handles new features
        ↓
Traffic shifted route by route to new system
(use feature flags, URL routing, or a proxy)
        ↓
Legacy routes go dark one by one
        ↓
Legacy system decommissioned when empty
```

```python
# Feature flag at the routing layer
async def get_user(user_id: int, request: Request) -> UserResponse:
    if feature_flags.is_enabled("new_user_service", request):
        return await new_user_service.get(user_id)   # new path
    return await legacy_user_service.get(user_id)    # old path
```

### Feature Flags

Feature flags decouple deployment from release — the single most valuable
operational capability you can give a team:

```python
from app.config import feature_flags

# Gradual rollout — percentage of users
@router.get("/checkout")
async def checkout(user: User = Depends(get_current_user)):
    if feature_flags.is_enabled("new_checkout", user_id=user.id, rollout_pct=10):
        return await new_checkout_flow(user)
    return await legacy_checkout_flow(user)

# Environment-based
if feature_flags.is_enabled("experimental_pricing"):
    price = new_pricing_engine.calculate(order)
else:
    price = legacy_pricing.calculate(order)
```

**Use LaunchDarkly, Unleash, or a simple Redis-backed flag store.** Don't hand-roll
complex flag logic in application code — it becomes impossible to audit.

### Fitness Functions — Continuous Architecture Validation

A fitness function is an automated test for an architectural property:

```python
# Enforce that no module in `domain/` imports from `infrastructure/`
def test_domain_has_no_infrastructure_imports():
    import ast, pathlib
    domain_path = pathlib.Path("src/myapp/domain")
    for py_file in domain_path.rglob("*.py"):
        tree = ast.parse(py_file.read_text())
        for node in ast.walk(tree):
            if isinstance(node, (ast.Import, ast.ImportFrom)):
                module = getattr(node, "module", "") or ""
                assert "infrastructure" not in module, (
                    f"{py_file}: domain module imports from infrastructure — "
                    f"architecture boundary violated"
                )

# Enforce response time SLA
def test_order_list_endpoint_under_200ms(benchmark, client):
    result = benchmark(client.get, "/orders/?limit=20")
    assert result.elapsed.total_seconds() < 0.2
```

---

## 8. Building for the 3am Pager (Operability)

The question to ask about every system you build: **"If this breaks at 3am, can
someone who isn't you figure out what's wrong and fix it?"**

If the answer is no, you have an operability problem regardless of code quality.

### Runbooks as First-Class Artifacts

```markdown
# Runbook: Order Processing Queue Backed Up

## Symptoms
- Alert: order_queue_depth > 1000 for > 5 minutes
- Users reporting order confirmation emails delayed

## Immediate Checks
1. Check worker health: `kubectl get pods -l app=order-worker`
2. Check error rate: Grafana → Order Processing → Error Rate
3. Check downstream deps: payment gateway status page

## Common Causes and Fixes

### Payment gateway degraded
Symptom: High error rate, mostly PaymentGatewayError in logs
Fix: Enable maintenance mode (disables new orders), wait for gateway recovery
Command: `feature_flags set payment_gateway_maintenance true`

### Worker OOM killed
Symptom: Workers in CrashLoopBackOff, high memory in last hour
Fix: Scale down queue, restart workers, investigate memory leak
Commands:
  kubectl rollout restart deployment/order-worker
  kubectl scale deployment/order-worker --replicas=2

## Escalation
If not resolved in 30 minutes: page on-call lead
If payment gateway down > 1 hour: notify business stakeholders
```

### Zero-Downtime Deployment Checklist

```
Before deploying:
□ New code handles OLD data formats (for in-flight requests during rollout)
□ New DB schema is backward compatible (additive only — no column renames/drops)
□ Migrations run BEFORE new code deploys (not after)
□ Feature flag available to disable new behavior without rollback
□ Rollback procedure documented and tested

Deploy sequence:
1. Run database migrations (additive — old code still works)
2. Deploy new code (canary → 10% → 50% → 100% or rolling)
3. Monitor error rate and latency for 10 minutes
4. If metrics stable → complete rollout
5. If degraded → rollback immediately, investigate

After:
□ Old columns/tables can be dropped in a SEPARATE deploy (weeks later)
□ Remove backward-compat code that was needed for the transition
```

---

## 9. Technology Selection Framework

The eight questions to ask before adopting any technology:

```
1. MATURITY: Is this production-proven, or are we early adopters paying the tax?
   Early adopter tax = bugs, API instability, poor docs, thin community

2. TEAM FIT: Does the team know this? What's the learning cost?
   A technology the team knows well beats a "better" one they don't

3. OPERATIONAL BURDEN: Who runs it? How is it monitored, backed up, upgraded?
   The most expensive software is the kind you have to operate

4. COMMUNITY & SUPPORT: Is this actively maintained? Is the ecosystem healthy?
   A library with 3 contributors and 200 open issues is a liability

5. LOCK-IN: If we need to replace this in 2 years, how hard is it?
   Write adapters/repositories around things that are hard to replace

6. ALTERNATIVE: What is the simplest thing that could possibly work?
   If a dict and a few functions solve the problem, use those

7. PROBLEM FIT: Does this technology solve our actual problem, or the problem we imagine?
   Re-evaluate after a 1-week spike, not based on the homepage

8. PRECEDENT: What are teams at similar scale using?
   Don't be the first to use X in production at scale. Let others pay that tax.
```

### Build vs. Buy vs. Open Source

```
BUILD WHEN:
  • It's a core competency — your competitive advantage lives here
  • Off-the-shelf solutions are a bad fit and the glue code would be worse
  • The operational cost of a third-party dependency exceeds the build cost

BUY (SaaS) WHEN:
  • It's not your core competency (email delivery, payments, auth)
  • The operational burden of self-hosting exceeds the SaaS cost
  • Speed to market matters more than cost at current scale

USE OPEN SOURCE WHEN:
  • Well-maintained, healthy community, good fit
  • You're prepared to read the source code when things break
  • You have a plan if the project goes dormant

THE RULE: Buy commodity, build differentiators, own nothing you don't have to.
```

---

## 10. Architecture Decision Records (ADRs)

An ADR is a short document that captures an important architectural decision,
the context it was made in, and the reasoning. It is the answer to "why is it
built this way?" six months later.

```markdown
# ADR-007: Use PostgreSQL as primary database

**Status**: Accepted
**Date**: 2024-03-15
**Author**: Pat Taylor

## Context
We need a primary data store for the order management system.
Options considered: PostgreSQL, MySQL, MongoDB, DynamoDB.

The data is highly relational (users → orders → items → products),
we need ACID transactions, and the team has existing PostgreSQL expertise.

## Decision
Use PostgreSQL 16 via SQLAlchemy 2.x with asyncpg driver.

## Consequences
**Positive:**
- ACID guarantees for order creation (critical for billing correctness)
- Full SQL expressiveness for complex reporting queries
- Team expertise reduces onboarding time
- Rich ecosystem (Alembic, SQLAlchemy, pgvector for future ML features)

**Negative:**
- Vertical scaling limits (addressable with read replicas when needed)
- Operational burden of running a stateful service (mitigated by RDS/managed PG)

**Risks:**
- Connection pool exhaustion under high concurrency → mitigated by PgBouncer

## Review Trigger
Revisit if: row count exceeds 500M in any table, or write throughput exceeds 10k TPS.
```

**ADRs belong in the repo** (`docs/adr/`), version-controlled alongside the code.
They are read far more than they are written. Keep them short — one page maximum.

**Write an ADR when:**
- Choosing between two or more viable technical approaches
- Making a decision that will be hard to reverse
- Choosing to NOT do something that seems obvious (document why)
- Establishing a pattern others will follow

---

## 11. The Architect-Developer Duality in Practice

### Staying in the Code

An architect who doesn't code makes decisions disconnected from reality.
The friction that matters — the thing that makes a pattern painful to use,
the performance characteristic you only feel when writing a hot loop,
the error message that makes debugging a nightmare — you only know these
by being in the code.

**Minimum viable coding practice for architects:**
- Own at least one non-trivial feature end-to-end each quarter
- Do code reviews, not just rubber-stamp approvals
- Write the hard tests — the integration tests nobody else wants to write
- Debug a production incident yourself at least monthly
- Pair with junior developers — you learn what your decisions cost them

### When to Be Pragmatic vs. Principled

```
BE PRINCIPLED about:
  • Security — never compromise, even under deadline pressure
  • Data integrity — a corrupt database is catastrophic and often irrecoverable
  • Irreversible decisions — schema changes, public APIs, auth systems
  • Technical debt that will compound (log it, schedule it, don't ignore it)

BE PRAGMATIC about:
  • Code style in a deadline crunch — fix it in the next sprint
  • Perfect architecture when MVP validation is more important
  • Tooling preferences when the team already knows something else
  • The "right" pattern when a simpler one is 80% as good
```

### Writing RFCs and Technical Proposals

When a change is large enough that people need to align before work starts:

```markdown
# RFC: Migrate order processing to async queue

**Author**: Pat Taylor
**Status**: Draft | Under Review | Accepted | Rejected
**Discussion deadline**: 2024-04-01

## Problem
Order processing currently blocks HTTP requests for up to 8 seconds during
payment gateway slowdowns. This causes timeouts and poor UX.

## Proposed Solution
Move payment processing to an async Celery queue. Return `202 Accepted`
immediately with an order ID. Client polls `/orders/{id}/status` or
receives a WebSocket update when processing completes.

## Alternatives Considered
1. Increase HTTP timeout to 30s — rejected: unacceptable UX, ties up connections
2. Payment gateway timeout reduction — rejected: doesn't solve slow gateway problem

## Implementation Plan
Phase 1: Add Celery + Redis (1 sprint)
Phase 2: Move payment step to queue (1 sprint)
Phase 3: Add status polling endpoint (1 sprint)
Phase 4: Add WebSocket notification (1 sprint, optional)

## Open Questions
- How do we handle duplicate submissions if the client retries?
- What SLA do we commit to for queue processing time?

## Success Metrics
- P95 order endpoint latency < 200ms (currently ~4000ms)
- Zero order processing timeouts in 30-day window
```

### The Principal Developer Test

Before shipping a significant change, ask these five questions:

```
1. "If I were hit by a bus, could the team maintain this?"
   If no → it needs better docs, tests, or simpler structure

2. "What breaks first when this is under 10x load?"
   If unknown → it needs a load test or at least a capacity estimate

3. "How do I roll this back in under 5 minutes?"
   If no answer → it needs a feature flag or a rollback procedure

4. "What monitoring tells me this is working?"
   If nothing → it needs instrumentation before it ships

5. "Is the next developer who touches this going to curse my name?"
   If yes → it needs more thought, not just more code
```
