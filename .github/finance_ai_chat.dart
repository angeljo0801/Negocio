import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database.dart';
import 'finance_ai_service.dart';
import 'finance_ai_settings.dart';
import 'finance_knowledge.dart';

class FinanceAiMessage {
  const FinanceAiMessage({
    required this.role,
    required this.text,
    required this.createdAt,
    this.responseSeconds,
  });

  final String role;
  final String text;
  final DateTime createdAt;
  final double? responseSeconds;

  FinanceAiMessage copyWith({String? text, double? responseSeconds}) =>
      FinanceAiMessage(
        role: role,
        text: text ?? this.text,
        createdAt: createdAt,
        responseSeconds: responseSeconds ?? this.responseSeconds,
      );

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
        if (responseSeconds != null) 'responseSeconds': responseSeconds,
      };

  factory FinanceAiMessage.fromJson(Map<String, dynamic> json) =>
      FinanceAiMessage(
        role: json['role']?.toString() == 'assistant' ? 'assistant' : 'user',
        text: json['text']?.toString() ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
                DateTime.now(),
        responseSeconds: (json['responseSeconds'] as num?)?.toDouble(),
      );
}

class FinanceAiSession {
  const FinanceAiSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<FinanceAiMessage> messages;

  factory FinanceAiSession.empty() {
    final now = DateTime.now();
    return FinanceAiSession(
      id: 'fin_chat_${now.microsecondsSinceEpoch}',
      title: 'Nuevo chat',
      createdAt: now,
      updatedAt: now,
      messages: const [],
    );
  }

  FinanceAiSession copyWith({
    String? title,
    DateTime? updatedAt,
    List<FinanceAiMessage>? messages,
  }) =>
      FinanceAiSession(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        messages: messages ?? this.messages,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((e) => e.toJson()).toList(),
      };

  factory FinanceAiSession.fromJson(Map<String, dynamic> json) =>
      FinanceAiSession(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Chat',
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
                DateTime.now(),
        updatedAt:
            DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
                DateTime.now(),
        messages: (json['messages'] is List)
            ? (json['messages'] as List)
                .whereType<Map>()
                .map((e) =>
                    FinanceAiMessage.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : const [],
      );

  static String titleFrom(String text) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return 'Nuevo chat';
    return clean.length <= 44
        ? clean
        : '${clean.substring(0, 44).trim()}…';
  }
}

class FinanceAiChatStore {
  static const _key = 'finance_ai_chat_sessions';

  static Future<List<FinanceAiSession>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return [];
      final result = data
          .whereType<Map>()
          .map((e) => FinanceAiSession.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return result;
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAll(List<FinanceAiSession> sessions) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _key,
      jsonEncode(sessions.map((e) => e.toJson()).toList()),
    );
  }
}

class FinanceAiContext {
  static const String knowledge = '''
BASE DE CONOCIMIENTO CONTABLE DE FINANZAS DEFINITIVA

REGLAS:
- Todo asiento debe cuadrar: total Debe = total Haber.
- Activos y gastos normalmente aumentan por el Debe.
- Pasivos, patrimonio e ingresos normalmente aumentan por el Haber.
- Efectivo 1010: aumenta Debe, disminuye Haber.
- Cuentas por cobrar 1020: aumenta Debe cuando un cliente queda debiendo y disminuye Haber cuando paga.
- Inventario 1030: aumenta Debe al comprar mercancía para vender; el costo pasa a Costo de ventas 5010 cuando corresponda reconocer la venta.
- Cuentas por pagar 2010: aumenta Haber al comprar o incurrir en un gasto a crédito; disminuye Debe al pagar.
- Capital aportado 3010 se acredita cuando el propietario aporta dinero.
- Retiros 3030 se debitan cuando el propietario saca dinero para uso personal.
- Ventas 4010 y otros ingresos se acreditan.
- Comisiones por remesas 4020 es ingreso por la comisión realmente ganada.
- Los gastos operativos se debitan y, si se pagan, Efectivo se acredita.
- Un préstamo recibido: Debe Efectivo / Haber Préstamo bancario 2500.
- Pago de principal: Debe Préstamo bancario / Haber Efectivo. El interés se registra aparte como gasto 7010.
- Una compra de equipo o maquinaria no es gasto inmediato: Debe Maquinaria 1500 / Haber Efectivo o Cuentas por pagar.
- No confundir utilidad con efectivo. Una venta a crédito puede producir ingreso sin entrada de efectivo.
- No confundir pago de deuda con gasto nuevo.
- Los movimientos sincronizados desde Paquetería usan referencias PAQ- para evitar duplicados.

AL ACONSEJAR:
- Usa primero las cuentas reales disponibles en el catálogo de la app.
- Si falta información esencial (por ejemplo, si fue efectivo o crédito), pregunta antes de asumir.
- Para explicar un asiento, muestra: concepto, cuenta Debe, cuenta Haber, importe y efecto financiero.
- Distingue hechos tomados de los datos del usuario de recomendaciones generales.
- No inventes saldos, impuestos, tasas ni obligaciones legales.
- Para impuestos o decisiones legales, explica que las reglas dependen de jurisdicción y que puede ser necesario verificar con un profesional.
''';

  static Future<String> buildLiveContext() async {
    final d = await AppDatabase.instance.db;
    final company = await AppDatabase.instance.setting('company');
    final currency = await AppDatabase.instance.setting('currency');

    final accounts = await d.query('accounts', orderBy: 'code');
    final balances = await d.rawQuery('''
      SELECT a.code,a.name,a.type,
      COALESCE(SUM(CASE WHEN t.deleted_at IS NULL THEN j.debit-j.credit ELSE 0 END),0) AS net_debit_credit
      FROM accounts a
      LEFT JOIN journal_lines j ON j.account_id=a.id
      LEFT JOIN transactions t ON t.id=j.transaction_id
      GROUP BY a.id,a.code,a.name,a.type
      ORDER BY a.code
    ''');
    final recent = await d.rawQuery('''
      SELECT t.id,t.date,t.description,t.reference,t.cash_flow_class
      FROM transactions t
      WHERE t.deleted_at IS NULL
      ORDER BY t.date DESC,t.id DESC
      LIMIT 6
    ''');
    final debts = await d.query(
      'debts',
      where: 'paid=0',
      orderBy: 'due_date ASC',
      limit: 6,
    );
    final remittances =
        await d.query('remittances', orderBy: 'created_at DESC', limit: 5);

    final b = StringBuffer();
    b.writeln('DATOS FINANCIEROS ACTUALES DEL USUARIO');
    b.writeln('Empresa: $company');
    b.writeln('Moneda: $currency');
    b.writeln();
    b.writeln('CATÁLOGO DE CUENTAS:');
    for (final a in accounts) {
      b.writeln('- ${a['code']} · ${a['name']} · tipo ${a['type']}');
    }
    b.writeln();
    b.writeln('SALDOS NETOS (Debe - Haber) POR CUENTA:');
    for (final row in balances) {
      final amount = (row['net_debit_credit'] as num?)?.toDouble() ?? 0;
      if (amount.abs() < 0.005) continue;
      b.writeln(
        '- ${row['code']} · ${row['name']}: ${amount.toStringAsFixed(2)}',
      );
    }
    b.writeln();
    b.writeln('TRANSACCIONES RECIENTES:');
    for (final tx in recent) {
      final lines = await d.rawQuery('''
        SELECT a.code,a.name,j.debit,j.credit
        FROM journal_lines j
        JOIN accounts a ON a.id=j.account_id
        WHERE j.transaction_id=?
        ORDER BY j.id
      ''', [tx['id']]);
      b.writeln(
        '- ${tx['date']} · ${tx['description']} · ref ${tx['reference'] ?? ''}',
      );
      for (final l in lines) {
        b.writeln(
          '  ${l['code']} ${l['name']} | Debe ${l['debit']} | Haber ${l['credit']}',
        );
      }
    }
    if (debts.isNotEmpty) {
      b.writeln();
      b.writeln('DEUDAS / COBROS PENDIENTES:');
      for (final row in debts) {
        b.writeln(
          '- ${row['kind']} · ${row['name']} · ${row['amount']} · vence ${row['due_date']}',
        );
      }
    }
    if (remittances.isNotEmpty) {
      b.writeln();
      b.writeln('REMESAS RECIENTES:');
      for (final row in remittances) {
        b.writeln(
          '- ${row['client']} · principal ${row['principal']} · esperado ${row['expected']} · ${row['status']}',
        );
      }
    }

    final paq = await AppDatabase.instance.setting('paqueteria_snapshot');
    if (paq.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(paq);
        if (decoded is Map) {
          final summary = decoded['summary'];
          b.writeln();
          b.writeln('RESUMEN SINCRONIZADO DESDE PAQUETERÍA:');
          b.writeln(jsonEncode(summary ?? const {}));
        }
      } catch (_) {}
    }
    return b.toString();
  }

  static String conversation(List<FinanceAiMessage> messages) {
    final selected =
        messages.length > 6 ? messages.sublist(messages.length - 6) : messages;
    return selected
        .where((m) => m.text.trim().isNotEmpty)
        .map((m) =>
            '${m.role == 'assistant' ? 'ASISTENTE' : 'USUARIO'}: ${m.text.trim()}')
        .join('\n');
  }

  static Future<String> prompt({
    required String question,
    required List<FinanceAiMessage> history,
    required bool includeLiveData,
  }) async {
    final live = includeLiveData ? await buildLiveContext() : '';
    final retrieved = FinanceKnowledge.retrieve(
      '$question\n${conversation(history)}',
      topK: 6,
    );
    return '''
Eres el Chat IA de Finanzas Definitiva: un asistente de contabilidad y administración financiera para un pequeño negocio.

REGLAS CRÍTICAS:
- No inventes datos financieros.
- Distingue correctamente quién debe a quién.
- Si falta información esencial para un asiento, pregunta antes de proponerlo.
- Todo asiento válido debe cuadrar.

CONOCIMIENTO LOCAL RECUPERADO POR EMBEDDINGS:
$retrieved

${includeLiveData ? live : 'NO SE INCLUYERON DATOS FINANCIEROS EN ESTA CONSULTA.'}

CONVERSACIÓN RECIENTE:
${conversation(history)}

PREGUNTA DEL USUARIO:
$question

Responde en el idioma del usuario. Sé práctico y claro. Cuando el usuario pregunte cómo registrar una operación, usa el catálogo de cuentas real y presenta un asiento Debe/Haber. Si faltan datos importantes, pregunta antes de afirmar un asiento definitivo. No digas que guardaste o modificaste datos: este chat aconseja; la creación real se confirma en las pantallas de Finanzas.
''';
  }
}

class FinanceAiChatPage extends StatefulWidget {
  final VoidCallback onChanged;
  const FinanceAiChatPage({super.key, required this.onChanged});

  @override
  State<FinanceAiChatPage> createState() => _FinanceAiChatPageState();
}

class _FinanceAiChatPageState extends State<FinanceAiChatPage> {
  final input = TextEditingController();
  List<FinanceAiSession> sessions = [];
  String? activeId;
  String provider = 'gemini';
  String responseMode = 'normal';
  bool useFinanceData = true;
  bool busy = false;
  bool autoSpanish = false;
  bool aiControlsExpanded = true;
  Timer? _timer;
  DateTime? _started;
  double _seconds = 0;

  FinanceAiSession? get active {
    if (activeId == null) return null;
    for (final s in sessions) {
      if (s.id == activeId) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(FinanceAiService.releaseProvider(provider));
    input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final loaded = await FinanceAiChatStore.load();
    if (loaded.isEmpty) loaded.add(FinanceAiSession.empty());
    if (!mounted) return;
    setState(() {
      sessions = loaded;
      activeId = loaded.first.id;
      provider = p.getString('finance_ai_provider') ?? 'gemini';
      responseMode = p.getString('finance_ai_response_mode') ?? 'normal';
      useFinanceData = p.getBool('finance_ai_use_data') ?? true;
      autoSpanish = p.getBool('finance_ai_auto_es') ?? false;
    });
  }

  Future<void> _save() => FinanceAiChatStore.saveAll(sessions);

  void _put(FinanceAiSession session) {
    final i = sessions.indexWhere((e) => e.id == session.id);
    if (i >= 0) {
      sessions[i] = session;
    } else {
      sessions.insert(0, session);
    }
  }

  Future<void> _newChat() async {
    final s = FinanceAiSession.empty();
    setState(() {
      sessions.insert(0, s);
      activeId = s.id;
    });
    await _save();
  }

  Future<void> _deleteChat(FinanceAiSession session) async {
    setState(() {
      sessions.removeWhere((e) => e.id == session.id);
      if (sessions.isEmpty) sessions.add(FinanceAiSession.empty());
      if (activeId == session.id) activeId = sessions.first.id;
    });
    await _save();
  }

  Future<void> _showHistory() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'Chats',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              for (final s in sessions)
                ListTile(
                  leading: Icon(
                    s.id == activeId
                        ? Icons.chat_bubble
                        : Icons.chat_bubble_outline,
                  ),
                  title: Text(s.title),
                  subtitle: Text(
                    '${s.messages.length} mensajes',
                  ),
                  onTap: () {
                    setState(() => activeId = s.id);
                    Navigator.pop(sheetContext);
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await _deleteChat(s);
                      if (context.mounted) setSheet(() {});
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _startTimer() {
    _timer?.cancel();
    _started = DateTime.now();
    _seconds = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _started == null) return;
      setState(() {
        _seconds =
            DateTime.now().difference(_started!).inMilliseconds / 1000.0;
      });
    });
  }

  double _stopTimer() {
    final start = _started;
    if (start != null) {
      _seconds = DateTime.now().difference(start).inMilliseconds / 1000.0;
    }
    _timer?.cancel();
    _timer = null;
    _started = null;
    return _seconds;
  }

  Future<void> _send() async {
    final question = input.text.trim();
    final current = active;
    if (question.isEmpty || busy || current == null) return;
    input.clear();

    final historyBefore = List<FinanceAiMessage>.from(current.messages);
    final user = FinanceAiMessage(
      role: 'user',
      text: question,
      createdAt: DateTime.now(),
    );
    final placeholder = FinanceAiMessage(
      role: 'assistant',
      text: 'Thinking…',
      createdAt: DateTime.now(),
    );
    var updated = current.copyWith(
      title: current.messages.isEmpty
          ? FinanceAiSession.titleFrom(question)
          : current.title,
      updatedAt: DateTime.now(),
      messages: [...current.messages, user, placeholder],
    );
    setState(() {
      _put(updated);
      busy = true;
    });
    await _save();
    _startTimer();

    try {
      final prompt = await FinanceAiContext.prompt(
        question: question,
        history: historyBefore,
        includeLiveData: useFinanceData,
      );
      final localDevice = provider == 'device';
      final safePrompt = localDevice && prompt.length > 6500
          ? prompt.substring(0, 6500)
          : prompt;
      final result = await FinanceAiService.askConfigured(
        prompt: safePrompt,
        providerOverride: provider,
        responseMode: localDevice ? 'fast' : responseMode,
        onPartial: localDevice
            ? null
            : (partial) {
                if (!mounted || partial.trim().isEmpty) return;
                final cur = active;
                if (cur == null || cur.messages.isEmpty) return;
                final m = List<FinanceAiMessage>.from(cur.messages);
                m[m.length - 1] = m.last.copyWith(text: partial);
                setState(() => _put(cur.copyWith(
                      updatedAt: DateTime.now(),
                      messages: m,
                    )));
              },
      );
      final cur = active;
      if (cur != null && cur.messages.isNotEmpty) {
        final m = List<FinanceAiMessage>.from(cur.messages);
        m[m.length - 1] = m.last.copyWith(text: result);
        updated = cur.copyWith(updatedAt: DateTime.now(), messages: m);
        if (mounted) setState(() => _put(updated));
      }
    } catch (e) {
      final cur = active;
      if (cur != null && cur.messages.isNotEmpty) {
        final m = List<FinanceAiMessage>.from(cur.messages);
        m[m.length - 1] = m.last.copyWith(
          text: 'No pude responder: ${FinanceAiService.userFacingError(e)}',
        );
        updated = cur.copyWith(updatedAt: DateTime.now(), messages: m);
        if (mounted) setState(() => _put(updated));
      }
    } finally {
      final elapsed = _stopTimer();
      final cur = active;
      if (cur != null && cur.messages.isNotEmpty) {
        final m = List<FinanceAiMessage>.from(cur.messages);
        if (m.last.role == 'assistant') {
          m[m.length - 1] = m.last.copyWith(responseSeconds: elapsed);
          _put(cur.copyWith(updatedAt: DateTime.now(), messages: m));
        }
      }
      await _save();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _changeProvider(String? value) async {
    if (value == null || busy) return;
    final previous = provider;
    final p = await SharedPreferences.getInstance();
    await p.setString('finance_ai_provider', value);
    if ((previous == 'device' || previous == 'manager') &&
        previous != value) {
      await FinanceAiService.releaseProvider(previous);
    }
    if (mounted) setState(() => provider = value);
  }

  Future<void> _changeMode(Set<String> values) async {
    if (values.isEmpty || busy) return;
    final v = values.first;
    final p = await SharedPreferences.getInstance();
    await p.setString('finance_ai_response_mode', v);
    if (mounted) setState(() => responseMode = v);
  }

  Future<void> _toggleData(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('finance_ai_use_data', value);
    if (mounted) setState(() => useFinanceData = value);
  }

  Future<void> _toggleAutoSpanish(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('finance_ai_auto_es', value);
    if (mounted) setState(() => autoSpanish = value);
  }

  Future<String> _providerLabel(String value) async {
    final p = await SharedPreferences.getInstance();
    switch (value) {
      case 'openai':
        return 'Online · ${p.getString('finance_ai_openai_model') ?? 'gpt-4.1-mini'}';
      case 'local':
        return 'Local · ${p.getString('finance_ai_local_model') ?? 'llama3.2:3b'}';
      case 'manager':
        return 'Local AI Manager · shared';
      case 'device':
        final path = p.getString('finance_ai_device_model_path') ?? '';
        return path.isEmpty ? 'GGUF · sin modelo' : 'GGUF · ${path.split('/').last}';
      default:
        return 'Gemini · ${p.getString('finance_ai_gemini_model') ?? 'gemini-2.5-flash'}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = active?.messages ?? const <FinanceAiMessage>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat IA'),
        actions: [
          IconButton(
            tooltip: 'Nuevo chat',
            onPressed: busy ? null : _newChat,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          IconButton(
            tooltip: 'Historial',
            onPressed: _showHistory,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Ajustes de IA',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FinanceAiSettingsPage(),
                ),
              );
              final p = await SharedPreferences.getInstance();
              if (mounted) {
                setState(() => provider =
                    p.getString('finance_ai_provider') ?? provider);
              }
            },
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: InkWell(
              onTap: busy
                  ? null
                  : () => setState(
                        () => aiControlsExpanded = !aiControlsExpanded,
                      ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                child: Row(
                  children: [
                    const Icon(Icons.tune, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        aiControlsExpanded
                            ? 'Ocultar controles de IA'
                            : 'Mostrar controles de IA',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Icon(
                      aiControlsExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 30,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (aiControlsExpanded) ...[
            FutureBuilder<String>(
              future: _providerLabel(provider),
              builder: (context, snapshot) => Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: DropdownButtonFormField<String>(
                  value: provider,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Modelo / IA',
                    helperText: snapshot.data ?? '',
                    border: const OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
                    DropdownMenuItem(
                      value: 'openai',
                      child: Text('LLM online compatible'),
                    ),
                    DropdownMenuItem(
                      value: 'local',
                      child: Text('LLM local / Ollama'),
                    ),
                    DropdownMenuItem(
                      value: 'manager',
                      child: Text('Local AI Manager'),
                    ),
                    DropdownMenuItem(
                      value: 'device',
                      child: Text('GGUF en este teléfono'),
                    ),
                  ],
                  onChanged: busy ? null : _changeProvider,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'fast', label: Text('Fast')),
                  ButtonSegment(value: 'normal', label: Text('Normal')),
                  ButtonSegment(value: 'deep', label: Text('Deep')),
                ],
                selected: {responseMode},
                onSelectionChanged: busy ? null : _changeMode,
              ),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Usar mis finanzas'),
              subtitle: Text(
                useFinanceData
                    ? 'La IA recibe el catálogo, saldos, asientos recientes, pendientes y resumen de Paquetería.'
                    : 'La IA responde con la base contable, sin leer tus cifras actuales.',
              ),
              value: useFinanceData,
              onChanged: busy ? null : _toggleData,
            ),
          ],
          const Divider(height: 1),
          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Text(
                        'Pregúntame cómo registrar una operación, cómo crear un asiento o cómo van tus finanzas.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final m = messages[messages.length - 1 - index];
                      final isLatest = index == 0 && m.role == 'assistant';
                      return FinanceAiBubble(
                        key: ValueKey(
                          '${m.createdAt.microsecondsSinceEpoch}:${m.role}:${m.text.length}',
                        ),
                        message: m,
                        provider: provider,
                        autoSpanish: autoSpanish,
                        onAutoSpanishChanged: _toggleAutoSpanish,
                        liveSeconds:
                            busy && isLatest ? _seconds : null,
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Pregunta a Finanzas IA…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: busy ? FinanceAiService.cancelCurrent : _send,
                    icon: Icon(
                      busy ? Icons.stop_rounded : Icons.send_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FinanceAiBubble extends StatefulWidget {
  const FinanceAiBubble({
    super.key,
    required this.message,
    required this.provider,
    required this.autoSpanish,
    required this.onAutoSpanishChanged,
    this.liveSeconds,
  });

  final FinanceAiMessage message;
  final String provider;
  final bool autoSpanish;
  final Future<void> Function(bool value) onAutoSpanishChanged;
  final double? liveSeconds;

  @override
  State<FinanceAiBubble> createState() => _FinanceAiBubbleState();
}

class _FinanceAiBubbleState extends State<FinanceAiBubble> {
  String? spanish;
  bool showSpanish = false;
  bool translating = false;
  Timer? autoTimer;

  bool get mine => widget.message.role == 'user';
  bool get canTranslate =>
      !mine &&
      widget.message.text.trim().isNotEmpty &&
      widget.message.text.trim().toLowerCase() != 'thinking…';

  @override
  void initState() {
    super.initState();
    _scheduleAuto();
  }

  @override
  void didUpdateWidget(covariant FinanceAiBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.text != widget.message.text) {
      spanish = null;
      showSpanish = false;
      translating = false;
      autoTimer?.cancel();
      _scheduleAuto();
    } else if (!oldWidget.autoSpanish && widget.autoSpanish) {
      _scheduleAuto();
    }
  }

  @override
  void dispose() {
    autoTimer?.cancel();
    super.dispose();
  }

  void _scheduleAuto() {
    if (!widget.autoSpanish || !canTranslate || widget.liveSeconds != null) return;
    autoTimer?.cancel();
    autoTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && widget.autoSpanish && canTranslate) _translate(show: true);
    });
  }

  Future<void> _translate({required bool show}) async {
    if (!canTranslate || translating) return;
    if (spanish != null) {
      if (mounted) setState(() => showSpanish = show);
      return;
    }
    setState(() {
      translating = true;
      showSpanish = show;
    });
    try {
      final result = await FinanceAiService.askConfigured(
        providerOverride: widget.provider,
        responseMode: 'fast',
        prompt:
            'Traduce al español el siguiente texto. Conserva cifras, códigos de cuentas y formato. Devuelve solamente la traducción:\n\n${widget.message.text}',
      );
      if (!mounted) return;
      setState(() {
        spanish = result;
        showSpanish = show;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('No pude traducir: ${FinanceAiService.userFacingError(e)}'),
          ),
        );
        setState(() => showSpanish = false);
      }
    } finally {
      if (mounted) setState(() => translating = false);
    }
  }

  Future<void> _copy() async {
    final text = (showSpanish && spanish != null ? spanish! : widget.message.text)
        .trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copiado al portapapeles.'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayed = showSpanish && spanish != null
        ? spanish!
        : widget.message.text;
    final seconds = widget.liveSeconds ?? widget.message.responseSeconds;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .86),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mine ? 'Tú' : 'Finanzas IA',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            SelectableText(
              translating && showSpanish && spanish == null
                  ? 'Traduciendo…'
                  : displayed,
            ),
            if (!mine && canTranslate) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: translating
                        ? null
                        : () => showSpanish
                            ? setState(() => showSpanish = false)
                            : _translate(show: true),
                    icon: const Icon(Icons.translate, size: 17),
                    label: Text(showSpanish ? 'Original' : 'ES'),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        widget.onAutoSpanishChanged(!widget.autoSpanish),
                    icon: Icon(
                      widget.autoSpanish
                          ? Icons.check_circle_outline
                          : Icons.autorenew_rounded,
                      size: 17,
                    ),
                    label:
                        Text(widget.autoSpanish ? 'Auto ES on' : 'Auto ES'),
                  ),
                  TextButton.icon(
                    onPressed: _copy,
                    icon: const Icon(Icons.copy_outlined, size: 17),
                    label: const Text('Copiar'),
                  ),
                ],
              ),
            ] else if (widget.message.text.trim().isNotEmpty) ...[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_outlined, size: 17),
                  label: const Text('Copiar'),
                ),
              ),
            ],
            if (seconds != null && !mine)
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${seconds.toStringAsFixed(1)} s',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
