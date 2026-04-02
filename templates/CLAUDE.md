## shellmates — Multi-Agent Orchestration

This project uses shellmates for multi-agent orchestration via tmux.
Full operating instructions are in ORCHESTRATOR.md — read it at the start of every orchestration session.

Setup:
- tmux session: orchestra
- Sub-agent pane: orchestra:0.0  (Gemini CLI — executor)
- Orchestrator pane: orchestra:0.1 (Claude Code — you)

Quick reference:
- Plan work:         /gsd:plan-phase N
- Delegate task:     tmux send-keys -t orchestra:0.0 "task..." Enter
- Check completion:  tmux capture-pane -t orchestra:0.0 -p | tail -20
- Read full output:  tmux capture-pane -t orchestra:0.0 -p -S -100 | tail -60
- Check git:         git log --oneline -5
- Project status:    /gsd:progress
