# Character art pipeline

Each fighter's painted art becomes a **cutout (puppet) rig**: body parts pinned onto the same skeleton the gray-box rig uses. Every move's wind-up, strike and recovery comes straight from the frame data, so the animations need no hand keyframing to start with.

## What each fighter needs (in `art/source/<id>/`)

| File | Used for | Required? |
| --- | --- | --- |
| `parts.webp` | Body-parts sheet. It becomes the rig | yes |
| `portrait.webp` | Select-screen card, plus the face icon next to the health bar | yes |
| `expressions.webp` | 3×2 grid: neutral, shout, hurt, laugh, point, dizzy. Shown on the results screen (and later in Story mode) | yes |
| `full_body.webp`, `turnaround.webp` | Reference only | no |

**Parts sheet rules** (the AI sheets already follow them):
- one piece per part on a flat gray background;
- joint cut-ends drawn as flat dark caps (the tool finds them automatically);
- parts: head, torso, pelvis/pants, both upper arms, forearms, a fist, thighs, lower legs with boots, and the signature tool.

## Adding a fighter's art

1. Put the images in `art/source/<id>/` with the names above.
2. Run `python3 tools/art/build_fighter.py tools/art/<id>.json --preview`, copying `tools/art/arghya.json` as the starting config. The preview writes `client/fighters/<id>/parts_preview.png` with every piece numbered.
3. In the config, set which piece number is which part (`comp`), plus each part's `pivot` (the joint it hangs from) and `tip` (the next joint), in sheet pixels.
4. Run `python3 tools/art/build_fighter.py tools/art/<id>.json`. It writes WebP parts, `rig.json` and the UI art into `client/fighters/<id>/art/`.
5. Check the result without starting the game: `python3 tools/art/preview_rig.py <id> out.png --bones`. It draws idle, punch, kick, overhead, crouch and hit poses with the skeleton overlaid (green bones, red joints), using the same math as the game. Adjust pivots and anchors until the parts sit on their joints.
   - If a piece has other parts painted onto it (Arghya's torso has sleeves attached), give it a `keep` polygon that outlines only the part you want.
   - Put the shoulder anchors on the jacket's shoulder seams.
6. Set `"rig": "cutout"` in the fighter's `fighter.json`. The `test_cutout_rigs_load` test checks that the art loads.

## Why the files look the way they do

- **Small downloads:** the art is WebP (Arghya's whole set is 401 KB) and exported unchanged (`importer="keep"`). The game decodes it at runtime (`client/fighters/_cutout/art.gd`).
- **Clean joints:** joint caps are filled with the neighbouring texture, and each child part starts slightly past its joint, so it tucks under its parent. That avoids the "flat cut caps" listed in the design doc's cleanup list.
- **Upgrade path:** when the artist repaints the parts in three-quarter view (as the design doc asks), only the source images and the joint coordinates change.

## Tools in the game

- **Training F5:** slow motion (quarter speed), for reviewing animation.
- **Training F1:** hitboxes, to check the art lines up with what actually hits.

## Pose pictures (no rigging)

Fighters are now drawn from one finished picture per pose, made with the prompts in
`docs/art-prompts.md` (Step 2: 7 sheets x 8 poses). The cutout rig above is kept as the
fallback for any state or move that has no picture yet.

1. Save the sheets as `art/source/<id>/poses/sheet1.webp` ... `sheet7.webp`.
2. Copy `tools/art/arghya_poses.json` to `tools/art/<id>_poses.json`. For each pose, draw a few
   lines (sheet pixels) along the body, legs and tool: where poses overlap on a sheet, each pixel
   goes to the pose whose lines are nearest. Set `"air": true` for poses off the ground, and
   `scale` if a sheet draws the character bigger or smaller than Sheet 1.
3. `python3 tools/art/build_poses.py tools/art/<id>_poses.json --preview` colours each pose's share
   of the sheet (written next to `fighter.json`; don't commit it). Fix lines until the colours match.
4. `python3 tools/art/build_poses.py tools/art/<id>_poses.json` writes `pose_*.webp` and `poses.json`.
5. `map` in the config says which pose shows when: states (idle, walk, block, hit, ...) and each
   move's wind-up / strike / recovery, timed by the frame data (`fighters/_poses/pose_rig.gd`).
   `tests/run.sh` checks every named picture exists and that a whole CPU match always has one.

Stages: `art/source/stages/*.webp` (Step 3) are scaled to 1920x720 into `client/stages/painted/`;
the painting pans behind the fighters (`stages/painted/stage.gd`).
