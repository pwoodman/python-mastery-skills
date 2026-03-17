# python-mastery

> An opinionated, practitioner-grade Python reference covering everything from 
> PEP 8 and naming conventions to production deployment, debugging methodology, 
> and safe refactoring — built from 20 years of hard-won experience, not just the docs.

## What this is

A Claude skill and human-readable reference that covers Python A-Z with the 
judgment of a senior developer and architect baked in — not just rules, but 
*when to break them and why*.

## Add to Claude Chat UI (Claude.ai)

1. Download `python-mastery.skill`.
2. In Claude.ai, enable Code execution in Settings → Capabilities.
3. Go to Customize → Skills.
4. Click `+`, choose `Upload a skill`, and select `python-mastery.skill`.
5. Toggle the skill on.

## Add to Claude Code

1. Create a skill folder in either `~/.claude/skills/python-mastery/` (personal) or `.claude/skills/python-mastery/` (project).
2. Copy the contents of `docs/` into that folder so it contains `SKILL.md` and `references/`.
3. In Claude Code, ask “List all available Skills” to confirm it’s discovered.

## Rebuild skill bundle

If you edit `docs/SKILL.md` or any `docs/references/*.md`, run:

- PowerShell (Windows): `./scripts/build-python-mastery-skill.ps1`

This regenerates `python-mastery.skill` from source content.

## Verify skill bundle

To confirm the bundle matches `docs/` exactly:

- PowerShell (Windows): `./scripts/check-python-mastery-skill.ps1`

To auto-rebuild the bundle on mismatch:

- PowerShell (Windows): `./scripts/check-python-mastery-skill.ps1 -Fix`

## Validate bundle and references

To verify all references exist and the skill bundle is up to date:

- PowerShell (Windows): `./scripts/validate-python-mastery-skill.ps1`

CI runs this validation on every push and pull request.

## Browse the docs

| Reference | What it covers |
|---|---|
| [Architect Mindset](docs/references/architect-mindset.md) | System design, tech debt, operability, ADRs |
| [Senior Judgment](docs/references/senior-judgment.md) | When to use a class vs function, when to split, abstraction cost |
| [Best Practices](docs/references/best-practices.md) | Pythonic idioms, SOLID, design patterns |
| [PEP 8 & Style](docs/references/pep8-style.md) | Formatting, naming, docstrings, toolchain |
| [Testing](docs/references/testing.md) | pytest, fixtures, mocking, TDD, coverage |
| [Troubleshooting](docs/references/troubleshooting.md) | Systematic debugging, break/fix loops, unknown tasks |
| [Safe Changes](docs/references/safe-changes.md) | Refactoring without breaking things |
| [Type System](docs/references/type-system.md) | Annotations, Protocols, generics, mypy |
| [Observability](docs/references/observability.md) | Logging, exceptions, debugging, profiling |
| [Web APIs](docs/references/web-apis.md) | FastAPI, Flask, REST design, auth |
| [Databases](docs/references/databases.md) | SQLAlchemy, Alembic, ORM patterns, N+1 |
| [Pydantic & Validation](docs/references/pydantic-validation.md) | Pydantic v2, settings, validators |
| [Async & Networking](docs/references/async-networking.md) | asyncio, httpx, WebSockets |
| [Data & ML](docs/references/data-and-ml.md) | pandas, NumPy, scikit-learn, PyTorch |
| [CLI & Scripting](docs/references/cli-scripting.md) | Typer, Click, Rich, subprocess |
| [Environments](docs/references/environments-packages.md) | pyenv, venv, uv, dependency security |
| [Decorators & Meta](docs/references/decorators-meta.md) | Decorators, descriptors, metaprogramming |
| [Deployment & Security](docs/references/deployment-security.md) | Docker, production config, OWASP |
| [Project Structure](docs/references/project-structure.md) | Layout, pyproject.toml, CI/CD |
| [Stdlib Essentials](docs/references/stdlib-essentials.md) | pathlib, datetime, collections, re |

## Contributing

PRs welcome. Each file has a clear scope — keep additions focused.
Open an issue before large changes so we can align on direction.

## License

MIT
