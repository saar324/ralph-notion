# Notion Integration for Ralph Loop

This fork adds Notion as a task source for Ralph, enabling autonomous task execution across multiple servers pulling from a shared Notion database.

## Quick Start

1. **Create a Notion Integration**
   - Go to https://www.notion.so/my-integrations
   - Create a new integration
   - Copy the secret token

2. **Set Up Your Database**

   Create a Notion database with these columns:

   | Column | Type | Purpose |
   |--------|------|---------|
   | Task | Title | Task description |
   | Status | Select | `backlog`, `ready`, `in_progress`, `done`, `stuck` |
   | Project | Select | Project filter (e.g., `lumutrix`, `bunnybite`) |
   | Priority | Select | `high`, `medium`, `low` |
   | Result | Text | Notes from Ralph after completion |
   | Commit | URL | Link to commit if applicable |
   | Assigned | Text | Hostname of server working on task |

3. **Share Database with Integration**
   - Open your database in Notion
   - Click "Share" → "Invite"
   - Select your integration

4. **Configure Ralph**

   Create `.ralphrc` in your project:
   ```bash
   NOTION_API_KEY="secret_xxx"
   NOTION_DATABASE_ID="your_database_id"
   NOTION_PROJECT_TAG="myproject"  # Optional: filter by project
   ```

5. **Run Ralph in Notion Mode**
   ```bash
   ralph --notion
   # or with monitoring
   ralph --notion --monitor
   ```

## How It Works

```
┌─────────────────────────────────────────────────────┐
│                     NOTION                          │
│           (shared task database)                    │
└──────────┬─────────────┬─────────────┬──────────────┘
           │             │             │
           ▼             ▼             ▼
     ┌───────────┐ ┌───────────┐ ┌───────────┐
     │ Server A  │ │ Server B  │ │ Server C  │
     │ Project A │ │ Project B │ │ Project C │
     │           │ │           │ │           │
     │ ralph     │ │ ralph     │ │ ralph     │
     │ --notion  │ │ --notion  │ │ --notion  │
     └───────────┘ └───────────┘ └───────────┘
```

Each server:
1. Polls Notion for tasks with status `ready` and matching project tag
2. Claims the highest priority task (sets to `in_progress`)
3. Generates a prompt from the task description
4. Runs Claude Code to complete the task
5. Updates Notion with results (`done` or `stuck`)
6. Moves to the next task

## Task Workflow

```
backlog → ready → in_progress → done
                      ↓
                    stuck
```

- **backlog**: Task added, not yet reviewed/approved
- **ready**: Task approved and ready for Ralph to pick up
- **in_progress**: Ralph is working on it
- **done**: Task completed successfully
- **stuck**: Ralph couldn't complete it, needs human intervention

## Commands

```bash
# Run in Notion mode
ralph --notion

# Run with monitoring (tmux)
ralph --notion --monitor

# Check Notion task counts
ralph --notion-status

# Run with verbose logging
ralph --notion --verbose
```

## Configuration Options

All Notion settings can be customized in `.ralphrc`:

```bash
# Required
NOTION_API_KEY="secret_xxx"
NOTION_DATABASE_ID="xxx"

# Optional
NOTION_PROJECT_TAG="myproject"      # Filter by project
NOTION_POLL_INTERVAL=30             # Seconds between polls when no tasks

# Status values (customize to match your database)
NOTION_STATUS_BACKLOG="backlog"
NOTION_STATUS_READY="ready"
NOTION_STATUS_IN_PROGRESS="in_progress"
NOTION_STATUS_DONE="done"
NOTION_STATUS_STUCK="stuck"

# Column names (customize to match your database schema)
NOTION_COL_TITLE="Task"
NOTION_COL_STATUS="Status"
NOTION_COL_PROJECT="Project"
NOTION_COL_PRIORITY="Priority"
NOTION_COL_RESULT="Result"
NOTION_COL_COMMIT="Commit"
NOTION_COL_ASSIGNED="Assigned"
```

## Multi-Server Setup

To run Ralph on multiple servers pulling from the same Notion database:

1. Clone this repo on each server
2. Create `.ralphrc` on each server with:
   - Same `NOTION_API_KEY` and `NOTION_DATABASE_ID`
   - Different `NOTION_PROJECT_TAG` for each project
3. Run `ralph --notion` on each server

Each server will automatically:
- Only pick up tasks tagged with its project
- Mark tasks as `in_progress` when claimed (prevents duplicates)
- Update results back to Notion when done

## Telegram Integration

If you have the Claude Telegram bot on each server, it works alongside Ralph:
- Ralph handles autonomous task processing
- Telegram bot provides manual intervention when tasks get stuck
- Both update the same Notion database
