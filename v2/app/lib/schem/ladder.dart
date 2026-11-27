// Ready-made schematics, laid out automatically: the power circuit on the left
// (phases L1 L2 L3 top-down to the motors) and the control circuit on the right as
// one tree of series / parallel branches between L1 (top) and N (bottom).
//
// The topology of every control circuit matches the reference wiring of the same
// circuit in lib/sim/circuits.dart, so the drawing is what the student wires in the lab.
import 'model.dart';
import 'symbols.dart';

/// one symbol in the control tree
class E {
  final String sym, tag;
  final Map<String, Object?> p;
  const E(this.sym, this.tag, [this.p = const {}]);
}

/// parallel branches (each one a series list of [E] / [Par])
class Par {
  final List<List<Object>> b;
  const Par(this.b);
}

// shorthands
E olnc(String t) => E('olnc', t);
E olno(String t) => E('olno', t);
E stop(String t) => E('pb_nc', t);
E start(String t) => E('pb_no', t);
E sel(String t) => E('sel', t);
E no(String t, String n) => E('no', t, {'no': n});
E nc(String t, String n) => E('nc', t, {'no': n});
E tno(String t) => E('tno', t, const {'no': '15-18'});
E tnc(String t) => E('tnc', t, const {'no': '15-16'});
E lsNo(String t) => E('ls_no', t);
E lsNc(String t) => E('ls_nc', t);
E coil(String t, [double v = 220]) => E('coil_kc', t, {'coilV': v});
E relay(String t) => E('coil_ka', t);
E timer(String t, String mode, double s) => E('coil_kt', t, {'mode': mode, 'T': s});
E lamp(String t, String col) => E('lamp', t, {'col': col});
E prox(String t) => E('prox_ind', t);
E photo(String t) => E('photo', t);
E reed(String t) => E('reed_no', t);
E valve(String t) => E('yv', t, const {'V': 220.0, 'W': 6.0, 'pf': 0.7});
E floatNo(String t) => E('float_no', t);
E floatNc(String t) => E('float_nc', t);

class _Lay {
  final SchemDoc d;
  _Lay(this.d);
  static const slot = 6.0, col = 5.0;

  SPlaced add(String sym, double x, double y, String tag, [Map<String, Object?>? p]) {
    final s = SPlaced(d.newId(), sym, x, y, tag, p: p);
    d.syms.add(s);
    return s;
  }

  void w(SPlaced a, String pa, SPlaced b, String pb, [double? y]) => d.wires.add(SWire('${a.id}.$pa', '${b.id}.$pb', y: y));
  void wk(String a, String b, [double? y]) => d.wires.add(SWire(a, b, y: y));

  // ---------------- measuring the tree
  int slots(Object o) {
    if (o is E) return 1;
    if (o is Par) return o.b.map(seriesSlots).fold(0, (a, b) => a > b ? a : b);
    if (o is List) return seriesSlots(o.cast<Object>());
    return 0;
  }

  int seriesSlots(List<Object> s) => s.fold(0, (a, o) => a + slots(o));

  int cols(Object o) {
    if (o is E) return 1;
    if (o is Par) return o.b.fold(0, (a, br) => a + seriesCols(br));
    return 0;
  }

  int seriesCols(List<Object> s) => s.fold(1, (a, o) => cols(o) > a ? cols(o) : a);

  // ---------------- placing: returns (entry pins, exit pins)
  (List<String>, List<String>) place(Object o, double x, int slot0, int span, double y0) {
    if (o is E) {
      final d0 = kSyms[o.sym]!;
      final top = d0.pins.first;
      final bot = d0.pins.last;
      final sy = y0 + slot0 * slot + (slot - d0.h) / 2 - 1;
      final s = add(o.sym, x - top.x, sy, o.tag, {...d0.params, ...o.p});
      return (['${s.id}.${top.id}'], ['${s.id}.${bot.id}']);
    }
    final p = o as Par;
    final ins = <String>[], outs = <String>[];
    var cx = x;
    for (final br in p.b) {
      final (i, e) = series(br, cx, slot0, span, y0);
      ins.addAll(i);
      outs.addAll(e);
      cx += seriesCols(br) * col;
    }
    return (ins, outs);
  }

  /// a series branch filling [span] slots: the last item sits at the bottom (loads line up)
  (List<String>, List<String>) series(List<Object> s, double x, int slot0, int span, double y0) {
    List<String>? first;
    var prev = <String>[];
    var at = slot0;
    for (var i = 0; i < s.length; i++) {
      final o = s[i];
      final n = slots(o);
      final last = i == s.length - 1;
      final start = last ? slot0 + span - n : at;
      final (ins, outs) = place(o, x, start, last ? n : n, y0);
      if (first == null) {
        first = ins;
      } else {
        join(prev, ins);
      }
      prev = outs;
      at = start + n;
    }
    return (first ?? const [], prev);
  }

  void join(List<String> outs, List<String> ins) {
    for (final o in outs) {
      wk(o, ins.first);
    }
    for (final i in ins.skip(1)) {
      wk(outs.first, i);
    }
  }

  // ---------------- control circuit between F1 (top) and N (bottom)
  void control(List<Object> tree, double x0) {
    const y0 = 11.0;
    final l1 = add('L1', x0 - 1, 1, 'L1');
    final f1 = add('mcb1', x0 - 1, 4, 'F1');
    w(l1, 'o', f1, '1');
    final span = seriesSlots(tree);
    final (ins, outs) = series(tree, x0, 0, span, y0);
    for (final i in ins) {
      wk('${f1.id}.2', i, 9.5);
    }
    final ny = y0 + span * slot + 1;
    final n = add('N', x0 - 1, ny, 'N');
    for (final o in outs) {
      wk(o, '${n.id}.o', ny - 1);
    }
  }

  // ---------------- power circuit
  late final List<SPlaced> phases;
  late SPlaced q1;

  void supply() {
    phases = [add('L1', 2, 1, 'L1'), add('L2', 4, 1, 'L2'), add('L3', 6, 1, 'L3')];
    q1 = add('mcb3', 2, 5, 'Q1');
    for (var i = 0; i < 3; i++) {
      w(phases[i], 'o', q1, '${2 * i + 1}');
    }
  }

  /// contactor main contacts at column [x] fed from Q1; returns the contacts
  SPlaced mains(String k, double x, {double y = 12, int n = 0}) {
    final s = add('kc3', x, y, k);
    for (var i = 0; i < 3; i++) {
      wk('${q1.id}.${2 * i + 2}', '${s.id}.${2 * i + 1}', x == 2 ? null : 10.5 + i * 0.5 + n * 0.0);
    }
    return s;
  }

  SPlaced ol(String f, SPlaced k, {double y = 19}) {
    final s = add('ol3', k.x, y, f, {'set': 8.5});
    for (var i = 0; i < 3; i++) {
      w(k, '${2 * i + 2}', s, '${2 * i + 1}');
    }
    return s;
  }

  SPlaced motor(String m, SPlaced from, {double y = 26, bool six = false}) {
    final s = add(six ? 'motor6' : 'motor3', from.x, y, m);
    const t = ['U1', 'V1', 'W1'];
    for (var i = 0; i < 3; i++) {
      w(from, '${2 * i + 2}', s, t[i]);
    }
    return s;
  }

  /// DOL chains side by side: (K, F, M) per motor
  double dol(List<(String, String, String)> m) {
    supply();
    var x = 2.0;
    for (final (k, f, mm) in m) {
      final kk = mains(k, x);
      motor(mm, ol(f, kk));
      x += 9;
    }
    return x + 4;
  }

  /// forward K1 / reverse K2 (L1 ↔ L3 swapped), overload, motor
  double reversing(String k1, String k2, String f, String m, {bool six = false}) {
    supply();
    final a = mains(k1, 2), b = mains(k2, 10);
    final o = ol(f, a, y: 20);
    // K2 outputs crossed onto the overload inputs at three heights
    wk('${b.id}.2', '${o.id}.5', 17.0);
    wk('${b.id}.4', '${o.id}.3', 17.5);
    wk('${b.id}.6', '${o.id}.1', 18.0);
    if (six) return _starDelta(o, m, 'KM4', 'KM3', 18);
    motor(m, o, y: 27);
    return 20;
  }

  /// reversing drives side by side: (forward K, reverse K, overload, motor) each
  double reversingN(List<(String, String, String, String)> d) {
    supply();
    var x = 2.0;
    for (final (k1, k2, f, m) in d) {
      final a = mains(k1, x), b = mains(k2, x + 8);
      final o = ol(f, a, y: 20);
      wk('${b.id}.2', '${o.id}.5', 17.0);
      wk('${b.id}.4', '${o.id}.3', 17.5);
      wk('${b.id}.6', '${o.id}.1', 18.0);
      motor(m, o, y: 27);
      x += 18;
    }
    return x;
  }

  /// star-delta: main KM1 (or the reversing pair before it), delta and star contactors
  double starDelta(String km, String f, String kd, String ks, String m) {
    supply();
    final a = mains(km, 2);
    final o = ol(f, a);
    return _starDelta(o, m, kd, ks, 10);
  }

  double _starDelta(SPlaced o, String m, String kd, String ks, double x) {
    final mo = add('motor6', 2, o.y + 8, m);
    const t = ['U1', 'V1', 'W1'];
    for (var i = 0; i < 3; i++) {
      w(o, '${2 * i + 2}', mo, t[i]);
    }
    final d = add('kc3', x, o.y + 8, kd);
    // delta contactor fed from the overload outputs
    for (var i = 0; i < 3; i++) {
      wk('${o.id}.${2 * i + 2}', '${d.id}.${2 * i + 1}', o.y + 5.5 + i * 0.5);
    }
    // its outputs close the delta: U1-W2, V1-U2, W1-V2
    const back = ['W2', 'U2', 'V2'];
    for (var i = 0; i < 3; i++) {
      wk('${d.id}.${2 * i + 2}', '${mo.id}.${back[i]}', mo.y + 7 + i * 0.5);
    }
    // star contactor below, on the same three ends, outputs bridged
    final s = add('kc3', x, mo.y + 11, ks);
    for (var i = 0; i < 3; i++) {
      wk('${mo.id}.${back[i]}', '${s.id}.${2 * i + 1}', mo.y + 8.5 + i * 0.5);
    }
    wk('${s.id}.2', '${s.id}.4', s.y + 5);
    wk('${s.id}.4', '${s.id}.6', s.y + 5);
    return x + 8;
  }
}

class ReadyCircuit {
  final String id, group, title, desc;
  final SchemDoc Function() build;

  /// the machine this circuit drives (lib/sim/plant.dart), if any
  final String? plant;
  const ReadyCircuit(this.id, this.group, this.title, this.desc, this.build, {this.plant});
}

SchemDoc _make(String title, double Function(_Lay) power, List<Object> control, {List<List<String>> mech = const []}) {
  final d = SchemDoc()..title = title;
  final l = _Lay(d);
  final x0 = power(l);
  l.control(control, x0 + 2);
  d.mech.addAll(mech);
  var mx = 0.0, my = 0.0;
  for (final s in d.syms) {
    if (s.x + s.size.width > mx) mx = s.x + s.size.width;
    if (s.y + s.size.height > my) my = s.y + s.size.height;
  }
  d.sheetW = (mx + 4 < 40 ? 40 : mx + 4).ceilToDouble();
  d.sheetH = (my + 6 < 30 ? 30 : my + 6).ceilToDouble();
  return d;
}

// a start / stop latch: S0 then (Sx ∥ K 13-14)
List<Object> _latch(String s, String k, [String n = '13-14']) => [Par([[start(s)], [no(k, n)]])];

final List<ReadyCircuit> kReady = [
  ReadyCircuit('c_dol', 'دوائر أساسية', 'تشغيل محرك وإيقافه بالضواغط مع لمبات البيان', 'تشغيل مباشر بإمساك ذاتي، ولمبات تشغيل وإيقاف وعطل.',
      () => _make('تشغيل مباشر DOL', (l) => l.dol([('K1', 'F2', 'M1')]), [
            Par([
              [
                olnc('F2'),
                Par([
                  [stop('S0'), ..._latch('S1', 'K1'), coil('K1')],
                  [no('K1', '53-54'), lamp('H1', 'g')],
                  [nc('K1', '21-22'), lamp('H2', 'r')],
                ])
              ],
              [olno('F2'), lamp('H3', 'y')],
            ])
          ])),
  ReadyCircuit('c_2loc', 'دوائر أساسية', 'تشغيل محرك من مكانين بضواغط تشغيل وإيقاف', 'الإيقاف على التوالي، والتشغيل على التوازي.',
      () => _make('التحكم من مكانين', (l) => l.dol([('K1', 'F2', 'M1')]), [
            olnc('F2'),
            stop('S01'),
            stop('S02'),
            Par([[start('S11')], [start('S12')], [no('K1', '13-14')]]),
            Par([[coil('K1')], [lamp('H1', 'g')]]),
          ])),
  ReadyCircuit('c_2start', 'دوائر أساسية', 'تشغيل محرك بضاغطي تشغيل وضاغط إيقاف واحد', 'أي ضاغط تشغيل يشغّل المحرك، وضاغط واحد يوقفه.',
      () => _make('تشغيلان وإيقاف', (l) => l.dol([('K1', 'F2', 'M1')]), [
            olnc('F2'),
            stop('S0'),
            Par([[start('S1')], [start('S2')], [no('K1', '13-14')]]),
            Par([[coil('K1')], [lamp('H1', 'g')]]),
          ])),
  ReadyCircuit('c_2hand', 'دوائر أساسية', 'تشغيل محرك بالضغط على ضاغطين معًا (أمان اليدين)', 'ضاغطا التشغيل على التوالي.',
      () => _make('التشغيل باليدين', (l) => l.dol([('K1', 'F2', 'M1')]), [
            olnc('F2'),
            stop('S0'),
            Par([
              [start('S1'), start('S2')],
              [no('K1', '13-14')]
            ]),
            Par([[coil('K1')], [lamp('H1', 'g')]]),
          ])),
  ReadyCircuit('c_ondelay', 'دوائر المؤقت', 'تشغيل محرك بعد مدة بمؤقت تأخير التوصيل', 'المرحّل يمسك التشغيل، والمؤقت يشغّل الكونتاكتور بعد الزمن.',
      () => _make('التشغيل المتأخر', (l) => l.dol([('K1', 'F2', 'M1')]), [
            olnc('F2'),
            stop('S0'),
            Par([
              [
                Par([[start('S1')], [no('KA1', '11-14')]]),
                Par([[relay('KA1')], [timer('KT1', 'on', 4)]])
              ],
              [tno('KT1'), Par([[coil('K1')], [lamp('H1', 'g')]])],
            ]),
          ])),
  ReadyCircuit('c_offdelay', 'دوائر المؤقت', 'إيقاف محرك بعد مدة بمؤقت تأخير الفصل', 'بعد الإيقاف يستمر المحرك حتى ينقضي زمن المؤقت.',
      () => _make('الإيقاف المتأخر', (l) => l.dol([('K1', 'F2', 'M1')]), [
            olnc('F2'),
            Par([
              [
                stop('S0'),
                Par([
                  [Par([[start('S1')], [no('KA1', '11-14')]]), relay('KA1')],
                  [no('KA1', '21-24'), timer('KT1', 'off', 5)],
                ])
              ],
              [tno('KT1'), Par([[coil('K1')], [lamp('H1', 'g')]])],
            ]),
          ])),
  ReadyCircuit('c_seq_on', 'تشغيل أكثر من محرك', 'محركان: لا يعمل الثاني إلا إذا كان الأول يعمل', 'نقطة مفتوحة من K1 على التوالي مع ملف K2.',
      () => _make('الثاني بعد الأول', (l) => l.dol([('K1', 'F2', 'M1'), ('K2', 'F3', 'M2')]), [
            olnc('F2'),
            olnc('F3'),
            Par([
              [stop('S0'), ..._latch('S1', 'K1'), coil('K1')],
              [stop('S2'), ..._latch('S3', 'K2'), no('K1', '53-54'), coil('K2')],
            ]),
          ])),
  ReadyCircuit('c_seq_off', 'تشغيل أكثر من محرك', 'محركان: لا يعمل الثاني إلا إذا كان الأول متوقفًا', 'نقطة مغلقة من K1 على التوالي مع ملف K2.',
      () => _make('الثاني والأول متوقف', (l) => l.dol([('K1', 'F2', 'M1'), ('K2', 'F3', 'M2')]), [
            olnc('F2'),
            olnc('F3'),
            Par([
              [stop('S0'), ..._latch('S1', 'K1'), coil('K1')],
              [stop('S2'), ..._latch('S3', 'K2'), nc('K1', '61-62'), coil('K2')],
            ]),
          ])),
  ReadyCircuit('c_seq_time', 'تشغيل أكثر من محرك', 'محركان: يعمل الثاني بعد الأول بزمن', 'K1 يشغّل المؤقت، والمؤقت يشغّل K2.',
      () => _make('التتابع بالمؤقت', (l) => l.dol([('K1', 'F2', 'M1'), ('K2', 'F3', 'M2')]), [
            olnc('F2'),
            olnc('F3'),
            stop('S0'),
            Par([
              [..._latch('S1', 'K1'), coil('K1')],
              [
                no('K1', '53-54'),
                Par([
                  [timer('KT1', 'on', 4)],
                  [tno('KT1'), coil('K2')]
                ])
              ],
            ]),
          ])),
  ReadyCircuit('c_seq_swap', 'تشغيل أكثر من محرك', 'يعمل الأول، ثم الثاني بعد زمن، ثم يتوقف الأول تلقائيًا', 'K2 يمسك على نفسه ويفصل K1 بنقطته المغلقة.',
      () => _make('التبديل بالمؤقت', (l) => l.dol([('K1', 'F2', 'M1'), ('K2', 'F3', 'M2')]), [
            olnc('F2'),
            olnc('F3'),
            stop('S0'),
            Par([
              [..._latch('S1', 'K1'), nc('K2', '61-62'), coil('K1')],
              [no('K1', '53-54'), timer('KT1', 'on', 4)],
              [
                Par([[tno('KT1')], [no('K2', '13-14')]]),
                coil('K2')
              ],
            ]),
          ])),
  ReadyCircuit('c_seq3', 'تشغيل أكثر من محرك', 'تشغيل ثلاثة محركات بالتتابع تلقائيًا بالمؤقتات', 'كل كونتاكتور يشغّل مؤقتًا يشغّل الذي بعده.',
      () => _make('ثلاثة محركات بالتتابع', (l) => l.dol([('K1', 'F2', 'M1'), ('K2', 'F3', 'M2'), ('K3', 'F4', 'M3')]), [
            olnc('F2'),
            olnc('F3'),
            olnc('F4'),
            stop('S0'),
            Par([
              [..._latch('S1', 'K1'), coil('K1')],
              [
                no('K1', '53-54'),
                Par([
                  [timer('KT1', 'on', 3)],
                  [tno('KT1'), coil('K2')],
                  [
                    no('K2', '53-54'),
                    Par([
                      [timer('KT2', 'on', 3)],
                      [tno('KT2'), coil('K3')]
                    ])
                  ],
                ])
              ],
            ]),
          ])),
  ReadyCircuit('c_rev', 'عكس الحركة', 'عكس اتجاه محرك بالضواغط', 'منع تداخل كهربائي بالنقاط المغلقة وميكانيكي بين K1 و K2.',
      () => _make('العكس بالضواغط', (l) => l.reversing('K1', 'K2', 'F2', 'M1'), [
            olnc('F2'),
            stop('S0'),
            Par([
              [..._latch('S1', 'K1'), nc('K2', '21-22'), Par([[coil('K1')], [lamp('H1', 'g')]])],
              [..._latch('S2', 'K2'), nc('K1', '21-22'), Par([[coil('K2')], [lamp('H2', 'b')]])],
            ]),
          ], mech: [['K1', 'K2']])),
  ReadyCircuit('c_rev_semi', 'عكس الحركة', 'عكس الحركة نصف التلقائي بمفتاح نهاية الشوط', 'تذهب العربة إلى LS2 وترجع وحدها وتقف عند LS1.',
      () => _make('نصف تلقائي', (l) => l.reversing('K1', 'K2', 'F2', 'M1'), [
            olnc('F2'),
            stop('S0'),
            Par([
              [..._latch('S1', 'K1'), lsNc('LS2'), nc('K2', '21-22'), Par([[coil('K1')], [lamp('H1', 'g')]])],
              [
                Par([[no('K2', '13-14')], [lsNo('LS2')]]),
                lsNc('LS1'),
                nc('K1', '21-22'),
                Par([[coil('K2')], [lamp('H2', 'b')]])
              ],
            ]),
          ], mech: [['K1', 'K2']])),
  ReadyCircuit('c_rev_auto', 'عكس الحركة', 'عكس الحركة التلقائي الترددي بمفاتيح نهاية الشوط', 'تذهب العربة وتعود بين LS1 و LS2 حتى تضغط S0.', plant: 'cart',
      () => _make('الحركة الترددية', (l) => l.reversing('K1', 'K2', 'F2', 'M1'), [
            olnc('F2'),
            stop('S0'),
            Par([
              [
                Par([[start('S1')], [no('K1', '13-14')], [lsNo('LS1')]]),
                lsNc('LS2'),
                nc('K2', '21-22'),
                Par([[coil('K1')], [lamp('H1', 'g')]])
              ],
              [
                Par([[start('S2')], [no('K2', '13-14')], [lsNo('LS2')]]),
                lsNc('LS1'),
                nc('K1', '21-22'),
                Par([[coil('K2')], [lamp('H2', 'b')]])
              ],
            ]),
          ], mech: [['K1', 'K2']])),
  ReadyCircuit('c_rev_timer', 'عكس الحركة', 'عكس الحركة بمفتاح نهاية الشوط ومؤقت (توقف عند كل طرف)', 'المفتاح يوقف الاتجاه ويشغّل مؤقتًا يشغّل الاتجاه العكسي.',
      () => _make('العكس مع التوقف', (l) => l.reversing('K1', 'K2', 'F2', 'M1'), [
            olnc('F2'),
            stop('S0'),
            Par([
              [
                Par([[start('S1')], [no('K1', '13-14')], [tno('KT2')]]),
                lsNc('LS2'),
                nc('K2', '21-22'),
                coil('K1')
              ],
              [
                Par([[start('S2')], [no('K2', '13-14')], [tno('KT1')]]),
                lsNc('LS1'),
                nc('K1', '21-22'),
                coil('K2')
              ],
              [lsNo('LS2'), timer('KT1', 'on', 3)],
              [lsNo('LS1'), timer('KT2', 'on', 3)],
            ]),
          ], mech: [['K1', 'K2']])),
  ReadyCircuit('c_sd', 'ستار دلتا', 'تشغيل ستار دلتا في اتجاه واحد بمؤقت', 'يبدأ المحرك نجمة ثم يتحول دلتا بعد زمن المؤقت.',
      () => _make('ستار دلتا', (l) => l.starDelta('KM1', 'F2', 'KM3', 'KM2', 'M1'), [
            olnc('F2'),
            stop('S0'),
            ..._latch('S1', 'KM1'),
            Par([
              [coil('KM1')],
              [timer('KT1', 'on', 5)],
              [tnc('KT1'), nc('KM3', '21-22'), Par([[coil('KM2')], [lamp('H1', 'y')]])],
              [tno('KT1'), nc('KM2', '21-22'), Par([[coil('KM3')], [lamp('H2', 'g')]])],
            ]),
          ], mech: [['KM2', 'KM3']])),
  ReadyCircuit('c_sd2', 'ستار دلتا', 'ستار دلتا في اتجاهين تلقائيًا بمؤقت', 'أمام وخلف، والتحويل من نجمة إلى دلتا في الاتجاهين.',
      () => _make('ستار دلتا في اتجاهين', (l) {
            l.reversing('K1', 'K2', 'F2', 'M1', six: true);
            return 36;
          }, [
            olnc('F2'),
            stop('S0'),
            Par([
              [..._latch('S1', 'K1'), nc('K2', '21-22'), Par([[coil('K1')], [lamp('H1', 'g')]])],
              [..._latch('S2', 'K2'), nc('K1', '21-22'), Par([[coil('K2')], [lamp('H2', 'b')]])],
              [
                Par([[no('K1', '53-54')], [no('K2', '53-54')]]),
                Par([
                  [timer('KT1', 'on', 5)],
                  [tnc('KT1'), nc('KM4', '21-22'), coil('KM3')],
                  [tno('KT1'), nc('KM3', '21-22'), coil('KM4')],
                ])
              ],
            ]),
          ], mech: [['K1', 'K2'], ['KM3', 'KM4']])),
  // ---- extra circuits
  ReadyCircuit('x_jog', 'دوائر إضافية', 'تشغيل لحظي ومستمر بمفتاح اختيار', 'مفتاح الاختيار S3 مغلق: تشغيل مستمر بالإمساك. مفتوح: المحرك يعمل ما دام S1 مضغوطًا.',
      () => _make('لحظي ومستمر', (l) => l.dol([('K1', 'F2', 'M1')]), [
            olnc('F2'),
            stop('S0'),
            Par([
              [start('S1')],
              [sel('S3'), no('K1', '13-14')]
            ]),
            Par([[coil('K1')], [lamp('H1', 'g')]]),
          ])),
  ReadyCircuit('x_tank', 'دوائر إضافية', 'ملء خزان تلقائيًا بطلمبة وعوّامتين', 'العوامة السفلى B1 تشغّل الطلمبة عند نقص المياه، والعليا B2 توقفها عند الامتلاء. اضغط على العوامة لتحاكي حركتها.',
      () => _make('ملء خزان بعوّامتين', (l) => l.dol([('K1', 'F2', 'M1')]), [
            olnc('F2'),
            stop('S0'),
            Par([[lsNc('B1')], [no('K1', '13-14')]]),
            lsNc('B2'),
            Par([[coil('K1')], [lamp('H1', 'b')]]),
          ])),
  ReadyCircuit('x_hoist', 'دوائر إضافية', 'ونش رفع وإنزال بضغط مستمر ومفاتيح حد', 'الرفع والإنزال ما دام الضاغط مضغوطًا، ومفتاح الحد يوقف الحركة عند النهاية.', plant: 'hoist',
      () => _make('ونش رفع وإنزال', (l) => l.reversing('K1', 'K2', 'F2', 'M1'), [
            olnc('F2'),
            stop('S0'),
            Par([
              [start('S1'), lsNc('B2'), nc('K2', '21-22'), Par([[coil('K1')], [lamp('H1', 'g')]])],
              [start('S2'), lsNc('B1'), nc('K1', '21-22'), Par([[coil('K2')], [lamp('H2', 'b')]])],
            ]),
          ], mech: [['K1', 'K2']])),
  // ---- machines and production lines (each drives a scene from lib/sim/plant.dart)
  ReadyCircuit('x_lift', 'ماكينات وخطوط إنتاج', 'أسانسير 3 أدوار بريليهات طلب', 'كل زرار طلب بيمسك ريليه لحد ما الكابينة توصل الدور. KP بيفتكر إن الكابينة تحت الدور الأول عشان يحدد الاتجاه.',
      () => _make('أسانسير 3 أدوار', (l) => l.reversing('K1', 'K2', 'F2', 'M1'), [
            olnc('F2'),
            stop('S0'),
            Par([
              [Par([[start('S1')], [no('KA1', '13-14')]]), lsNc('B1'), relay('KA1')],
              [Par([[start('S2')], [no('KA2', '13-14')]]), lsNc('B2'), relay('KA2')],
              [Par([[start('S3')], [no('KA3', '13-14')]]), lsNc('B3'), relay('KA3')],
              [Par([[lsNo('B1')], [no('KP', '13-14')]]), lsNc('B2'), lsNc('B3'), relay('KP')],
              [
                Par([[no('KA3', '23-24')], [no('KA2', '23-24'), no('KP', '23-24')]]),
                lsNc('B3'),
                nc('K2', '21-22'),
                Par([[coil('K1')], [lamp('H1', 'g')]])
              ],
              [
                Par([[no('KA1', '23-24')], [no('KA2', '33-34'), nc('KP', '31-32')]]),
                lsNc('B1'),
                nc('K1', '21-22'),
                Par([[coil('K2')], [lamp('H2', 'b')]])
              ],
            ]),
          ], mech: [['K1', 'K2']]), plant: 'lift'),
  ReadyCircuit('x_sort', 'ماكينات وخطوط إنتاج', 'سير فرز المعادن ببستم نيوماتيك', 'السير شغال بالإمساك الذاتي، والحساس الحثي B2 بيشغّل صمام البستم Y1 طول ما فيه معدن قدامه.',
      () => _make('سير فرز المعادن', (l) => l.dol([('K1', 'F2', 'M1')]), [
            olnc('F2'),
            stop('S0'),
            Par([
              [Par([[start('S1')], [no('K1', '13-14')]]), Par([[coil('K1')], [lamp('H1', 'g')]])],
              [no('K1', '23-24'), prox('B2'), valve('Y1')],
            ]),
          ]), plant: 'sort'),
  ReadyCircuit('x_press', 'ماكينات وخطوط إنتاج', 'مكبس نيوماتيك: دورة واحدة بزرار', 'S1 بيشتغل بس لو القطعة موجودة (B3). الذراع تنزل لحد B2، وKA2 بيفصل KA1 فالذراع ترجع.',
      () => _make('مكبس نيوماتيك', (l) => 2, [
            stop('S0'),
            Par([
              [Par([[start('S1'), photo('B3')], [no('KA1', '13-14')]]), nc('KA2', '21-22'), relay('KA1')],
              [reed('B2'), relay('KA2')],
              [no('KA1', '23-24'), valve('Y1')],
            ]),
          ]), plant: 'press'),
  ReadyCircuit('x_fill', 'ماكينات وخطوط إنتاج', 'خط تعبئة زجاجات أوتوماتيك', 'KA0 بيمسك تشغيل الخط. الفوتوسل B1 بيشغّل KA1: السير يقف والصمام Y1 يفتح، لحد ما حساس المستوى B2 يحس إن الزجاجة اتملت.',
      () => _make('خط تعبئة زجاجات', (l) => l.dol([('K1', 'F2', 'M1')]), [
            olnc('F2'),
            stop('S0'),
            Par([
              [Par([[start('S1')], [no('KA0', '13-14')]]), relay('KA0')],
              [no('KA0', '23-24'), Par([[nc('KA1', '21-22')], [floatNo('B2')]]), Par([[coil('K1')], [lamp('H1', 'g')]])],
              [photo('B1'), relay('KA1')],
              [no('KA1', '13-14'), floatNc('B2'), valve('Y1')],
            ]),
          ]), plant: 'fill'),
  // ---- production lines (lib/lines/lines.dart): the sheets beside their panel-lab exercises
  ReadyCircuit('l_belt', 'خطوط الإنتاج', 'سير نقل كراتين: تشغيل وإيقاف مع حماية الأوفرلود', 'تشغيل مباشر بإمساك ذاتي، ولمبات شغال وواقف وعطل.',
      () => _make('سير نقل كراتين', (l) => l.dol([('K1', 'F2', 'M1')]), [
            Par([
              [
                olnc('F2'),
                Par([
                  [stop('S0'), ..._latch('S1', 'K1'), coil('K1')],
                  [no('K1', '53-54'), lamp('H1', 'g')],
                  [nc('K1', '21-22'), lamp('H2', 'r')],
                ])
              ],
              [olno('F2'), lamp('H3', 'y')],
            ])
          ])),
  ReadyCircuit('l_fan', 'خطوط الإنتاج', 'مروحة شفط بتشتغل من مكانين', 'الإيقاف على التوالي والتشغيل على التوازي، ولمبة في كل مكان.',
      () => _make('مروحة شفط من مكانين', (l) => l.dol([('K1', 'F2', 'M1')]), [
            olnc('F2'),
            stop('S01'),
            stop('S02'),
            Par([[start('S11')], [start('S12')], [no('K1', '13-14')]]),
            Par([[coil('K1')], [lamp('H1', 'g')], [lamp('H2', 'g')]]),
          ])),
  ReadyCircuit('l_press2h', 'خطوط الإنتاج', 'مكبس آمن بالإيدين الاتنين', 'S1 وS2 والفوتوسل B3 على التوالي قبل KA1، وKA1 بيشغّل صمام المكبس Y1.',
      () => _make('مكبس بالإيدين الاتنين', (l) => 2, [
            stop('S0'),
            Par([
              [start('S1'), start('S2'), photo('B3'), relay('KA1')],
              [no('KA1', '11-14'), Par([[valve('Y1')], [lamp('H1', 'y')]])],
            ]),
          ]), plant: 'press'),
  ReadyCircuit('l_gate', 'خطوط الإنتاج', 'بوابة مصنع: فتح وقفل ومفاتيح نهاية شوط', 'K1 فتح وK2 قفل، بإمساك ذاتي وانترلوك، وكل مفتاح نهاية بيوقف اتجاهه.',
      () => _make('بوابة مصنع', (l) => l.reversing('K1', 'K2', 'F2', 'M1'), [
            olnc('F2'),
            stop('S0'),
            Par([
              [..._latch('S1', 'K1'), lsNc('LS2'), nc('K2', '21-22'), Par([[coil('K1')], [lamp('H1', 'y')]])],
              [..._latch('S2', 'K2'), lsNc('LS1'), nc('K1', '21-22'), Par([[coil('K2')], [lamp('H2', 'y')]])],
            ]),
          ], mech: [['K1', 'K2']])),
  ReadyCircuit('l_crusher', 'خطوط الإنتاج', 'كسارة حجارة: ستار دلتا بتايمر', 'KM1 وKM2 بيبدأوا ستار، والتايمر KT1 بيفصل الستار ويشغّل الدلتا KM3.',
      () => _make('كسارة حجارة', (l) => l.starDelta('KM1', 'F2', 'KM3', 'KM2', 'M1'), [
            olnc('F2'),
            stop('S0'),
            ..._latch('S1', 'KM1'),
            Par([
              [coil('KM1')],
              [timer('KT1', 'on', 5)],
              [tnc('KT1'), nc('KM3', '21-22'), Par([[coil('KM2')], [lamp('H1', 'y')]])],
              [tno('KT1'), nc('KM2', '21-22'), Par([[coil('KM3')], [lamp('H2', 'g')]])],
            ]),
          ], mech: [['KM2', 'KM3']])),
  ReadyCircuit('l_crane', 'خطوط الإنتاج', 'ونش علوي بتلات حركات', 'تلات دواير عكس حركة بضغط مستمر، ومفتاح حد وانترلوك قبل كل ملف.',
      () => _make('ونش علوي', (l) => l.reversingN([('K1', 'K2', 'F2', 'M1'), ('K3', 'K4', 'F3', 'M2'), ('K5', 'K6', 'F4', 'M3')]), [
            olnc('F2'),
            olnc('F3'),
            olnc('F4'),
            stop('S0'),
            Par([
              [start('S1'), lsNc('B1'), nc('K2', '21-22'), coil('K1')],
              [start('S2'), lsNc('B2'), nc('K1', '21-22'), coil('K2')],
              [start('S3'), lsNc('B4'), nc('K4', '21-22'), coil('K3')],
              [start('S4'), lsNc('B3'), nc('K3', '21-22'), coil('K4')],
              [start('S5'), lsNc('B6'), nc('K6', '21-22'), coil('K5')],
              [start('S6'), lsNc('B5'), nc('K5', '21-22'), coil('K6')],
            ]),
          ], mech: [['K1', 'K2'], ['K3', 'K4'], ['K5', 'K6']])),
  ReadyCircuit('l_oven', 'خطوط الإنتاج', 'فرن تجفيف بثرموستات ومروحة تأخير فصل', 'KA1 بيشغّل التايمر KT1 (تأخير فصل) والمروحة K1، والسخانات من KA1 بشرط المروحة والثرموستات.',
      () => _make('فرن تجفيف', (l) => l.dol([('K1', 'F2', 'M1')]), [
            olnc('F2'),
            Par([
              [
                stop('S0'),
                Par([
                  [Par([[start('S1')], [no('KA1', '11-14')]]), relay('KA1')],
                  [
                    no('KA1', '21-24'),
                    Par([
                      [timer('KT1', 'off', 8)],
                      [no('K1', '13-14'), const E('thermo_nc', 'B1'), Par([[const E('heat', 'E1')], [lamp('H1', 'y')]])],
                    ])
                  ],
                ])
              ],
              [tno('KT1'), Par([[coil('K1')], [lamp('H2', 'g')]])],
            ]),
          ])),
  ReadyCircuit('l_mixer', 'خطوط الإنتاج', 'خلاط عجين بعكس اتجاه تلقائي', 'KA2 ذاكرة الاتجاه: KT1 بيشغّله فيلف شمال، وKT2 بيفكّه فيرجع يمين. وغطا الأمان B1 قبل KA1.',
      () => _make('خلاط عجين', (l) => l.reversing('K1', 'K2', 'F2', 'M1'), [
            olnc('F2'),
            stop('S0'),
            Par([
              [Par([[start('S1')], [no('KA1', '11-14')]]), lsNo('B1'), relay('KA1')],
              [
                no('KA1', '21-24'),
                Par([
                  [nc('KA2', '11-12'), nc('K2', '21-22'), Par([[coil('K1')], [lamp('H1', 'g')]])],
                  [no('KA2', '11-14'), nc('K1', '21-22'), Par([[coil('K2')], [lamp('H2', 'b')]])],
                  [no('K1', '13-14'), timer('KT1', 'on', 4)],
                  [Par([[tno('KT1')], [no('KA2', '21-24'), tnc('KT2')]]), relay('KA2')],
                  [no('K2', '13-14'), timer('KT2', 'on', 4)],
                ])
              ],
            ]),
          ], mech: [['K1', 'K2']])),
  ReadyCircuit('l_fill', 'خطوط الإنتاج', 'خط تعبئة زجاجات', 'KA0 بيمسك الخط. الفوتوسل B1 بيشغّل KA1: السير يقف والصمام Y1 يفتح لحد حساس المستوى B2.',
      () => _make('خط تعبئة زجاجات', (l) => l.dol([('K1', 'F2', 'M1')]), [
            olnc('F2'),
            stop('S0'),
            Par([
              [Par([[start('S1')], [no('KA0', '11-14')]]), relay('KA0')],
              [no('KA0', '21-24'), Par([[nc('KA1', '11-12')], [floatNo('B2')]]), Par([[coil('K1')], [lamp('H1', 'g')]])],
              [photo('B1'), relay('KA1')],
              [no('KA1', '21-24'), floatNc('B2'), valve('Y1')],
            ]),
          ]), plant: 'fill'),
  ReadyCircuit('l_sort', 'خطوط الإنتاج', 'فرز كراتين ببستم نيوماتيك', 'السير بإمساك ذاتي، ومن نقطة K1 53-54 والحساس الحثي B2 بيتغذى صمام البستم Y1.',
      () => _make('فرز كراتين', (l) => l.dol([('K1', 'F2', 'M1')]), [
            olnc('F2'),
            stop('S0'),
            Par([
              [Par([[start('S1')], [no('K1', '13-14')]]), Par([[coil('K1')], [lamp('H1', 'g')]])],
              [no('K1', '53-54'), prox('B2'), valve('Y1')],
            ]),
          ]), plant: 'sort'),
  ReadyCircuit('l_tank2', 'خطوط الإنتاج', 'تانك مية بطلمبة أساسية واحتياطي', 'العوامة الواطية بتشغّل KA1 والعالية بتفصله. KA1 بيشغّل K1 من نقطة F2 95-96، ولو F2 فصل نقطته 97-98 تشغّل K2.',
      () => _make('تانك بطلمبتين', (l) => l.dol([('K1', 'F2', 'M1'), ('K2', 'F3', 'M2')]), [
            stop('S0'),
            Par([
              [Par([[floatNc('B1')], [no('KA1', '11-14')]]), floatNc('B2'), relay('KA1')],
              [
                no('KA1', '21-24'),
                Par([
                  [olnc('F2'), Par([[coil('K1')], [lamp('H1', 'g')]])],
                  [olno('F2'), Par([[olnc('F3'), Par([[coil('K2')], [lamp('H2', 'g')]])], [lamp('H3', 'y')]])],
                ])
              ],
            ]),
          ])),
  ReadyCircuit('l_washer', 'خطوط الإنتاج', 'غسالة زجاجات بتلات خطوات', 'كل تايمر بيتغذى من نقطة اللي قبله 15-18، ونقطته 15-16 بتشغّل خطوته. وKT3 بيفك إمساك KA1 في الآخر.',
      () => _make('غسالة زجاجات', (l) => 2, [
            stop('S0'),
            Par([
              [tnc('KT3'), Par([[start('S1')], [no('KA1', '11-14')]]), lsNo('B1'), Par([[relay('KA1')], [lamp('H1', 'g')]])],
              [
                no('KA1', '21-24'),
                Par([
                  [timer('KT1', 'on', 4)],
                  [tnc('KT1'), valve('Y1')],
                  [
                    tno('KT1'),
                    Par([
                      [timer('KT2', 'on', 4)],
                      [tnc('KT2'), valve('Y2')],
                      [tno('KT2'), Par([[timer('KT3', 'on', 4)], [valve('Y3')]])],
                    ])
                  ],
                ])
              ],
            ]),
          ])),
  ReadyCircuit('l_lift', 'خطوط الإنتاج', 'أسانسير بضاعة 3 أدوار', 'ريليه طلب لكل دور بيتفصل بحساس دوره، والاتجاه من مكان الكابينة، ونقطة الكونتاكتور بتمسك الاتجاه.',
      () => _make('أسانسير بضاعة', (l) => l.reversing('K1', 'K2', 'F2', 'M1'), [
            olnc('F2'),
            stop('S0'),
            Par([
              [Par([[start('S1')], [no('KA1', '11-14')]]), lsNc('B1'), relay('KA1')],
              [Par([[start('S2')], [no('KA2', '11-14')]]), lsNc('B2'), relay('KA2')],
              [Par([[start('S3')], [no('KA3', '11-14')]]), lsNc('B3'), relay('KA3')],
              [
                Par([[no('KA3', '21-24')], [no('KA2', '21-24'), Par([[lsNo('B1')], [no('K1', '13-14')]])]]),
                nc('K2', '21-22'),
                Par([[coil('K1')], [lamp('H1', 'g')]])
              ],
              [
                Par([[no('KA1', '21-24')], [no('KA2', '21-24'), Par([[lsNo('B3')], [no('K2', '13-14')]])]]),
                nc('K1', '21-22'),
                Par([[coil('K2')], [lamp('H2', 'b')]])
              ],
            ]),
          ], mech: [['K1', 'K2']]), plant: 'lift'),
  ReadyCircuit('l_hpress', 'خطوط الإنتاج', 'مكبس هيدروليك بطلمبة وسولونويدين', 'الطلمبة K1 بتغذي دايرة الكبس. KA1 نزول لحد البريشر سويتش B2، وKA2 طلوع لحد مفتاح الحد B1.',
      () => _make('مكبس هيدروليك', (l) => l.dol([('K1', 'F2', 'M1')]), [
            olnc('F2'),
            stop('S0'),
            ..._latch('S1', 'K1'),
            Par([
              [Par([[coil('K1')], [lamp('H1', 'g')]])],
              [Par([[start('S2')], [no('KA1', '11-14')]]), lsNc('B2'), relay('KA1')],
              [no('KA1', '21-24'), valve('Y1')],
              [Par([[const E('press_no', 'B2')], [no('KA2', '11-14')]]), lsNc('B1'), relay('KA2')],
              [const E('press_no', 'B2'), no('KA2', '21-24'), valve('Y2')],
            ]),
          ])),
  ReadyCircuit('l_line3', 'خطوط الإنتاج', 'خط تغليف: تشغيل بالتتابع وإيقاف بالعكس', 'K3 على طول، وK2 بعد KT1، وK1 بعد KT2. وفي الإيقاف KT3 وKT4 (تأخير فصل) بيوقفوا K2 ثم K3.',
      () => _make('خط تغليف كامل', (l) => l.dol([('K1', 'F2', 'M1'), ('K2', 'F3', 'M2'), ('K3', 'F4', 'M3')]), [
            Par([
              [
                stop('S00'),
                olnc('F2'),
                olnc('F3'),
                olnc('F4'),
                Par([
                  [
                    stop('S0'),
                    Par([
                      [Par([[start('S1')], [no('KA0', '11-14')]]), relay('KA0')],
                      [
                        no('KA0', '21-24'),
                        Par([
                          [timer('KT1', 'on', 3)],
                          [timer('KT2', 'on', 6)],
                          [timer('KT3', 'off', 3)],
                          [timer('KT4', 'off', 6)],
                          [tno('KT2'), Par([[coil('K1')], [lamp('H1', 'g')]])],
                        ])
                      ],
                    ])
                  ],
                  [tno('KT4'), Par([[coil('K3')], [lamp('H2', 'y')]])],
                  [tno('KT3'), Par([[tno('KT1')], [no('K2', '13-14')]]), coil('K2')],
                ])
              ],
              [Par([[olno('F2')], [olno('F3')], [olno('F4')]]), lamp('H3', 'r')],
            ]),
          ])),
];

ReadyCircuit? readyById(String id) {
  for (final r in kReady) {
    if (r.id == id) return r;
  }
  return null;
}
