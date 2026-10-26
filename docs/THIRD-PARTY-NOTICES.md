# Third-party notices

ULTRABLADE is a **non-commercial homage** to *HyperBlade* (1996, Wizbang! Software Productions /
Activision). It is not affiliated with, endorsed by or licensed from the rights holders. The
original code, arena shaders, game design and procedural audio in this repo are original work
created for this remake; the original game's trademarks and assets remain with their owners.

## ActionForge animation assets

- Source: <https://actionforge.app/>; developer docs: <https://pritas.github.io/actionforge_ui/index.html>
- Files: `game/assets/actionforge/rig/rig-human.glb` and
  `game/assets/actionforge/animations/*.glb`.
- The ActionForge site states that the animation library is in the **public domain (CC0)** and may
  be used commercially without attribution. Clips by **Quaternius** come from his Universal
  Animation Library packs (CC0).
- The ActionForge application/source is © CGstuff, all rights reserved; only the animation assets
  are used here. Downloaded 2026-10-26. Root-motion position tracks are stripped at runtime; the
  source files are otherwise unmodified.
- Provenance: `game/assets/actionforge/NOTICE.md`.

## Fonts

- **Rajdhani** (SemiBold/Bold) — SIL Open Font License 1.1.
- **Share Tech Mono** — SIL Open Font License 1.1.
- Licence texts: `game/assets/fonts/OFL-Rajdhani.txt`,
  `game/assets/fonts/OFL-ShareTechMono.txt`.
- Google Fonts sources were downloaded 2026-10-26. No other font files are redistributed.

## Audio

- All 31 WAV files were synthesised for this project by
  `tools/generate_audio.py` using Python/numpy and deterministic seeds. They are original
  recordings, marked **CC0-1.0 intended**; no samples, music models or third-party sound libraries
  were used.
- `music_match.wav` is a 40-second original dark synthwave/industrial loop.
- Provenance: `game/assets/audio/NOTICE.md`.

## Engine and runtime

- Godot Engine 4.7.2 — MIT licence. The exported runtime includes Godot Engine binaries; see
  <https://godotengine.org/license>.

This notice is provided for provenance; it is not legal advice. A commercial release would need a
rights-holder review of the *HyperBlade* name/derivative work and a fresh review of all generated
assets.
