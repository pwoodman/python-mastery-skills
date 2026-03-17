# CLI & Scripting — Click, Typer, subprocess

## Table of Contents
1. Typer — Modern CLIs (Recommended)
2. Click — Flexible CLIs
3. argparse — Stdlib Option
4. Script Design Patterns
5. subprocess Automation
6. Rich — Terminal Output

---

## 1. Typer — Modern CLIs (Recommended)

Typer uses Python type hints to define CLI interfaces. Least boilerplate, best for new code.

```python
# cli.py
import typer
from pathlib import Path
from typing import Annotated

app = typer.Typer(help="My data processing tool")

@app.command()
def process(
    input_file: Annotated[Path, typer.Argument(help="Input CSV file")],
    output_dir: Annotated[Path, typer.Option("--output", "-o", help="Output directory")] = Path("./output"),
    verbose: Annotated[bool, typer.Option("--verbose", "-v")] = False,
    limit: Annotated[int, typer.Option(help="Max rows to process")] = 0,
) -> None:
    """Process an input CSV and write results to output directory."""
    if not input_file.exists():
        typer.echo(f"Error: {input_file} not found", err=True)
        raise typer.Exit(code=1)

    output_dir.mkdir(parents=True, exist_ok=True)

    if verbose:
        typer.echo(f"Processing {input_file} → {output_dir}")

    with typer.progressbar(read_records(input_file), label="Processing") as records:
        for record in records:
            process_record(record, output_dir)

    typer.echo(typer.style("Done!", fg=typer.colors.GREEN))

# Sub-commands
users_app = typer.Typer()
app.add_typer(users_app, name="users")

@users_app.command("create")
def create_user(name: str, email: str) -> None:
    """Create a new user."""
    ...

@users_app.command("list")
def list_users(active_only: bool = False) -> None:
    """List users."""
    ...

if __name__ == "__main__":
    app()
```

```
# Usage:
python cli.py data.csv --output ./results --verbose
python cli.py users create "Pat Taylor" pat@x.com
python cli.py users list --active-only
python cli.py --help
```

### Entry Point in pyproject.toml

```toml
[project.scripts]
myapp = "myapp.cli:app"
```

After `pip install -e .` → `myapp` is available as a system command.

---

## 2. Click — Flexible CLIs

Click has more configuration options than Typer. Good when you need precise control.

```python
import click

@click.group()
@click.version_option(version="1.0.0")
@click.option("--config", "-c", type=click.Path(exists=True), help="Config file path")
@click.pass_context
def cli(ctx: click.Context, config: str | None) -> None:
    """My CLI application."""
    ctx.ensure_object(dict)
    ctx.obj["config"] = load_config(config) if config else {}

@cli.command()
@click.argument("filename", type=click.Path(exists=True))
@click.option("--format", "-f", type=click.Choice(["csv", "json", "parquet"]), default="csv")
@click.option("--dry-run", is_flag=True, default=False, help="Preview without writing")
@click.pass_context
def export(ctx: click.Context, filename: str, format: str, dry_run: bool) -> None:
    """Export data to specified format."""
    if dry_run:
        click.echo(f"[DRY RUN] Would export {filename} as {format}")
        return
    data = load(filename)
    write(data, format)
    click.echo(click.style(f"Exported {len(data)} records", fg="green"))

@cli.command()
@click.argument("user_id", type=int)
@click.confirmation_option(prompt="Are you sure you want to delete this user?")
def delete_user(user_id: int) -> None:
    """Delete a user (requires confirmation)."""
    user_service.delete(user_id)
    click.echo(f"Deleted user {user_id}")

if __name__ == "__main__":
    cli()
```

### Click Input Prompts

```python
@cli.command()
def configure() -> None:
    api_key = click.prompt("Enter API key", hide_input=True)
    environment = click.prompt("Environment", type=click.Choice(["dev", "prod"]), default="dev")
    if click.confirm("Save these settings?"):
        save_config(api_key, environment)
```

---

## 3. argparse — Stdlib Option

Use for scripts that need no dependencies, or when embedding in a larger system.

```python
import argparse
import sys

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mytool",
        description="Process data files",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("input", help="Input file path")
    parser.add_argument("-o", "--output", default="./output", help="Output directory")
    parser.add_argument("-v", "--verbose", action="store_true")
    parser.add_argument("--limit", type=int, default=0, metavar="N", help="Max records")
    parser.add_argument(
        "--format",
        choices=["csv", "json"],
        default="csv",
    )
    return parser

def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        run(args)
        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())
```

---

## 4. Script Design Patterns

### Canonical Script Structure

```python
#!/usr/bin/env python3
"""
Script description.

Usage:
    python script.py [options] <input>
"""
import logging
import sys
from pathlib import Path

logger = logging.getLogger(__name__)

def setup_logging(verbose: bool) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)s %(message)s",
        datefmt="%H:%M:%S",
    )

def main() -> int:
    """Entry point. Returns exit code."""
    # Parse args here
    try:
        run()
        return 0
    except KeyboardInterrupt:
        print("\nAborted.")
        return 130
    except Exception as e:
        logger.error("Fatal error: %s", e, exc_info=True)
        return 1

if __name__ == "__main__":
    sys.exit(main())
```

### Progress Reporting

```python
from rich.progress import Progress, SpinnerColumn, TimeElapsedColumn

with Progress(SpinnerColumn(), *Progress.get_default_columns(), TimeElapsedColumn()) as progress:
    task = progress.add_task("Processing...", total=len(items))
    for item in items:
        process(item)
        progress.advance(task)
```

---

## 5. subprocess Automation

```python
import subprocess
from pathlib import Path

def run_command(
    args: list[str],
    *,
    cwd: Path | None = None,
    env: dict | None = None,
    timeout: float | None = 60.0,
) -> str:
    """Run a shell command and return stdout. Raises on error."""
    result = subprocess.run(
        args,
        capture_output=True,
        text=True,
        cwd=cwd,
        env=env,
        timeout=timeout,
        check=True,     # raises CalledProcessError on non-zero exit
    )
    return result.stdout.strip()

# Examples
git_hash  = run_command(["git", "rev-parse", "--short", "HEAD"])
file_list = run_command(["find", ".", "-name", "*.py"], cwd=Path("src"))

# When check=False — inspect return code yourself
result = subprocess.run(["pytest", "--tb=short"], capture_output=True, text=True)
if result.returncode != 0:
    logger.warning("Tests failed:\n%s", result.stdout)
    return False
return True

# Real-time output streaming (long-running processes)
def stream_command(args: list[str]) -> int:
    with subprocess.Popen(args, stdout=subprocess.PIPE, text=True) as proc:
        for line in proc.stdout:
            print(line, end="", flush=True)
    return proc.returncode
```

### Shell Script Replacement Patterns

```python
from pathlib import Path
import shutil

# Shell: cp -r src/ dst/
shutil.copytree("src", "dst")

# Shell: find . -name "*.pyc" -delete
for f in Path(".").rglob("*.pyc"):
    f.unlink()

# Shell: mkdir -p /some/deep/path
Path("/some/deep/path").mkdir(parents=True, exist_ok=True)

# Shell: ls *.csv | head -5
csv_files = sorted(Path(".").glob("*.csv"))[:5]

# Shell: wc -l file.txt
line_count = Path("file.txt").read_text().count("\n")

# Shell: cat a.txt b.txt > combined.txt
combined = Path("combined.txt")
for source in [Path("a.txt"), Path("b.txt")]:
    combined.write_text(combined.read_text() + source.read_text() if combined.exists() else source.read_text())
```

---

## 6. Rich — Terminal Output

```python
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.syntax import Syntax
from rich import print as rprint   # drop-in rich print

console = Console()

# Styled output
console.print("[bold green]Success![/bold green]")
console.print("[red]Error:[/red] something went wrong")
console.log("Processing complete", style="dim")  # adds timestamp

# Pretty-print data structures
rprint({"key": "value", "numbers": [1, 2, 3]})

# Tables
table = Table(title="Order Summary", show_header=True)
table.add_column("ID", style="dim")
table.add_column("Customer")
table.add_column("Total", justify="right")
for order in orders:
    table.add_row(str(order.id), order.customer, f"${order.total:.2f}")
console.print(table)

# Panels for emphasis
console.print(Panel("Build complete in 2.4s", title="Done", border_style="green"))

# Syntax highlighting
code = Path("script.py").read_text()
console.print(Syntax(code, "python", theme="github-dark", line_numbers=True))
```
