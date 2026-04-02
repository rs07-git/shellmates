# Using the Workflow Without GSD

GSD makes planning structured and persistent, but the tmux orchestration works perfectly well without it. This is a good starting point if you want to try the workflow before installing GSD, or if your project doesn't need formal phase planning.

---

## The Difference

| With GSD | Without GSD |
|----------|------------|
| `/gsd:plan-phase` creates a PLAN.md | Claude writes the plan inline in chat |
| Plans saved to `.planning/phases/` | Plans exist only in the conversation |
| `/gsd:progress` restores context | You manually tell Claude where you left off |
| Phase state tracked in STATE.md | No persistent state between sessions |

Both approaches use the same tmux protocol — the only difference is how the plan gets created.

---

## Example Without GSD

### You say to Claude:

```
I want to add a search endpoint to this API — GET /search?q=... that searches
posts by title and content.

Please:
1. Write a detailed implementation plan
2. Save it to .planning/search-plan.md (create the directory if needed)  
3. Send the plan to Gemini in pane orchestra:0.0 and have it implement
4. Wait for PHASE_COMPLETE and report back
```

### Claude writes the plan and saves it:

Claude creates `.planning/search-plan.md`:

```markdown
# Search Endpoint Plan

## Files to modify
- backend/app/routers/search.py (new)
- backend/app/main.py (register router)
- backend/tests/test_search.py (new)

## Tasks
1. Create GET /search router in search.py
   - Query param: q (required, min 2 chars)
   - Search posts.title and posts.content with ILIKE
   - Return list of matching posts (id, title, excerpt)
2. Register router in main.py
3. Write tests: no query, short query, matching results, no results

## Test command
pytest tests/test_search.py -v
```

### Claude delegates to Gemini:

```bash
tmux send-keys -t orchestra:0.0 "Please implement the search feature.

The plan is at .planning/search-plan.md — read it first.
Project context is in GEMINI.md.

Commit after each task. When done, run pytest tests/test_search.py -v.
Output PHASE_COMPLETE: search — <summary>" Enter
```

### Everything else works the same.

---

## When to Upgrade to GSD

Consider installing GSD when:
- Your project has **more than ~5 planned features** — GSD's ROADMAP.md keeps you oriented
- You're working **across multiple sessions** — STATE.md remembers where you left off
- You want **structured verification** — `/gsd:verify-work` checks implementation against plan
- The plans are getting complex — GSD's phase structure keeps things organized

Install GSD:
```bash
npx get-shit-done-cc@latest
```

Then initialize your existing project:
```bash
/gsd:map-codebase    # maps what you've built
/gsd:new-project     # sets up planning structure
```
