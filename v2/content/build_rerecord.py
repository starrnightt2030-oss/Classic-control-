"""Build the re-recording scripts for clips that are still missing from assets/audio.

    python build_rerecord.py            -> recording/rerecord/rr_01.txt … + manifest_rr_XX.json + README

A clip counts as missing when assets/audio/<clip> doesn't exist. The texts are taken
unchanged from the original parts (tts_part_XX.txt), in the original order, and packed
into files of at most MAX_CHARS characters so each file stays well under the
recording tool's ~11-minute limit.
"""
import json
import os
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
REC = HERE / "recording"
AUDIO = HERE.parent / "assets" / "audio"
import sys
MAX_CHARS = int(sys.argv[1]) if len(sys.argv) > 1 else 1500
OUT = REC / "rerecord"
MARK = "\n\n.\n\n"


def main():
    OUT.mkdir(exist_ok=True)
    for f in OUT.glob("*"):
        f.unlink()
    todo = []
    for part in range(1, 100):
        tts = REC / f"tts_part_{part:02d}.txt"
        man = REC / f"manifest_part_{part:02d}.json"
        if not tts.exists():
            break
        order = json.loads(man.read_text(encoding="utf8"))["order"]
        clips = [s.strip() for s in tts.read_text(encoding="utf8").split(MARK) if s.strip()]
        assert len(clips) == len(order)
        for name, text in zip(order, clips):
            if not (AUDIO / name).exists():
                todo.append((name, text))
    files, cur, size = [], [], 0
    for name, text in todo:
        add = len(text) + len(MARK)
        if cur and size + add > MAX_CHARS:
            files.append(cur)
            cur, size = [], 0
        cur.append((name, text))
        size += add
    if cur:
        files.append(cur)
    for i, group in enumerate(files, 1):
        body = MARK.join(t for _, t in group)
        (OUT / f"rr_{i:02d}.txt").write_text(body, encoding="utf8")
        (OUT / f"manifest_rr_{i:02d}.json").write_text(
            json.dumps({"order": [n for n, _ in group], "pause_marker": MARK, "chars": len(body)}, ensure_ascii=False, indent=1),
            encoding="utf8")
    lines = [
        "# إعادة تسجيل المقاطع الناقصة",
        "",
        f"الملفات دي فيها **{len(todo)} مقطع** لسه مالهمش صوت في التطبيق، ومقسومين على **{len(files)} ملف** صغير، وكل ملف أقل من {MAX_CHARS} حرف (حوالي دقيقتين صوت)، عشان النموذج يقرا النص حرفيًا من غير ما يخرج عنه.",
        "",
        "## طريقة التسجيل (مهم)",
        "1. **اقرا النص زي ما هو بالظبط:** استخدم وضع تحويل النص لصوت (Text to Speech)، **مش وضع الجلسة أو المحادثة**. وضع الجلسة بيعيد صياغة الكلام وبيتخطى أجزاء، وده اللي حصل في جزء من التسجيلات الأولى.",
        "2. **كل ملف `rr_XX.txt` يتسجّل لوحده ويتحفظ لوحده:** `rr_01.wav`، `rr_02.wav`، وهكذا.",
        "3. **سيب النقطة اللي لوحدها في سطر بين المقاطع زي ما هي:** دي بتعمل وقفة، والوقفة دي هي اللي بنقسم عندها.",
        "4. **نفس الصوت ونفس السرعة** اللي في التسجيلات الأولى.",
        "",
        "| الملف | عدد المقاطع | عدد الحروف | أول مقطع |",
        "|---|---|---|---|",
    ]
    for i, group in enumerate(files, 1):
        lines.append(f"| rr_{i:02d}.txt | {len(group)} | {sum(len(t) for _, t in group)} | `{group[0][0]}` |")
    (OUT / "README.md").write_text("\n".join(lines) + "\n", encoding="utf8")
    print(len(todo), "clips in", len(files), "files")


if __name__ == "__main__":
    main()
