#!/usr/bin/env bash
# status.sh — Show all shellmates sessions with their current state
#
# Usage:
#   ./scripts/status.sh           # Show all sessions
#   ./scripts/status.sh --json    # Machine-readable JSON output

set -euo pipefail

MANIFEST_FILE="${HOME}/.shellmates/sessions.json"
JSON_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_MODE=true; shift ;;
    -h|--help) echo "Usage: $0 [--json]"; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Collect all tmux session names
ALL_TMUX_SESSIONS=$(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)

if [[ -z "$ALL_TMUX_SESSIONS" ]]; then
  echo "No tmux sessions running."
  exit 0
fi

# Build and print the session status table using Python
python3 - <<PYEOF
import json
import os
import subprocess
import datetime

manifest_file = "$MANIFEST_FILE"
json_mode = $( [[ "$JSON_MODE" == "true" ]] && echo "True" || echo "False" )

# Load manifest
manifest_sessions = {}
if os.path.exists(manifest_file):
  try:
    with open(manifest_file) as f:
      data = json.load(f)
    for s in data.get("sessions", []):
      manifest_sessions[s["name"]] = s
  except Exception:
    pass

# Get all live tmux sessions
try:
  raw = subprocess.check_output(
    ["tmux", "list-sessions", "-F", "#{session_name}|#{session_created}"],
    stderr=subprocess.DEVNULL, text=True
  ).strip()
  tmux_sessions = {}
  for line in raw.splitlines():
    parts = line.split("|", 1)
    name = parts[0]
    created_ts = int(parts[1]) if len(parts) > 1 else 0
    tmux_sessions[name] = created_ts
except Exception:
  tmux_sessions = {}

# Combine: manifest entries + any live sessions not in manifest
all_names = list(manifest_sessions.keys())
for name in tmux_sessions:
  if name not in all_names:
    all_names.append(name)

if not all_names:
  print("No shellmates sessions found.")
  exit()

def get_pane_cmd(pane_id):
  """Check what process is running in a specific pane (by stable pane ID like %12)."""
  try:
    result = subprocess.check_output(
      ["tmux", "display-message", "-p", "-t", pane_id, "#{pane_current_command}"],
      stderr=subprocess.DEVNULL, text=True
    ).strip()
    return result
  except Exception:
    return "?"

def age_str(ts):
  if ts == 0:
    return "unknown"
  delta = datetime.datetime.now() - datetime.datetime.fromtimestamp(ts)
  days = delta.days
  hours = delta.seconds // 3600
  minutes = (delta.seconds % 3600) // 60
  if days > 0:
    return f"{days}d ago"
  elif hours > 0:
    return f"{hours}h ago"
  else:
    return f"{minutes}m ago"

def infer_status(entry, is_alive):
  """Return a human-readable status for the session."""
  if not is_alive:
    return "dead (tmux gone)"
  panes = entry.get("panes", {})
  if not panes:
    return "alive (no pane info)"
  statuses = []
  shell_cmds = {"bash", "zsh", "sh", "fish", "?"}
  for role, pane_id in panes.items():
    cmd = get_pane_cmd(pane_id)
    if cmd in shell_cmds:
      statuses.append(f"{role} idle")
    else:
      statuses.append(f"{role} active ({cmd})")
  return ", ".join(statuses)

rows = []
for idx, name in enumerate(all_names, 1):
  is_alive = name in tmux_sessions
  entry = manifest_sessions.get(name, {})
  created_ts = tmux_sessions.get(name, 0)

  purpose = entry.get("purpose", "(no manifest entry)")
  project = entry.get("project_dir", "—")
  project_short = project.replace(os.environ.get("HOME", ""), "~")
  agents = ", ".join(entry.get("agents", ["?"])) if entry else "?"
  status = infer_status(entry, is_alive) if entry else ("alive" if is_alive else "dead")
  age = age_str(created_ts)

  rows.append({
    "idx": idx,
    "name": name,
    "purpose": purpose,
    "project": project_short,
    "agents": agents,
    "status": status,
    "age": age,
    "is_alive": is_alive,
    "has_manifest": bool(entry)
  })

if json_mode:
  print(json.dumps(rows, indent=2))
else:
  print("Shellmates sessions:\n")
  fmt = "  {idx:<3}  {name:<16}  {purpose:<28}  {project:<30}  {agents:<8}  {age:<10}  {status}"
  header = fmt.format(idx="#", name="name", purpose="purpose", project="project",
                      agents="agents", age="age", status="status")
  print(header)
  print("  " + "─" * (len(header) - 2))
  for r in rows:
    marker = "" if r["is_alive"] else " [dead]"
    manifest_note = "" if r["has_manifest"] else " *"
    print(fmt.format(
      idx=r["idx"],
      name=r["name"] + marker,
      purpose=r["purpose"] + manifest_note,
      project=r["project"],
      agents=r["agents"],
      age=r["age"],
      status=r["status"]
    ))

  print("")
  if any(not r["has_manifest"] for r in rows):
    print("  * Session not tracked by shellmates (started outside launch.sh)")
  print("  To close sessions: bash scripts/teardown.sh")
PYEOF
