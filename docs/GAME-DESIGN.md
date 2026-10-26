# ULTRABLADE — game design (playable slice)

**One-line pitch:** HyperBlade's lethal future-hockey, rebuilt as a fast, readable, neon-drenched
arcade sport for one player against a disposable AI squad.

## Fantasy

You are a **drome athlete** in the year 2099. The rink is a corporate bloodsport cathedral: black
ice, holographic crowd, hard-light arches, a glowing rok. The crowd wants goals; the league wants
casualties. Give them both.

## Core loop (faithful to HyperBlade)

1. **Skate** into the drome; your AI teammate and goalie hold formation.
2. **Take the rok** — skate over the loose rok or slash it free from an opponent.
3. **Score** — carry it into the enemy goal, or stop and charge a shot from range.
4. **Fight** — jaks and body checks hurt. Killed skaters leave the ice; the next goal or period
   brings a reserve in. Kill both enemy forwards and score for an early **ANNIHILATION** win.
5. **Use the drome** — boost pads, spinning turnstiles and the **killball charger** change the fight.

## Match rules

| Rule | Value |
| --- | --- |
| Teams | Blue (player) vs Red (AI) |
| Active skaters | 2 per side; 1 AI goalie per side (invulnerable) |
| Periods | 3 × 90 seconds |
| Clock | Stops after a goal, resumes on the next faceoff |
| Goal | 1 point |
| Skater HP | 100 |
| Downed skater | Out until the next goal or period restart; a reserve takes the slot |
| Annihilation | If both enemy skaters are down and you score, match ends immediately |
| Overtime | Sudden-death 45 s if tied at the final horn |
| Difficulty | One readable AI profile; speed/reaction scales with match phase |

## Moves

| Move | Effect |
| --- | --- |
| Boost | Costs stamina; accelerates; can body-check for minor damage/knockback |
| Slash | Short-range jak arc; 10 damage, interrupts, can dislodge the rok |
| Heavy slash | Longer wind-up, 24 damage and knockdown; leaves you exposed |
| Body check | Sprint into an opponent for 8 damage and a push |
| Jump | Hops hazards and checks; no puck loss |
| Shot | Charged throw; speed and damage scale with charge; killball is a heavier projectile |
| Pass | Snaps the rok to your teammate's path |
| Killball | Skate over the charger with the rok; next shot/throw electrocutes and explodes |

## Arena — "THE VAULT"

A black-glass elliptical drome 62 m long, 34 m wide, with low curved boards and goals cut into each
end. Center ice carries a giant animated league sigil. Visual language:

- Obsidian ice with cyan/magenta team light pools, wet reflections and skate trails.
- Holographic crowd tiers, floating banner drones, overhead jumbotron.
- Cyan = player/Blue, magenta/red = enemy/Red, amber = danger/killball.
- Hard industrial typography, chrome + emissive trim; broadcast overlays.
- Hazards: two rotating turnstiles at mid-ice, laser hurdle strips near each blue line, two boost
  strips per side, and a central killball charger.

## Presentation

- Chase camera behind the player with FOV kick on boost, mouse orbit, target-assist reticle.
- Goal: 0.7 s slow-motion, ball-cam cut, shockwave, screen flash, crowd roar, broadcast lower-third.
- Combat: hit-stop (~40 ms), camera shake, spark/ice-shard bursts, damage numbers.
- HUD: scoreboard, clock/period, roster pips, health/stamina, minimap, kill feed, contextual prompts.
- Menus: in-world title screen over the drome, one-key start, controls card, pause.

## Content in the slice

One arena, two team identities (Blue "ICE SAINTS", Red "REDLINE SYNDICATE"), four AI outfield profiles
(Striker, Enforcer, Runner, Anchor) dressed by role, one goalie per team, one lethal hazard set.
Roster names and colour variants are cosmetic in this slice.

## Modern additions that serve the core

- Readable combat: clear wind-ups, hit sparks, health bars above skaters, directional damage flash.
- Skill expression: charged shots, bank shots off boards, slash timing, boost management.
- Broadcast style, but never obscuring play.
- Accessibility options in the pause menu: screen shake, blood/gore toggle, HUD scale (if time permits).

## Explicitly out of scope

Multiplayer, season/tournament meta, roster progression, licensed music, console/gamepad support,
character creator, full original 12-team/12-arena content. The design leaves room for them.
