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
5. Set `"rig": "cutout"` in the fighter's `fighter.json`. The `test_cutout_rigs_load` test checks that the art loads.

## Why the files look the way they do

- **Small downloads:** the art is WebP (Arghya's whole set is 401 KB) and exported unchanged (`importer="keep"`). The game decodes it at runtime (`client/fighters/_cutout/art.gd`).
- **Clean joints:** joint caps are filled with the neighbouring texture, and each child part starts slightly past its joint, so it tucks under its parent. That avoids the "flat cut caps" listed in the design doc's cleanup list.
- **Upgrade path:** when the artist repaints the parts in three-quarter view (as the design doc asks), only the source images and the joint coordinates change.

## Tools in the game

- **Training F5:** slow motion (quarter speed), for reviewing animation.
- **Training F1:** hitboxes, to check the art lines up with what actually hits.
