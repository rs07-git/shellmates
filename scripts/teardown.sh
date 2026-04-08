#!/usr/bin/env bash
# teardown.sh — Close shellmates sessions safely
#
# Shows all active sessions with context, then lets you choose which to close.
# Never kills sessions automatically — always confirms first.
#
# Usage:
#   ./scripts/teardown.sh         # Interactive: choose which sessions to close
#   ./scripts/teardown.sh --all   # Close all shellmates sessions (skips per-session prompt)

set -euo pipefail

MANIFEST_FILE="${HOME}/.shellmates/sessions.json"
KILL_ALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) KILL_ALL=true; shift ;;
    -h|--help)
      echo "Usage: $0 [--all]"
      echo "  --all   Close all sessions without per-session prompts"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Check if tmux is running at all
if ! tmux list-sessions &>/dev/null 2>&1; then
  echo "No tmux sessions running."
  exit 0
fi

# Build session list via status.sh --json
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_JSON=$(bash "$SCRIPT_DIR/status.sh" --json 2>/dev/null || echo "[]")

SESSION_COUNT=$(python3 -c "import json,sys; data=json.loads('$( echo "$SESSION_JSON" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" )'); print(len(data))" 2>/dev/null || echo "0")

if [[ "$SESSION_COUNT" == "0" ]]; then
  echo "No sessions found."
  exit 0
fi

# Display sessions and collect kill list
python3 - <<PYEOF
import json, os, subprocess, sys

manifest_file = "$MANIFEST_FILE"
kill_all = $( [[ "$KILL_ALL" == "true" ]] && echo "True" || echo "False" )

# Re-read sessions
try:
  raw = subprocess.check_output(
    ["tmux", "list-sessions", "-F", "#{session_name}|#{session_created}"],
    stderr=subprocess.DEVNULL, text=True
  ).strip()
  live_sessions = {line.split("|")[0] for line in raw.splitlines() if line}
except Exception:
  live_sessions = set()

manifest_sessions = {}
if os.path.exists(manifest_file):
  try:
    with open(manifest_file) as f:
      data = json.load(f)
    for s in data.get("sessions", []):
      manifest_sessions[s["name"]] = s
  except Exception:
    pass

# Build list: manifest first, then untracked live sessions
all_names = list(manifest_sessions.keys())
for name in live_sessions:
  if name not in all_names:
    all_names.append(name)

if not all_names:
  print("No sessions found.")
  sys.exit(0)

import datetime
def age_str(ts):
  if ts == 0: return "unknown"
  delta = datetime.datetime.now() - datetime.datetime.fromtimestamp(ts)
  d, h, m = delta.days, delta.seconds//3600, (delta.seconds%3600)//60
  return f"{d}d" if d > 0 else (f"{h}h" if h > 0 else f"{m}m")

# Get tmux created times
try:
  raw2 = subprocess.check_output(
    ["tmux", "list-sessions", "-F", "#{session_name}|#{session_created}"],
    stderr=subprocess.DEVNULL, text=True
  ).strip()
  created_map = {}
  for line in raw2.splitlines():
    parts = line.split("|")
    if len(parts) == 2:
      created_map[parts[0]] = int(parts[1])
except Exception:
  created_map = {}

print("\nShellmates sessions:\n")
rows = []
for idx, name in enumerate(all_names, 1):
  is_alive = name in live_sessions
  entry = manifest_sessions.get(name, {})
  purpose = entry.get("purpose", "(untracked)")
  project = entry.get("project_dir", "—").replace(os.environ.get("HOME", ""), "~")
  agents = ", ".join(entry.get("agents", ["?"])) if entry else "?"
  ts = created_map.get(name, 0)
  age = age_str(ts)
  alive_str = "alive" if is_alive else "dead"
  print(f"  [{idx}] {name:<16}  {purpose:<30}  {project:<28}  {agents:<8}  {age:<6}  {alive_str}")
  rows.append({"idx": idx, "name": name, "is_alive": is_alive})

print("")

if kill_all:
  to_kill = [r["name"] for r in rows if r["is_alive"]]
  print(f"--all flag set. Closing {len(to_kill)} session(s): {', '.join(to_kill)}")
  # Write kill list for bash to read
  with open("/tmp/.shellmates_kill_list", "w") as f:
    f.write("\n".join(to_kill))
  sys.exit(0)

print("Which sessions would you like to close?")
print("  Enter numbers separated by spaces, 'all' to close all alive sessions,")
print("  or press Enter to cancel: ", end="", flush=True)

try:
  response = input().strip().lower()
except (EOFError, KeyboardInterrupt):
  print("\nCancelled.")
  sys.exit(0)

if not response:
  print("Cancelled.")
  sys.exit(0)

if response == "all":
  to_kill = [r["name"] for r in rows if r["is_alive"]]
else:
  to_kill = []
  for part in response.split():
    try:
      idx = int(part)
      match = next((r for r in rows if r["idx"] == idx), None)
      if match:
        if match["is_alive"]:
          to_kill.append(match["name"])
        else:
          print(f"  Session [{idx}] {match['name']} is already dead — skipping.")
      else:
        print(f"  Unknown number: {part}")
    except ValueError:
      print(f"  Skipping invalid input: {part}")

if not to_kill:
  print("Nothing to close.")
  sys.exit(0)

# Write kill list for bash to read
with open("/tmp/.shellmates_kill_list", "w") as f:
  f.write("\n".join(to_kill))

print(f"\nClosing: {', '.join(to_kill)}")
PYEOF

# Read the kill list and execute
if [[ ! -f /tmp/.shellmates_kill_list ]]; then
  exit 0
fi

KILL_LIST=$(cat /tmp/.shellmates_kill_list)
rm -f /tmp/.shellmates_kill_list

if [[ -z "$KILL_LIST" ]]; then
  exit 0
fi

while IFS= read -r SESSION_NAME; do
  [[ -z "$SESSION_NAME" ]] && continue

  echo -n "  Closing '$SESSION_NAME'... "
  if tmux kill-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "done"
  else
    echo "already gone"
  fi

  # Remove from manifest
  if [[ -f "$MANIFEST_FILE" ]]; then
    python3 - <<PYEOF2
import json, os

manifest_file = "$MANIFEST_FILE"
session_name = "$SESSION_NAME"

if os.path.exists(manifest_file):
  with open(manifest_file) as f:
    data = json.load(f)
  data["sessions"] = [s for s in data.get("sessions", []) if s["name"] != session_name]
  with open(manifest_file, "w") as f:
    json.dump(data, f, indent=2)
PYEOF2
  fi

done <<< "$KILL_LIST"

echo ""
echo "Done. Run 'bash scripts/status.sh' to verify."
