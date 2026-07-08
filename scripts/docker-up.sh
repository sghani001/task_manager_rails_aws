#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
docker compose up --build -d

echo "
Docker services started.
Open http://localhost:3000
To stop them: docker compose down
"