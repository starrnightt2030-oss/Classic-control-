# معمل الكلاسيك كنترول — الإصدار الثاني (v2)
### Classic Control Simulation Lab — v2 rebuild

الفولدر ده فيه **إعادة بناء التطبيق بالكامل**. التطبيق الحالي، اللي هو `index.html` في جذر المشروع، شغال زي ما هو على GitHub Pages، والفولدر ده مش بيأثر عليه.

> **لو أول مرة تقرا المشروع:** ابدأ بالملفات دي بالترتيب:
> 1. [`docs/01-vision.md`](docs/01-vision.md): إحنا بنبني إيه ولمين.
> 2. [`docs/05-progress.md`](docs/05-progress.md): وصلنا لفين بالظبط.
> 3. [`docs/06-roadmap.md`](docs/06-roadmap.md): الخطوة الجاية والخطة كاملة.

---

## هيكل الفولدر

```
v2/
├── README.md            ← الملف ده
├── docs/                ← التوثيق: الرؤية، والمعمارية، والقرارات، والتقدم، والخطة
├── models/              ← كود بناء النماذج ثلاثية الأبعاد (Blender Python)
│   ├── lib.py           ← خامات، وأشكال أساسية، ومسامير ترامل، وإضاءة وكاميرا الاستوديو
│   ├── kit.py           ← خط الإنتاج: أجزاء بأسماء، وتفكيك، ونقط الأسهم، والتصدير
│   ├── callouts.py      ← رسم الأسهم والأسماء عربي وإنجليزي على صور التفكيك
│   ├── contactor.py     ← الكونتاكتور
│   ├── overload.py      ← الأوفرلود الحراري
│   ├── addons.py        ← البلوك المساعد وتايمر الهوا (بيتركبوا على وش الكونتاكتور)
│   ├── mcb.py           ← القاطع MCB بالبولات 1 و2 و3 و4
│   ├── rccb.py          ← قاطع التسرب الأرضي
│   ├── mpcb.py          ← قاطع حماية المحرك
│   ├── publish.py       ← نقل الملفات النهائية من out/ لـ assets/
│   ├── door.py          ← مكونات الباب: ضواغط XB2، وطوارئ، وسليكتور، ولمبات AD16، وعلب ضواغط
│   ├── din.py           ← جسم الأجهزة المودولار على الريل (مشترك)
│   ├── relays.py        ← الريليهات وقواعدها والتايمرات
│   ├── reversing.py     ← الكونتاكتور العاكس والانترلوك
│   ├── sheet.py         ← لوحة صور مجمعة لكذا مكون
│   └── fonts/           ← خط Cairo عربي وإنجليزي (رخصة SIL OFL)
├── assets/
│   ├── models/          ← ملفات GLB الجاهزة للتطبيق
│   └── renders/         ← صور المكونات مجمّعة ومفكوكة بالأسماء
└── content/             ← الشرح الأكاديمي لكل مكون (JSON): نصوص، وأعطال، واختبارات، وأسماء ملفات الصوت
```

## إزاي تشغّل كود النماذج

```bash
# مرة واحدة: بيئة Python 3.13 فيها Blender كمكتبة
uv venv bvenv --python 3.13
uv pip install --python bvenv/bin/python bpy pillow

cd v2/models
../../bvenv/bin/python contactor.py all          # الكونتاكتور: مجمّع، ومفكوك، ومن جوه وهو شغال
../../bvenv/bin/python overload.py               # مجمّع + مفكوك
../../bvenv/bin/python addons.py aux             # البلوك المساعد
../../bvenv/bin/python addons.py timer           # تايمر الهوا
../../bvenv/bin/python mcb.py single             # قاطع 1 بول (مجمّع + مفكوك)
../../bvenv/bin/python mcb.py multi              # 2 و3 و4 بول
# الأسهم والأسماء على صورة التفكيك:
../../bvenv/bin/python -c "import callouts, overload; callouts.auto('overload', overload.PARTS, 'تفكيك أجزاء الأوفرلود', 'Overload — Exploded')"
```
النتايج بتطلع في `v2/models/out/`، والفولدر ده مش بيترفع على Git. والملفات النهائية بتتنقل يدوي لـ `assets/`.

## قواعد العمل

- **كل شغل يخلص يترفع على GitHub** في الفرع `v2-rebuild`، مع تحديث [`docs/05-progress.md`](docs/05-progress.md).
- **ممنوع شعارات وأسماء الشركات** (Schneider وABB وCHINT...). كل المكونات عليها ماركة التطبيق `ELDAWLY`، وأكواد موديلات خاصة بيه.
- **الشرح بالعامية المصرية بأسلوب أكاديمي دقيق**، وأي رقم لازم يكون من مواصفة قياسية أو متعلّم عليه "يتراجع من الكتالوج". التفاصيل في [`docs/04-content-guide.md`](docs/04-content-guide.md).
