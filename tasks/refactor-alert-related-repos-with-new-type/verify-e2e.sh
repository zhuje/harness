#!/bin/bash
set -e

# =============================================================================
# E2E verification script for alert/silence type refactoring
# =============================================================================
# Starts all required services, waits for readiness, then prints the URL.
# Press Ctrl+C to tear everything down.
#
# Services:
#   1. Podman compose  (alertmanager :9093, prometheus :9090, avalanche :9001)
#   2. Perses backend  (:8080)
#   3. Perses UI       (:3000, proxies API to :8080)
#   4. Alertmanager plugin dev server (:3015, registered via percli)
# =============================================================================

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PERSES="$ROOT/projects/perses"
SHARED="$ROOT/projects/perses-shared"
PLUGINS="$ROOT/projects/perses-plugins"
SPEC="$ROOT/projects/perses-spec"
LOGDIR="$ROOT/tasks/refactor-alert-related-repos-with-new-type/logs"
mkdir -p "$LOGDIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PIDS=()

cleanup() {
  echo ""
  echo -e "${YELLOW}Shutting down...${NC}"

  for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done

  echo -e "${YELLOW}Stopping podman compose...${NC}"
  podman compose --file "$PERSES/dev/docker-compose.yaml" \
    --profile prometheus --profile avalanche --profile alertmanager \
    down 2>/dev/null || true

  echo -e "${GREEN}All services stopped.${NC}"
  exit 0
}
trap cleanup INT TERM EXIT

wait_for_port() {
  local port=$1 name=$2 timeout=${3:-60}
  local elapsed=0
  echo -ne "  Waiting for ${name} on :${port}..."
  while ! curl -sf "http://localhost:${port}" >/dev/null 2>&1; do
    sleep 2
    elapsed=$((elapsed + 2))
    if [ "$elapsed" -ge "$timeout" ]; then
      echo -e " ${RED}TIMEOUT${NC}"
      echo -e "${RED}${name} did not start within ${timeout}s. Check $LOGDIR/${name}.log${NC}"
      return 1
    fi
  done
  echo -e " ${GREEN}ready${NC}"
}

wait_for_url() {
  local url=$1 name=$2 timeout=${3:-60}
  local elapsed=0
  echo -ne "  Waiting for ${name} at ${url}..."
  while ! curl -sf "$url" >/dev/null 2>&1; do
    sleep 2
    elapsed=$((elapsed + 2))
    if [ "$elapsed" -ge "$timeout" ]; then
      echo -e " ${RED}TIMEOUT${NC}"
      return 1
    fi
  done
  echo -e " ${GREEN}ready${NC}"
}

# ── Step 1: Build spec ───────────────────────────────────────────────────────
echo -e "${CYAN}[1/7] Building perses-spec/ts...${NC}"
(cd "$SPEC/ts" && npm run build) > "$LOGDIR/spec-build.log" 2>&1
echo -e "  ${GREEN}done${NC}"

# ── Step 2: Build shared and link into perses ────────────────────────────────
echo -e "${CYAN}[2/7] Building perses-shared and linking into perses...${NC}"
(cd "$SHARED" && npm run build) > "$LOGDIR/shared-build.log" 2>&1
echo -e "  Build ${GREEN}done${NC}"

(cd "$SHARED/scripts/link-with-perses" && bash link-with-perses.sh link --perses "$PERSES") > "$LOGDIR/link-with-perses.log" 2>&1
echo -e "  Link ${GREEN}done${NC}"

# ── Step 3: Install perses UI deps ──────────────────────────────────────────
echo -e "${CYAN}[3/7] Installing perses UI dependencies...${NC}"
(cd "$PERSES/ui" && npm install) > "$LOGDIR/perses-ui-install.log" 2>&1
echo -e "  ${GREEN}done${NC}"

# ── Step 4: Build perses backend ────────────────────────────────────────────
echo -e "${CYAN}[4/7] Building perses backend (Go)...${NC}"
(cd "$PERSES" && make build-api) > "$LOGDIR/perses-build.log" 2>&1
echo -e "  ${GREEN}done${NC}"

# ── Step 5: Start podman compose (alertmanager, prometheus, avalanche) ──────
echo -e "${CYAN}[5/7] Starting test infrastructure (alertmanager, prometheus, avalanche)...${NC}"
podman compose --file "$PERSES/dev/docker-compose.yaml" \
  --profile prometheus --profile avalanche --profile alertmanager \
  up -d > "$LOGDIR/podman-compose.log" 2>&1
wait_for_url "http://localhost:9093/-/ready" "alertmanager" 60
wait_for_url "http://localhost:9090/-/ready" "prometheus" 60

# ── Step 6: Start perses backend ────────────────────────────────────────────
echo -e "${CYAN}[6/7] Starting perses backend...${NC}"
(cd "$PERSES" && ./bin/perses --config ./dev/config.yaml --log.level=info) \
  > "$LOGDIR/perses-backend.log" 2>&1 &
PIDS+=($!)
wait_for_url "http://localhost:8080/api/v1/health" "perses-backend" 30

# ── Step 7a: Start perses UI (shared mode) ──────────────────────────────────
echo -e "${CYAN}[7/7] Starting perses UI (shared mode) and alertmanager plugin...${NC}"

SHARED_PACKAGES_PATH="$SHARED" \
  npm run --prefix "$PERSES/ui/app" start:shared \
  > "$LOGDIR/perses-ui.log" 2>&1 &
PIDS+=($!)

# ── Step 7b: Start alertmanager plugin via percli ───────────────────────────
(cd "$PLUGINS" && percli plugin start alertmanager) \
  > "$LOGDIR/percli-plugin.log" 2>&1 &
PIDS+=($!)

# Wait for UI
wait_for_port 3000 "perses-ui" 120

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  All services are running!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "  ${CYAN}Perses UI:${NC}        http://localhost:3000"
echo -e "  ${CYAN}Perses API:${NC}       http://localhost:8080"
echo -e "  ${CYAN}Alertmanager:${NC}     http://localhost:9093"
echo -e "  ${CYAN}Prometheus:${NC}       http://localhost:9090"
echo -e "  ${CYAN}Plugin dev:${NC}       http://localhost:3015"
echo ""
echo -e "  ${YELLOW}Logs in:${NC}          $LOGDIR/"
echo ""
echo -e "  ${YELLOW}Verify:${NC}"
echo -e "    - Alert table shows states: Firing, Silenced, Pending"
echo -e "    - Silence table shows states: Active, Expired, Pending"
echo -e "    - Silence create/expire works"
echo -e "    - Search filtering works on both tables"
echo ""
echo -e "  Press ${RED}Ctrl+C${NC} to stop all services."
echo ""

# Keep alive until interrupted
wait
