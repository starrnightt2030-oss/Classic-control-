import 'package:classic_control/quiz/bank.dart';
import 'package:classic_control/schem/ladder.dart';
import 'package:classic_control/schem/symbols.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('question bank is well formed', () {
    final ids = <String>{};
    final cats = kQuizCats.map((c) => c.$1).toSet();
    for (final q in kQuiz) {
      expect(ids.add(q.id), isTrue, reason: 'duplicate ${q.id}');
      expect(cats.contains(q.cat), isTrue, reason: q.id);
      expect(q.o.length, greaterThanOrEqualTo(3), reason: q.id);
      expect(q.o.toSet().length, q.o.length, reason: 'duplicate options in ${q.id}');
      final f = q.fig;
      if (f != null && f.startsWith('sym:')) expect(kSyms.containsKey(f.substring(4)), isTrue, reason: q.id);
      if (f != null && f.startsWith('circ:')) expect(readyById(f.substring(5)), isNotNull, reason: q.id);
    }
    for (final c in cats) {
      expect(kQuiz.where((q) => q.cat == c).length, greaterThanOrEqualTo(5), reason: c);
    }
  });
}
