// Binds a machine (lib/sim/plant.dart) to the running schematic by device tags.
import '../sim/engine.dart';
import '../sim/plant.dart';
import 'model.dart';

class SchemPlantIo implements PlantIo {
  final SchemDoc doc;
  final SchemSim sim;
  SchemPlantIo(this.doc, this.sim);

  // the drawing does not change while the simulation runs, so each tag is looked up once
  final _found = <String, Comp?>{};
  Set<String>? _tags;

  Comp? _comp(String tag, String kind, bool Function(SPlaced s) ok) => _found.putIfAbsent('$kind:$tag', () {
        for (final s in doc.syms) {
          if (s.tag == tag && ok(s)) return sim.lab.byId(sim.compOf[s.id] ?? '');
        }
        return null;
      });

  @override
  double motor(String tag) {
    final c = _comp(tag, 'm', (s) => s.d.engine == 'motor' || s.d.engine == 'motor1');
    if (c == null) return 0;
    final run = c.s.mode == 'star' || c.s.mode == 'delta' || c.s.mode == 'run';
    return run ? c.s.spd * (c.s.dir == 0 ? 1 : c.s.dir) : 0;
  }

  @override
  bool on(String tag) {
    final c = _comp(tag, 'l', (s) => s.d.engine == 'lamp');
    return c != null && !c.s.dead && c.s.fault != 'lamp_dead' && c.s.v > c.num_('V') * 0.6;
  }

  @override
  void sense(String tag, bool active) {
    final done = <String>{};
    for (final s in doc.syms) {
      if (s.tag != tag || (s.d.engine != 'ls' && s.d.engine != 'prox')) continue;
      final id = s.d.shared ? s.tag : sim.compOf[s.id];
      if (id == null || !done.add(id)) continue;
      sim.lab.actuate(id, 'ls', active);
    }
  }

  @override
  bool has(String tag) => (_tags ??= {for (final s in doc.syms) s.tag}).contains(tag);
}
