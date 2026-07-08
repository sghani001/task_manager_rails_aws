Project 1: Task Manager — Rails + Hotwire (Turbo Streams, ActionCable, Background Jobs) + Production AWS Deployment

**What:** Full-stack task management app, real-time by default, **no React** — Rails renders HTML, Turbo Streams push diffs over ActionCable, and a background job demonstrates async work pushing a live UI update on completion. **Stack:** Rails 7 (full-stack, Hotwire) + PostgreSQL + Turbo Rails + Stimulus + ActionCable + Solid Queue (or Sidekiq) + VPC + EC2 + RDS + EBS + CloudWatch + IAM **Time:** 6-8h core + 5-6h AWS deployment extension **Cost:** $0 (stay within free-tier instance types/hours)

### Architecture (core app)

```
Browser (Turbo Drive + Turbo Frames)
    ↓ (normal HTML form submits)
Rails Controller
    ↓ renders turbo_stream.erb → also broadcasts
Task model (Turbo::Broadcastable)
    ↓ (WebSocket, over ActionCable)
Turbo Streams Channel  →  every open tab/browser updates automatically
    ↑
Background Job (ActiveJob) — finishes async work, then broadcasts its own Turbo Stream update
    ↓
PostgreSQL
```

The key mental shift from the React version: there is no client-side state, no `fetch`/`axios`, no manual DOM diffing. A form submit or a background job finishing both do the same thing — they broadcast a `<turbo-stream>` fragment, and every connected browser patches its DOM to match, no JS required.

### Step 1: Create the Rails app (full-stack, not `--api`)

```bash
rails new task_manager --database=postgresql
cd task_manager
bundle install
```

Rails 7 ships with `turbo-rails` and `stimulus-rails` in the Gemfile by default (via importmap) — nothing extra to install for Hotwire itself. Add a job backend:

```ruby
# Gemfile
gem "solid_queue" # Rails 7.1+ built-in, simplest option — or gem "sidekiq" if you prefer Redis-backed
```

```bash
bin/rails solid_queue:install
```

### Step 2: Generate the Task model

```bash
rails g model Task title:string description:text status:string user_id:integer duration_estimate:string
rails g model User email:string password_digest:string
rails db:create
rails db:migrate
```

### Step 3: Turbo Streams over ActionCable — automatic model broadcasting

You don't need a hand-rolled `ActionCable.server.broadcast` call or a custom channel here — `Turbo::Broadcastable` (built into every `ApplicationRecord` in Rails 7) does exactly that, but sends a `<turbo-stream>` HTML fragment instead of raw JSON, so the browser patches the DOM directly.

**app/models/task.rb:**

```ruby
class Task < ApplicationRecord
  belongs_to :user
  broadcasts_to ->(task) { "tasks_#{task.user_id}" }, inserts_by: :prepend
end
```

That one line replaces the entire `after_create_commit` / `after_update_commit` / `after_destroy_commit` block from the JSON-API version — `broadcasts_to` wires all three lifecycle callbacks automatically and renders the `Task` partial as the stream fragment.

If you want a named channel explicitly (useful once you add more than one broadcasting model), you can still scaffold one:

```bash
rails generate channel tasks
```

**app/channels/tasks_channel.rb:**

```ruby
class TasksChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user
  end
end
```

### Step 4: Controller — renders HTML by default, Turbo Stream when needed

```ruby
# config/routes.rb
Rails.application.routes.draw do
  resources :tasks
  root "tasks#index"
end
```

**app/controllers/tasks_controller.rb:**

```ruby
class TasksController < ApplicationController
  before_action :set_task, only: [:update, :destroy]

  def index
    @tasks = Task.where(user_id: current_user.id)
  end

  def create
    @task = current_user.tasks.new(task_params)
    @task.save
    # No explicit render needed for the *other* browsers — broadcasts_to handles that.
    # For the *submitting* browser, redirect (Turbo Drive) or respond_to :turbo_stream if you
    # want an instant, no-flicker response without waiting for the WebSocket round-trip.
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to tasks_path }
    end
  end

  def update
    @task.update(task_params)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to tasks_path }
    end
  end

  def destroy
    @task.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to tasks_path }
    end
  end

  private

  def set_task
    @task = Task.find(params[:id])
  end

  def task_params
    params.require(:task).permit(:title, :description, :status)
  end
end
```

### Step 5: Views — Turbo Frames + Turbo Streams, no JavaScript

**app/views/tasks/index.html.erb:**

```erb
<h1>Task Manager</h1>

<%= turbo_stream_from "tasks_#{current_user.id}" %>

<%= render "form", task: Task.new %>

<div class="task-board">
  <% %w[todo in_progress completed].each do |status| %>
    <div class="task-column">
      <h2><%= status.humanize %></h2>
      <turbo-frame id="tasks_<%= status %>">
        <%= render @tasks.where(status: status) %>
      </turbo-frame>
    </div>
  <% end %>
</div>
```

**app/views/tasks/_task.html.erb:**

```erb
<div id="<%= dom_id(task) %>" class="task-card">
  <strong><%= task.title %></strong>
  <p><%= task.description %></p>
  <% if task.duration_estimate.present? %>
    <span class="badge">Est: <%= task.duration_estimate %></span>
  <% end %>
  <%= button_to "Delete", task, method: :delete, form: { data: { turbo_confirm: "Delete this task?" } } %>
</div>
```

**app/views/tasks/_form.html.erb:**

```erb
<%= form_with model: task do |f| %>
  <%= f.text_field :title, placeholder: "Task title..." %>
  <%= f.text_area :description, placeholder: "Description..." %>
  <%= f.hidden_field :status, value: "todo" %>
  <%= f.submit "Add Task" %>
<% end %>
```

**app/views/tasks/create.turbo_stream.erb:**

```erb
<%= turbo_stream.prepend "tasks_todo", @task %>
<%= turbo_stream.replace "new_task", partial: "tasks/form", locals: { task: Task.new } %>
```

Note the difference in intent between `broadcasts_to` on the model and the `create.turbo_stream.erb` view: the model broadcast keeps **every other open tab/browser** in sync; the view template gives the **submitting browser** an instant response without a WebSocket round-trip. Both fire from the same action — that's the standard Hotwire pattern.

### Step 6: Background job that finishes async work, then pushes a Turbo Stream update

This is the "job runs → triggers a UI update" pattern you asked about. Example: a job that estimates how long a task will take (simulating something slower, like an AWS Lambda call or an LLM call) and updates the card once it's done — without the user refreshing or waiting on the request.

**app/jobs/task_duration_estimate_job.rb:**

```ruby
class TaskDurationEstimateJob < ApplicationJob
  queue_as :default

  def perform(task_id)
    task = Task.find(task_id)

    # Simulate slow async work — e.g. calling out to an AWS Lambda,
    # a Textract job, or any other long-running process.
    estimate = SlowEstimationService.call(task.title, task.description)
    task.update!(duration_estimate: estimate)

    # The task already re-broadcasts via broadcasts_to on update — but if you want
    # a more targeted UI change (e.g. flash a "estimate ready" badge), broadcast explicitly:
    Turbo::StreamsChannel.broadcast_replace_to(
      "tasks_#{task.user_id}",
      target: ActionView::RecordIdentifier.dom_id(task),
      partial: "tasks/task",
      locals: { task: task }
    )
  end
end
```

Enqueue it from the controller after create:

```ruby
def create
  @task = current_user.tasks.new(task_params)
  if @task.save
    TaskDurationEstimateJob.perform_later(@task.id)
  end
  respond_to do |format|
    format.turbo_stream
    format.html { redirect_to tasks_path }
  end
end
```

**What actually happens on screen:** the task card appears instantly (Turbo Stream from the controller response), with no duration badge. A few seconds later — whenever the background job finishes — the same card re-renders in place with the estimate badge, on every open browser, with zero polling and zero client-side JavaScript. This is the core Hotwire value proposition: async work completing is just another Turbo Stream broadcast, indistinguishable in the view layer from a user-triggered update.

*(Optional Stimulus controller: a small `task_form_controller.js` that clears the form and shows a "saving..." spinner on submit is a nice touch, but isn't required — Turbo Drive handles the request/response lifecycle on its own

### Step 6.1: Monitoring Background Jobs — Three Practical Ways

Here's how to verify your background jobs are actually triggering and processing, from "glance at the UI" to "inspect the queue":

#### Option 1: Make the app show job status (recommended for production)

Add a visual indicator so you can see the job processing in real-time in the browser. Add a `processing_status` field:

```bash
rails g migration AddProcessingStatusToTasks processing_status:string
rails db:migrate
```

Update the job to broadcast status changes:

**app/jobs/task_duration_estimate_job.rb:**

```ruby
class TaskDurationEstimateJob < ApplicationJob
  queue_as :default

  def perform(task_id)
    task = Task.find(task_id)

    # Mark as processing and broadcast immediately
    task.update!(processing_status: "estimating")
    broadcast_task(task)  # Card shows "estimating..." spinner immediately

    # Simulate slow async work
    estimate = SlowEstimationService.call(task.title, task.description)

    # Mark as done with the estimate and broadcast
    task.update!(duration_estimate: estimate, processing_status: "done")
    broadcast_task(task)  # Card updates to show the estimate
  end

  private

  def broadcast_task(task)
    Turbo::StreamsChannel.broadcast_replace_to(
      "tasks_#{task.user_id}",
      target: ActionView::RecordIdentifier.dom_id(task),
      partial: "tasks/task",
      locals: { task: task }
    )
  end
end
```

Update the task partial to show the status:

**app/views/tasks/_task.html.erb:**

```erb
<div id="<%= dom_id(task) %>" class="task-card">
  <strong><%= task.title %></strong>
  <p><%= task.description %></p>
  
  <% if task.processing_status == "estimating" %>
    <span class="badge badge-processing">⏳ Estimating duration...</span>
  <% elsif task.duration_estimate.present? %>
    <span class="badge badge-success">✓ Est: <%= task.duration_estimate %></span>
  <% end %>
  
  <%= button_to "Delete", task, method: :delete, form: { data: { turbo_confirm: "Delete this task?" } } %>
</div>
```

Now you can visually see:
- Card appears → shows "⏳ Estimating duration..."
- Job completes → card updates to "✓ Est: 2 hours"

#### Option 2: Mission Control - Jobs Dashboard

Mission Control is the official Rails jobs dashboard (like Sidekiq Web UI). It shows queued, in-progress, finished, and failed jobs in real-time.

Add to Gemfile:

```ruby
# Gemfile
gem "mission_control-jobs"
```

```bash
bundle install
```

Mount in routes:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount MissionControl::Jobs::Engine, at: "/jobs"
  
  resources :tasks
  root "tasks#index"
end
```

Visit `http://localhost:3000/jobs` in development (or your production URL + `/jobs`) to see:
- All queued jobs
- Currently executing jobs
- Completed jobs with execution time
- Failed jobs with error details

This is perfect for debugging — you can see exactly when jobs are picked up and when they finish.

#### Option 3: Query Solid Queue directly (console/debugging)

Since Solid Queue is database-backed (no Redis), you can query it directly in `rails console`:

```ruby
# Open Rails console
rails console

# Count jobs not yet finished
SolidQueue::Job.where(finished_at: nil).count

# Find recent TaskDurationEstimateJob jobs
SolidQueue::Job.where(class_name: "TaskDurationEstimateJob")
              .order(created_at: :desc)
              .first

# Jobs actively being processed right now
SolidQueue::ClaimedExecution.count

# Failed jobs
SolidQueue::FailedExecution.count

# See the most recent failed job (if any)
SolidQueue::FailedExecution.last&.error
```

#### Option 4: Watch the worker process in development

The fastest sanity check while developing — run the worker in a separate terminal so you see logs in real-time:

```bash
# Terminal 1: Rails server
rails server

# Terminal 2: Solid Queue worker
bin/jobs
```

The worker terminal will print:
```
[SolidQueue] Claimed job TaskDurationEstimateJob (id: 123)
[SolidQueue] Completed job TaskDurationEstimateJob (id: 123) in 5.2s
```

This gives instant feedback that jobs are being picked up and processed.

**Recommended approach:** Use **Option 1** (processing_status field) for user-facing feedback + **Option 4** (bin/jobs terminal) during development. Add **Option 2** (Mission Control) for production monitoring

---

## AWS Deployment Guide

Repo: `https://github.com/sghani001/task_manager_rails_aws` — Rails 8.1.3, Docker (production Dockerfile using Thruster on port 80), PostgreSQL, Solid Queue/Cable.

**Structure:**

- **Part 0 — IAM & Account Setup** (do this once, first)
- **Part 1 — Cost Safety Net** (do this once, first)
- **Part A — Console (GUI) Deployment** — click through, deploy, test, teardown
- **Part B — CLI / IaC Deployment** — the same thing, scripted
- **Appendix — Known Issues & Fixes** (from our debugging session)

---

## Part 0 — IAM & Account Setup (do this once, first)

### 0.1 Log in as root, just for this setup step

Go to `console.aws.amazon.com`, sign in with your root email/password.

### 0.2 Create a dedicated IAM user

1. Search bar → **IAM** → **Users** → **Create user**.
2. Name: e.g. `task_manager_admin`.
3. Check **Provide user access to the AWS Management Console**, set a password.
4. Click **Next**.

### 0.3 Attach permissions

Attach **`AdministratorAccess`** (easiest for a personal/test account).

If you'd rather scope it down, attach these instead:
- `AmazonEC2FullAccess`
- `AmazonRDSFullAccess`
- Custom inline policy `EC2InstanceConnectAccess`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ec2-instance-connect:SendSSHPublicKey", "ec2:DescribeInstances"],
      "Resource": "*"
    }
  ]
}
```

### 0.4 Create CLI access keys (for Part B later)

1. Click the user → **Security credentials** tab.
2. **Create access key** → CLI → copy both keys, save somewhere safe.

### 0.5 (Recommended) Enable MFA

Account page → **Security credentials** → **Multi-factor authentication (MFA)** — protects against compromised credentials.

### 0.6 Log out of root, log back in as your IAM user

From here on, everything is done as this IAM user (never root).

---

## Part 1 — Cost Safety Net (do this once, first)

1. **Set a budget alert:** Budgets → Create budget → Monthly cost budget `$5` → alert at 80%.
2. **Free Tier recall** (under 12-month account):
   - EC2: 750 hrs/month `t3.micro`
   - RDS: 750 hrs/month `db.t3.micro` or `db.t4g.micro`, Single-AZ, 20GB
   - EBS: 30GB
3. **This guide avoids:**
   - NAT Gateway (~$0.045/hr + data)
   - Unattached Elastic IP ($0.005/hr)
4. **Rule:** Teardown same day.

---

## Part A — Console (GUI) Deployment

### Architecture

```
Internet
   │
   ▼
EC2 instance (public subnet, default VPC)
  └─ Docker container: Rails 8.1 (Thruster + Puma, port 80)
   │
   ▼ (port 5432, security-group-to-security-group only)
RDS PostgreSQL (Single-AZ, db.t3.micro, NOT publicly accessible)
```

### A1. Before you open the console

- Have your `config/master.key` value handy.
- Log into the console **as your IAM user**.
- Pick one region (e.g. `us-east-1`) and stick with it.

### A2. Create a Key Pair

1. EC2 → Key Pairs → **Create key pair**.
2. Name: `task-manager-key`, Type: RSA, Format: .pem.
3. **Move it immediately to `~/.ssh/`** — keeping it on a mapped/cloud-synced drive (e.g. `G:\`) causes OpenSSH to fail to parse it with "type -1" errors:

```bash
mv ~/Downloads/task-manager-key.pem ~/.ssh/task-manager-key.pem
chmod 400 ~/.ssh/task-manager-key.pem
ssh-keygen -y -f ~/.ssh/task-manager-key.pem   # verify it parses
```

### A3. Create Security Groups

1. **`web-sg`:**
   - Inbound: SSH (22) from `0.0.0.0/0`, HTTP (80) from `0.0.0.0/0`

2. **`db-sg`:**
   - Inbound: PostgreSQL (5432) from **`web-sg`** (security-group-to-security-group, not a CIDR)

> SSH open to `0.0.0.0/0` avoids the EC2 Instance Connect IP mismatch issue (Instance Connect originates from AWS IP ranges, not your laptop). For a same-day test instance this is acceptable.

### A4. Launch RDS PostgreSQL

1. RDS → **Create database** → Standard create → PostgreSQL.
2. Template: **Free tier**.
3. DB instance identifier: `task-manager-db`.
4. Master username: `taskadmin` — save the password.
5. DB instance class: whichever free-tier micro is pre-selected (`db.t3.micro` or `db.t4g.micro` — both equally free).
6. Storage: 20 GiB gp2, no autoscaling.
7. Multi-AZ: **No**.
8. **Connectivity:**
   - VPC: default, Public access: **No**
   - Security group: **`db-sg`** (replace default)
9. **Additional configuration:**
   - Initial database name: **`task_manager_production`** (mandatory)
   - Backup retention: `0` days
10. **Create database** — wait 5-10 min for status = **Available**.
11. Copy the **Endpoint** address.

### A5. Launch EC2 Instance

1. EC2 → Instances → **Launch instance**.
2. Name: `task-manager-web`.
3. AMI: **Amazon Linux 2023**.
4. Type: `t3.micro`.
5. Key pair: `task-manager-key`.
6. **Network settings:**
   - Auto-assign public IP: **Enable**
   - Security group: **`web-sg`**
7. Storage: 20 GiB gp3.
8. **Advanced details → User data** — paste this (fill placeholders):

```bash
#!/bin/bash
set -x
exec > >(tee /var/log/task-manager-deploy.log)
exec 2>&1

echo "===== TASK MANAGER DEPLOYMENT START ====="
dnf update -y
dnf install -y docker git postgresql15
systemctl enable docker
systemctl start docker

# Create task_manager role (needed by config/database.yml for Solid Queue/Cable/Cache)
PGPASSWORD=YOUR_DB_PASSWORD psql -h YOUR_RDS_ENDPOINT -U taskadmin -d postgres -c "
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'task_manager') THEN
      CREATE ROLE task_manager LOGIN PASSWORD 'YOUR_DB_PASSWORD';
    END IF;
  END
  \$\$;
  ALTER ROLE task_manager CREATEDB;
"

git clone https://github.com/sghani001/task_manager_rails_aws.git /opt/task_manager
cd /opt/task_manager
docker build -t task_manager .

docker run -d --name task_manager \
  -p 80:80 \
  -e RAILS_MASTER_KEY=YOUR_MASTER_KEY_HERE \
  -e DATABASE_URL="postgres://taskadmin:YOUR_DB_PASSWORD@YOUR_RDS_ENDPOINT:5432/task_manager_production?sslmode=require" \
  -e TASK_MANAGER_DATABASE_PASSWORD=YOUR_DB_PASSWORD \
  -e DATABASE_HOST=YOUR_RDS_ENDPOINT \
  -e MISSION_CONTROL_USERNAME=admin \
  -e MISSION_CONTROL_PASSWORD=YOUR_DB_PASSWORD \
  -e PGSSLMODE=require \
  --restart unless-stopped \
  task_manager

echo "===== DEPLOYMENT COMPLETE ====="
```

**Important notes on this script:**
- `postgresql15` client is installed for `psql` to create the `task_manager` role.
- The `task_manager` role is required because `config/database.yml` uses `username: task_manager` for all 4 production databases (primary, cache, queue, cable).
- `?sslmode=require` and `PGSSLMODE=require` are both needed — RDS enforces SSL connections.
- `MISSION_CONTROL_USERNAME`/`PASSWORD` are needed because `config/initializers/mission_control.rb` uses `ENV.fetch(...)` with no default in production.
- The Dockerfile's `ENTRYPOINT` (`bin/docker-entrypoint`) runs `rails db:prepare` + `foreman start` — no separate migrate step needed.

### A6. Test

Wait ~3 min after launch. Then:

```bash
curl -I http://<PUBLIC_IP>/
ssh -i ~/.ssh/task-manager-key.pem ec2-user@<PUBLIC_IP>
sudo tail -20 /var/log/task-manager-deploy.log
sudo docker ps -a
sudo docker logs task_manager
```

Browser checks:
- Task board loads, create a task
- Open a second tab — changes appear instantly without refresh
- New tasks briefly show "⏳ Estimating..." then update with an estimate (proves Solid Queue is processing jobs)

### A7. Teardown (same day)

1. EC2 → Terminate `task-manager-web`.
2. RDS → Delete `task-manager-db` (skip final snapshot).
3. EC2 → Volumes → delete any orphaned volumes.
4. EC2 → Security Groups → delete `web-sg` and `db-sg`.

---

## Part B — CLI / IaC Deployment

Requires the AWS CLI installed and configured with access keys from Part 0.4.

### B1. Variables

```bash
export AWS_REGION=us-east-1
export DB_PASSWORD='ChangeMe123!'
export RAILS_MASTER_KEY='paste_from_config/master.key'
```

### B2. Security groups

```bash
VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)

WEB_SG_ID=$(aws ec2 create-security-group --group-name web-sg --description "Task manager web" --vpc-id $VPC_ID --query 'GroupId' --output text)
DB_SG_ID=$(aws ec2 create-security-group --group-name db-sg --description "Task manager db" --vpc-id $VPC_ID --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $WEB_SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $WEB_SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $DB_SG_ID --protocol tcp --port 5432 --source-group $WEB_SG_ID
```

### B3. RDS

```bash
SUBNET_IDS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID --query 'Subnets[].SubnetId' --output text)

aws rds create-db-subnet-group \
  --db-subnet-group-name task-manager-subnet-group \
  --db-subnet-group-description "Task manager subnets" \
  --subnet-ids $SUBNET_IDS

aws rds create-db-instance \
  --db-instance-identifier task-manager-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --master-username taskadmin \
  --master-user-password "$DB_PASSWORD" \
  --allocated-storage 20 \
  --db-name task_manager_production \
  --vpc-security-group-ids $DB_SG_ID \
  --db-subnet-group-name task-manager-subnet-group \
  --no-multi-az \
  --no-publicly-accessible \
  --backup-retention-period 0

aws rds wait db-instance-available --db-instance-identifier task-manager-db

DB_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier task-manager-db --query 'DBInstances[0].Endpoint.Address' --output text)
echo "RDS endpoint: $DB_ENDPOINT"
```

### B4. EC2 instance

```bash
KEY_NAME=task-manager-key-cli
aws ec2 create-key-pair --key-name $KEY_NAME --query 'KeyMaterial' --output text > ~/.ssh/$KEY_NAME.pem
chmod 400 ~/.ssh/$KEY_NAME.pem

AMI_ID=$(aws ec2 describe-images --owners amazon \
  --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)

cat > user-data.sh <<EOF
#!/bin/bash
set -x
exec > >(tee /var/log/task-manager-deploy.log)
exec 2>&1

dnf update -y
dnf install -y docker git postgresql15
systemctl enable docker
systemctl start docker

PGPASSWORD=$DB_PASSWORD psql -h $DB_ENDPOINT -U taskadmin -d postgres -c "
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'task_manager') THEN
      CREATE ROLE task_manager LOGIN PASSWORD '$DB_PASSWORD';
    END IF;
  END
  \$\$;
  ALTER ROLE task_manager CREATEDB;
"

git clone https://github.com/sghani001/task_manager_rails_aws.git /opt/task_manager
cd /opt/task_manager
docker build -t task_manager .

docker run -d --name task_manager \\
  -p 80:80 \\
  -e RAILS_MASTER_KEY=$RAILS_MASTER_KEY \\
  -e DATABASE_URL="postgres://taskadmin:$DB_PASSWORD@$DB_ENDPOINT:5432/task_manager_production?sslmode=require" \\
  -e TASK_MANAGER_DATABASE_PASSWORD=$DB_PASSWORD \\
  -e DATABASE_HOST=$DB_ENDPOINT \\
  -e MISSION_CONTROL_USERNAME=admin \\
  -e MISSION_CONTROL_PASSWORD=$DB_PASSWORD \\
  -e PGSSLMODE=require \\
  --restart unless-stopped \\
  task_manager
EOF

INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.micro \
  --key-name $KEY_NAME \
  --security-group-ids $WEB_SG_ID \
  --user-data file://user-data.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=task-manager-web}]' \
  --query 'Instances[0].InstanceId' --output text)

aws ec2 wait instance-running --instance-ids $INSTANCE_ID
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "App will be live shortly at: http://$PUBLIC_IP/"
```

### B5. Test

```bash
sleep 120
curl -I http://$PUBLIC_IP/
ssh -i ~/.ssh/$KEY_NAME.pem ec2-user@$PUBLIC_IP
sudo tail -20 /var/log/task-manager-deploy.log
```

### B6. Teardown

```bash
aws ec2 terminate-instances --instance-ids $INSTANCE_ID
aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID

aws rds delete-db-instance --db-instance-identifier task-manager-db --skip-final-snapshot
aws rds wait db-instance-deleted --db-instance-identifier task-manager-db

aws ec2 delete-security-group --group-id $DB_SG_ID
aws ec2 delete-security-group --group-id $WEB_SG_ID

aws ec2 delete-key-pair --key-name $KEY_NAME
rm -f ~/.ssh/$KEY_NAME.pem user-data.sh
```

### B7. Verification

```bash
aws ec2 describe-instances --filters "Name=tag:Name,Values=task-manager-web"
aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier'
aws ec2 describe-security-groups --filters "Name=group-name,Values=web-sg,db-sg"
```

---

## Appendix — Known Issues & Fixes (from our debugging session)

| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| Docker build fails: `foreman: command not found` | `foreman` gem missing from Gemfile (Procfile needs it) | Add `gem "foreman"` to Gemfile; `bin/docker-entrypoint` uses `bundle exec foreman start` |
| App crashes on boot: `KeyError: key not found: "MISSION_CONTROL_USERNAME"` | `config/initializers/mission_control.rb` uses `ENV.fetch()` without a default | Set `MISSION_CONTROL_USERNAME` and `MISSION_CONTROL_PASSWORD` env vars on `docker run` (or add fallback defaults in the initializer) |
| Container exits: `thrust: command not found` | Procfile references `thrust` but Docker's PATH doesn't find it (or gem is missing) | Ensure `gem "thruster"` is in Gemfile (provides `thrust` binary) |
| App runs but can't connect to RDS: `SSL connection required` | RDS enforces SSL; `DATABASE_URL` missing `?sslmode=require` | Add `?sslmode=require` to `DATABASE_URL` and `-e PGSSLMODE=require` |
| RDS connection fails: `role "task_manager" does not exist` | `config/database.yml` uses `username: task_manager` for production, but only `taskadmin` (RDS master) exists | Create the `task_manager` role in PostgreSQL via user-data script before running Docker |
| `ssh -i key.pem ...` says `no pubkey loaded ... type -1` | Key file on a mapped/cloud-synced drive (e.g. `G:\`) that OpenSSH can't read | Copy `.pem` to `~/.ssh/` and `chmod 400`; validate with `ssh-keygen -y -f ~/.ssh/key.pem` |
| EC2 Instance Connect: "Error establishing SSH connection" | IAM user lacks `ec2-instance-connect:SendSSHPublicKey` permission | Attach `AmazonEC2FullAccess` or the scoped custom policy from Part 0.3 |
| `ssh` connects then hangs forever | Possible MTU/packet fragmentation on some Wi-Fi/hotspots | Try `ssh -o IPQoS=none -i key.pem ec2-user@ip`, or test from a different network |
| RDS console won't let you pick `db.t3.micro` | Free tier template pre-selects `db.t4g.micro` instead | Both are equally free-tier eligible — proceed with whichever is pre-selected |

---

## Quick Reference — What Costs Money If Left Running

| Resource | Free Tier | Post-Free-Tier |
|----------|-----------|----------------|
| EC2 `t3.micro` | $0 (750h/month) | ~$0.0104/hr |
| RDS `db.t3.micro` / `db.t4g.micro` | $0 (750h/month) | ~$0.016/hr |
| RDS storage (20GB) | $0 (up to 20GB) | ~$0.10/GB-month |
| Elastic IP (unattached) | — | ~$0.005/hr |
| NAT Gateway | — | ~$0.045/hr + data — **not used here** |

For a single afternoon on Free Tier, cost is **$0** if you teardown same day.

---

## Scripted IaC (scripts/ folder)

Ready-to-run scripts at `scripts/deploy-aws-cli.sh` and `scripts/teardown-aws-cli.sh`:

```bash
bash scripts/deploy-aws-cli.sh    # prompts for secrets, idempotent
bash scripts/teardown-aws-cli.sh  # destroys everything
```