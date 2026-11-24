/// Content models, parsed from assets/content/<component>.json
/// (schema: v2/docs/04-content-guide.md).
library;

class Clip {
  final String? audio;
  final String text;
  const Clip({this.audio, required this.text});

  static Clip? fromJson(Object? j) {
    if (j is! Map) return null;
    return Clip(audio: j['audio'] as String?, text: (j['text_ar'] ?? '') as String);
  }
}

class Lesson {
  final String id;
  final String titleAr;
  final String titleEn;
  final String text;
  final String? audio;
  const Lesson({required this.id, required this.titleAr, required this.titleEn, required this.text, this.audio});

  factory Lesson.fromJson(Map j) => Lesson(
        id: (j['id'] ?? '') as String,
        titleAr: (j['title_ar'] ?? '') as String,
        titleEn: (j['title_en'] ?? '') as String,
        text: (j['text_ar'] ?? '') as String,
        audio: j['audio'] as String?,
      );
}

class Part {
  final String id;
  final String nameAr;
  final String nameEn;
  final String text;
  final String? fault;
  final String? test;
  final String? audio;
  const Part({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.text,
    this.fault,
    this.test,
    this.audio,
  });

  factory Part.fromJson(Map j) => Part(
        id: (j['id'] ?? '') as String,
        nameAr: (j['name_ar'] ?? '') as String,
        nameEn: (j['name_en'] ?? '') as String,
        text: (j['text_ar'] ?? '') as String,
        fault: j['fault_ar'] as String?,
        test: j['test_ar'] as String?,
        audio: j['audio'] as String?,
      );
}

class Component {
  final String id;
  final String nameAr;
  final String nameEn;
  final String model;
  final List<String> variants;
  final Clip? intro;
  final Clip? opening;
  final Clip? closing;
  final List<Lesson> lessons;
  final List<Part> parts;
  final List<String> references;

  const Component({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.model,
    required this.variants,
    this.intro,
    this.opening,
    this.closing,
    required this.lessons,
    required this.parts,
    required this.references,
  });

  factory Component.fromJson(Map j) {
    final model = (j['model'] ?? '') as String;
    final v = (j['variants'] as List?)?.cast<String>() ?? const <String>[];
    return Component(
      id: (j['component'] ?? '') as String,
      nameAr: (j['name_ar'] ?? '') as String,
      nameEn: (j['name_en'] ?? '') as String,
      model: model,
      variants: v.isEmpty ? [model] : v,
      intro: Clip.fromJson(j['intro']),
      opening: Clip.fromJson(j['opening']),
      closing: Clip.fromJson(j['closing']),
      lessons: ((j['lesson'] as List?) ?? const []).whereType<Map>().map(Lesson.fromJson).toList(),
      parts: ((j['parts'] as List?) ?? const []).whereType<Map>().map(Part.fromJson).toList(),
      references: ((j['references'] as List?) ?? const []).map((e) => e.toString()).toList(),
    );
  }

  Part? partById(String? id) {
    if (id == null) return null;
    for (final p in parts) {
      if (p.id == id) return p;
    }
    return null;
  }
}
