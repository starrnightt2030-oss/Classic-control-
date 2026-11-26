import 'package:classic_control/meters/bench.dart';
import 'package:classic_control/meters/instruments.dart';
import 'package:classic_control/meters/tasks.dart';
import 'package:flutter_test/flutter_test.dart';

InstState meter(Instrument i, String knob) {
  final s = InstState(i);
  s.knob = i.knob.indexWhere((k) => k.label == knob);
  expect(s.knob, isNot(-1), reason: knob);
  return s;
}

void plug(InstState s, Map<String, (String, String?)> leads) {
  for (final e in leads.entries) {
    final l = s.lead(e.key);
    l.jack = e.value.$1;
    l.at = e.value.$2;
  }
}

void main() {
  group('board', () {
    test('phase and line voltages', () {
      final b = BoardBench();
      expect(b.between('pt_IN_L1', 'pt_N').abs, closeTo(230, 1));
      expect(b.between('pt_IN_L1', 'pt_IN_L2').abs, closeTo(398, 2));
      expect(b.between('pt_N', 'pt_PE').abs, lessThan(1));
    });

    test('switching Q1 off kills X1 and leaves the motor windings to measure', () {
      final b = BoardBench();
      b.setSwitch('tog_Q1', false);
      expect(b.between('pt_X1_L1', 'pt_X1_L2').abs, lessThan(1));
      expect(b.resistance('pt_X1_L1', 'pt_X1_L2'), closeTo(3.0, 0.05));
      expect(b.resistance('pt_X1_L1', 'pt_PE'), greaterThan(100e6));
      expect(b.resistance('pt_PE', 'pt_X1_PE'), lessThan(0.1));
    });

    test('clamp: one wire reads the motor current, the whole cable reads ~0', () {
      final b = BoardBench()..t = 10;
      final i1 = b.clampCurrent('clamp_L1').abs;
      expect(i1, greaterThan(5));
      expect(i1, lessThan(9));
      expect(b.clampCurrent('clamp_CABLE').abs, lessThan(0.1));
    });

    test('inrush after switching the motor on', () {
      final b = BoardBench()..t = 10;
      b.setSwitch('tog_Q1', false);
      b.setSwitch('tog_Q1', true);
      expect(b.clampCurrent('clamp_L1').abs, greaterThan(40));
      b.tick(3);
      expect(b.clampCurrent('clamp_L1').abs, lessThan(9));
    });
  });

  group('analog multimeter', () {
    test('ACV 250 on L1-N reads 230', () {
      final s = meter(avo, 'ACV 250');
      plug(s, {'red': ('v', 'pt_IN_L1'), 'black': ('com', 'pt_N')});
      final r = readInstrument(s, BoardBench());
      expect(r.needle, closeTo(0.92, 0.01));
      expect(r.danger, isNull);
    });

    test('a range too small pegs the needle and warns', () {
      final s = meter(avo, 'ACV 50');
      plug(s, {'red': ('v', 'pt_IN_L1'), 'black': ('com', 'pt_IN_L2')});
      final r = readInstrument(s, BoardBench());
      expect(r.needle!, greaterThan(1));
      expect(r.danger, isNotNull);
    });

    test('ohms on a live circuit is a mistake', () {
      final s = meter(avo, 'Ω ×1');
      plug(s, {'red': ('v', 'pt_IN_L1'), 'black': ('com', 'pt_N')});
      final r = readInstrument(s, BoardBench());
      expect(r.danger, isNotNull);
      expect(r.short, isTrue);
    });

    test('winding resistance on the ohm scale (after zeroing)', () {
      final m = MotorBench()..links = 'none';
      final s = meter(avo, 'Ω ×1')..ohmZeroed = true;
      plug(s, {'red': ('v', 'pt_U1'), 'black': ('com', 'pt_U2')});
      final r = readInstrument(s, m);
      expect(r.value, closeTo(1.52, 0.01));
      expect(r.needle, closeTo(20 / 21.52, 0.01));
    });

    test('AC on a DC range: needle stays near zero and trembles', () {
      final s = meter(avo, 'DCV 250');
      plug(s, {'red': ('v', 'pt_IN_L1'), 'black': ('com', 'pt_N')});
      final r = readInstrument(s, BoardBench());
      expect(r.needle!, lessThan(0.05));
      expect(r.jitter, greaterThan(0));
    });
  });

  group('digital multimeter', () {
    test('heater current in series through the 10 A jack', () {
      final b = BoardBench()..linkX2 = false;
      final s = meter(dmm, 'A');
      plug(s, {'red': ('10a', 'pt_X2_L'), 'black': ('com', 'pt_X2_Lo')});
      b.bridges.add(('pt_X2_L', 'pt_X2_Lo'));
      final r = readInstrument(s, b);
      expect(r.value, closeTo(1000 / 230, 0.05));
    });

    test('red lead left in 10 A across L-N is a short', () {
      final s = meter(dmm, 'V~');
      plug(s, {'red': ('10a', 'pt_IN_L1'), 'black': ('com', 'pt_N')});
      final r = readInstrument(s, BoardBench());
      expect(r.short, isTrue);
    });

    test('continuity beeps on the earth bond', () {
      final s = meter(dmm, '•)))');
      plug(s, {'red': ('v', 'pt_PE'), 'black': ('com', 'pt_X1_PE')});
      expect(readInstrument(s, BoardBench()).beep, isTrue);
    });
  });

  group('megger', () {
    test('healthy motor: hundreds of megohms after the reading settles', () {
      final m = MotorBench();
      final s = meter(megger, '500V')
        ..test = true
        ..testSince = 10;
      plug(s, {'red': ('line', 'pt_U1'), 'black': ('earth', 'pt_PE')});
      final r = readInstrument(s, m);
      expect(r.value, greaterThan(100));
    });

    test('a damp motor shows the weak winding', () {
      final m = MotorBench()
        ..links = 'none'
        ..fault = MotorFault.damp;
      final s = meter(megger, '500V')
        ..test = true
        ..testSince = 10;
      plug(s, {'red': ('line', 'pt_U1'), 'black': ('earth', 'pt_BODY')});
      expect(readInstrument(s, m).value, lessThan(1));
      s.lead('red').at = 'pt_V1';
      expect(readInstrument(s, m).value, greaterThan(5));
    });

    test('live circuit lights the warning', () {
      final m = MotorBench()..switches['tog_iso'] = true;
      final s = meter(megger, '500V');
      plug(s, {'red': ('line', 'pt_U1'), 'black': ('earth', 'pt_PE')});
      expect(readInstrument(s, m).led, isTrue);
    });
  });

  group('wattmeter', () {
    InstState wired() {
      final s = InstState(wattmeter);
      plug(s, {'ia': ('ia', 'pt_X2_L'), 'i5': ('i5', 'pt_X2_Lo'), 'vc': ('vc', 'pt_X2_Lo'), 'v300': ('v300', 'pt_X2_N')});
      return s;
    }

    test('heater: 1000 W', () {
      final b = BoardBench()..linkX2 = false;
      b.bridges.add(('pt_X2_L', 'pt_X2_Lo'));
      final r = readInstrument(wired(), b);
      expect(r.value, closeTo(1000, 5));
      expect(r.needle, closeTo(1000 / 1500, 0.01));
    });

    test('pump motor: 750 W at cos phi 0.72', () {
      final b = BoardBench()
        ..linkX2 = false
        ..heater = HeaterLoad.motor;
      b.bridges.add(('pt_X2_L', 'pt_X2_Lo'));
      expect(readInstrument(wired(), b).value, closeTo(750, 5));
    });

    test('current coil reversed: the needle goes left', () {
      final b = BoardBench()..linkX2 = false;
      final s = wired();
      s.lead('ia').at = 'pt_X2_Lo';
      s.lead('i5').at = 'pt_X2_L';
      b.bridges.add(('pt_X2_Lo', 'pt_X2_L'));
      expect(readInstrument(s, b).value, lessThan(-900));
    });

    test('current coil across L-N is a short', () {
      final s = InstState(wattmeter);
      plug(s, {'ia': ('ia', 'pt_IN_L1'), 'i5': ('i5', 'pt_N')});
      expect(readInstrument(s, BoardBench()).short, isTrue);
    });
  });

  test('a guided task completes when its steps are done', () {
    final t = tasks.firstWhere((t) => t.id == 'avo_phase');
    final run = TaskRun(t);
    final s = meter(avo, 'ACV 250');
    plug(s, {'red': ('v', 'pt_IN_L1'), 'black': ('com', 'pt_N')});
    final b = BoardBench();
    run.update(Ctx(s, b, readInstrument(s, b)));
    expect(run.finished, isTrue);
  });

  test('every task belongs to a known instrument and bench', () {
    for (final t in tasks) {
      final i = instrumentByKey(t.instrument);
      expect(i.benches, contains(t.bench), reason: t.id);
    }
  });
}
