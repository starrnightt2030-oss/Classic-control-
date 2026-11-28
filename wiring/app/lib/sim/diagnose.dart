// Live wiring check: what is wrong with the wiring as it stands, where, and why.
// It looks at the wiring itself (no switch positions needed), like a teacher
// looking over the student's board before letting them switch the power on.
import 'model.dart';
import 'solver.dart';

class Issue {
  final bool error; // false = a warning (works, but not the right way)
  final String title;
  final String why; // the explanation shown to the student
  final Set<String> terms;
  final Set<int> wires;
  const Issue(this.error, this.title, this.why, {this.terms = const {}, this.wires = const {}});
}

enum Role { phase, neutral, earth, switched, none }

const switchKinds = {Kind.sw1, Kind.sw2, Kind.swi, Kind.swd, Kind.pb, Kind.dimmer};

/// The nets of the board when every switch is open: terminals joined by wires,
/// bars, and the always-closed paths of breakers and meters.
class Nets {
  final Map<String, String> _p = {};
  String find(String x) {
    _p.putIfAbsent(x, () => x);
    var r = x;
    while (_p[r] != r) {
      r = _p[r]!;
    }
    var c = x;
    while (_p[c] != r) {
      final n = _p[c]!;
      _p[c] = r;
      c = n;
    }
    return r;
  }

  void join(String a, String b) {
    final ra = find(a), rb = find(b);
    if (ra != rb) _p[ra] = rb;
  }

  bool same(String a, String b) => find(a) == find(b);
}

Nets netsOf(Sim s, {bool throughDevices = true}) {
  final n = Nets();
  for (final w in s.wires) {
    n.join(w.a, w.b);
  }
  for (final p in s.parts) {
    String t(String id) => '${p.id}.$id';
    switch (p.kind) {
      case Kind.nbar:
        for (final x in ['n2', 'n3', 'n4']) {
          n.join(t('n1'), t(x));
        }
      case Kind.ebar:
        for (final x in ['e2', 'e3', 'e4']) {
          n.join(t('e1'), t(x));
        }
      case Kind.mcb:
        if (throughDevices) n.join(t('in'), t('out'));
      case Kind.rcd:
      case Kind.meter:
        if (throughDevices) {
          n.join(t('Li'), t('Lo'));
          n.join(t('Ni'), t('No'));
        }
      default:
        break;
    }
  }
  return n;
}

List<Issue> diagnose(Sim s, {bool checkColours = true}) {
  final out = <Issue>[];
  final nets = netsOf(s);
  String? findKind(Kind k, String term) {
    for (final p in s.parts) {
      if (p.kind == k) return '${p.id}.$term';
    }
    return null;
  }

  final l = findKind(Kind.supply, 'L'), nn = findKind(Kind.supply, 'N'), pe = findKind(Kind.supply, 'PE');
  final roles = <String, Role>{};
  Role roleOf(String key) {
    final r = nets.find(key);
    return roles.putIfAbsent(r, () {
      if (l != null && nets.same(key, l)) return Role.phase;
      if (nn != null && nets.same(key, nn)) return Role.neutral;
      if (pe != null && nets.same(key, pe)) return Role.earth;
      return Role.none;
    });
  }

  Set<int> wiresOfNet(String key) => {
        for (var i = 0; i < s.wires.length; i++)
          if (nets.same(s.wires[i].a, key)) i
      };

  // dead shorts: two supply conductors in the same net
  if (l != null && nn != null && nets.same(l, nn)) {
    out.add(Issue(true, 'قصر: الفاز متوصل بالنيوترال مباشرة',
        'في سلك (أو أكتر) بيوصل الفاز بالنيوترال من غير حمل في النص. أول ما تشغّل الكهرباء القاطع هيفصل أو الفيوز هيضرب. تتبّع الأسلاك المعلّمة بالأحمر.',
        wires: wiresOfNet(l)));
  }
  if (l != null && pe != null && nets.same(l, pe)) {
    out.add(Issue(true, 'الفاز متوصل بالأرضي',
        'الأرضي سلك حماية بس، عمره ما يوصل بالفاز. كده جسم الأجهزة هيبقى عليه كهربا ومفتاح التسريب هيفصل.', wires: wiresOfNet(l)));
  }
  if (nn != null && pe != null && nets.same(nn, pe)) {
    out.add(Issue(true, 'النيوترال متوصل بالأرضي',
        'النيوترال والأرضي بيتربطوا عند مصدر التغذية بس (عند المحول أو أول لوحة). لو ربطتهم في الدايرة، تيار الرجوع هيمشي في سلك الأرضي ومفتاح التسريب (RCD) هيفصل.',
        wires: wiresOfNet(nn)));
  }

  for (var i = 0; i < s.wires.length; i++) {
    final w = s.wires[i];
    final pa = w.a.split('.').first, pb = w.b.split('.').first;
    final part = s.part(pa);
    if (pa == pb && part != null && !jboxKinds.contains(part.kind) && part.kind != Kind.nbar && part.kind != Kind.ebar) {
      out.add(Issue(true, 'سلك بين طرفين في نفس الجهاز (${part.id})',
          'الطرفين دول المفروض الجهاز نفسه هو اللي يوصّلهم أو يفصلهم. السلك ده بيعمل كوبري (by-pass): المفتاح مش هيتحكم في حاجة، أو هيبقى قصر لو الطرفين فاز ونيوترال.',
          terms: {w.a, w.b}, wires: {i}));
    }
    if (!checkColours) continue;
    final r = roleOf(w.a);
    final c = w.color;
    if (r == Role.earth && c != WireColor.earth) {
      out.add(Issue(true, 'سلك الأرضي لازم يبقى أخضر في أصفر',
          'حسب المواصفة (IEC 60445) لون الأرضي أخضر/أصفر بس، ولا يُستخدم اللون ده لأي حاجة تانية. أي فني بعدك لازم يعرف الأرضي من لونه.',
          wires: {i}));
    } else if (r != Role.earth && r != Role.none && c == WireColor.earth) {
      out.add(Issue(true, 'لون الأرضي مستخدم في سلك ${r == Role.phase ? 'فاز' : 'نيوترال'}',
          'الأخضر في الأصفر محجوز للأرضي. لو حد لمس السلك ده فاكره أرضي هيتكهرب.', wires: {i}));
    } else if (r == Role.phase && c == WireColor.blue) {
      out.add(Issue(true, 'سلك أزرق شايل فاز',
          'الأزرق للنيوترال. الفاز بيتوصل بالبني (أو الأحمر/الأسود في التمديدات القديمة). غيّر لون السلك عشان أي حد يشتغل بعدك ميتلخبطش.', wires: {i}));
    } else if (r == Role.neutral && c != WireColor.blue) {
      out.add(Issue(false, 'النيوترال لونه أزرق',
          'سلك النيوترال المفروض يبقى أزرق فاتح. الدايرة هتشتغل، بس التمديد مش مطابق للمواصفة.', wires: {i}));
    } else if (r == Role.none && c == WireColor.blue) {
      out.add(Issue(false, 'أزرق على سلك راجع من مفتاح',
          'السلك الراجع من المفتاح للمبة هو فاز متحكَّم فيه. لونه بني أو أسود أو رمادي، مش أزرق.', wires: {i}));
    }
  }

  for (final p in s.parts) {
    String t(String id) => '${p.id}.$id';
    if (switchKinds.contains(p.kind)) {
      final onN = [for (final x in p.type.terms) if (roleOf(t(x.id)) == Role.neutral) t(x.id)];
      if (onN.isNotEmpty) {
        out.add(Issue(true, 'المفتاح ${p.id} متركّب على النيوترال',
            'المفتاح لازم يقطع الفاز. لو قطع النيوترال اللمبة هتطفي، بس الدواية هتفضل عليها فاز وأنت بتغيّر اللمبة ممكن تتكهرب.',
            terms: onN.toSet()));
      }
    }
    if (p.kind == Kind.lamp) {
      if (roleOf(t('L')) == Role.neutral) {
        out.add(Issue(false, 'الفاز والنيوترال معكوسين في الدواية ${p.id}',
            'المسمار الوسطاني في الدواية (L) للفاز، والقلاووظ (N) للنيوترال. لو اتعكسوا، القلاووظ اللي إيدك ممكن تلمسه وانت بتغيّر اللمبة هيبقى عليه فاز.',
            terms: {t('L')}));
      }
    }
    if (p.kind == Kind.socket) {
      final pe0 = roleOf(t('PE'));
      if (pe0 != Role.earth && s.wires.any((w) => w.touches(t('L')) || w.touches(t('N')))) {
        out.add(Issue(false, 'البريزة ${p.id} من غير أرضي',
            'طرف الأرضي في البريزة بيحمي اللي بيستخدم جهاز جسمه معدن: لو حصل تسريب، التيار يروح للأرض ومفتاح التسريب يفصل بدل ما يعدّي في جسم الإنسان.',
            terms: {t('PE')}));
      }
      if (roleOf(t('L')) == Role.neutral && roleOf(t('N')) == Role.phase) {
        out.add(Issue(false, 'البريزة ${p.id} معكوسة (L و N)',
            'الأجهزة هتشتغل، بس فيها مفاتيح بتقطع طرف واحد، فممكن يبقى الجهاز مطفي وجواه فاز. التزم: L شمال، N يمين حسب علامات البريزة.',
            terms: {t('L'), t('N')}));
      }
    }
    if (jboxKinds.contains(p.kind)) {
      for (final x in p.type.terms) {
        final k = t(x.id);
        final c = s.wires.where((w) => w.touches(k)).length;
        if (c == 1) {
          out.add(Issue(false, 'نقطة في ${p.id} داخلها سلك واحد بس',
              'نقطة التجميع (الوصلة) في العلبة بتجمع سلكين أو أكتر. سلك داخل لوحده ومش طالع منه حاجة يبقى توصيلة ناقصة أو سلك سايب لازم يتعزل.',
              terms: {k}));
        }
      }
    }
  }
  return out;
}
