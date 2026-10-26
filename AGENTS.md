# AGENTS.md — ULTRABLADE

This is the **UltraBlade** game repository. It uses **Godot 4.7.2** for PC (see `docs/ENGINE-DECISION.md`).
Use Gypsy Studio for project checks, probes and evidence.

## Gypsy Studio

**Standing rule:** a request to "add XXX to the toolkit" extends **Gypsy Studio** (a reusable
plugin/capability/docs/tests integration in the ProjectGypsy checkout), not this game repo. ActionForge
is installed as Gypsy's reference toolkit; see `gypsy toolkit list` / `gypsy toolkit actionforge catalog`.

- Gypsy home: `C:\OneDrive\OneDrive - Cyber 7 Group\GHRepo\Games\ProjectGypsy`
- Verify: `python "$env:GYPSY_HOME\workstream\gypsy.py" version`
- Dashboard: http://127.0.0.1:8765/
- Project check: `python "$env:GYPSY_HOME\workstream\gypsy.py" check --project "<this repo>"`
- Engine probe: `python "$env:GYPSY_HOME\workstream\gypsy.py" engines probe`
- Toolkit registry: `python "$env:GYPSY_HOME\workstream\gypsy.py" toolkit list`
- Verify the game: `.\scripts\verify_ultrablade.ps1`; repo hygiene: `python scripts\check_repo.py`

Do not claim checks that were not run. Record evidence in `docs/EVIDENCE.md`.
