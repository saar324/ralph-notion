#!/usr/bin/env bash

# notion_source.sh - Notion task source for Ralph Loop
# Enables Ralph to pull tasks from Notion database and report results back

# =============================================================================
# CONFIGURATION
# =============================================================================

# These can be set in .ralphrc or environment variables
NOTION_API_KEY="${NOTION_API_KEY:-}"
NOTION_DATABASE_ID="${NOTION_DATABASE_ID:-}"
NOTION_PROJECT_TAG="${NOTION_PROJECT_TAG:-}"  # Filter tasks by project (e.g., "lumutrix")
NOTION_API_VERSION="2022-06-28"

# Status values (customizable via .ralphrc)
NOTION_STATUS_BACKLOG="${NOTION_STATUS_BACKLOG:-backlog}"
NOTION_STATUS_READY="${NOTION_STATUS_READY:-ready}"
NOTION_STATUS_IN_PROGRESS="${NOTION_STATUS_IN_PROGRESS:-in_progress}"
NOTION_STATUS_DONE="${NOTION_STATUS_DONE:-done}"
NOTION_STATUS_STUCK="${NOTION_STATUS_STUCK:-stuck}"

# Column names in Notion (customizable via .ralphrc)
NOTION_COL_TITLE="${NOTION_COL_TITLE:-Task}"
NOTION_COL_STATUS="${NOTION_COL_STATUS:-Status}"
NOTION_COL_PROJECT="${NOTION_COL_PROJECT:-Project}"
NOTION_COL_PRIORITY="${NOTION_COL_PRIORITY:-Priority}"
NOTION_COL_RESULT="${NOTION_COL_RESULT:-Result}"
NOTION_COL_COMMIT="${NOTION_COL_COMMIT:-Commit}"
NOTION_COL_ASSIGNED="${NOTION_COL_ASSIGNED:-Assigned}"

# Ralph directory for state files
RALPH_DIR="${RALPH_DIR:-.ralph}"
NOTION_CURRENT_TASK_FILE="$RALPH_DIR/.notion_current_task"
NOTION_TASK_CACHE_FILE="$RALPH_DIR/.notion_task_cache"

# =============================================================================
# API HELPERS
# =============================================================================

# notion_api_call - Make authenticated API call to Notion
#
# Parameters:
#   $1 (method) - HTTP method (GET, POST, PATCH)
#   $2 (endpoint) - API endpoint (e.g., /databases/xxx/query)
#   $3 (data) - JSON body (optional)
#
# Returns:
#   0 - Success (outputs JSON response)
#   1 - Error
#
notion_api_call() {
    local method=$1
    local endpoint=$2
    local data="${3:-}"

    if [[ -z "$NOTION_API_KEY" ]]; then
        echo "Error: NOTION_API_KEY not set" >&2
        return 1
    fi

    local url="https://api.notion.com/v1${endpoint}"
    local curl_args=(
        -s
        -X "$method"
        -H "Authorization: Bearer $NOTION_API_KEY"
        -H "Notion-Version: $NOTION_API_VERSION"
        -H "Content-Type: application/json"
    )

    if [[ -n "$data" ]]; then
        curl_args+=(-d "$data")
    fi

    local response
    local http_code

    # Make request and capture both response and status code
    response=$(curl "${curl_args[@]}" -w "\n%{http_code}" "$url" 2>/dev/null)
    http_code=$(echo "$response" | tail -1)
    response=$(echo "$response" | sed '$d')

    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        echo "$response"
        return 0
    else
        echo "Error: Notion API returned $http_code" >&2
        echo "$response" >&2
        return 1
    fi
}

# =============================================================================
# AVAILABILITY CHECK
# =============================================================================

# check_notion_available - Check if Notion is configured and accessible
#
# Returns:
#   0 - Notion available
#   1 - Not available
#
check_notion_available() {
    # Check for required config
    if [[ -z "$NOTION_API_KEY" ]]; then
        return 1
    fi

    if [[ -z "$NOTION_DATABASE_ID" ]]; then
        return 1
    fi

    # Check if curl is available
    if ! command -v curl &>/dev/null; then
        return 1
    fi

    # Check if jq is available
    if ! command -v jq &>/dev/null; then
        return 1
    fi

    # Test API connection by fetching database info
    local response
    if ! response=$(notion_api_call "GET" "/databases/$NOTION_DATABASE_ID" 2>/dev/null); then
        return 1
    fi

    # Verify we got a valid database response
    if ! echo "$response" | jq -e '.id' &>/dev/null; then
        return 1
    fi

    return 0
}

# =============================================================================
# TASK FETCHING
# =============================================================================

# fetch_notion_tasks - Fetch tasks from Notion database
#
# Parameters:
#   $1 (status) - Status filter (optional, default: "ready")
#   $2 (limit) - Maximum tasks to fetch (optional, default: 10)
#
# Outputs:
#   JSON array of tasks with id, title, priority, status
#
# Returns:
#   0 - Success
#   1 - Error
#
fetch_notion_tasks() {
    local status="${1:-$NOTION_STATUS_READY}"
    local limit="${2:-10}"

    # Build filter
    local filter="{\"and\": ["

    # Filter by status
    filter+="{\"property\": \"$NOTION_COL_STATUS\", \"select\": {\"equals\": \"$status\"}}"

    # Filter by project if set
    if [[ -n "$NOTION_PROJECT_TAG" ]]; then
        filter+=",{\"property\": \"$NOTION_COL_PROJECT\", \"select\": {\"equals\": \"$NOTION_PROJECT_TAG\"}}"
    fi

    filter+="]}"

    # Build sort (by priority, then by created time)
    local sorts="[{\"property\": \"$NOTION_COL_PRIORITY\", \"direction\": \"ascending\"}, {\"timestamp\": \"created_time\", \"direction\": \"ascending\"}]"

    # Build request body
    local body=$(jq -n \
        --argjson filter "$filter" \
        --argjson sorts "$sorts" \
        --argjson page_size "$limit" \
        '{filter: $filter, sorts: $sorts, page_size: $page_size}')

    # Query database
    local response
    if ! response=$(notion_api_call "POST" "/databases/$NOTION_DATABASE_ID/query" "$body"); then
        return 1
    fi

    # Parse results into simplified format
    echo "$response" | jq '[.results[] | {
        id: .id,
        title: (.properties["'"$NOTION_COL_TITLE"'"].title[0].plain_text // "Untitled"),
        status: (.properties["'"$NOTION_COL_STATUS"'"].select.name // "unknown"),
        priority: (.properties["'"$NOTION_COL_PRIORITY"'"].select.name // "medium"),
        project: (.properties["'"$NOTION_COL_PROJECT"'"].select.name // ""),
        url: .url
    }]'

    return 0
}

# get_next_notion_task - Get the next task to work on
#
# Outputs:
#   JSON object with task details, or empty if no tasks
#
# Returns:
#   0 - Success (may be empty)
#   1 - Error
#
get_next_notion_task() {
    local tasks
    if ! tasks=$(fetch_notion_tasks "$NOTION_STATUS_READY" 1); then
        return 1
    fi

    # Get first task
    local task
    task=$(echo "$tasks" | jq '.[0] // empty')

    if [[ -z "$task" || "$task" == "null" ]]; then
        echo ""
        return 0
    fi

    echo "$task"
    return 0
}

# get_notion_task_count - Get count of tasks in a status
#
# Parameters:
#   $1 (status) - Status to count (optional, default: "ready")
#
# Returns:
#   0 and echoes count
#
get_notion_task_count() {
    local status="${1:-$NOTION_STATUS_READY}"
    local tasks

    if ! tasks=$(fetch_notion_tasks "$status" 100); then
        echo "0"
        return 1
    fi

    echo "$tasks" | jq 'length'
    return 0
}

# =============================================================================
# TASK STATUS UPDATES
# =============================================================================

# update_notion_task_status - Update a task's status
#
# Parameters:
#   $1 (task_id) - Notion page ID
#   $2 (status) - New status value
#
# Returns:
#   0 - Success
#   1 - Error
#
update_notion_task_status() {
    local task_id=$1
    local status=$2

    local body=$(jq -n \
        --arg status "$status" \
        --arg col "$NOTION_COL_STATUS" \
        '{properties: {($col): {select: {name: $status}}}}')

    notion_api_call "PATCH" "/pages/$task_id" "$body" >/dev/null
}

# claim_notion_task - Mark a task as in_progress and assign to this Ralph instance
#
# Parameters:
#   $1 (task_id) - Notion page ID
#
# Returns:
#   0 - Success
#   1 - Error
#
claim_notion_task() {
    local task_id=$1
    local hostname=$(hostname -s 2>/dev/null || echo "unknown")
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local body=$(jq -n \
        --arg status "$NOTION_STATUS_IN_PROGRESS" \
        --arg status_col "$NOTION_COL_STATUS" \
        --arg assigned_col "$NOTION_COL_ASSIGNED" \
        --arg assigned "$hostname" \
        '{properties: {
            ($status_col): {select: {name: $status}},
            ($assigned_col): {rich_text: [{text: {content: $assigned}}]}
        }}')

    if notion_api_call "PATCH" "/pages/$task_id" "$body" >/dev/null; then
        # Save current task info locally
        echo "$task_id" > "$NOTION_CURRENT_TASK_FILE"
        return 0
    fi

    return 1
}

# complete_notion_task - Mark a task as done with result notes
#
# Parameters:
#   $1 (task_id) - Notion page ID
#   $2 (result) - Result notes/summary (optional)
#   $3 (commit_url) - Git commit URL (optional)
#
# Returns:
#   0 - Success
#   1 - Error
#
complete_notion_task() {
    local task_id=$1
    local result="${2:-Completed by Ralph}"
    local commit_url="${3:-}"

    # Truncate result to 2000 chars (Notion limit)
    result="${result:0:2000}"

    # Build properties update
    local properties="{\"$NOTION_COL_STATUS\": {\"select\": {\"name\": \"$NOTION_STATUS_DONE\"}}}"

    # Add result if provided
    if [[ -n "$result" ]]; then
        properties=$(echo "$properties" | jq --arg result "$result" --arg col "$NOTION_COL_RESULT" \
            '. + {($col): {rich_text: [{text: {content: $result}}]}}')
    fi

    # Add commit URL if provided
    if [[ -n "$commit_url" ]]; then
        properties=$(echo "$properties" | jq --arg url "$commit_url" --arg col "$NOTION_COL_COMMIT" \
            '. + {($col): {url: $url}}')
    fi

    local body=$(jq -n --argjson props "$properties" '{properties: $props}')

    if notion_api_call "PATCH" "/pages/$task_id" "$body" >/dev/null; then
        # Clear current task file
        rm -f "$NOTION_CURRENT_TASK_FILE"
        return 0
    fi

    return 1
}

# mark_notion_task_stuck - Mark a task as stuck with notes
#
# Parameters:
#   $1 (task_id) - Notion page ID
#   $2 (reason) - Why the task is stuck
#
# Returns:
#   0 - Success
#   1 - Error
#
mark_notion_task_stuck() {
    local task_id=$1
    local reason="${2:-Ralph encountered an issue}"

    # Truncate reason
    reason="${reason:0:2000}"

    local body=$(jq -n \
        --arg status "$NOTION_STATUS_STUCK" \
        --arg status_col "$NOTION_COL_STATUS" \
        --arg result "$reason" \
        --arg result_col "$NOTION_COL_RESULT" \
        '{properties: {
            ($status_col): {select: {name: $status}},
            ($result_col): {rich_text: [{text: {content: $result}}]}
        }}')

    if notion_api_call "PATCH" "/pages/$task_id" "$body" >/dev/null; then
        rm -f "$NOTION_CURRENT_TASK_FILE"
        return 0
    fi

    return 1
}

# =============================================================================
# TASK PROMPT GENERATION
# =============================================================================

# generate_notion_prompt - Generate a PROMPT.md from a Notion task
#
# Parameters:
#   $1 (task_json) - Task JSON object from get_next_notion_task
#
# Outputs:
#   Prompt content suitable for Claude Code
#
generate_notion_prompt() {
    local task_json=$1

    local title=$(echo "$task_json" | jq -r '.title // "No title"')
    local priority=$(echo "$task_json" | jq -r '.priority // "medium"')
    local project=$(echo "$task_json" | jq -r '.project // "unknown"')
    local task_id=$(echo "$task_json" | jq -r '.id // ""')
    local task_url=$(echo "$task_json" | jq -r '.url // ""')

    cat << PROMPT_EOF
# Task: $title

## Context
- **Project**: $project
- **Priority**: $priority
- **Task ID**: $task_id
- **Notion URL**: $task_url

## Instructions

Complete the following task. When finished:
1. Ensure all changes are working correctly
2. Run any relevant tests
3. Commit your changes with a descriptive message

## Task Description

$title

## Completion Criteria

- [ ] Task requirements are fully implemented
- [ ] Code compiles/runs without errors
- [ ] Relevant tests pass
- [ ] Changes are committed

When you have completed all items, include the following in your response:
\`\`\`
RALPH_STATUS:
EXIT_SIGNAL=true
WORK_SUMMARY=<brief description of what was done>
\`\`\`
PROMPT_EOF
}

# =============================================================================
# CURRENT TASK MANAGEMENT
# =============================================================================

# get_current_notion_task - Get the currently claimed task ID
#
# Returns:
#   Task ID if one is claimed, empty otherwise
#
get_current_notion_task() {
    if [[ -f "$NOTION_CURRENT_TASK_FILE" ]]; then
        cat "$NOTION_CURRENT_TASK_FILE"
    else
        echo ""
    fi
}

# clear_current_notion_task - Clear the current task (abandon without updating Notion)
#
clear_current_notion_task() {
    rm -f "$NOTION_CURRENT_TASK_FILE"
}

# =============================================================================
# TELEGRAM NOTIFICATION HELPERS
# =============================================================================

# These functions help format messages for the Telegram bot integration

# format_task_for_telegram - Format a task for Telegram notification
#
# Parameters:
#   $1 (task_json) - Task JSON object
#   $2 (status) - Current status message
#
format_task_for_telegram() {
    local task_json=$1
    local status="${2:-Working on task}"

    local title=$(echo "$task_json" | jq -r '.title // "Unknown"')
    local priority=$(echo "$task_json" | jq -r '.priority // "medium"')
    local project=$(echo "$task_json" | jq -r '.project // "unknown"')

    echo "🔄 *$status*"
    echo ""
    echo "📋 *Task:* $title"
    echo "📁 *Project:* $project"
    echo "⚡ *Priority:* $priority"
}

# =============================================================================
# EXPORTS
# =============================================================================

export -f notion_api_call
export -f check_notion_available
export -f fetch_notion_tasks
export -f get_next_notion_task
export -f get_notion_task_count
export -f update_notion_task_status
export -f claim_notion_task
export -f complete_notion_task
export -f mark_notion_task_stuck
export -f generate_notion_prompt
export -f get_current_notion_task
export -f clear_current_notion_task
export -f format_task_for_telegram
