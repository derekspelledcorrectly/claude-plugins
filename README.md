# Derek's Claude Code Plugins

Workflow and utility plugins for Claude Code.

## Installation

```bash
# Add the marketplace
/plugin marketplace add derekspelledcorrectly/claude-plugins

# Browse available plugins
/plugin

# Install a specific plugin
/plugin install <plugin-name>@derek-plugins
```

## Available Plugins

| Plugin | Description |
|--------|-------------|
| [chezmoi](plugins/chezmoi/) | Chezmoi-aware dotfile editing guard and expertise. Prevents direct edits to chezmoi-managed files and provides chezmoi workflow guidance. |
| [pr-stack](plugins/pr-stack/) | Plan and implement features as stacks of small, focused PRs using TDD with git-town branch management. |

## Adding a Plugin

Each plugin lives in `plugins/<plugin-name>/` with the standard Claude Code plugin structure:

```
plugins/<plugin-name>/
  .claude-plugin/
    plugin.json
  commands/      # Slash commands (.md)
  agents/        # Subagent definitions (.md)
  skills/        # Skills (subdirs with SKILL.md)
  hooks/         # Event handlers (hooks.json)
```

Register it in `.claude-plugin/marketplace.json` under the `plugins` array.
