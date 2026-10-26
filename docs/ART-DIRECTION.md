# ART DIRECTION — UltraBlade

## Reference DNA

- Original HyperBlade: 1996 flat-shaded polygonal athletes, huge elliptical half-pipe drome,
  team-coloured floor wedges, brutal low-camera skating, glowing goal mouths, cyan HUD frames.
- Modern reference points: `Tron: Legacy` arena lighting, `Speedball` readability, `Rocket League`
  camera/fov language, modern esports broadcast overlays (score bug, kill feed, player cams).
- Do not imitate a specific real-world league or team; invent the league ("The Drome League") and
  the two teams.

## Palette

| Token | Hex | Use |
| --- | --- | --- |
| Void | `#05070f` | space, background, UI shadow |
| Ice | `#0a1524` | rink base, glass |
| Cyan | `#21e6ff` | player team, UI primary, boost |
| Blue deep | `#0b67ff` | player light pools |
| Magenta | `#ff2d6f` | enemy team, danger, goal |
| Amber | `#ffb020` | killball, hazard, warnings |
| Bone | `#eaf6ff` | text, highlights |
| Steel | `#3a4a63` | trims, boards |

## Forms

- Ellipse / capsule / swept curves; no right angles in the arena silhouette.
- Skaters: sleek mannequin base with angular pads, helmet visor, one oversized left jak.
- UI: thin 1 px chrome rules, wide tracking, clipped corners, vertical labels, scanline textures.
- Fonts: use built-in system sans (Godot default) with heavy weight and letterspacing, or bundle an
  OFL font only if provenance is recorded. No random web font downloads.

## Lighting

- Mood is a night game under black light: low ambient, strong team-colour pools, cyan edge trim,
  emissive signage, fog on the floor.
- Bloom is high but controlled; do not blind the player.
- Use a single directional/key light plus emissive and Omni lights; 4 GB VRAM budget.

## Motion / effects

- Speed lines and FOV kick only when boosting; skate sparks and trail ribbons.
- Goal: white-out, chromatic ring, radial particles, slow motion.
- Hits: 40 ms hit-stop, small camera shake, white/team-colour flash, ice chips.
- Crowd: instanced pixels/holograms that shimmer, not thousands of skinned meshes.
