# Fighter data files

Every fighter is one folder: `fighters/<id>/fighter.json` (plus, later, its rig scene and animations).
Adding a fighter means adding a folder. The engine finds it automatically and never needs a code change.
Folders starting with `_` are shared parts, not fighters.

All numbers must be whole numbers. The loader rejects fractions so the fight stays deterministic.

## Units

| What | Unit |
| --- | --- |
| Boxes (`[x, y, w, h]`) | pixels. `x` is forward from the feet when facing right, `y` is up from the floor |
| Speeds (`walk`, `dash`, `jump`, `motion`, `launch`) | 1/100 pixel per frame (so 360 = 3.6 px/frame) |
| Gravity | 1/100 pixel per frame, per frame |
| Frame data | frames at 60 per second |
| Damage, meter | points. One meter bar = 500 |

## Top level

`id`, `name`, `archetype`, `color` (gray-box draw colour), `rig`, `health`,
`walk {forward, back}`, `dash {forward {frames, speed}, back {...}}`,
`jump {squat, velocity, gravity, forward}`, `pushbox {w, h}`,
`hurtboxes {stand: [...], crouch: [...], air: [...]}`, `moves {...}`.

## Moves

Required set (the loader checks it):

- **Normals:** `st_`, `cr_` or `j_` + `lp`, `hp`, `lk` or `hk`, for 12 in total. Light buttons use category `light`, heavy buttons use `heavy`.
- **Throw:** `throw`, with category `throw`.
- **Specials:** any name, category `special` and `input: {dir: forward|down|back, button: hp|hk}`. Doing the classic motion instead (forward = quarter-circle forward, down = dragon punch, back = quarter-circle back) gives +10% damage.
- **Super:** category `super`, with `meter_cost` 500.
- **Ultra:** category `ultra`, with `meter_cost` 1500.

Move fields:

| Field | Meaning |
| --- | --- |
| `startup`, `active`, `recovery` | Frames. `startup` is the number of frames before the first active frame |
| `damage`, `chip` | Damage on hit / on block |
| `hitstun`, `blockstun` | Frames the opponent can't act |
| `pushback` | Pixels the opponent slides back. It goes to the attacker when the opponent is in the corner |
| `level` | `mid` (default), `low` (must crouch-block), `overhead` (must stand-block). Air attacks are always overhead |
| `strength` | `light` or `heavy`. This picks 4 or 8 frames of hit-stop. It defaults from the category |
| `box` | Hitbox. For throws it is checked against the opponent's pushbox |
| `knockdown` | `true` = the opponent is knocked down |
| `launch` | `[vx, vy]`. Sends the opponent into a juggle (up to 3 juggle hits after it) |
| `cancel` | What this move can cancel into once it connects. Use categories (`heavy`, `special`, `super`, `ultra`) or move names |
| `motion` | `[[from, to, vx], ...]`. The fighter moves forward during those frames |
| `invuln` | `{from, to, strike, throw, projectile}` invincibility windows |
| `armor` | `[from, to, hits]`. Absorbs that many hits during those frames |
| `hurt_extend` | Extra hurtboxes from the first active frame on (the limb you can hit) |
| `meter_cost`, `flash` | Meter cost, and the super-flash freeze in frames |
| `grab`, `breakable` | Command grab. `breakable` defaults to `true` for the normal throw only |
| `hits` | Multi-hit moves: a list of hits that override any field above, with `start`, `active`, and an optional `repeat` + `every` |
