# Engine decision — Godot 4.7.2

**Status:** accepted, 2026-10-26. **Engine:** Godot 4.7.2 (Forward+), Windows PC.

## Recommendation

For an UltraBlade/HyperBlade-style game — a fast, close-quarters 3D skating combat game with
procedural arenas, glTF characters, heavy visual effects and a small team — **Godot 4.7.2 is the
right engine** for this project.

## Why

1. **It is proven on this machine.** Godot is the only engine here with a verified headless
   import/test loop, exported Windows binary, windowed capture and deterministic demo. Unity is
   installed but has no import/build adapter in this workstream; Unreal 5.8 fails the 4 GB VRAM
   hardware gate.
2. **Iteration speed fits arcade combat.** GDScript + instant scene reload + headless smoke tests
   let us tune movement, hit feedback and camera feel in minutes, not compile cycles. That feel is
   the game.
3. **The renderer is enough.** Low-poly skaters, a banded arena, emissive neon, bloom, particles and
   a few lights run comfortably on the T600. We do not need UE5's Nanite/Lumen for this art style.
4. **The asset contract matches ActionForge.** Godot imports glTF/GLB natively, including the
   ActionForge CC0 rig and clips. Export to Windows/PC is one command.
5. **No licence friction.** No runtime royalty, no activation server, no per-seat editor cost.
6. **The workstream already speaks Godot.** Gypsy's engine adapter, smoke tests and hardware gate
   were built around 4.7.2; choosing it keeps the evidence pipeline real instead of aspirational.

## Alternatives considered

| Engine | Assessment |
| --- | --- |
| **Unity 6** | Viable for a 3D sports/combat game and strong asset store. Rejected for this slice because it adds a licence/activation dependency and the local workflow has no proven import/build loop. A port if requirements change. |
| **Unreal 5.8** | Best-in-class lighting, but hardware-gated here (4 GB VRAM vs 8 GB minimum) and too heavy for a fast-iteration arcade prototype. |
| **Flax** | No proven headless path; experimental adapter. |

## Consequences

Godot-specific gameplay code; a future engine move is a port. This is accepted: the slice's value is
the feel and the design evidence, both of which are engine-neutral.
