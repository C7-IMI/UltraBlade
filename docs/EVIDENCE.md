# Evidence — what was actually run

This file records the verification performed for the UltraBlade playable slice. It is not a
quality claim beyond what is written here. Timestamps are local (America/Chicago), 2026-10-26.

**Environment:** Windows 11-class PC, NVIDIA T600 Laptop GPU (4 GB VRAM), Godot
4.7.2.stable.official.ed1daf0bf, Vulkan Forward+ for windowed runs, headless for logic runs.

## Repository separation

- The game lives in its own Git repository:
  `C:\OneDrive\OneDrive - Cyber 7 Group\GHRepo\Games\UltraBlade`.
- The ProjectGypsy checkout is a separate repository. A recursive search of ProjectGypsy for
  UltraBlade paths found **none**; all game files below are in the UltraBlade repo.
- `project.gypsy.json` in this repo pins Godot 4.7.2 / adapter `godot-4` / target `pc`.

## Game logic

| Check | Exact command | Observed result |
| --- | --- | --- |
| Headless boot/import | `godot_console.exe --headless --path game --import` | exit 0 |
| Core selftest | `godot_console.exe --headless --path game -- --selftest` | exit 0; 18/18 checks; `ULTRABLADE_SELFTEST_OK checks=18 failures=[]` |
| End-to-end integration | `godot_console.exe --headless --path game -s res://tools/integration_test.gd` | exit 0; **25/25** checks; `ULTRABLADE_INTEGRATION_OK checks=25 failures=[]` |
| AI demo | `godot_console.exe --headless --path game -- --demo-seconds 8 --demo` | exit 0; `ULTRABLADE_DEMO_OK ... state=goal ... score=0-1 ... saw_pickup=true saw_shot=true saw_hit=true saw_goal=true` |

The integration test boots the real `main.tscn`, injects synthetic keyboard/mouse input through
Godot's Input system, and checks:

1. Main scene loads; six skaters exist; the arena contract returns bounds.
2. The ActionForge skater model attaches to the player.
3. `W` moves the controlled skater.
4. A held/released left mouse press fires a charged shot (puck released with velocity > 12 m/s).
5. A real puck crossing the enemy goal plane increments the blue score and enters the goal state
   (no forced score call).
6. The red goalie saves a centered shot.
7. A slash damages an adjacent opponent.
8. A turnstile hazard damages a skater standing in its arc.
9. Skating through the killball charger arms the puck.
10. Pause/resume changes state.
11. Both enemy forwards down + a goal flags annihilation and ends the match.
12. The pause menu has three audio sliders; moving MASTER updates the setting and the real
    AudioServer master bus to ~0.55.
13. MUSIC is applied to its bus and persisted; the mute toggle toggles the real master bus.

## Repository hygiene

- `python scripts/check_repo.py` → **PASS**: 138 UTF-8 text files with no BOM and no CR; 61 binary
  files skipped; 13 relative Markdown links resolve; `CHECK_REPO_OK`.

## Windowed presentation

- `godot_console.exe --path game -- --capture` (windowed, Vulkan/Forward+, T600) → exit 0.
- Four 1600×900 PNGs written to `artifacts/captures/`:
  `01-menu.png`, `02-gameplay.png`, `03-goal.png`, `04-broadcast.png`.
- `godot_console.exe --path game -s res://tools/volume_preview.gd` (windowed) → exit 0;
  `05-pause.png` captures the pause **AUDIO MIX** with MASTER 65%, MUSIC 50%, SFX 80%;
  compressed as `docs/media/pause.jpg`.
- Volume/mix changes are saved to `user://settings.cfg` and applied to the Master/Music/SFX
  buses through `AudioDirector.set_volume/get_volume/set_muted`. Keyboard: `[` / `]` master,
  `M` mute.
- Compressed copies used in the README live in `docs/media/`.
- The capture is evidence of presentation, not a subjective quality score.

## Teammate subsystem checks (all run inside this repo)

| Subsystem | Exact command | Observed result |
| --- | --- | --- |
| Arena builder | `godot_console.exe --headless --quit-after 350 --path game res://tools/arena_preview.tscn -- --selftest` | exit 0, empty stderr; `ARENA_SELFTEST_OK`; 35/35 checks; **31 draws, 27,882 tris, 10 lights, 1,728 crowd instances, static_bodies=9, shapes=51**; goal areas at z=−30.5/+30.5; 4 spawn transforms per side; 4 boost pads; 4 hazards; bounds 16/30; no floor collider (match layer owns it) |
| ActionForge skater integration | `godot_console.exe --headless --path game -s res://tools/skater_preview.gd` | exit 0, empty stderr; `SKATER_SELFTEST_PASS checks=93`; 20 clips; cold library 73.28 ms, cached 0.002 ms; per-model build 3.96–9.93 ms; 24 renderables/skater; 11 root-motion clips stripped |
| ActionForge skater preview scene | `godot_console.exe --headless --path game --quit-after 120 res://tools/skater_preview.tscn` | exit 0 |
| Procedural audio | `godot_console.exe --headless --path game -s res://tools/audio_preview.gd` | `[AUDIO_PREVIEW] checks=121 fails=0`, `UB_AUDIO_PREVIEW_OK`, exit 0; 31 WAVs / 12.26 MB; 44.1 kHz 16-bit PCM; loops tagged forward |
| Audio generation | `python tools/generate_audio.py --verify-only` | `VERIFY 31 assets, 12.26 MB ... PASS` |

## Build and exported-binary smoke

- `godot_console.exe --headless --path game --export-release "Windows Desktop" ..\build\UltraBlade.exe`
  → exit 0; `build/UltraBlade.exe` produced.
- `build\UltraBlade.exe --headless -- --selftest` → exit 0; same 18/18 marker.
- The export uses the pinned 4.7.2 Windows Desktop template from this machine.

Final export: **124,297,152 bytes**, SHA-256
`C4943CBD6B788DAFD30DC332BA9BF5185632D6638B3E00F646348FC1D668384A` (2026-10-26, volume-control rebuild).
The exported binary was also run windowed in capture mode, and wrote four 1600×900 PNGs, proving
that the packaged project loads its scene, arena, skater models, audio and HUD outside the editor.
The final build was re-smoked with `build\UltraBlade.exe --headless -- --selftest` → exit 0,
18/18 checks.

## Gypsy Studio

- `python <GYPSY_HOME>\workstream\gypsy.py version` → **Gypsy Studio 0.1.0**
- `python <GYPSY_HOME>\workstream\gypsy.py engines probe` → Godot 4.7.2 usable; UE5 5.8 gate
  failed (4 GB VRAM < 8 GB); Unity 6000.6.7f1 usable; Flax 1.13 usable/experimental.
- `python <GYPSY_HOME>\workstream\gypsy.py check --project <this repo>` → **checks: PASS |
  capabilities 48 | tools 16 | project UltraBlade** (after the ActionForge toolkit extension).
- ActionForge was added to Gypsy Studio as a reusable toolkit: `gypsy toolkit list|show|probe|capabilities`
  and `gypsy toolkit actionforge catalog|fetch`. I re-ran the real probe (HTTP 200, HEAD) and a
  temp-project fetch of the rig + `idle_loop` + `walk_loop` (618,624 / 87,216 / 79,692 bytes) with
  SHA-256 provenance and `NOTICE.md`; the temp project was removed after inspection. Gypsy's own
  suite ran 215 tests OK (1 skip), `check_all` 6/6 PASS, and `capabilities check` 48/0 errors.
- The Gypsy dashboard is running at <http://127.0.0.1:8765/> (**HTTP 200**); its state shows the
  existing Phase-1..5 slices passing, the current clean checks, and the ActionForge capability count.
  No state was faked. The toolkit change has its own Retrace/BuildNotes/ADR-015 evidence in the
  ProjectGypsy repo.

## Not verified / honest gaps

- Human feel, fun, balance and enough time to master the controls were **not** measured. I played
  through scripts and captures; the subjective tuning is a first pass and should be playtested.
- No gamepad support, no multiplayer, no full league/gauntlet, no character select and no
  long-session soak.
- AI teammate/enemy decision quality is good enough to generate shots, hits, saves and goals in
  the demo, not a deep sports AI.
- The goal, pause and end-screen captures are staged/triggered states; actual match transitions
  were exercised by the integration test.
- Generated audio is original procedural content marked CC0-1.0 intended; it has not been through
  a formal commercial licence review.
- The ActionForge library version is hand-curated (20 clip IDs). The plugin can fetch arbitrary
  safe known IDs, but the website library is not crawled.
