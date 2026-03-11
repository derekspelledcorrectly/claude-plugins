# PR Stacking Workflow - Local Configuration

**IMPORTANT**: This file is local to your repository and should never be committed to git. Add `STACK-*.md` to your `.git/info/exclude` file.

This file configures project-specific quality checks and validation commands that the PR stacking implementation agent will run during the TDD cycle.

## How This Works

The implementation agent uses **context-aware selection** to choose which section to run based on what it's doing:

- **Early Iteration Check**: Fast validation during active development (after writing tests/implementation)
- **Pre-Commit Check**: Comprehensive validation before creating a commit
- **Pre-PR Check** (optional): Final validation before proposing the PR on GitHub

### Command Format

- **Individual commands**: Listed as bullet points, executed separately with per-command progress reporting
- **Command chains**: Use `&&` to chain commands, executed as single bash command
- **Auto-detection**: Agent automatically detects format and executes accordingly

## Early Iteration Check

Quick validation during active development. Runs after writing tests or implementation to catch obvious issues fast.

**When this runs**: During TDD RED/GREEN phases, after making code changes

**Example commands**:
- `deno fmt`
- `npm run lint`
- `go fmt ./...`
- `black .`
- `cargo fmt && cargo clippy`

**For this project**:
- `command-here`

## Pre-Commit Check

Thorough validation before creating a commit. This is your quality gate - all checks must pass before committing.

**When this runs**: Step 5 (Quality Check) in the implementation workflow, right before creating the commit

**Example commands**:
- `deno fmt && deno task check`
- `npm run lint && npm run type-check && npm test`
- `go fmt ./... && go vet ./... && go test ./...`
- `pytest && mypy . && black --check .`
- `cargo fmt && cargo clippy && cargo test`

**For this project**:
- `command-here`

## Pre-PR Check (Optional)

Final comprehensive validation before proposing the PR. Use this for expensive operations like full integration tests, E2E tests, or security scans.

**When this runs**: After commit is created, before running `git town propose`

**Example commands**:
- `deno task check:full && deno task test:integration`
- `npm run test:e2e && npm run security-audit`
- `go test -race ./... && go test -bench=.`
- `pytest --cov && safety check`
- `cargo test --all-features && cargo audit`

**For this project** (delete this section if not needed):
- `command-here`

---

## Examples for Common Tech Stacks

### Deno/TypeScript
```markdown
## Early Iteration Check
- `deno fmt`

## Pre-Commit Check
- `deno fmt && deno task check`

## Pre-PR Check
- `deno task check:full`
```

### Node.js/TypeScript
```markdown
## Early Iteration Check
- `npm run format`
- `npm run lint`

## Pre-Commit Check
- `npm run format && npm run lint && npm run type-check && npm test`

## Pre-PR Check
- `npm run test:integration && npm run test:e2e`
```

### Python
```markdown
## Early Iteration Check
- `black .`
- `ruff check .`

## Pre-Commit Check
- `black . && ruff check . && mypy . && pytest`

## Pre-PR Check
- `pytest --cov --cov-report=term-missing && safety check`
```

### Go
```markdown
## Early Iteration Check
- `go fmt ./...`
- `go vet ./...`

## Pre-Commit Check
- `go fmt ./... && go vet ./... && go test ./...`

## Pre-PR Check
- `go test -race ./... && go test -bench=. && staticcheck ./...`
```

### Rust
```markdown
## Early Iteration Check
- `cargo fmt`
- `cargo clippy`

## Pre-Commit Check
- `cargo fmt && cargo clippy && cargo test`

## Pre-PR Check
- `cargo test --all-features && cargo audit && cargo bench`
```

---

## Tips

1. **Keep Early Iteration fast**: Aim for <10 seconds. Fast feedback = faster development.
2. **Make Pre-Commit comprehensive**: This is your quality gate. Include all checks that must pass.
3. **Use Pre-PR for expensive operations**: Integration tests, security scans, benchmarks.
4. **Chain related commands**: Use `&&` to ensure commands run in sequence and fail fast.
5. **Test your commands**: Make sure they work from the repo root before adding them here.

## Troubleshooting

**Commands not running?**
- Ensure the file is named `.stack-workflow.md` exactly
- Place it in the repository root (same level as `.git/`)
- Check that commands work when run manually from repo root

**Commands failing?**
- Agent will show you the error output
- Fix the issue and the agent will re-run the check
- If a command is flaky, consider removing it or fixing the underlying issue

**Want to update commands?**
- Just edit this file directly
- Changes take effect immediately in the next implementation session
- No need to restart Claude Code
