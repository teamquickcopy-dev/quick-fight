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

    def draw(self, canvas, feet, pose, bones=False):
        """Same steps as cutout_rig.gd draw(): FK pose, planted feet (IK), two-handed grip (IK)."""
        c = self.cfg
        L, A = c["lengths"], c["anchors"]
        p = pose
        spin = p.get("spin", 0.0)
        ank = c["ankle_h"]
        lt, ls = L["leg_upper_F"], L["leg_lower_F"]
        hip_center = (0.0, -(lt + ls + ank - p.get("drop", 0.0)))
        pr = math.radians(spin + p["lean"] * 0.3)
        waist = add(hip_center, rot((0, A["hip_F"][1]), pr), -1)
        tr = math.radians(p["lean"] + spin)
        tdir = rot((0, -1), tr)
        neck = add(waist, tdir, L["torso"])
        hip_f, hip_b = add(waist, rot(A["hip_F"], pr)), add(waist, rot(A["hip_B"], pr))
        sh_f, sh_b = add(waist, rot(A["shoulder_F"], tr)), add(waist, rot(A["shoulder_B"], tr))
        bones_list = []

        def part(name, at, d, tint=1.0):
            if name not in self.tex:
                return
            pp = c["parts"][name]
            axis = math.atan2(pp["tip"][1] - pp["pivot"][1], pp["tip"][0] - pp["pivot"][0])
            ang = math.atan2(d[1], d[0]) - axis
            img = self.tex[name]
            s = c["draw_scale"] * SCALE
            img = img.resize((max(1, round(img.width * s)), max(1, round(img.height * s))), Image.LANCZOS)
            piv = (pp["pivot"][0] * s, pp["pivot"][1] * s)
            w, h = img.size
            R = math.ceil(math.hypot(max(piv[0], w - piv[0]), max(piv[1], h - piv[1]))) + 2
            padded = Image.new("RGBA", (2 * R, 2 * R))
            padded.paste(img, (round(R - piv[0]), round(R - piv[1])))
            padded = padded.rotate(-math.degrees(ang), resample=Image.BICUBIC)
            if tint != 1.0:
                r, g, b, a = padded.split()
                f = lambda v: int(v * tint)
                padded = Image.merge("RGBA", (r.point(f), g.point(f), b.point(f), a))
            canvas.alpha_composite(padded, (round(feet[0] + at[0] * SCALE - R), round(feet[1] + at[1] * SCALE - R)))

        def norm(v):
            n = math.hypot(*v) or 1.0
            return (v[0] / n, v[1] / n)

        def sub(a, b):
            return (a[0] - b[0], a[1] - b[1])

        def ik(a, t, l1, l2, knee):
            d = sub(t, a)
            dist = min(max(math.hypot(*d), abs(l1 - l2) + 0.01), l1 + l2 - 0.01)
            off = math.acos(max(-1.0, min(1.0, (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist))))
            base = math.atan2(d[1], d[0])
            j1 = add(a, (math.cos(base + off), math.sin(base + off)), l1)
            j2 = add(a, (math.cos(base - off), math.sin(base - off)), l1)
            if knee:
                return j1 if j1[0] > j2[0] else j2
            return j1 if j1[1] > j2[1] else j2

        def leg(hip, td, sd, l1, l2):
            knee = add(hip, ddir(td), l1)
            ankle = add(knee, ddir(sd), l2)
            if abs(spin) < 30 and ankle[1] > -ank - 26:
                target = (ankle[0], -ank)
                knee = ik(hip, target, l1, l2, True)
                return knee, add(knee, norm(sub(target, knee)), l2), True
            return knee, ankle, False

        def draw_leg(side, hip, lg, tint):
            knee, ankle, planted = lg
            sd = norm(sub(ankle, knee))
            part("foot_" + side, ankle, (1, 0) if planted else rot(sd, -math.pi / 2), tint)
            part("leg_lower_" + side, knee, sd, tint)
            part("leg_upper_" + side, hip, norm(sub(knee, hip)), tint)
            bones_list.extend([(hip, knee), (knee, ankle)])

        leg_f = leg(hip_f, p["ft"] + spin, p["fs"] + spin, lt, ls)
        leg_b = leg(hip_b, p["bt"] + spin, p["bs"] + spin, L["leg_upper_B"], L["leg_lower_B"])
        f_el = add(sh_f, ddir(p["fu"] + spin), L["arm_upper_F"])
        fist = add(f_el, ddir(p["fl"] + spin), L["arm_lower_F"])
        tool_dir = ddir(p["fl"] + spin + p.get("to", 100.0))
        grip = "tool" in self.tex and p.get("grip", 0.0) >= 0.5
        if grip:
            target = add(fist, tool_dir, 22.0)
            b_el = ik(sh_b, target, L["arm_upper_B"], L["arm_lower_B"], False)
            b_wr = add(b_el, norm(sub(target, b_el)), L["arm_lower_B"])
        else:
            b_el = add(sh_b, ddir(p["bu"] + spin), L["arm_upper_B"])
            b_wr = add(b_el, ddir(p["bl"] + spin), L["arm_lower_B"])
        bf = norm(sub(b_wr, b_el))
        back = 0.72
        if not grip:
            part("arm_lower_B", b_el, bf, back)
            part("hand_B", b_wr, bf, back)
        part("arm_upper_B", sh_b, norm(sub(b_el, sh_b)), back)
        draw_leg("B", hip_b, leg_b, back)
        part("pelvis", waist, rot((0, -1), pr))
        draw_leg("F", hip_f, leg_f, 1.0)
        part("torso", waist, tdir)
        if grip:
            part("arm_lower_B", b_el, bf, 0.9)
        part("head", neck, rot(tdir, math.radians(p["lean"] * 0.4)))
        part("tool", fist, tool_dir)
        if grip:
            part("hand_B", b_wr, bf, 0.9)
        part("arm_lower_F", f_el, norm(sub(fist, f_el)))
        part("arm_upper_F", sh_f, norm(sub(f_el, sh_f)))
        if bones:
            dr = ImageDraw.Draw(canvas)
            sc = lambda q: (feet[0] + q[0] * SCALE, feet[1] + q[1] * SCALE)
            for a, b in bones_list + [(sh_f, f_el), (f_el, fist), (sh_b, b_el), (b_el, b_wr), (waist, neck), (hip_center, waist)]:
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
