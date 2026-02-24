# Ralph Notion

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> Notion as a task source for [Ralph](https://github.com/frankbria/ralph-claude-code) autonomous development loops.

This fork adds Notion integration to Ralph, letting multiple servers pull tasks from a shared Notion database and execute them autonomously with Claude Code.

## How It Works

```
               NOTION DATABASE
          (shared task board for all servers)
          ┌──────────────────────────┐
          │  Task A  │ ready  │ high │
          │  Task B  │ ready  │ med  │
          │  Task C  │ done   │ low  │
          └─────┬────────┬──────────┘
                │        │
        ┌───────┘        └───────┐
        ▼                        ▼
   ┌──────────┐            ┌──────────┐
   │ Server A │            │ Server B │
   │ ralph    │            │ ralph    │
   │ --notion │            │ --notion │
   └──────────┘            └──────────┘
```

Each server polls Notion for `ready` tasks, claims one, runs Claude Code to complete it, and updates Notion with the result (`done` or `stuck`).

## Quick Start

### 1. Install Ralph

```bash
git clone https://github.com/saar324/ralph-notion.git
cd ralph-notion
./install.sh
```

### 2. Set Up Notion

Create a [Notion integration](https://www.notion.so/my-integrations) and a database with these columns:

| Column | Type | Values |
|--------|------|--------|
| Task | Title | Task description |
| Status | Select | `backlog`, `ready`, `in_progress`, `done`, `stuck` |
| Project | Select | Your project tags |
| Priority | Select | `high`, `medium`, `low` |
| Result | Text | Filled by Ralph after completion |
| Commit | URL | Filled by Ralph with commit link |
| Assigned | Text | Filled by Ralph with server hostname |

Share the database with your integration (Share > Invite > select integration).

### 3. Configure

Create `.ralphrc` in your project directory:

```bash
NOTION_API_KEY="secret_xxx"
NOTION_DATABASE_ID="your_database_id"
NOTION_PROJECT_TAG="myproject"       # optional: filter by project
```

See [sample-ralphrc-notion](sample-ralphrc-notion) for all available options.

### 4. Run

```bash
ralph --notion                # basic
ralph --notion --monitor      # with tmux dashboard
ralph --notion --verbose      # with detailed logging
ralph --notion-status         # check task counts
```

## Task Workflow

```
backlog → ready → in_progress → done
                       ↓
                     stuck
```

- **backlog** - task added, not yet approved
- **ready** - approved, Ralph will pick it up
- **in_progress** - Ralph is working on it
- **done** - completed successfully
- **stuck** - Ralph couldn't finish, needs human help

## Multi-Server Setup

Run Ralph on multiple servers pulling from the same Notion database:

1. Install on each server
2. Use the same `NOTION_API_KEY` and `NOTION_DATABASE_ID`
3. Set a different `NOTION_PROJECT_TAG` per project
4. Run `ralph --notion` on each server

Tasks are claimed atomically (set to `in_progress` on pickup) so no two servers work the same task.

## Run as a Service

```bash
# Install as systemd service (auto-starts on boot)
./install-service.sh /path/to/your/project
```

## Configuration Reference

All settings go in `.ralphrc`. See [sample-ralphrc-notion](sample-ralphrc-notion) for the full list, including:

- Notion API credentials and database ID
- Custom status values and column names
- Claude Code timeout and rate limiting
- Session management and circuit breaker thresholds

## More Details

- [NOTION.md](NOTION.md) - full Notion integration docs
- [docs/user-guide/](docs/user-guide/) - Ralph user guide
- [TESTING.md](TESTING.md) - running the test suite (566 tests)
- [CONTRIBUTING.md](CONTRIBUTING.md) - contributor guide

## Based On

This is a fork of [Ralph for Claude Code](https://github.com/frankbria/ralph-claude-code) by Frank Bria, which implements the [Ralph technique](https://ghuntley.com/ralph/) by Geoffrey Huntley.

## License

MIT - see [LICENSE](LICENSE).
