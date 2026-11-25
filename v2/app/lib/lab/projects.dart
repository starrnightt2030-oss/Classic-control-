// Named projects saved on the device (panel worksheets and schematics).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/theme.dart';

class SavedProject {
  final String kind, name, json;
  final DateTime at;
  const SavedProject(this.kind, this.name, this.json, this.at);
}

class ProjectStore {
  static const _key = 'cc_projects_v1';

  static Future<List<SavedProject>> list(String kind) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final m = jsonDecode(raw) as List;
    final out = <SavedProject>[];
    for (final e in m) {
      final j = e as Map<String, dynamic>;
      if (j['k'] != kind) continue;
      out.add(SavedProject(kind, j['n'] as String, j['j'] as String, DateTime.tryParse(j['t'] as String? ?? '') ?? DateTime.now()));
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }

  static Future<List<Map<String, dynamic>>> _all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    return raw == null ? [] : (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> _write(List<Map<String, dynamic>> l) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(l));
  }

  static Future<void> save(String kind, String name, String json) async {
    final l = await _all();
    l.removeWhere((e) => e['k'] == kind && e['n'] == name);
    l.add({'k': kind, 'n': name, 'j': json, 't': DateTime.now().toIso8601String()});
    await _write(l);
  }

  static Future<void> delete(String kind, String name) async {
    final l = await _all();
    l.removeWhere((e) => e['k'] == kind && e['n'] == name);
    await _write(l);
  }
}

/// Save the current work under a name, or open / delete a saved one.
Future<void> showProjectsSheet(BuildContext context,
    {required String kind, required String suggestedName, required String Function() current, required void Function(String json, String name) onOpen}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _ProjectsSheet(kind: kind, suggestedName: suggestedName, current: current, onOpen: onOpen),
  );
}

class _ProjectsSheet extends StatefulWidget {
  final String kind, suggestedName;
  final String Function() current;
  final void Function(String json, String name) onOpen;
  const _ProjectsSheet({required this.kind, required this.suggestedName, required this.current, required this.onOpen});
  @override
  State<_ProjectsSheet> createState() => _ProjectsSheetState();
}

class _ProjectsSheetState extends State<_ProjectsSheet> {
  late final TextEditingController name = TextEditingController(text: widget.suggestedName);
  List<SavedProject>? items;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final l = await ProjectStore.list(widget.kind);
    if (mounted) setState(() => items = l);
  }

  String _when(DateTime t) => '${t.year}/${t.month.toString().padLeft(2, '0')}/${t.day.toString().padLeft(2, '0')}  ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('مشاريعي المحفوظة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: name, decoration: const InputDecoration(hintText: 'اسم المشروع', isDense: true))),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: () async {
              final n = name.text.trim();
              if (n.isEmpty) return;
              await ProjectStore.save(widget.kind, n, widget.current());
              await _reload();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حفظ «$n»')));
              }
            },
            icon: const Icon(Icons.save_rounded),
            label: const Text('حفظ'),
          ),
        ]),
        const SizedBox(height: 14),
        if (items == null)
          const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
        else if (items!.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد مشاريع محفوظة بعد.', textAlign: TextAlign.center, style: TextStyle(color: CC.muted)))
        else
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
            child: ListView(shrinkWrap: true, children: [
              for (final p in items!)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined, color: CC.accentSoft),
                  title: Text(p.name),
                  subtitle: Text(_when(p.at), textDirection: TextDirection.ltr, textAlign: TextAlign.right, style: const TextStyle(color: CC.muted, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onOpen(p.json, p.name);
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: CC.red),
                    onPressed: () async {
                      await ProjectStore.delete(widget.kind, p.name);
                      await _reload();
                    },
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}
