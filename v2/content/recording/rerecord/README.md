# إعادة تسجيل المقاطع الناقصة

الملفات دي فيها **377 مقطع** لسه مالهمش صوت في التطبيق، ومقسومين على **22 ملف** صغير، وكل ملف أقل من 4000 حرف (حوالي 5 دقايق صوت).

## طريقة التسجيل (مهم)
1. **اقرا النص زي ما هو بالظبط:** استخدم وضع تحويل النص لصوت (Text to Speech)، **مش وضع الجلسة أو المحادثة**. وضع الجلسة بيعيد صياغة الكلام وبيتخطى أجزاء، وده اللي حصل في جزء من التسجيلات الأولى.
2. **كل ملف `rr_XX.txt` يتسجّل لوحده ويتحفظ لوحده:** `rr_01.wav`، `rr_02.wav`، وهكذا.
3. **سيب النقطة اللي لوحدها في سطر بين المقاطع زي ما هي:** دي بتعمل وقفة، والوقفة دي هي اللي بنقسم عندها.
4. **نفس الصوت ونفس السرعة** اللي في التسجيلات الأولى.

| الملف | عدد المقاطع | عدد الحروف | أول مقطع |
|---|---|---|---|
| rr_01.txt | 21 | 3693 | `stage/lab_intro.mp3` |
| rr_02.txt | 11 | 3913 | `contactor/silver_tip.mp3` |
| rr_03.txt | 10 | 3890 | `overload/lesson_phase_loss.mp3` |
| rr_04.txt | 15 | 3879 | `overload/base_housing.mp3` |
| rr_05.txt | 13 | 3803 | `pneumatic_timer/lesson_definition.mp3` |
| rr_06.txt | 15 | 3801 | `pneumatic_timer/plunger.mp3` |
| rr_07.txt | 13 | 3911 | `rccb/lesson_principle.mp3` |
| rr_08.txt | 15 | 3815 | `rccb/mechanism.mp3` |
| rr_09.txt | 16 | 3883 | `mpcb/front_cover.mp3` |
| rr_10.txt | 18 | 3578 | `fuse/holder.mp3` |
| rr_11.txt | 15 | 3723 | `pushbutton/block.mp3` |
| rr_12.txt | 19 | 3905 | `estop/block_contacts.mp3` |
| rr_13.txt | 20 | 3785 | `pilot_lamp/lesson_ghost.mp3` |
| rr_14.txt | 19 | 3750 | `timer/lesson_vs_pneumatic.mp3` |
| rr_15.txt | 19 | 3723 | `reversing_contactor/interlock_rocker.mp3` |
| rr_16.txt | 22 | 3723 | `limit_switch/intro.mp3` |
| rr_17.txt | 23 | 3884 | `signaling/intro.mp3` |
| rr_18.txt | 23 | 3800 | `current_transformer/case.mp3` |
| rr_19.txt | 20 | 3805 | `installation/opening.mp3` |
| rr_20.txt | 22 | 3807 | `enclosure/opening.mp3` |
| rr_21.txt | 20 | 3778 | `control_transformer/bracket.mp3` |
| rr_22.txt | 8 | 1605 | `motor_1ph/lesson_reverse.mp3` |
