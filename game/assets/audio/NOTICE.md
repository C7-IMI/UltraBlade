# ULTRABLADE audio -- provenance and license

All WAV files in this directory are original works generated procedurally by this
repository with tools/generate_audio.py (Python 3 + numpy, built-in wave module).

- No downloaded samples, no sample packs, no field recordings.
- No generative music/AI models were used (no MusicGen, no Stable Audio, etc.).
- Every sound is synthesized from oscillators/noise/envelopes/filters/convolution in code.
- Intended license: CC0-1.0 (public domain dedication) for these generated audio assets.
- Deterministic: each asset seeds a numpy Generator from CRC32(asset name); re-running the
  same tool version reproduces the same audio.

Generator: tools/generate_audio.py (pipeline ultrablade-audio-v1).
Format: 44.1 kHz, 16-bit PCM WAV. Mono for positional/impact SFX; stereo for music,
ambience, horn and stingers.

Generated: 2026-10-26 11:05:21 UTC
Total: 31 files, 12.26 MB (budget 25 MB).

| file | channels | duration | loop | base volume | purpose |
| --- | --- | --- | --- | --- | --- |
| skate_loop.wav | 1 | 2.00 s | yes | -14.0 dB | Seamless ice-skate hiss + scrape loop for skater motion (mono, loop). |
| slash.wav | 1 | 0.45 s | no | -3.0 dB | Short jak slash whoosh with metal shing; pitch up for light, down for heavy. |
| metal_hit.wav | 1 | 0.80 s | no | -2.0 dB | Jak-on-jak metal clash: inharmonic partials plus transient. |
| heavy_hit.wav | 1 | 1.00 s | no | -2.0 dB | Heavy slash impact: low metal ring, crunch and sub drop. |
| body_check.wav | 1 | 0.60 s | no | -3.0 dB | Body-check thud with gear rattle. |
| puck_pickup.wav | 1 | 0.38 s | no | +0.0 dB | Rok pickup: magnetic snap plus rising chirp. |
| shot.wav | 1 | 0.55 s | no | -2.5 dB | Charged shot launch: swept whoosh, crack and low thump. |
| goal_horn.wav | 2 | 2.20 s | no | -1.0 dB | Stadium air-horn chord with crowd bed (stereo). |
| crowd_swell.wav | 2 | 3.20 s | no | -4.0 dB | Crowd roar swell with claps for goals and big hits (stereo). |
| crowd_loop.wav | 2 | 8.00 s | yes | -12.0 dB | Seamless crowd murmur bed for AudioDirector.set_crowd (stereo, loop). |
| turnstile_hum.wav | 1 | 4.00 s | yes | -16.0 dB | Rotating turnstile hazard hum plus whoosh loop (mono, loop). |
| ui_click.wav | 1 | 0.16 s | no | -12.0 dB | Primary UI click. |
| ui_hover.wav | 1 | 0.10 s | no | -18.0 dB | Soft UI hover tick. |
| ui_back.wav | 1 | 0.22 s | no | -14.0 dB | UI back/cancel two-tone blip. |
| killball_charge.wav | 1 | 1.60 s | no | -5.0 dB | Killball charger rising electric whine with sparks. |
| killball_zap.wav | 1 | 0.90 s | no | -1.0 dB | Killball electric discharge: gated noise, zap glide, sub boom. |
| countdown_beep.wav | 1 | 0.22 s | no | +2.0 dB | Countdown beep (3-2-1). |
| countdown_go.wav | 1 | 0.50 s | no | +2.0 dB | Countdown GO tone. |
| victory.wav | 2 | 2.60 s | no | -1.0 dB | Victory stinger: rising blips, dark power chord, impact (stereo). |
| death.wav | 2 | 2.20 s | no | -1.0 dB | Death stinger: descending detuned saws, reverse swell, sub boom (stereo). |
| horn_short.wav | 2 | 1.00 s | no | +0.0 dB | Short period/whistle horn for faceoffs (stereo). |
| crowd_goal.wav | 2 | 2.40 s | no | +0.0 dB | Big goal crowd roar with claps, layered under the horn (stereo). |
| defeat.wav | 2 | 2.40 s | no | -1.0 dB | Defeat stinger: descending saws, low minor pad, sub drop (stereo). |
| down.wav | 1 | 0.90 s | no | +0.0 dB | Skater knocked down: falling slide tone, thud and gear clatter. |
| boost_pad.wav | 1 | 0.55 s | no | +0.0 dB | Boost pad pickup: rising sweep, tone rise and sparkle. |
| save.wav | 1 | 0.70 s | no | +0.0 dB | Goalie save: glove slap, leather thump and crowd gasp. |
| hit_rok.wav | 1 | 0.35 s | no | +0.0 dB | Rok impact: short metal tick plus plastic knock. |
| pass.wav | 1 | 0.40 s | no | +0.0 dB | Quick pass flick whoosh with tap. |
| killball_throw.wav | 1 | 0.85 s | no | +0.0 dB | Killball throw: electric launch whoosh, scanning whine and crackle. |
| slash_hit.wav | 1 | 0.50 s | no | +0.0 dB | Light jak slash impact: whoosh plus bright metal tick and thump. |
| music_match.wav | 2 | 40.00 s | yes | -6.0 dB | 40.0 s seamless dark synthwave/industrial match loop (stereo, loop). |

Loop assets (skate_loop, crowd_loop, turnstile_hum, music_match) are built with circular
synthesis/filtering/convolution so the end wraps into the start; verify seams with
python tools/generate_audio.py --verify-only (writes artifacts/audio/audit.json).

Regenerate: C:/Python/python.exe tools/generate_audio.py
