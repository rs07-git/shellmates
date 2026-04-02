# End-to-End Example: Building a Feature with GSD + tmux

This walks through the complete workflow from idea to working code, using a realistic example: adding a user authentication system to a FastAPI + Next.js project.

---

## Starting state

- Project is initialized with GSD (`.planning/ROADMAP.md` exists)
- tmux session `orchestra` is running (`scripts/launch.sh` was used)
  - `orchestra:0.0` — Gemini CLI
  - `orchestra:0.1` — Claude Code (you're here)
- `GEMINI.md` is in the project root and filled out

---

## 1. Tell Claude what you want

In Claude's pane (right side), you say:

```
I want to add user authentication. Users should be able to register with
email + password and log in. Use bcrypt for hashing and return a JWT.
Please use GSD to plan this and then have Gemini implement it.
```

---

## 2. Claude plans with GSD

Claude runs:

```
/gsd:plan-phase
```

GSD asks a few clarifying questions, then produces `.planning/phases/3-user-auth/PLAN.md` — something like:

```markdown
# Phase 3 — User Authentication

## Goal
Users can register and log in with email + password. Backend returns JWT.

## Files to create/modify
- backend/app/routers/auth.py (new)
- backend/app/services/auth_service.py (new)
- backend/app/models/user.py (new)
- backend/schema.sql (add users table)
- backend/tests/test_auth.py (new)

## Tasks
1. Add users table migration (email, hashed_password, created_at)
2. Create UserService with register() and login() methods (bcrypt)
3. Create JWT utility (encode/decode, 24h expiry)
4. Add POST /auth/register and POST /auth/login routes
5. Write tests for: success register, duplicate email, wrong password, valid login

## Verification
- pytest tests/test_auth.py -v — all tests pass
- git status — clean tree
```

Claude shows you the plan. You say: *"Looks good, delegate to Gemini."*

---

## 3. Claude delegates to Gemini

Claude runs:

```bash
tmux send-keys -t orchestra:0.0 "Please execute Phase 3 — User Authentication.

The plan is at .planning/phases/3-user-auth/PLAN.md — read it completely before writing any code.

Project context is in GEMINI.md at the root.

Rules:
- Commit after each task in the plan
- Run pytest tests/test_auth.py -v before signaling complete
- Use non-interactive flags for all shell commands

When done, output:
PHASE_COMPLETE: Phase 3 — <one-line summary>" Enter
```

---

## 4. Gemini executes

In the left pane, you watch Gemini work through the plan:

```
> Reading .planning/phases/3-user-auth/PLAN.md...
> Reading GEMINI.md...
> Creating migration: backend/migrations/003_users_table.sql
> Running migration...
> Creating backend/app/models/user.py
> Creating backend/app/services/auth_service.py
> Creating backend/app/routers/auth.py
> Creating backend/tests/test_auth.py
> Running pytest tests/test_auth.py -v...
  test_register_success PASSED
  test_register_duplicate_email PASSED
  test_login_success PASSED
  test_login_wrong_password PASSED
  test_login_unknown_email PASSED
  5 passed in 0.82s
> Committing...
[main a3f9c12] feat(auth): add user registration and login endpoints

PHASE_COMPLETE: Phase 3 — email/password auth added, bcrypt hashing, JWT response, 5 tests pass
AWAITING_INSTRUCTIONS
```

---

## 5. Claude reviews

Claude polls for completion:

```bash
tmux capture-pane -t orchestra:0.0 -p | tail -20
```

Sees `PHASE_COMPLETE`. Now Claude checks the evidence:

```bash
git log --oneline -5
git diff HEAD~1 --stat
```

Output:
```
a3f9c12 feat(auth): add user registration and login endpoints
  backend/app/routers/auth.py         | 52 +++++++++
  backend/app/services/auth_service.py| 38 +++++++
  backend/app/models/user.py          | 22 ++++
  backend/tests/test_auth.py          | 41 +++++++
  backend/migrations/003_users_table.sql | 12 ++
  5 files changed, 165 insertions(+)
```

Claude reports back to you:

```
Gemini completed Phase 3. Here's what was done:

✓ users table migration (003_users_table.sql)
✓ UserService with bcrypt register/login
✓ JWT utility with 24h expiry
✓ POST /auth/register and POST /auth/login endpoints
✓ 5 tests, all passing

The implementation looks correct. Ready for Phase 4 whenever you are.
```

---

## 6. Continue to next phase

You say: *"Great. Now add the frontend login page."*

Claude runs `/gsd:plan-phase` for Phase 4, and the cycle repeats.

---

## What This Demonstrates

- **You stayed in one conversation with Claude** — no context switching
- **Gemini had a fresh context** — no confusion from Phase 1 or 2 history
- **The plan was self-contained** — PLAN.md + GEMINI.md gave Gemini everything it needed
- **Commits happened incrementally** — easy to review or revert
- **The workflow scales** — Phases 4, 5, 6 follow the exact same loop
