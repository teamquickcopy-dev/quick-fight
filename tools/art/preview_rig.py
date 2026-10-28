"""Renders a fighter's cutout rig in several poses, outside the game, for tuning joints.

    python3 tools/art/preview_rig.py arghya [out.png] [--bones]

Uses the same math as client/fighters/_cutout/cutout_rig.gd and reads the pose angles from
client/fighters/_graybox/box_rig.gd, so what you see here is what the game draws.
--bones overlays the skeleton (bones and joint dots) to check that parts line up with joints.
"""
import json
import math
import os
import re
import sys

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SCALE = 3          # preview magnification
CELL = (300, 300)  # per pose, in game px


def gd_dict(text):
    return {k: float(v) for k, v in re.findall(r'"(\w+)":\s*(-?[\d.]+)', text)}


def load_poses():
    src = open(os.path.join(ROOT, "client/fighters/_graybox/box_rig.gd")).read()
    poses = {}
    for name in ("IDLE", "CROUCH", "AIR", "HIT", "BLOCK", "WIN", "DASH"):
        m = re.search(r"const %s := \{(.*?)\}" % name, src, re.S)
        poses[name] = gd_dict(m.group(1))
    kinds = {}
    for m in re.finditer(r'"(\w+)": \[\{(.*?)\}, \{(.*?)\}\]', src, re.S):
        kinds[m.group(1)] = (gd_dict(m.group(2)), gd_dict(m.group(3)))
    return poses, kinds


def over(base, extra):
    out = dict(base)
    out.update(extra)
    return out


def rot(v, a):
    c, s = math.cos(a), math.sin(a)
    return (v[0] * c - v[1] * s, v[0] * s + v[1] * c)


def add(a, b, k=1.0):
    return (a[0] + b[0] * k, a[1] + b[1] * k)


def ddir(deg):
    r = math.radians(deg)
    return (math.sin(r), math.cos(r))


class Rig:
    def __init__(self, fid):
        d = os.path.join(ROOT, "client/fighters", fid, "art")
        self.cfg = json.load(open(os.path.join(d, "rig.json")))
        self.tex = {k: Image.open(os.path.join(d, p["texture"])).convert("RGBA") for k, p in self.cfg["parts"].items()}

    def draw(self, canvas, feet, pose, bones=False, tint=None):
        c = self.cfg
        L, A = c["lengths"], c["anchors"]
        p = pose
        spin = p.get("spin", 0.0)
        legs = L["leg_upper_F"] + L["leg_lower_F"] + c["sole"]
        hip_center = (0.0, -(legs - p.get("drop", 0.0)))
        pr = math.radians(spin + p["lean"] * 0.3)
        waist = add(hip_center, rot((0, A["hip_F"][1]), pr), -1)
        tr = math.radians(p["lean"] + spin)
        tdir = rot((0, -1), tr)
        neck = add(waist, tdir, L["torso"])
        hip_f, hip_b = add(waist, rot(A["hip_F"], pr)), add(waist, rot(A["hip_B"], pr))
        sh_f, sh_b = add(waist, rot(A["shoulder_F"], tr)), add(waist, rot(A["shoulder_B"], tr))
        joints = []

        def part(name, at, direction):
            if name not in self.tex:
                return
            pp = c["parts"][name]
            axis = math.atan2(pp["tip"][1] - pp["pivot"][1], pp["tip"][0] - pp["pivot"][0])
            ang = math.atan2(direction[1], direction[0]) - axis
            img = self.tex[name]
            s = c["draw_scale"] * SCALE
            img = img.resize((max(1, round(img.width * s)), max(1, round(img.height * s))), Image.LANCZOS)
            piv = (pp["pivot"][0] * s, pp["pivot"][1] * s)
            # Rotate around the pivot: pad so the pivot is the centre, then rotate.
            w, h = img.size
            R = math.ceil(math.hypot(max(piv[0], w - piv[0]), max(piv[1], h - piv[1]))) + 2
            padded = Image.new("RGBA", (2 * R, 2 * R))
            padded.paste(img, (round(R - piv[0]), round(R - piv[1])))
            padded = padded.rotate(-math.degrees(ang), resample=Image.BICUBIC)
            if tint:
                r, g, b, a = padded.split()
                padded = Image.merge("RGBA", (r.point(lambda v: v * tint), g.point(lambda v: v * tint), b.point(lambda v: v * tint), a))
            x = feet[0] + at[0] * SCALE - R
            y = feet[1] + at[1] * SCALE - R
            canvas.alpha_composite(padded, (round(x), round(y)))

        def limb(name, frm, deg, draw=True, t=None):
            d = ddir(deg)
            end = add(frm, d, L[name])
            if draw:
                part(name, frm, d) if t is None else part_t(name, frm, d, t)
            joints.append((frm, end))
            return end

        def part_t(name, at, d, t):
            nonlocal tint
            old, tint = tint, t
            part(name, at, d)
            tint = old

        back = 0.72
        b_el = limb("arm_upper_B", sh_b, p["bu"] + spin, False)
        b_wr = limb("arm_lower_B", b_el, p["bl"] + spin, True, back)
        part_t("hand_B", b_wr, ddir(p["bl"] + spin), back)
        limb("arm_upper_B", sh_b, p["bu"] + spin, True, back)
        b_kn = limb("leg_upper_B", hip_b, p["bt"] + spin, False)
        limb("leg_lower_B", b_kn, p["bs"] + spin, True, back)
        limb("leg_upper_B", hip_b, p["bt"] + spin, True, back)
        part("pelvis", waist, rot((0, -1), pr))
        f_kn = limb("leg_upper_F", hip_f, p["ft"] + spin, False)
        limb("leg_lower_F", f_kn, p["fs"] + spin)
        limb("leg_upper_F", hip_f, p["ft"] + spin)
        part("torso", waist, tdir)
        part("head", neck, rot(tdir, math.radians(p["lean"] * 0.4)))
        f_el = limb("arm_upper_F", sh_f, p["fu"] + spin, False)
        fist = limb("arm_lower_F", f_el, p["fl"] + spin, False)
        part("tool", fist, ddir(p["fl"] + spin + p.get("to", 100.0)))
        limb("arm_lower_F", f_el, p["fl"] + spin)
        limb("arm_upper_F", sh_f, p["fu"] + spin)
        if bones:
            dr = ImageDraw.Draw(canvas)
            sc = lambda q: (feet[0] + q[0] * SCALE, feet[1] + q[1] * SCALE)
            for a, b in joints + [(waist, neck), (hip_center, waist)]:
                dr.line([sc(a), sc(b)], fill=(0, 255, 0, 255), width=2)
                for q in (a, b):
                    x, y = sc(q)
                    dr.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(255, 40, 40, 255))


def main():
    fid = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith("--") else f"/tmp/{fid}_rig_preview.png"
    bones = "--bones" in sys.argv
    poses, kinds = load_poses()
    idle = poses["IDLE"]
    shots = [
        ("idle", idle),
        ("punch", over(idle, kinds["punch"][1])),
        ("kick", over(idle, kinds["kick"][1])),
        ("overhead wind-up", over(idle, kinds["overhead"][0])),
        ("crouch", poses["CROUCH"]),
        ("hit", over(idle, poses["HIT"])),
    ]
    rig = Rig(fid)
    W, H = CELL[0] * SCALE, CELL[1] * SCALE
    sheet = Image.new("RGBA", (W * len(shots), H), (40, 42, 52, 255))
    dr = ImageDraw.Draw(sheet)
    for i, (name, pose) in enumerate(shots):
        x0 = i * W
        dr.line([(x0, H - 40), (x0 + W, H - 40)], fill=(120, 120, 130, 255), width=2)
        rig.draw(sheet, (x0 + W * 0.42, H - 40), pose, bones)
        dr.text((x0 + 10, 10), name, fill=(255, 255, 255, 255))
    sheet.convert("RGB").save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
