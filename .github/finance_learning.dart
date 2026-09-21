import 'dart:convert';

import 'package:flutter/material.dart';

import 'database.dart';
import 'finance_knowledge.dart';

class FinanceLearningStore {
  static Future<void> ensureSchema() async {
    final d = await AppDatabase.instance.db;
    await d.execute('''
      CREATE TABLE IF NOT EXISTS learned_finance_rules(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        text TEXT NOT NULL,
        tags TEXT NOT NULL DEFAULT '',
        scope TEXT NOT NULL DEFAULT 'both',
        vector_json TEXT NOT NULL,
        confidence REAL NOT NULL DEFAULT 0.85,
        enabled INTEGER NOT NULL DEFAULT 1,
        source TEXT NOT NULL DEFAULT 'ai_verified',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        uses INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static Future<String> retrieve(String query, {int topK = 4}) async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    final rows = await d.query(
      'learned_finance_rules',
      where: 'enabled=1',
      orderBy: 'updated_at DESC',
      limit: 250,
    );
    if (rows.isEmpty) return '';
    final q = FinanceKnowledge.embedding(query);
    final scored = <MapEntry<Map<String, dynamic>, double>>[];
    for (final row in rows) {
      try {
        final raw = jsonDecode(row['vector_json'].toString());
        if (raw is! List) continue;
        final v = raw.map((e) => (e as num).toDouble()).toList();
        scored.add(MapEntry(row, FinanceKnowledge.cosine(q, v)));
      } catch (_) {}
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    final selected = scored.where((e) => e.value >= 0.05).take(topK).toList();
    for (final e in selected) {
      await d.rawUpdate(
        'UPDATE learned_finance_rules SET uses=uses+1 WHERE id=?',
        [e.key['id']],
      );
    }
    return selected
        .map(
          (e) =>
              '[REGLA APRENDIDA · ${e.key['scope']}] ${e.key['title']}\n${e.key['text']}',
        )
        .join('\n\n');
  }

  static Future<bool> considerCandidate({
    required String text,
    required String tags,
    required String scope,
  }) async {
    final clean = text.trim();
    if (clean.length < 35 || clean.length > 900) return false;
    final lower = clean.toLowerCase();
    if (RegExp(
          r'\b\d+(?:[.,]\d+)?\s*(?:usd|dolares|dólares|pesos)?\b',
          caseSensitive: false,
        ).hasMatch(clean) &&
        !lower.contains('cuenta') &&
        !lower.contains('código') &&
        !lower.contains('codigo')) {
      return false;
    }
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    final vector = FinanceKnowledge.embedding('$tags $clean');
    final rows = await d.query(
      'learned_finance_rules',
      where: 'enabled=1',
      orderBy: 'updated_at DESC',
      limit: 250,
    );
    for (final row in rows) {
      try {
        final raw = jsonDecode(row['vector_json'].toString());
        if (raw is! List) continue;
        final existing = raw.map((e) => (e as num).toDouble()).toList();
        if (FinanceKnowledge.cosine(vector, existing) >= 0.90) {
          await d.rawUpdate(
            'UPDATE learned_finance_rules SET updated_at=?, confidence=MIN(0.99,confidence+0.02) WHERE id=?',
            [DateTime.now().toIso8601String(), row['id']],
          );
          return false;
        }
      } catch (_) {}
    }
    final now = DateTime.now().toIso8601String();
    final first = clean.split(RegExp(r'[.!?\n]')).first.trim();
    await d.insert('learned_finance_rules', {
      'title': first.length > 80 ? first.substring(0, 80) : first,
      'text': clean,
      'tags': tags.trim(),
      'scope': const {'personal', 'business', 'both'}.contains(scope)
          ? scope
          : 'both',
      'vector_json': jsonEncode(vector),
      'confidence': 0.85,
      'enabled': 1,
      'source': 'ai_verified',
      'created_at': now,
      'updated_at': now,
      'uses': 0,
    });
    return true;
  }

  static Future<void> saveManual({
    int? id,
    required String title,
    required String text,
    required String tags,
    required String scope,
  }) async {
    final cleanTitle = title.trim();
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      throw Exception('Escribe el conocimiento que quieres guardar.');
    }
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    final selectedScope =
        const {'personal', 'business', 'both'}.contains(scope) ? scope : 'both';
    final vector = FinanceKnowledge.embedding(
      '$cleanTitle $tags $cleanText',
    );
    final now = DateTime.now().toIso8601String();
    final values = {
      'title': cleanTitle.isEmpty
          ? (cleanText.length > 80 ? cleanText.substring(0, 80) : cleanText)
          : cleanTitle,
      'text': cleanText,
      'tags': tags.trim(),
      'scope': selectedScope,
      'vector_json': jsonEncode(vector),
      'confidence': 1.0,
      'enabled': 1,
      'source': 'manual',
      'updated_at': now,
    };
    if (id == null) {
      await d.insert('learned_finance_rules', {
        ...values,
        'created_at': now,
        'uses': 0,
      });
    } else {
      await d.update(
        'learned_finance_rules',
        values,
        where: 'id=?',
        whereArgs: [id],
      );
    }
  }

  static Future<List<Map<String, dynamic>>> all() async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    return d.query('learned_finance_rules', orderBy: 'updated_at DESC');
  }

  static Future<void> setEnabled(int id, bool enabled) async {
    final d = await AppDatabase.instance.db;
    await d.update(
      'learned_finance_rules',
      {'enabled': enabled ? 1 : 0},
      where: 'id=?',
      whereArgs: [id],
    );
  }

  static Future<void> delete(int id) async {
    final d = await AppDatabase.instance.db;
    await d.delete('learned_finance_rules', where: 'id=?', whereArgs: [id]);
  }
}

class LearnedFinanceRulesPage extends StatefulWidget {
  const LearnedFinanceRulesPage({super.key});
  @override
  State<LearnedFinanceRulesPage> createState() =>
      _LearnedFinanceRulesPageState();
}

class _LearnedFinanceRulesPageState extends State<LearnedFinanceRulesPage> {
  List<Map<String, dynamic>> rules = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await FinanceLearningStore.all();
    if (mounted) setState(() => rules = data);
  }


  Future<void> _editKnowledge([Map<String, dynamic>? existing]) async {
    final title = TextEditingController(
      text: existing?['title']?.toString() ?? '',
    );
    final body = TextEditingController(
      text: existing?['text']?.toString() ?? '',
    );
    final tags = TextEditingController(
      text: existing?['tags']?.toString() ?? '',
    );
    var scope = existing?['scope']?.toString() ?? 'both';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(
            existing == null ? 'Agregar conocimiento' : 'Editar conocimiento',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(
                    labelText: 'Título (opcional)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: body,
                  minLines: 4,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'Regla o conocimiento',
                    hintText:
                        'Ej.: Si una compra es personal, confirmar con qué dinero se pagó antes de registrarla.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tags,
                  decoration: const InputDecoration(
                    labelText: 'Etiquetas (opcional)',
                    hintText: 'deuda, personal, tarjeta...',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: scope,
                  decoration: const InputDecoration(labelText: 'Ámbito'),
                  items: const [
                    DropdownMenuItem(
                      value: 'both',
                      child: Text('Personal y Negocio'),
                    ),
                    DropdownMenuItem(
                      value: 'personal',
                      child: Text('Solo Personal'),
                    ),
                    DropdownMenuItem(
                      value: 'business',
                      child: Text('Solo Negocio'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialog(() => scope = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      await FinanceLearningStore.saveManual(
        id: existing?['id'] as int?,
        title: title.text,
        text: body.text,
        tags: tags.text,
        scope: scope,
      );
      await _load();
    }
    title.dispose();
    body.dispose();
    tags.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Base de conocimiento')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editKnowledge(),
        icon: const Icon(Icons.add),
        label: const Text('Agregar conocimiento'),
      ),
      body: rules.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Todavía no hay conocimiento adicional. Puedes agregarlo manualmente o dejar que la IA aprenda reglas generales verificadas.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: rules.length,
              itemBuilder: (_, i) {
                final r = rules[i];
                final enabled = r['enabled'] == 1;
                return Card(
                  child: ListTile(
                    title: Text(r['title'].toString()),
                    subtitle: Text(
                      '${r['text']}\nÁmbito: ${r['scope']} · fuente: ${r['source']} · usos: ${r['uses']}',
                    ),
                    onTap: () => _editKnowledge(r),
                    isThreeLine: true,
                    leading: Switch(
                      value: enabled,
                      onChanged: (v) async {
                        await FinanceLearningStore.setEnabled(r['id'] as int, v);
                        await _load();
                      },
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await FinanceLearningStore.delete(r['id'] as int);
                        await _load();
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
