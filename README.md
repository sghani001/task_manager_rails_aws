# Task Manager

A real-time Kanban board built with **Ruby on Rails 8** using the **Hotwire** stack — **Turbo Streams**, **ActionCable**, and **Stimulus** — for a fast, server-driven single-page experience without writing custom JavaScript.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Ruby on Rails 8.1.3 |
| Database | PostgreSQL |
| Real-time | ActionCable + SolidCable |
| Frontend | Hotwire (Turbo Drive, Turbo Frames, Turbo Streams) |
| JS Framework | Stimulus |
| JS Bundling | Importmap (no Node/Webpack build step) |
| Background Jobs | SolidQueue |
| Job Monitoring | Mission Control Jobs |

## Key Features

### Task Board (Kanban)
- Three-column board: **To Do**, **In Progress**, **Completed**
- Create tasks via inline form
- Move tasks between columns with **status buttons** on each card
- **Drag-and-drop** between columns (HTML Drag & Drop API via Stimulus)

### Real-Time Updates via ActionCable
When a task is created, updated, or deleted, changes are broadcast to **all connected browsers** over ActionCable via Turbo Streams. Other users see cards appear, move, or update without refreshing.

### Async Duration Estimation
When a task is created, a background job (`TaskDurationEstimateJob`) simulates a slow async process (e.g., calling an external API like AWS Lambda/Textract). The card shows:
1. A "⏳ Estimating duration..." spinner immediately
2. The estimated duration once the job completes

The status transitions (`estimating` → `done`) are broadcast in real-time via ActionCable.

## How Turbo Streams & ActionCable Are Used

### Turbo Streams (Server-Responded)

Turbo Streams deliver HTML fragments over regular HTTP responses. The controller responds with `format.turbo_stream` for create, update, and destroy actions.

| Action | File | Behavior |
|--------|------|----------|
| **Create** | `create.turbo_stream.erb` | Prepends task to To Do column, resets the form, updates the To Do count badge |
| **Update** (status changed) | `update.turbo_stream.erb` | Replaces both affected column frames (old + new status) so cards move and empty states render; updates both count badges |
| **Update** (no status change) | `update.turbo_stream.erb` | Replaces the task card in-place |
| **Destroy** | `destroy.turbo_stream.erb` | Removes the task card, updates the affected column's count badge |

**Column frame replacement** on status change ensures that:
- Moving the last card out of a column shows the "No tasks in this column yet." empty state
- Dropping a card into an empty column properly renders the card
- Both columns are updated in a single response

### ActionCable (Broadcast to All Clients)

The `Task` model uses `broadcasts_to` to automatically broadcast create/update/destroy events to the `tasks_<user_id>` stream. Additionally, `TaskDurationEstimateJob` manually calls `Turbo::StreamsChannel.broadcast_replace_to` to push estimation status updates to all connected browsers.

| Event | Source | What Happens |
|-------|--------|-------------|
| Task created | Model broadcast | Card is prepended to the To Do column in all open browsers |
| Task updated (non-status) | Model broadcast | Card content is replaced in-place |
| Task deleted | Model broadcast | Card is removed from all open browsers |
| Estimation started | Background job | Card shows "Estimating..." spinner via `broadcast_replace_to` |
| Estimation complete | Background job | Card shows the estimate via `broadcast_replace_to` |

### Stimulus Controller: Drag-and-Drop

`app/javascript/controllers/task_board_controller.js` handles the HTML Drag & Drop API:

- `dragStart` / `dragEnd` — manages visual feedback (opacity, rotation, column highlighting)
- `dragOver` / `dragEnter` / `dragLeave` — highlights the target column
- `drop` — sends a `PATCH /tasks/:id` with `task[status]=new_status` via `fetch`, then processes the Turbo Stream response with `Turbo.renderStreamMessage(html)` to update the DOM

The fetch uses `Accept: text/vnd.turbo-stream.html` so the server returns a Turbo Stream response, which is then rendered client-side by Turbo — no JSON API needed.

## Getting Started

### Prerequisites

- Ruby 3.x
- PostgreSQL
- Bundler

### Setup

```bash
git clone <repo-url>
cd task_manager
bundle install
rails db:create db:migrate db:seed
rails server
```

Visit `http://localhost:3000`. The app auto-creates a demo user (`demo@example.com` / `password`).

### Running Tests

```bash
rails test
```

## Deployment

The app includes a `Dockerfile` and `.kamal/` deploy hooks for [Kamal](https://kamal-deploy.org/). Environment variables required:

- `MISSION_CONTROL_USERNAME` / `MISSION_CONTROL_PASSWORD` — for the job monitoring dashboard at `/jobs`
- `RAILS_MASTER_KEY` — for credentials
