# Quick Fight: Design Team

Oct 28, 2026 · @HollyHood

A 4-fighter browser fighting game where three print-shop designers battle for the big client job and then face their boss. It is our learning build: every system a 45-fighter game needs, built once, with smoother animation than Friday Fighters.

## Game at a glance

Play free in any browser, 1v1, 60fps, with smooth cutout animation on every move. The world is a print and design shop: creatives fight with the tools of their craft.

| Item | Decision |
| --- | --- |
| Title | Quick Fight: Design Team (full title locked before launch after a USPTO and domain check) |
| Genre | 2D one-on-one fighter, Street Fighter / Mortal Kombat style |
| Platform | Web browser (desktop, phone, tablet, console browsers), installable app with offline play |
| Roster | 4 fighters: Arghya, Jitu, Tamal, Brad Ballard (boss) |
| Stages | 2: the print floor, the design studio |
| Players | 1P vs CPU, 2P local, online (quick match + private room code) |
| Price | Free; ads at natural breaks + cosmetic shop later |
| Team permission | All four real people have agreed to appear |

**Pillars**

1. **Motion first.** Every attack has wind-up, strike and recovery. This is where Friday Fighters is weakest (one picture per attack on 40 of 42 fighters).
2. **Easy to learn, deep to master.** Simple direction + button specials, with combos, meter and counters underneath.
3. **Instant to play.** Under 5 seconds from link to title screen on a phone over 4G.
4. **Fully owned.** Original characters, original music, no real brands or logos.
5. **Learning build.** Each fighter teaches the team one system, so the next 41 fighters reuse proven parts.

## The fighters

Four fighters, four archetypes, each teaching the team one system. Character art is locked (ChatGPT designs, approved).

| Fighter | Archetype | Look | Signature tool | Health | Walk speed | Teaches the team |
| --- | --- | --- | --- | --- | --- | --- |
| Arghya | All-rounder (starter) | Sunglasses, black-and-white geometric overshirt, CMYK splatter tee, cargo pants, work boots | Giant squeegee-hammer | 1000 | Medium | Basics: walk, jump, 4 attacks, block |
| Jitu | Rushdown | Splatter bomber jacket, white tee, harness, cargo joggers, high-tops | Steel ruler (back) + cutter (hip) | 950 | Fast | Combos and cancels |
| Tamal | Zoner | Black hoodie, ink-stained apron, ink-cartridge bandolier, high-tops | Ink cartridges + swatch fan | 950 | Slow | Projectiles and spacing |
| Brad Ballard | Boss / grappler | Bald, grey beard, white shirt, loose navy tie, suspenders, ID lanyard, gold watch | Heavy stapler | 1200 | Very slow | Grabs and armor |

Every fighter has the same base set: 4 standing normals, 4 crouching, 4 jumping, a throw, 2 specials, 1 super (1 bar), 1 Ultra (3 bars), intro, taunt, victory, KO.

### Arghya: the all-rounder

| Move | Input | What it does |
| --- | --- | --- |
| Squeegee Swing | Forward + Heavy Punch | Mid-range overhead swing, knocks down |
| Heat Press Palm | Down + Heavy Punch | Rising palm strike, anti-air |
| Ink Roll | Back + Heavy Kick | Rolling dash through projectiles |
| Super: Heat Press | 1 bar | Pins the opponent under a heat-press plate and presses them flat |
| Ultra: Full Bleed | 3 bars | Hammer combo ending in a CMYK ink explosion across the screen |

### Jitu: the rushdown

| Move | Input | What it does |
| --- | --- | --- |
| Rush Order | Forward + Heavy Punch | Fast dash punch, cancels into Ruler Slash |
| Ruler Slash | Down + Heavy Kick | Low sweep with the ruler, knocks down |
| Crop Mark | Back + Heavy Punch | Quick cross-slash counter |
| Super: Ctrl+Z | 1 bar | Rewinds and replays his last combo with extra damage |
| Ultra: Deadline Rush | 3 bars | 12-hit cutter-and-ruler flurry |

### Tamal: the zoner

| Move | Input | What it does |
| --- | --- | --- |
| Cartridge Toss | Forward + Heavy Punch | Throws an ink cartridge straight ahead (fast, low damage) |
| Ink Arc | Down + Heavy Punch | Lobbed cartridge that bursts into a puddle (slows opponents) |
| Swatch Fan | Back + Heavy Kick | Close-range fan swipe that pushes the opponent away |
| Super: Print Run | 1 bar | Barrage of flying posters across the screen |
| Ultra: Color Correction | 3 bars | Sprays all four CMYK inks in sequence, each hit tinting the opponent |

### Brad Ballard: the boss

| Move | Input | What it does |
| --- | --- | --- |
| Stapler Punch | Forward + Heavy Punch | Slow, heavy punch with armor (absorbs one hit) |
| Budget Cut | Down + Heavy Kick | Command grab, big damage |
| Meeting Called | Back + Heavy Punch | Shoulder charge with armor |
| Super: Client Revisions | 1 bar | Throw combo: slam, slam, slam, "Final\_FINAL\_v3" |
| Ultra: You're Fired | 3 bars | Grabs, staples a pink slip to the opponent, launches them off screen |

Brad is the Arcade boss and is locked until the player beats Arcade once.

## Controls and combat

Four attack buttons plus directions, the same layout as Friday Fighters so players feel at home. No assists or tag teams in this build: they come with the bigger roster.

| Action | Keyboard (P1) | Gamepad | Touch |
| --- | --- | --- | --- |
| Move / jump / crouch | WASD | Left stick / D-pad | Left virtual stick |
| Light Punch | J | X / Square | Button |
| Heavy Punch | K | Y / Triangle | Button |
| Light Kick | U | A / Cross | Button |
| Heavy Kick | I | B / Circle | Button |
| Block | Hold back | Hold back | Hold back on stick |
| Throw | Light Punch + Light Kick (close) | Same | Button |
| Super (1 bar) | Heavy Punch + Heavy Kick | Same | Button (lights up when ready) |
| Ultra (3 bars) | Down + Heavy Punch + Heavy Kick | Same | Button (lights up when ready) |
| Pause | Esc | Start / Options | Corner button |

All keys and buttons remap in Settings. Player 2 gets arrow keys + numpad by default.

**Specials** use one direction + one button (forward, down or back + Heavy Punch or Heavy Kick). Optional classic motions (quarter-circle forward, dragon punch) do the same moves with 10% more damage for experienced players.

**Core rules**

- Game logic runs at a fixed 60 ticks per second, independent of screen refresh.
- Every attack has 3 phases: startup (wind-up), active (can hit) and recovery. Frame data lives in each fighter's data file, never in code.
- Hitboxes (where an attack hits) and hurtboxes (where a fighter can be hit) are simple rectangles in fighter units, written by hand in the data file. No physics engine.
- Hit-stop: the game freezes 4 frames on light hits and 8 on heavy hits so impacts feel heavy. Camera shake on heavy hits and knockdowns.
- Combos: light attacks cancel into heavy attacks, heavy attacks cancel into specials. A combo counter shows on screen.
- Damage scaling: each hit after the 3rd in a combo does 10% less, down to a floor of 40%.
- Meter: 3 bars, built by landing hits (most), blocking, and taking damage. Super costs 1 bar, Ultra costs all 3.
- Juggles: launchers send the opponent up; up to 3 juggle hits before they fall out.
- Knockdown and get-up with a short invincibility window so players can't be trapped forever.
- Counter-hit: hitting an opponent during their startup does 20% more damage and shows a COUNTER banner.
- Throws can be broken by pressing throw within 7 frames.
- Rounds: best of 3, 99-second timer. Time-out goes to the player with more health.
- Finisher: after the final round, the winner can press Super within 2 seconds to trigger a short cinematic finisher. Cosmetic only.
- CPU: 3 difficulty levels (Intern, Senior Designer, Art Director). The CPU reads spacing and the player's meter.

## Modes and story

Five modes at launch. Story and Arcade share one plot: deadline night at the shop.

| Mode | What it is | Milestone |
| --- | --- | --- |
| Arcade | Pick a designer, beat the other two, then Brad. Beating it unlocks Brad. | Alpha |
| Versus | 1P vs CPU or 2P local on one keyboard or two gamepads; pick both fighters and the stage | Prototype |
| Training | Dummy opponent, infinite meter toggle, frame data and hitbox display | Prototype |
| Online | Quick match or private 4-letter room code; rematch, change fighter, find new opponent | Beta |
| Story | 4 short chapters with dialogue between fights and a tip before each one | Launch |

**Story: "Deadline Night"**

It's 9 p.m. A huge client order lands, due at 8 a.m. Brad Ballard announces only one designer will lead the job, and the winner gets the corner office.

1. **Chapter 1: Proof Check.** Arghya catches Jitu "borrowing" his layout. They settle it on the print floor. Tip: block a heavy attack, then punish.
2. **Chapter 2: Color Matters.** Tamal says Arghya's colors are off. A fight about CMYK breaks out in the design studio. Tip: close the distance between projectiles.
3. **Chapter 3: Rush Job.** Jitu wants the job more than anyone and ambushes the winner. Tip: don't panic under pressure, wait for a gap.
4. **Chapter 4: Final\_FINAL\_v3.** Brad rejects the design for the eleventh time. The boss fight. Ending: the team ships the job together at 7:59 a.m.

Dialogue is short (2 to 4 lines per scene), shown as portraits with speech bubbles using the expression sheets.

## Stages

Two original stages, each built as 4 scrolling layers (sky or back wall, midground, fight floor, foreground props) with at least one moving element. No real business names or logos.

| Stage | Setting | Layers and props | Moving element | Stage interaction |
| --- | --- | --- | --- | --- |
| The Print Floor | Large production shop at night, fluorescent lights | Wide-format printers, a DTF printer, a heat press, paper stacks, ink shelves, garage door with street outside | Printer heads sliding, sheets feeding out | Knockdown near the heat press: steam burst + bonus hit-stop |
| The Design Studio | Open-plan studio, late evening, city view | Monitors with mock layouts, pin-up boards with sketches, coffee cups, a client chair | Screens flicker, a coworker peeks in at the window when a Super lands | Finisher in the corner knocks a pin-up board over |

Both stages get a day version later as a free cosmetic.

## Art and animation

Cutout (puppet) animation: each fighter is one painted set of body parts rigged to a skeleton, animated smoothly at 60fps. Hand-drawn frames are added only for Supers, Ultras and finishers.

**Approved source art per fighter (5 images each):** full-body design, turnaround, expression sheet, select-screen portrait, body-parts sheet.

**Cleanup the artist must do before rigging**

- [ ] Remove the Nike swoosh and Jumpman logos from Tamal's and Jitu's sneakers (full body, turnaround, parts). Replace with an original sneaker design. Required before anything goes public.
- [ ] Repaint each parts sheet in three-quarter view to match the full-body fighting stance (the AI sheets are front view).
- [ ] One of each part only: head, torso, pelvis, upper arms, forearms, hands (open and fist), thighs, shins, feet, signature tool.
- [ ] Round, fully painted joint ends with overlap; no flat cut caps.
- [ ] Layered PSD per fighter, one layer per part, named to the rig convention (e.g. `arm_upper_L`).
- [ ] Keep one shared palette and outline weight across all four.

**Animation list per fighter (about 45 animations)**

| Group | Animations |
| --- | --- |
| Movement | idle, walk forward, walk back, dash forward, dash back, crouch, jump (up, peak, fall), land |
| Defense | stand block, crouch block, hit high, hit low, hit air, knockdown, get-up, throw break, KO |
| Normals | 4 standing, 4 crouching, 4 jumping (each with startup, active, recovery) |
| Specials | 3 specials, throw, Super, Ultra |
| Presentation | intro, taunt, victory, finisher, select-screen idle |

**Effects library (shared, made once):** light hit spark, heavy hit spark, block spark, counter flash, dust on landing and dash, ink splash (CMYK variants), sweat drops, shockwave ring, motion trail, super flash, KO flash. Every fighter casts a soft floor shadow.

**Tools (free, open source):** Godot 4's built-in 2D skeleton and animation editor for rigging, Krita or Photoshop for repaints, Aseprite or Krita for hand-drawn effect frames.

## Audio

All audio is original or properly licensed. No covers of real songs (Friday Fighters' biggest legal risk).

- **Music:** 4 tracks (menu, print floor, design studio, Brad boss theme), each a 60 to 90 second loop. Made by a local producer or licensed with written permission.
- **Voices:** Jitu, Tamal, Arghya and Brad record their own lines on a phone in a quiet room: intro (2), taunt (2), attack grunts (6), hit (4), Super call (1), Ultra call (1), victory (3), KO (1). About 20 lines each.
- **Sound effects:** squeegee swoosh, ruler whip, ink splat, stapler clack, heat-press hiss, paper flutter, body hits (light, heavy), blocks, footsteps, crowd-free ambient shop hum. From CC0 libraries or recorded in the shop.
- **Mix:** music ducks 6 dB when a Super or announcer line plays; all audio normalized to -14 LUFS, shipped as compressed .ogg with .mp3 fallback.

## Tech architecture

The fight simulation runs in each player's browser and only button inputs travel between them, so the server stays small and cheap.

&#91;embedded content: Quick Fight architecture · 2 browsers, 6 server services\]

The server loads the game, pairs players and relays traffic only when a direct link fails; it never runs fights.

## Build plan

About 14 weeks from first code to public launch, with art running alongside code. Each milestone has a gate it must pass before the next one starts.

1. **Engine choice test (week 1).** Build an empty Godot 4 web export and a plain JavaScript + WebGL page, both with one animated rig. Gate: pick the one that reaches the title screen in under 5 seconds on a mid-range Android phone over 4G.
2. **Gray-box prototype (weeks 2 to 4).** Two placeholder fighters (colored boxes on simple rigs), one flat stage, all core rules from the Controls section, Versus and Training modes. Gate: hits feel heavy, combos work, 60fps steady on that phone.
3. **Online prototype (weeks 5 to 6).** Rollback netcode over WebRTC, room codes, relay fallback. Gate: playable at 150 ms ping between Saint Paul and Dhaka with no visible stutter.
4. **Arghya vertical slice (weeks 6 to 8).** First real fighter fully rigged and animated on the Print Floor, with effects, voices and music. Gate: you and the team agree it looks better than Friday Fighters side by side.
5. **Alpha: full roster (weeks 9 to 11).** Jitu, Tamal and Brad; Design Studio stage; Arcade mode; CPU at 3 levels. Gate: 10 outside players finish Arcade and report no blocking bugs.
6. **Beta: polish and online (weeks 12 to 13).** Quick match, rematch flow, settings, touch controls, installable app, ads. Gate: 50-person public playtest, crash rate under 1%.
7. **Launch (week 14).** Story mode, trailer, YouTube Shorts and TikTok clips, merch drop of all four characters printed in-house.

## Developer handoff

The developer starts in Claude Code with this document plus the clean-room spec in the Mobile Game Project (`claude/friday-fighters-clean-room-spec.md`). Never open, copy or paste Friday Fighters code or art.

**Stack (self-hosted, open source, no monthly subscriptions)**

| Layer | Choice |
| --- | --- |
| Game client | Godot 4 web export (GDScript), or JavaScript + WebGL if week 1's test says so |
| Netcode | Rollback (GGPO-style; Godot Rollback Netcode add-on or own implementation), WebRTC data channels |
| Signaling + matchmaking | FastAPI with WebSockets |
| Relay for blocked connections | coturn (same as the Card Room stack) |
| Data | PostgreSQL (players, matches, ranked ladder), Redis (queues, presence) |
| Files | MinIO for game builds and assets, Caddy in front with HTTPS and caching |
| Analytics | Umami (self-hosted) |
| Payments (later) | Stripe Checkout for cosmetics |
| Deploy | Docker Compose on our VPS; CI builds the web export and uploads to MinIO |

**Repo layout**

```
quick-fight/
  client/            # Godot project
    engine/          # sim loop, input buffer, state machine, hit detection (no fighter-specific code)
    fighters/        # one folder per fighter: data file (frame data, boxes), rig scene, animations
    stages/          # print_floor, design_studio
    ui/              # menus, HUD, select screen, settings, touch controls
    net/             # rollback, WebRTC, room codes
    fx/              # shared effects library
  server/            # FastAPI signaling, matchmaking, presence, ranked
  infra/             # docker-compose.yml, Caddyfile, coturn config
  docs/              # this doc exported, clean-room spec, frame-data tables
  tests/             # determinism tests, frame-data tests, server tests
```

**Engineering rules**

- The fight simulation is deterministic: whole-number math for positions and boxes, fixed 60 ticks per second, no randomness without a shared seed. Required for rollback.
- Fighters are data. Adding a fighter means adding a folder, never changing engine code.
- Online inputs come only from the network layer; the sim never reads the keyboard directly.
- Automated test: run the same 10,000-frame input recording twice and compare game state every frame. Must match exactly.
- Performance budget: under 5 s to title screen on 4G, under 400 MB memory in the browser, steady 60fps on a mid-range Android phone.
- Every merge request runs tests and a web build; no direct pushes to main.

**First prompt to give Claude Code**

```
Read docs/quick-fight-design.md and docs/friday-fighters-clean-room-spec.md.
We are building the Week 1 engine test and the Week 2-4 gray-box prototype for Quick Fight: Design Team.
1. Set up the repo layout from the handoff section.
2. Build a minimal Godot 4 web export: title screen, one stage, two placeholder fighters.
3. Implement the deterministic 60-tick sim, input buffer, state machine, hit/hurt boxes, hit-stop,
   meter, combos and rounds exactly as the Controls and combat section describes.
4. Fighter frame data must load from a data file per fighter.
5. Add the determinism test.
Show me the plan first, then build it step by step and run the tests after each step.
```

## Open questions

- [ ] Who is the developer, and who is the 2D artist/rigger for the parts cleanup?
- [ ] Full title: "Quick Fight: Design Team" as is, or a distinctive spelling for trademark? Run a USPTO search and check the domain.
- [ ] Music: which local producer, and on what terms?
- [ ] Ads: which ad network (we choose; not decided yet).
- [ ] Should the shop's real name appear anywhere (credits only, or a stage poster)? Default: credits only.
