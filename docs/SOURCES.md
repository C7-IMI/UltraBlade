# SOURCES — HyperBlade (1996) reference

All items accessed/last checked **2026-10-26** (America/Chicago) while compiling [docs/HYPERBLADE-REFERENCE.md](HYPERBLADE-REFERENCE.md). Tier: **P** = primary (the game, its manual, its developer, period reviews); **S** = secondary/aggregated; **L** = local evidence (gitignored, not redistributed).

## Primary sources

| # | Source | URL | Notes |
| --- | --- | --- | --- |
| P1 | *HyperBlade* Windows 95 install guide + quick-reference card (scan, OCR text) | https://archive.org/details/hyper-blade-manual · [manual text](https://archive.org/download/hyper-blade-manual/HyperBlade_Manual_djvu.txt) · [quick-ref text](https://archive.org/download/hyper-blade-manual/HyperBlade_Quick_Ref_djvu.txt) | **Primary evidence for HUD, controls, drome objects, install specs, LAN play, tips.** OCR mangles the key-layout page and some tables; quoted only where legible and corroborated |
| P2 | Wizbang! Software Productions 1996 website (archived) | [home](https://web.archive.org/web/19961230032435/http://www.wizbang.com/) · [HyperBlade page](https://web.archive.org/web/19970130162706/http://www.wizbang.com/hyperblade.htm) · [Wiz-Who](https://web.archive.org/web/19970130162659/http://www.wizbang.com/whizwho.htm) | Studio pitch, founding 1994, ADLIB engine, DirectX claim, Next Generation cover, planned fall 1996 release |
| P3 | MobyGames: *HyperBlade* entry, credits, release info | live: https://www.mobygames.com/game/1402/hyperblade/ · archived copies: [main (2010)](https://web.archive.org/web/20101104184911/http://www.mobygames.com/game/windows/hyperblade) · [release info](https://web.archive.org/web/20101105025641/http://www.mobygames.com/game/windows/hyperblade/release-info) · [credits (2015)](https://web.archive.org/web/20150513092417/http://www.mobygames.com/game/windows/hyperblade/credits) | Release dates, ESRB Teen, credits, MobyRank/critic scores. Live site blocks automated fetches (Cloudflare), so the archive snapshots are cited. Its "1st-person" perspective field is wrong |
| P4 | *Next Generation* #15 (March 1996), pp. 46–48 preview | https://archive.org/details/nextgen-issue-015 · [OCR text](https://archive.org/download/nextgen-issue-015/Next_Generation_Issue_015_March_1996_djvu.txt) | Pre-release preview: flat-shading rationale and Peterson quote, 12-team composition, planned modes, motion capture, camera options, "15-minute game"/scores in the 20s |
| P5 | GameSpot review — Tim Soete, 5 Dec 1996 | https://www.gamespot.com/reviews/hyperblade-review/1900-2537770/ | Canonical URL cited. Cloudflare blocks direct fetch; content was read through a text-rendering proxy. Positive, no numeric score exposed |
| P6 | *PC Gamer* review — Todd Vaughn, Feb 1997, 78% | https://web.archive.org/web/19991209061404/http://www.pcgamer.com/reviews/547.html | Team names, squad shape, camera, arena variety, verdict and highs/lows |
| P7 | *Computer Games Magazine* #8 (1997) review — Steve Bauman, 3/5 | https://web.archive.org/web/20030523220506/http://www.cdmag.com/articles/008/022/hyperblade_review.html | Gameplay critique, AI/team personalities, technical bugs, the "next year's model" line |
| P8 | CNET Gamecenter review — Hugh Falk, 3 Dec 1996 | [archived mirror](https://archive.kontek.net/gotcha.classicgaming.gamespy.com/gamecenter/HyperBlade%20-%20PC%20Review%20-%20Gamecenter%20-%20CNET_com.htm) (original: gamecenter.com/Reviews/Item/0,6,341,00.html) | Year 2065, "striker/defender/goalie + 2 subs", roller-hockey-in-a-half-pipe description, Speedball framing |

## Secondary / aggregated sources

| # | Source | URL | Notes |
| --- | --- | --- | --- |
| S1 | Wikipedia, "HyperBlade" (oldid 1381716495, edited 24 Oct 2026) | https://en.wikipedia.org/wiki/HyperBlade | Used for reception template, development/cancelled ports, sales, awards and unsourced lore; every borrowed claim is tagged **[U]** in the reference. Local copy: `reference/wiki-hyperblade.html` (gitignored) |
| S2 | Old-Games.com, "HyperBlade Download (1996 Sports Game)" | https://www.old-games.com/download/4692/hyperblade | HUD + rear-view mirror description, roster/reserve rules, LAN, 45 players/12 teams/12 arenas/3 skill levels. Local copy: `reference/oldgames-hyperblade.html` (gitignored) |
| S3 | Games Domain review text, reproduced on My Abandonware | https://www.myabandonware.com/game/hyperblade-dgd | Exhibition/gauntlet structure, player stats, fighting moves, annihilation win, blood toggle |
| S4 | My Abandonware game page | https://www.myabandonware.com/game/hyperblade-dgd | Preservation status, release territories, community notes on modern-OS workarounds |
| S5 | Internet Archive, *HyperBlade* playable demo | https://archive.org/details/Hyper_201307 | Evidence the demo/preview build survives |

## Local evidence (gitignored; do not commit)

- `reference/hyperblade-1.jpg … hyperblade-10.jpg` and `reference/hyperblade-contact.jpg` — publicly circulated 1996 press screenshots kept locally. Used for: HUD layout (health bar, roster column, clock/period pips, "Rear View" inset, LOS/SEA score strip, radar, announcement banner), intro screens ("Welcome to HOUSTON", exhibition match, LA vs Seattle), and the arena-information screen (Chicago Machine: capacity 120,000, built 2057, "Hi-Frequency Noise", 699 fatalities, sponsor BioBriefs, home/visitor object legend, AWARDS).
- `reference/wiki-hyperblade.html`, `reference/oldgames-hyperblade.html` — offline copies of S1/S2 used for extraction.
- Not included: the ActionForge assets under `reference/actionforge/` (unrelated to this research).

## Contradictions recorded

| Topic | Conflicting evidence | Handling in reference |
| --- | --- | --- |
| Release date | Wikipedia infobox 1 Nov 1996; Wikipedia body 16 Dec 1996; MobyGames 12 Dec 1996; reviews 3–5 Dec 1996 | "December 1996"; exact day unresolved |
| Annihilation win | Games Domain: kill all four opposing forwards then score to win; Wikipedia: annihilated team can still win on points | Rule treated as real; edge cases flagged |
| Period length | Wikipedia: 3/5/7-minute option; NextGen preview: 15-minute match | Default assumed 5 min; option unverified |
| Camera naming | PC Gamer/old-games: chase/over-shoulder third person; NextGen: "second-person over-the-shoulder" with optional third-person camera | Chase-cam feel described; terminology flagged |
| Goalie invulnerability | Wikipedia: invulnerable except mines; Old-Games: cannot be killed | Cannot be killed is solid; mine exception **[U]** |
| Swarf spelling | Manual: swarf/swarfs; Wikipedia: swarves | Manual spelling preferred |
| Perspective tag | MobyGames: "1st-person"; all screenshots/reviews: chase camera | Database error, disregarded |
| Sales | >1M copies by Sept 1998 (Wizbang release via Wikipedia); no independent audit found | Tagged **[U]** |

## Method and limitations

- Facts were taken from P1–P8 first; S1–S3 were used only for otherwise unreachable detail and are tagged **[U]**.
- MobyGames and GameSpot block automated fetching; MobyGames details come from Internet Archive snapshots (capture dates shown above) and GameSpot text via a reader proxy, with the canonical URL cited.
- The original Coming Soon Magazine review (86/100 per MobyRank) and the original Wizbang press release pages were not retrievable; their claims are represented through MobyGames/Wikipedia and marked accordingly.
- No complete 12-team/45-player roster is available in reachable sources; only the names in the reference are documented.
- OCR noise in the manual scan affects the key-layout diagram; semantic control descriptions are reliable, exact keys are not.
- Quotes are kept short (≤ 25 words) and attributed; no review text or manual passages are reproduced in bulk.
