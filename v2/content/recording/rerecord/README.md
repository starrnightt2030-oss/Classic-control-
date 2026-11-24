# إعادة تسجيل المقاطع الناقصة

الملفات دي فيها **386 مقطع** لسه مالهمش صوت في التطبيق، ومقسومين على **61 ملف** صغير، وكل ملف أقل من 1500 حرف (حوالي دقيقتين صوت)، عشان النموذج يقرا النص حرفيًا من غير ما يخرج عنه.

## طريقة التسجيل (مهم)
1. **اقرا النص زي ما هو بالظبط:** استخدم وضع تحويل النص لصوت (Text to Speech)، **مش وضع الجلسة أو المحادثة**. وضع الجلسة بيعيد صياغة الكلام وبيتخطى أجزاء، وده اللي حصل في جزء من التسجيلات الأولى.
2. **كل ملف `rr_XX.txt` يتسجّل لوحده ويتحفظ لوحده:** `rr_01.wav`، `rr_02.wav`، وهكذا.
3. **سيب النقطة اللي لوحدها في سطر بين المقاطع زي ما هي:** دي بتعمل وقفة، والوقفة دي هي اللي بنقسم عندها.
4. **نفس الصوت ونفس السرعة** اللي في التسجيلات الأولى.

| الملف | عدد المقاطع | عدد الحروف | أول مقطع |
|---|---|---|---|
| rr_01.txt | 23 | 1197 | `global/slogan_short.mp3` |
| rr_02.txt | 3 | 1218 | `contactor/intro.mp3` |
| rr_03.txt | 3 | 1227 | `contactor/lesson_coil_data.mp3` |
| rr_04.txt | 3 | 1307 | `contactor/fixed_bottom.mp3` |
| rr_05.txt | 3 | 1376 | `contactor/return_springs.mp3` |
| rr_06.txt | 5 | 1249 | `contactor/base.mp3` |
| rr_07.txt | 4 | 1462 | `overload/lesson_principle.mp3` |
| rr_08.txt | 3 | 1304 | `overload/lesson_standard.mp3` |
| rr_09.txt | 3 | 1201 | `overload/test_button.mp3` |
| rr_10.txt | 4 | 1179 | `overload/compensation.mp3` |
| rr_11.txt | 4 | 1274 | `aux_block/lesson_terminals.mp3` |
| rr_12.txt | 6 | 1388 | `aux_block/slide.mp3` |
| rr_13.txt | 5 | 1432 | `pneumatic_timer/opening.mp3` |
| rr_14.txt | 4 | 1339 | `pneumatic_timer/lesson_terminals.mp3` |
| rr_15.txt | 6 | 1455 | `pneumatic_timer/needle.mp3` |
| rr_16.txt | 6 | 1128 | `pneumatic_timer/plunger.mp3` |
| rr_17.txt | 4 | 1310 | `mcb/lesson_selection.mp3` |
| rr_18.txt | 5 | 1363 | `mcb/mechanism.mp3` |
| rr_19.txt | 4 | 1464 | `rccb/lesson_principle.mp3` |
| rr_20.txt | 6 | 1469 | `rccb/lesson_wiring.mp3` |
| rr_21.txt | 5 | 1450 | `rccb/test_resistor.mp3` |
| rr_22.txt | 6 | 1256 | `rccb/line_terminals.mp3` |
| rr_23.txt | 4 | 1206 | `mpcb/lesson_vs.mp3` |
| rr_24.txt | 5 | 1395 | `mpcb/lesson_handle.mp3` |
| rr_25.txt | 5 | 1470 | `mpcb/setting_dial.mp3` |
| rr_26.txt | 7 | 1460 | `mpcb/contacts.mp3` |
| rr_27.txt | 9 | 1206 | `fuse/lesson_types.mp3` |
| rr_28.txt | 6 | 1421 | `pushbutton/intro.mp3` |
| rr_29.txt | 5 | 1390 | `pushbutton/cap.mp3` |
| rr_30.txt | 6 | 1411 | `pushbutton/block.mp3` |
| rr_31.txt | 6 | 1330 | `estop/lesson_reset.mp3` |
| rr_32.txt | 5 | 1391 | `estop/ring_nut.mp3` |
| rr_33.txt | 8 | 1359 | `selector/opening.mp3` |
| rr_34.txt | 5 | 1393 | `selector/ring_nut.mp3` |
| rr_35.txt | 8 | 1391 | `pilot_lamp/opening.mp3` |
| rr_36.txt | 9 | 1337 | `pb_station/intro.mp3` |
| rr_37.txt | 6 | 1451 | `control_relay/socket.mp3` |
| rr_38.txt | 8 | 1353 | `timer/lesson_star_delta.mp3` |
| rr_39.txt | 6 | 1236 | `timer/socket.mp3` |
| rr_40.txt | 5 | 1256 | `reversing_contactor/lesson_electrical.mp3` |
| rr_41.txt | 7 | 1338 | `reversing_contactor/interlock_housing.mp3` |
| rr_42.txt | 4 | 1180 | `proximity_sensor/lesson_inductive.mp3` |
| rr_43.txt | 8 | 1342 | `proximity_sensor/lesson_photo.mp3` |
| rr_44.txt | 7 | 1354 | `limit_switch/opening.mp3` |
| rr_45.txt | 9 | 1319 | `limit_switch/switch.mp3` |
| rr_46.txt | 8 | 1347 | `solenoid_valve/intro.mp3` |
| rr_47.txt | 7 | 1269 | `signaling/lesson_colors.mp3` |
| rr_48.txt | 10 | 1383 | `panel_meter/lesson_wiring.mp3` |
| rr_49.txt | 8 | 1432 | `current_transformer/intro.mp3` |
| rr_50.txt | 8 | 1425 | `current_transformer/terminals.mp3` |
| rr_51.txt | 9 | 1411 | `rotary_switches/knob.mp3` |
| rr_52.txt | 7 | 1249 | `electronic_protection/lesson_kwh.mp3` |
| rr_53.txt | 4 | 1466 | `motor/intro.mp3` |
| rr_54.txt | 10 | 1382 | `motor/lesson_parts_maint.mp3` |
| rr_55.txt | 11 | 1423 | `tools/lesson_safety.mp3` |
| rr_56.txt | 6 | 1167 | `enclosure/earth.mp3` |
| rr_57.txt | 6 | 1377 | `control_transformer/lesson_rating.mp3` |
| rr_58.txt | 8 | 1374 | `control_transformer/terminals.mp3` |
| rr_59.txt | 9 | 1358 | `power_supply_24v/lesson_protection.mp3` |
| rr_60.txt | 5 | 1462 | `motor_1ph/intro.mp3` |
| rr_61.txt | 7 | 1322 | `motor_1ph/lesson_safety.mp3` |
