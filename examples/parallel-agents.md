# Example: Parallel Agent Execution

When two tasks are independent, you can run them simultaneously and cut the total time roughly in half.

---

## When to use this

- Two features touching completely different files
- Running tests in parallel with implementation
- Auditing multiple files simultaneously
- One agent researches while another implements

**Never run parallel tasks on the same files** — you'll get merge conflicts.

---

## Setup

Use the 4-pane session:

```bash
bash /path/to/shellmates/scripts/launch-full-team.sh
```

Session layout:
```
┌──────────────────┬──────────────────┐
│  full:0.0        │  full:0.1        │
│  Gemini worker A │  Claude (you)    │
├──────────────────┼──────────────────┤
│  full:0.2        │  full:0.3        │
│  Gemini worker B │  Codex executor  │
└──────────────────┴──────────────────┘
```

---

## Example: Two independent API features

**Task A (Gemini worker A):** Add `GET /posts/:id` endpoint  
**Task B (Gemini worker B):** Add pagination to `GET /posts`

These touch different parts of the codebase — safe to parallelize.

### Claude sends both at once:

```bash
# Task A → Gemini worker A
tmux send-keys -t full:0.0 "Add GET /posts/:id to backend/app/routers/posts.py.
- Return 404 if post not found
- Follow the pattern in GET /users/:id
- Write a test in tests/test_posts.py
- Commit and output PHASE_COMPLETE when done." Enter

# Task B → Gemini worker B  
tmux send-keys -t full:0.2 "Add cursor-based pagination to GET /posts in backend/app/routers/posts.py.
- Accept ?cursor=<id>&limit=20 query params
- Return {items: [...], next_cursor: id | null}
- Write a test in tests/test_posts_pagination.py
- Commit and output PHASE_COMPLETE when done." Enter
```

### Claude polls both:

```bash
echo "=== Worker A ===" && tmux capture-pane -t full:0.0 -p | tail -5
echo "=== Worker B ===" && tmux capture-pane -t full:0.2 -p | tail -5
```

### Claude waits for both to complete, then reviews:

```bash
git log --oneline -5
```

---

## Example: Research + Implement in parallel

You can have one agent research while another implements an unrelated feature.

```bash
# Gemini A: research the best OAuth2 library for this stack
tmux send-keys -t full:0.0 "Research the best way to add Google OAuth2 to this FastAPI app.
Read backend/app/routers/auth.py first for existing auth context.
Return: recommended library, key integration steps, any gotchas.
Output PHASE_COMPLETE when done." Enter

# Gemini B: implement an unrelated feature while research runs
tmux send-keys -t full:0.2 "Add rate limiting to all API endpoints.
Use slowapi (already in requirements.txt).
Limit: 100 requests/minute per IP.
Add tests. Commit. Output PHASE_COMPLETE." Enter
```

Claude collects research output from Gemini A, then uses it to inform the next plan.

---

## Example: Fan-out code audit

Run the same check across multiple files simultaneously.

```bash
# Three files, three agents, all at once
tmux send-keys -t full:0.0 "Audit backend/app/routers/users.py for security issues.
Look for: SQL injection, missing auth checks, exposed secrets, input validation gaps.
Output a numbered list of findings, severity (high/med/low), and line numbers.
Output PHASE_COMPLETE when done." Enter

tmux send-keys -t full:0.2 "Audit backend/app/routers/posts.py for security issues.
[same instructions]
Output PHASE_COMPLETE when done." Enter

tmux send-keys -t full:0.3 "Audit backend/app/routers/auth.py for security issues.
[same instructions]
Output PHASE_COMPLETE when done." Enter
```

Claude waits for all three, then synthesizes findings:

```bash
# Capture all three outputs
for PANE in full:0.0 full:0.2 full:0.3; do
  echo "=== $PANE ==="
  tmux capture-pane -t "$PANE" -p -S -100 | tail -40
done
```

---

## Tips for Parallel Work

1. **Be explicit about file ownership.** Tell each agent exactly which files it owns. "You are working on `routers/users.py` only."

2. **Use separate test files.** `test_users.py` for one agent, `test_posts.py` for another — no collisions.

3. **Check git carefully after both finish.** `git log --oneline -8` should show two separate commits with no shared files.

4. **If one finishes early, let it idle.** Don't give it new work until both are done — parallel commits to the same branch can still conflict on unrelated lines.
