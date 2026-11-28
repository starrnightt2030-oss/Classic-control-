import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stars per circuit, quiz scores, saved free-lab boards, settings.
class Progress extends ChangeNotifier {
  Progress._();
  static final Progress i = Progress._();
  SharedPreferences? _p;
  final Map<String, int> stars = {};
  final Map<String, int> faultsFound = {};
  final Map<String, int> quizBest = {};
  String studentName = '';
  String lastCircuit = '';
  bool sound = true;
  bool bigUi = false;

  Future<void> load() async {
    try {
      _p = await SharedPreferences.getInstance();
      final j = _p!.getString('progress');
      if (j != null) {
        final m = jsonDecode(j) as Map<String, dynamic>;
        stars.addAll(Map<String, int>.from(m['stars'] ?? {}));
        faultsFound.addAll(Map<String, int>.from(m['faults'] ?? {}));
        quizBest.addAll(Map<String, int>.from(m['quiz'] ?? {}));
        studentName = m['name'] ?? '';
        lastCircuit = m['last'] ?? '';
        sound = m['sound'] ?? true;
        bigUi = m['big'] ?? false;
      }
    } catch (e) {
      debugPrint('progress load: $e');
    }
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      await _p?.setString('progress', jsonEncode({'stars': stars, 'faults': faultsFound, 'quiz': quizBest, 'name': studentName, 'last': lastCircuit, 'sound': sound, 'big': bigUi}));
    } catch (e) {
      debugPrint('progress save: $e');
    }
  }

  void setStars(String id, int s) {
    if ((stars[id] ?? 0) < s) stars[id] = s;
    _save();
  }

  void foundFault(String id) {
    faultsFound[id] = (faultsFound[id] ?? 0) + 1;
    _save();
  }

  void setQuiz(String id, int pct) {
    if ((quizBest[id] ?? 0) < pct) quizBest[id] = pct;
    _save();
  }

  void setLast(String id) {
    lastCircuit = id;
    _save();
  }

  void setName(String n) {
    studentName = n;
    _save();
  }

  void setSound(bool v) {
    sound = v;
    _save();
  }

  void setBigUi(bool v) {
    bigUi = v;
    _save();
  }

  int get totalStars => stars.values.fold(0, (a, b) => a + b);

  // saved free-lab boards
  List<String> boards() => _p?.getStringList('boards') ?? [];
  String? board(String name) => _p?.getString('board:$name');
  Future<void> saveBoard(String name, String json) async {
    final l = boards();
    if (!l.contains(name)) l.add(name);
    await _p?.setStringList('boards', l);
    await _p?.setString('board:$name', json);
    notifyListeners();
  }

  Future<void> deleteBoard(String name) async {
    final l = boards()..remove(name);
    await _p?.setStringList('boards', l);
    await _p?.remove('board:$name');
    notifyListeners();
  }
}
