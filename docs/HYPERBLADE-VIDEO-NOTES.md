# HYPERBLADE VIDEO REFERENCE NOTES

Research pass for the modern UltraBlade drome. These notes come from the three supplied
YouTube references, sampled frame-by-frame (the videos themselves are not redistributed).

## Sources

- [Hyperblade (PC) - Gameplay / No Commentary](https://www.youtube.com/watch?v=EpScHKYEEpE)
  — Bit Game Reviews, 12:11, 2020.
- [THL 2066 Season - Finals - BLAM! Nemesis vs. Tokio Ronins](https://www.youtube.com/watch?v=FNt_1BBHiwE)
  — Transnational HyperBlade League, 12:43, 2022.
- [HyperBlade (1996) - Official Trailer](https://www.youtube.com/watch?v=iAJBpyQwRXo)
  — Retro Game Trailers, 1:37.

## What the footage actually shows

### 1. The drome is a bowl, not a flat rink

The gameplay clips are dominated by a huge grey playfield whose sides sweep upward into steep,
skateable banks. The camera regularly looks across a curved wall with no vertical boards in view;
players ride high on the bank with the camera tilted relative to the ice. The edge is marked by
long, bright lane curves rather than a flat perimeter wall.

At around **1:00–3:00** in the first video, the camera is low behind a skater on a broad curved
surface; at **4:30–6:00** the view is almost side-on across the bank. A later frame shows two
skaters riding a steep blue surface high above the central lane. This is the key layout correction:
**ellipse in plan, trough/half-pipe in section.**

### 2. The surface is divided into skateable lanes and ramps

The bowl is not one smooth blank half-pipe. It has:

- long painted lane lines running down the curved walls;
- a central flat/darker band used as the main goal-to-goal channel;
- large team-coloured wedges fanning out from the centre;
- raised ridges and chute-like structures that act as ramps;
- jump/boost hazards and circular pads on the flat central lane.

The goal-to-goal straight is readable, but the sides are open, high-speed space. Combat and puck
carries spill up the banks rather than being bounded by a flat rectangle.

### 3. Team diversity is part of the presentation

The league final footage shows several uniform identities across the rosters. The gameplay clips
show red/blue players, the trailer has green uniforms, and the arena/crowd uses the two competing
team colours. The official trailer's menu shots also show multiple **home/visitor** team plates.

Our slice therefore supports four home squads and four away squads, with live uniform recolour,
HUD names and scoreboard colours:

| Side | Squads | Palette |
| --- | --- | --- |
| Home | Ice Saints, Cobalt Kings, Glacier Guard, Neon Oracle | cyan → electric blue, teal, ice |
| Away | Redline Syndicate, Ember Legion, Crimson Choir, Solar Kings | red → orange, magenta, gold |

### 4. Camera and read

The camera is a low, behind-the-skater broadcast chase view. A small rear-view inset sits in the
upper right of the HUD. The player list, health pips and score bug are always visible, so combat
information is never hidden. Our modern HUD keeps the same priority with a minimap instead of the
rear-view inset.

### 5. Goals and verticality

Goals are cut into the end of the drome and the centre lane stays low so the rok can be shot into
them. The raised banks beside the goal lane create the characteristic "down in the trough" look;
players can carry the rok up a wall and attack from a raised angle.

## Implemented in UltraBlade

- **True ellipse** drome outline (not a rounded rectangle), with a radial bowl mesh.
- **Curved height field**: flat goal lane, banks rising to 4.2 m; skaters, puck, hazards and camera
  all sample the same surface.
- **Bank riding**: skaters follow and land on the curved surface, tilt into the slope, jump from
  banks, and can fight/carry on the walls.
- **Raised rim rails** replacing flat side boards; crowd/stands remain beyond the rim.
- **Lane paintings** re-projected onto the curved surface; team-coloured wedges and centre sigil.
- **Hazards/pads** moved onto valid parts of the surface.
- **Team selection** in the title menu, four squads per side, live uniform/HUD/scoreboard recolour.
- **Bank-aware camera** clearance and deeper chase framing.

## Deliberate differences

- UltraBlade is still a single arena vertical slice; original multi-arena tour and season structure
  are out of scope.
- The original HUD rear-view inset is represented by the modern minimap rather than a second render.
- Surface grip/slope physics are arcade-tuned for readability, not a skate sim.
