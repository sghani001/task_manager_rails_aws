<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:0A071B,50:1A1235,100:635BFF&height=200&section=header&text=Task%20Manager&fontSize=48&fontColor=ffffff&fontAlignY=38&desc=Real-Time%20Hotwire%20Kanban%20%C2%B7%20Rails%208&descSize=18&descAlignY=58&descColor=635BFF" width="100%" />

<br/>

[![Rails Version](https://img.shields.io/badge/Rails-8.1.3-CC0000?style=for-the-badge&logo=ruby-on-rails&logoColor=white)](https://rubyonrails.org/)
[![Ruby Version](https://img.shields.io/badge/Ruby-3.x-CC0000?style=for-the-badge&logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![Database](https://img.shields.io/badge/PostgreSQL-Active-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org/)

<br/>

> *A high-performance, single-page Kanban interface powered by the server-driven Hotwire stack—zero custom JavaScript tracking state.*

</div>

---

## 🖥️ App Demonstration

<video src="https://github.com/user-attachments/assets/139a80f2-1122-4230-a889-acf44fd8e17c" autoplay loop muted playsinline width="100%" style="border-radius: 8px; border: 1px solid #1A1235; max-height: 500px; object-fit: cover;"></video>

---

## 🛠️ Tech Stack & Architecture

The architecture leverages the modern Rails 8 framework to deliver an SPA-like experience with zero Node.js compilation dependencies.

| Layer | Technology | Role |
| :--- | :--- | :--- |
| **Backend Framework** | `Ruby on Rails 8.1.3` | Core MVC domain and business logic |
| **Database** | `PostgreSQL` | Relational storage engine |
| **Real-time Pipeline** | `ActionCable` + `SolidCable` | Full-duplex WebSocket management |
| **Frontend Reactive** | `Hotwire (Drive, Frames, Streams)` | Server-driven HTML fragment differential updates |
| **Client Interaction** | `Stimulus` | Hardware-accelerated Drag & Drop API binding |
| **Asset Pipeline** | `Importmap` | Production asset loading without a build step |
| **Background Processing**| `SolidQueue` + `Mission Control` | Async execution engine & administration dashboard |

---

## ✨ Key Features

### 📋 Reactive Kanban Board
* **State Categorization:** Three-column layout tracking **To Do**, **In Progress**, and **Completed** paradigms.
* **Instant Manipulation:** Create items dynamically via inline UI controls or cycle card phases instantly using localized action bindings.
* **Fluid Drag-and-Drop:** Native HTML Drag & Drop API interface wired directly through optimized Stimulus lifecycles.

### ⚡ Concurrent Live Sync
When any entity state mutates (create, update, delete), changes stream asynchronously to **all connected browser instances** via WebSockets. Interface nodes update instantly without full-page reloads.

### ⏳ Asynchronous Background Estimations
Card creation dispatches an analytical wrapper (`TaskDurationEstimateJob`) to a database-backed queue to mock or call decoupled integrations (e.g., AWS Lambda workflows):
1. **Immediate State:** Displays a localized `⏳ Estimating duration...` spinner instantly upon record persistence.
2. **Resolved State:** The worker completes computational analysis and pushes state transformations (`estimating` ➔ `done`) globally across the streaming channel.

---

## 🔄 Dynamic Streams & Websocket Pipeline

### 🌐 Server-Driven Turbo Streams

| HTTP Action | Target Controller Context | Layout Side Effects |
| :--- | :--- | :--- |
| **Create** | `create.turbo_stream.erb` | Prepends entity markup, resets form state, and increments section counts. |
| **Update (Phase Switch)** | `update.turbo_stream.erb` | Re-evaluates both origin and target frames, resolving empty states cleanly. |
| **Update (Content Inline)**| `update.turbo_stream.erb` | Hot-swaps the distinct card view components in-place. |
| **Destroy** | `destroy.turbo_stream.erb` | Purges node trees from the DOM and recalculates dashboard column metrics. |

### 🛰️ ActionCable Multi-Client Broadcasting
Models employ strict lifecycle triggers (`broadcasts_to`) to delegate messaging directly onto private tenant keys (`tasks_<user_id>`). Intermittent heavy states manually pass down mutations via explicit overrides:

```ruby
# Pushing background processing changes directly to the UI layer
Turbo::StreamsChannel.broadcast_replace_to(
  stream_identifier, 
  target: "task_#{id}", 
  partial: "tasks/task", 
  locals: { task: self }
)

```

### 🎛️ Stimulus Drag-and-Drop Layer

`app/javascript/controllers/task_board_controller.js` intercepts client pointer events to coordinate layout behaviors:

* Manages runtime drop-zone states (`dragenter`, `dragleave`, visual scale shifts).
* Dispatches an asynchronous native `fetch` payload (`PATCH /tasks/:id`) containing explicit form tokens.
* Configures header parameters to negotiate strict responses: `Accept: text/vnd.turbo-stream.html`. This pipes the returned raw HTML directly back into `Turbo.renderStreamMessage(html)` for fast client-side painting.

---

## 🚀 Getting Started

### Prerequisites

* **Ruby:** `^3.x`
* **Database:** `PostgreSQL`
* **Dependency Manager:** `Bundler`

### Setup & Infrastructure Provisioning

```bash
git clone <repo-url>
cd task_manager
bundle install
rails db:create db:migrate db:seed

```

### Execution

Boot up the integrated configuration environment:

```bash
bin/dev

```

*The ecosystem binds directly to `http://localhost:3000`. A persistent demo sandbox account (`demo@example.com` / `password`) evaluates auto-creation mechanisms seamlessly upon initial route access.*

### Test Execution

```bash
rails test

```

---

## 📦 Production Deployment

The production container profile relies on native multi-stage `Dockerfile` environments and automated orchestration via [Kamal](https://kamal-deploy.org/).

### Essential Environment Schemas

Ensure target staging platforms expose the following systemic primitives:

* `RAILS_MASTER_KEY`: Core cryptographic environment initialization block.
* `MISSION_CONTROL_USERNAME` / `MISSION_CONTROL_PASSWORD`: Credential parameters mapping explicit access to route interfaces at `/jobs`.
<img src="https://capsule-render.vercel.app/api?type=waving&color=0:635BFF,50:1A1235,100:0A071B&height=120&section=footer&fontSize=1" width="100%" />
