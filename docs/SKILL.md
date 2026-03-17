---
name: python-mastery
description: >
  Senior-level Python reference covering style, design, testing, types, web APIs,
  data/ML, deployment, debugging, and safe refactoring. Use for any Python question.
  When unsure which file to load, start with senior-judgment.md.
---

# Python Mastery — A-Z Reference Skill

**Load only the files relevant to the task. Never load all files at once.**

## Full Reference Map

| File | Topic | Load When... |
|---|---|---|
| `architect-mindset.md` | Architect+developer duality, system design tradeoffs, tech debt, non-functional requirements, integration patterns, data architecture, evolutionary architecture, operability, ADRs | System design, scaling, "how do we build this as a system", technical leadership, build vs buy |
| `senior-judgment.md` | Naming craft, class vs function vs module, when to split, modularity, abstraction cost | Code-level design decisions, code review, function/class architecture |
| `best-practices.md` | Pythonic idioms, function design, OOP, SOLID, patterns, error handling | Code quality, idioms, refactoring |
| `pep8-style.md` | Formatting, whitespace, imports, docstrings, linting toolchain | Style, formatting, linting questions |
| `testing.md` | pytest, fixtures, mocking, TDD, coverage, async testing | Writing or reviewing tests |
| `type-system.md` | Annotations, unions, Protocols, TypeVar, generics, mypy | Type hints, mypy, generics |
| `observability.md` | Logging, structlog, exceptions, debugging, profiling | Logging setup, exception design, debugging |
| `project-structure.md` | Layout, pyproject.toml, packaging, CI/CD | Project setup, packaging, CI |
| `stdlib-essentials.md` | pathlib, datetime, collections, functools, itertools, re, subprocess, json/csv | Standard library usage questions |
| `web-apis.md` | FastAPI, Flask, REST design, JWT auth, middleware, testing | Building or reviewing HTTP APIs |
| `databases.md` | SQLAlchemy ORM/2.x, Alembic migrations, pooling, N+1, repositories | Database queries, ORM, migrations |
| `pydantic-validation.md` | Pydantic v2, field validators, pydantic-settings, discriminated unions | Data validation, settings, Pydantic questions |
| `async-networking.md` | asyncio, gather, TaskGroup, httpx, WebSockets, semaphores | Async code, HTTP clients, concurrency |
| `data-and-ml.md` | pandas, NumPy, scikit-learn pipelines, PyTorch training, data pipelines | Data analysis, ML, model training |
| `cli-scripting.md` | Typer, Click, argparse, Rich, subprocess automation | CLI tools, scripts, automation |
| `environments-packages.md` | pyenv, venv, uv, poetry, pip-tools, dependency security | Environment setup, package management |
| `decorators-meta.md` | Writing decorators, functools.wraps, descriptors, __slots__, __init_subclass__ | Decorators, metaprogramming |
| `deployment-security.md` | Docker, production config, health checks, SQL injection, secrets, OWASP | Deployment, containerization, security |
| `troubleshooting.md` | Systematic debug protocol, reading errors, break/fix loops, unknown tasks, MRE | Debugging, stuck on a problem, "why isn't this working" |
| `safe-changes.md` | Pre-flight checklist, renaming safely, signature changes, dead code cleanup, consolidation, expand-contract, regression prevention | Refactoring, renaming, cleanup, "don't break things" |

## Decision Guide

```
"Is this good Python?" / code-level design       → senior-judgment.md + best-practices.md
System design / scaling / "how do we build this"  → architect-mindset.md
Format / style / naming question               → pep8-style.md
Testing question                               → testing.md
Type hints / mypy                              → type-system.md
Logging / exceptions / debugging               → observability.md
Project setup / packaging / CI                 → project-structure.md
pathlib / datetime / collections / re          → stdlib-essentials.md
FastAPI / Flask / REST API / auth              → web-apis.md
SQLAlchemy / Alembic / DB queries              → databases.md
Pydantic / validation / settings               → pydantic-validation.md
async/await / httpx / WebSockets               → async-networking.md
pandas / numpy / sklearn / PyTorch             → data-and-ml.md
CLI / Click / Typer / scripting                → cli-scripting.md
venv / pyenv / uv / packages / security audit  → environments-packages.md
Decorators / metaprogramming / descriptors     → decorators-meta.md
Docker / production / deployment / security    → deployment-security.md
Debugging / "it doesn't work" / stuck         → troubleshooting.md
Refactoring / renaming / cleanup / "don't break things" → safe-changes.md
New unknown task / unfamiliar library          → troubleshooting.md (section 4)
Code review (broad)                            → senior-judgment.md + relevant domain files
```

## Universal Principles (Always Apply)

1. **Readability first.** Optimize for the reader, not the writer.
2. **Explicit over implicit.** Don't be clever. Be clear.
3. **One thing, one level.** Functions do one thing at one abstraction level.
4. **Fail loudly and early.** Validate inputs, raise meaningful errors.
5. **Boring is a virtue.** The obvious solution wins every time.
6. **Abstractions earn their keep.** Every indirection layer has a cost.
7. **Measure, then optimize.** Profile first. Never guess.
8. **Test behavior, not implementation.**
9. **Never use system Python.** Always use pyenv + venv or uv.
10. **All secrets from environment.** Never hardcode keys, passwords, or URLs.

## Python Version Baseline

Target **Python 3.10+** unless user specifies:
- `X | Y` union types, `match`/`case`, built-in generics (`list[str]`, `dict[str, int]`)
- Python 3.11+: `tomllib`, `ExceptionGroup`, `asyncio.TaskGroup`
- Python 3.12+: `itertools.batched`, type parameter syntax `class Stack[T]:`

## Recommended Toolchain

| Role | Tool |
|---|---|
| Package manager | `uv` (fast, modern) |
| Formatter | `Black` |
| Linter | `Ruff` |
| Type checker | `mypy --strict` |
| Testing | `pytest` + `pytest-cov` |
| Git hooks | `pre-commit` |
| HTTP client | `httpx` |
| Web framework | `FastAPI` |
| Validation | `Pydantic v2` |
| ORM | `SQLAlchemy 2.x` |

## Show Before/After When Proposing Changes

When reviewing or refactoring user code and proposing changes, show the original and
the improved version side by side.
Use realistic domain names in examples — never `foo`, `bar`, `x`.
Cite PEP numbers for official style guidance.
