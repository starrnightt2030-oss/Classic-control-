"""Builds scripts_for_recording.md: every narration text with the exact audio file name it must be saved as.
Run: python build_recording_script.py"""
import json, glob, os

HERE = os.path.dirname(os.path.abspath(__file__))
files = sorted(glob.glob(os.path.join(HERE, "*.json")))
out = ["# نصوص التسجيل الصوتي — معمل الكلاسيك كنترول v2", "",
       "كل فقرة تحتها اسم الملف اللي لازم تتحفظ بيه بالظبط (داخل `assets/audio/`).",
       "التسجيل بنفس الصوت للتطبيق كله. الصيغة المقترحة: MP3 أو Opus، أحادي، من 48 لـ 64 kbps.", ""]
count = 0
for f in files:
    d = json.load(open(f, encoding="utf8"))
    comp = d["component"]
    out += ["---", "", f"## {d['name_ar']} — {d['name_en']}", ""]
    if "intro" in d:
        out += [f"**مقدمة** — `{d['intro']['audio']}`", "", d["intro"]["text_ar"], ""]
        count += 1
    for l in d.get("lesson", []):
        fn = f"{comp}/lesson_{l['id']}.mp3"
        out += [f"**{l['title_ar']}** — `{fn}`", "", l["text_ar"], ""]
        count += 1
    for p in d.get("parts", []):
        out += [f"**{p['name_ar']}** — `{p['audio']}`", "", p["text_ar"], ""]
        count += 1
out.insert(4, f"إجمالي المقاطع: **{count}** مقطع، من **{len(files)}** مكون.")
open(os.path.join(HERE, "scripts_for_recording.md"), "w", encoding="utf8").write("\n".join(out))
print(count, "clips from", len(files), "components")
