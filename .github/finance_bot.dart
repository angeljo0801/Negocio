
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database.dart';
import 'finance_ai_service.dart';
import 'finance_knowledge.dart';
import 'finance_learning.dart';
import 'personal_finance.dart';
import 'models.dart';

class FinanceAssistantPage extends StatefulWidget {
  final VoidCallback onChanged;
  const FinanceAssistantPage({super.key, required this.onChanged});

  @override
  State<FinanceAssistantPage> createState() => _FinanceAssistantPageState();
}

class _FinanceAssistantPageState extends State<FinanceAssistantPage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final messages = <_BotMessage>[
    const _BotMessage(
      fromUser: false,
      text: 'Soy tu asistente financiero con IA. Dime una operación con tus palabras, por ejemplo: “Pagué \$45 de gasolina” o “Un cliente me pagó \$120”. Te explicaré el asiento y podrás crearlo después de revisarlo.',
    ),
  ];
  bool busy = false;
  Timer? _backgroundRefresh;
  static bool _globalCancelRequested = false;

  static const _assistantHistoryKey = 'finance_assistant_history_v2';
  static const _assistantBusyKey = 'finance_assistant_busy_v2';

  @override
  void initState() {
    super.initState();
    _ensureExtraAccounts();
    _loadAssistantMessages();
    _backgroundRefresh = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshBackgroundState(),
    );
  }

  @override
  void dispose() {
    // Keep AI work alive when leaving this screen. The configured model is
    // released by the manager/idle policy instead of navigation.
    _backgroundRefresh?.cancel();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _ensureExtraAccounts() async {
    await PersonalFinanceStore.ensureSchema();
    await FinanceLearningStore.ensureSchema();
    final d = await AppDatabase.instance.db;
    const rows = [
      ['4030', 'Ingresos por envíos y servicios', 'revenue', 'sales'],
      ['6060', 'Transporte / gasolina', 'expense', 'operating'],
      ['6070', 'Viajes / envíos', 'expense', 'operating'],
      ['6080', 'Comidas / viáticos', 'expense', 'operating'],
      ['6090', 'Otros gastos operativos', 'expense', 'operating'],
    ];
    for (final r in rows) {
      await d.rawInsert(
        'INSERT OR IGNORE INTO accounts(code,name,type,subtype) VALUES(?,?,?,?)',
        r,
      );
    }
  }

  String _norm(String value) {
    var s = value.toLowerCase().trim();
    const from = 'áéíóúüñ';
    const to = 'aeiouun';
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    return s;
  }

  bool _has(String s, List<String> words) => words.any(s.contains);

  double? _amount(String text) {
    final matches = RegExp(
      r'(?:usd\s*|\$\s*)?(\d{1,9}(?:[\.,]\d{1,2})?)',
      caseSensitive: false,
    ).allMatches(text);
    if (matches.isEmpty) return null;
    final raw = matches.first.group(1)?.replaceAll(',', '.');
    return double.tryParse(raw ?? '');
  }


  Future<String> _accountCatalog() async {
    final d = await AppDatabase.instance.db;
    final rows = await d.query(
      'accounts',
      columns: ['code', 'name', 'type', 'subtype'],
      orderBy: 'code ASC',
    );
    final business = rows
        .map(
          (r) =>
              r['code'].toString() +
              '|' +
              r['name'].toString() +
              '|' +
              r['type'].toString() +
              '|' +
              (r['subtype'] == null ? '' : r['subtype'].toString()) +
              '|business',
        )
        .join('\n');
    final personal = await PersonalFinanceStore.catalogText();
    return 'CUENTAS NEGOCIO:\n$business\n\nCUENTAS PERSONALES:\n$personal';
  }

  Future<void> _loadAssistantMessages() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_assistantHistoryKey);
    final storedBusy = p.getBool(_assistantBusyKey) ?? false;
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final loaded = decoded
              .whereType<Map>()
              .map((e) => _BotMessage.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          if (loaded.isNotEmpty) {
            messages
              ..clear()
              ..addAll(loaded);
          }
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() => busy = storedBusy);
      _scrollDown();
    } else {
      busy = storedBusy;
    }
  }

  Future<void> _saveAssistantMessages({bool? isBusy}) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _assistantHistoryKey,
      jsonEncode(messages.map((e) => e.toJson()).toList()),
    );
    if (isBusy != null) {
      await p.setBool(_assistantBusyKey, isBusy);
    }
  }

  Future<void> _refreshBackgroundState() async {
    if (busy) return;
    final p = await SharedPreferences.getInstance();
    final storedBusy = p.getBool(_assistantBusyKey) ?? false;
    if (!storedBusy) return;
    await _loadAssistantMessages();
  }

  String _conversationContext() {
    final start = messages.length > 6 ? messages.length - 6 : 0;
    return messages
        .sublist(start)
        .map((m) => (m.fromUser ? 'USUARIO: ' : 'ASISTENTE: ') + m.text)
        .join('\n');
  }

  Map<String, dynamic> _decodeAiObject(String raw) {
    var value = raw.trim();
    final first = value.indexOf('{');
    final last = value.lastIndexOf('}');
    if (first >= 0 && last > first) {
      value = value.substring(first, last + 1);
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return decoded.map((key, item) => MapEntry(key.toString(), item));
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _verifyAiDecision({
    required String original,
    required String catalog,
    required String history,
    required String knowledge,
    required Map<String, dynamic> draft,
  }) async {
    final prompt = '''
Eres el verificador contable final de Finanzas Definitiva.

Tu trabajo NO es repetir la primera respuesta. Debes comparar cuidadosamente:
1. el mensaje original del usuario,
2. el historial reciente,
3. la propuesta o decisión preliminar,
4. el catálogo real de cuentas.

OBJETIVO:
Decidir si la interpretación preliminar realmente corresponde al lenguaje natural del usuario y si el asiento contable es correcto antes de enseñárselo.

REGLAS OBLIGATORIAS:
- No inventes hechos que el usuario no haya dicho.
- No cambies quién debe a quién.
- "Me deben" y "yo debo" son situaciones opuestas.
- Si falta el origen de una deuda, la forma de pago o cualquier dato esencial para elegir cuentas correctamente, usa action "clarify".
- Solo usa action "proposal" si el mensaje y el historial justifican claramente una cuenta Debe, una cuenta Haber y un importe.
- Debe y Haber deben representar correctamente el efecto económico.
- Usa únicamente códigos existentes en el catálogo.
- Si la propuesta preliminar es incorrecta pero puedes corregirla con certeza usando lo que el usuario ya dijo, devuelve la propuesta corregida.
- Si la consulta solo pide explicación o consejo, usa action "answer".
- No guardes nada.
- Tu salida será la decisión FINAL que verá el usuario.
- Finanzas Definitiva tiene dos ámbitos separados: Personal y Negocio.
- Paquetería pertenece únicamente a Negocio y nunca se registra automáticamente en Personal.
- Si algo es personal y no está claro si se pagó con dinero personal o del negocio, usa clarify.
- Usa códigos Pxxxx solo para Personal y códigos numéricos normales para Negocio.
- Si la operación afecta ambos ámbitos, valida también linkedScope y su segunda pareja de cuentas.
- learnRule solo puede contener una regla GENERAL reutilizable, sin nombres, importes, fechas ni datos privados.

Devuelve SOLO JSON válido:
{"reply":"texto breve y claro","action":"proposal|clarify|answer","scope":"business|personal|unknown","description":"","amount":0,"debitCode":"","creditCode":"","cashClass":"operating|investing|financing|noncash","linkedScope":"none|business|personal","linkedDescription":"","linkedDebitCode":"","linkedCreditCode":"","learnRule":"","learnTags":"","learnScope":"business|personal|both"}

CONOCIMIENTO LOCAL RECUPERADO:
$knowledge

CATÁLOGO:
$catalog

HISTORIAL:
$history

MENSAJE ORIGINAL:
$original

DECISIÓN PRELIMINAR:
${jsonEncode(draft)}
''';

    final raw = await FinanceAiService.askConfigured(
      prompt: prompt,
      responseMode: 'fast',
    );
    final verified = _decodeAiObject(raw);
    if (verified.isEmpty) {
      throw Exception(
        'La segunda revisión de IA no devolvió una decisión válida.',
      );
    }
    return verified;
  }

  double _aiAmount(dynamic value) {
    if (value is num) return value.toDouble();
    final raw = value == null ? '' : value.toString().trim().replaceAll(',', '.');
    return double.tryParse(raw) ?? 0;
  }

  String _cashClass(dynamic value) {
    final candidate = value == null ? '' : value.toString().trim().toLowerCase();
    const allowed = {'operating', 'investing', 'financing', 'noncash'};
    return allowed.contains(candidate) ? candidate : 'operating';
  }

  Future<String?> _accountName(String scope, String code) async {
    if (scope == 'personal') {
      final row = await PersonalFinanceStore.accountByCode(code);
      return row?['name']?.toString();
    }
    final d = await AppDatabase.instance.db;
    final rows = await d.query(
      'accounts',
      columns: ['name'],
      where: 'code=?',
      whereArgs: [code],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['name']?.toString();
  }

  Future<_BotReply> _answerWithAi(String original) async {
    final catalog = await _accountCatalog();
    final history = _conversationContext();
    final baseKnowledge = FinanceKnowledge.retrieve(
      '$original\n$history',
      topK: 6,
    );
    final learnedKnowledge = await FinanceLearningStore.retrieve(
      '$original\n$history',
      topK: 4,
    );
    final knowledge = [
      baseKnowledge,
      if (learnedKnowledge.isNotEmpty) learnedKnowledge,
    ].join('\n\n');

    final prompt = '''
Eres el intérprete inteligente del Asistente financiero de Finanzas Definitiva.
Entiende lenguaje natural en español o inglés, incluso frases coloquiales, incompletas o con errores.
Decide si el usuario hace una pregunta, describe una operación contable o necesita una aclaración.

REGLAS CRÍTICAS:
- Nunca guardes nada. Solo explica, pregunta o propone; el usuario confirma después.
- No inventes datos. Usa el historial para respuestas cortas.
- Si falta un dato que cambia las cuentas, usa action "clarify" y haz UNA pregunta concreta.
- Usa action "proposal" únicamente con importe válido, una cuenta Debe y una Haber justificadas por el mensaje.
- Usa solo códigos del catálogo. No inviertas quién debe a quién.
- Si la operación requiere más de dos líneas, explícalo y no fuerces un asiento incorrecto.
- Finanzas Definitiva tiene dos ámbitos separados: Personal y Negocio.
- Paquetería pertenece SIEMPRE a Negocio; nunca la pases automáticamente a Personal.
- Si el usuario confirma que una compra es personal pero no dice si salió de dinero personal o del negocio, pregunta la fuente de fondos.
- Usa códigos Pxxxx solo para Personal y códigos numéricos normales para Negocio.
- Si una operación afecta ambos ámbitos, usa linkedScope y una segunda pareja de cuentas.
- Puedes proponer learnRule solo si descubriste una regla GENERAL reutilizable; nunca incluyas nombres, importes, fechas ni datos privados.

CONOCIMIENTO LOCAL RECUPERADO POR EMBEDDINGS:
$knowledge

Devuelve SOLO un objeto JSON válido, sin texto extra, con esta forma:
{"reply":"texto breve y claro","action":"proposal|clarify|answer","scope":"business|personal|unknown","description":"","amount":0,"debitCode":"","creditCode":"","cashClass":"operating|investing|financing|noncash","linkedScope":"none|business|personal","linkedDescription":"","linkedDebitCode":"","linkedCreditCode":"","learnRule":"","learnTags":"","learnScope":"business|personal|both"}

CATÁLOGO DE CUENTAS:
$catalog

HISTORIAL RECIENTE:
$history

MENSAJE ACTUAL:
$original
''';

    final raw = await FinanceAiService.askConfigured(
      prompt: prompt,
      responseMode: 'fast',
    );
    final draft = _decodeAiObject(raw);

    if (draft.isEmpty) {
      final plain = raw.trim();
      if (plain.isEmpty) {
        throw Exception('La IA no devolvió una respuesta.');
      }
      return _BotReply(plain);
    }

    // Mandatory second AI pass. Nothing from the first interpretation is shown
    // until the verifier compares it with the user's message, history and the
    // real account catalog.
    final obj = await _verifyAiDecision(
      original: original,
      catalog: catalog,
      history: history,
      knowledge: knowledge,
      draft: draft,
    );

    final reply = (obj['reply'] ?? '').toString().trim();
    final action = (obj['action'] ?? 'answer').toString().trim().toLowerCase();
    final scope = (obj['scope'] ?? 'unknown').toString().trim().toLowerCase();
    final learnRule = (obj['learnRule'] ?? '').toString().trim();
    if (learnRule.isNotEmpty) {
      await FinanceLearningStore.considerCandidate(
        text: learnRule,
        tags: (obj['learnTags'] ?? '').toString(),
        scope: (obj['learnScope'] ?? 'both').toString(),
      );
    }
    final requestText = _norm('$original $history');
    final explicitlyWantsEntry = _has(requestText, [
      'crea el asiento',
      'crear el asiento',
      'creame el asiento',
      'haz el asiento',
      'hacer el asiento',
      'registra el asiento',
      'registrar el asiento',
      'propon el asiento',
      'proponer el asiento',
    ]);

    if (explicitlyWantsEntry && action == 'answer') {
      return const _BotReply(
        'Antes de mostrarte un asiento necesito confirmar los datos que determinan el Debe y el Haber. Dime qué originó la operación y si se pagó, se cobró o quedó pendiente.',
      );
    }

    if (action != 'proposal') {
      return _BotReply(
        reply.isEmpty
            ? 'Entendí el mensaje, pero necesito un poco más de información.'
            : reply,
      );
    }

    final amount = _aiAmount(obj['amount']);
    final debitCode = (obj['debitCode'] ?? '').toString().trim();
    final creditCode = (obj['creditCode'] ?? '').toString().trim();
    final description = (obj['description'] ?? '').toString().trim();

    if (amount <= 0 ||
        debitCode.isEmpty ||
        creditCode.isEmpty ||
        debitCode == creditCode) {
      return _BotReply(
        reply.isEmpty
            ? 'Entendí la operación, pero necesito confirmar un dato antes de proponerte el asiento.'
            : reply,
      );
    }

    if (scope != 'business' && scope != 'personal') {
      return const _BotReply(
        'Antes de proponerte el asiento necesito saber si esta operación pertenece a tus finanzas personales o a las del negocio.',
      );
    }

    final debitName = await _accountName(scope, debitCode);
    final creditName = await _accountName(scope, creditCode);
    if (debitName == null || creditName == null) {
      return _BotReply(
        (reply.isEmpty ? 'Entendí la operación.' : reply) +
            '\n\nNo preparé el asiento porque una de las cuentas no existe en el catálogo del ámbito seleccionado.',
      );
    }

    final linkedScope =
        (obj['linkedScope'] ?? 'none').toString().trim().toLowerCase();
    final linkedDebitCode =
        (obj['linkedDebitCode'] ?? '').toString().trim();
    final linkedCreditCode =
        (obj['linkedCreditCode'] ?? '').toString().trim();
    String linkedDebitName = '';
    String linkedCreditName = '';
    if (linkedScope == 'business' || linkedScope == 'personal') {
      if (linkedScope == scope ||
          linkedDebitCode.isEmpty ||
          linkedCreditCode.isEmpty ||
          linkedDebitCode == linkedCreditCode) {
        return const _BotReply(
          'La operación afecta Personal y Negocio, pero necesito aclarar cómo se movió el dinero entre ambos antes de crear los asientos vinculados.',
        );
      }
      linkedDebitName =
          await _accountName(linkedScope, linkedDebitCode) ?? '';
      linkedCreditName =
          await _accountName(linkedScope, linkedCreditCode) ?? '';
      if (linkedDebitName.isEmpty || linkedCreditName.isEmpty) {
        return const _BotReply(
          'La operación afecta Personal y Negocio, pero una de las cuentas vinculadas no existe. Necesito revisar la propuesta.',
        );
      }
    }

    return _BotReply(
      reply.isEmpty ? 'La propuesta pasó la revisión final de la IA.' : reply,
      proposal: _BotProposal(
        scope: scope,
        description:
            description.isEmpty ? 'Asiento sugerido por IA' : description,
        amount: amount,
        debitCode: debitCode,
        debitName: debitName,
        creditCode: creditCode,
        creditName: creditName,
        cashClass: _cashClass(obj['cashClass']),
        linkedScope: linkedScope,
        linkedDescription:
            (obj['linkedDescription'] ?? '').toString().trim(),
        linkedDebitCode: linkedDebitCode,
        linkedDebitName: linkedDebitName,
        linkedCreditCode: linkedCreditCode,
        linkedCreditName: linkedCreditName,
      ),
    );
  }

  Future<_BotReply> _answer(String original) async {
    final normalized = _norm(original);
    final amount = _amount(original);

    if (_has(normalized, [
      'quiero agregar conocimiento',
      'quiero anadir conocimiento',
      'agregar conocimiento',
      'anadir conocimiento',
    ])) {
      return const _BotReply(
        'Claro. Puedes agregar una regla o conocimiento a la base financiera y elegir si aplica a Personal, Negocio o Ambos.',
        knowledgeAction: true,
      );
    }

    // Deterministic guard for debt direction. A bare statement that the user
    // owes someone does not tell us whether cash was borrowed or whether a
    // purchase/expense is still unpaid, so no journal entry is safe yet.
    final userOwesSomeone = amount != null &&
        _has(normalized, [
          'le debo ',
          'yo debo ',
          'debo a ',
          'debo pagarle',
          'tengo que pagarle',
          'tengo una deuda con',
        ]);
    final originAlreadyClear = _has(normalized, [
      'me presto',
      'me prestaron',
      'prestamo',
      'compre',
      'compra',
      'mercancia',
      'inventario',
      'gasolina',
      'alquiler',
      'renta',
      'servicio',
      'factura',
      'gasto',
      'equipo',
      'maquinaria',
    ]);

    if (userOwesSomeone && !originAlreadyClear) {
      return _BotReply(
        'Entiendo que debes ${amount.toStringAsFixed(2)}, pero necesito saber qué originó esa deuda antes de proponerte un asiento. ¿Esa persona te prestó el dinero y lo recibiste, o le debes por una compra o gasto que todavía no has pagado?',
      );
    }

    final someoneOwesUser = amount != null &&
        _has(normalized, [
          'me deben ',
          'me debe ',
          'me tienen que pagar',
          'tienen que pagarme',
        ]);
    if (someoneOwesUser && !originAlreadyClear) {
      return _BotReply(
        'Entiendo que te deben ${amount.toStringAsFixed(2)}, pero necesito saber qué originó ese derecho de cobro antes de proponerte un asiento. ¿Fue una venta a crédito, dinero que tú prestaste, una compra que pagaste por esa persona u otra cosa?',
      );
    }

    final historyNorm = _norm(_conversationContext());
    final saysPersonal = _has(normalized, [
      'es personal',
      'fue personal',
      'para mi',
      'para mí',
      'gasto personal',
      'compra personal',
    ]);
    final sourceKnown = _has('$normalized $historyNorm', [
      'dinero personal',
      'efectivo personal',
      'banco personal',
      'tarjeta personal',
      'cuenta personal',
      'dinero del negocio',
      'efectivo del negocio',
      'cuenta del negocio',
      'tarjeta del negocio',
    ]);
    if (saysPersonal && !sourceKnown) {
      return const _BotReply(
        'Perfecto, lo trataré como una operación personal. ¿La pagaste con tu dinero personal (efectivo, banco o tarjeta) o con dinero del negocio?',
      );
    }

    try {
      return await _answerWithAi(original);
    } catch (e) {
      if (_globalCancelRequested) {
        return const _BotReply('Respuesta detenida.');
      }
      final fallback = await _answerRules(original);
      final error = FinanceAiService.userFacingError(e);
      return _BotReply(
        fallback.text +
            '\n\nIA no disponible: ' +
            error +
            '\nUsé el intérprete local de respaldo para no dejarte sin respuesta.',
        proposal: fallback.proposal,
      );
    }
  }

  Future<_BotReply> _answerRules(String original) async {
    final s = _norm(original);
    final amount = _amount(original);

    if (_has(s, ['que es debe', 'que significa debe', 'debe y haber', 'que es haber'])) {
      return const _BotReply(
        'En un asiento, el Debe y el Haber son los dos lados de la contabilidad. Los activos y gastos normalmente aumentan por el Debe; los pasivos, patrimonio e ingresos normalmente aumentan por el Haber. La suma del Debe siempre tiene que ser igual a la suma del Haber.',
      );
    }

    if (_has(s, ['como crear un asiento', 'crear asiento', 'hacer un asiento']) && amount == null) {
      return const _BotReply(
        'Puedes hacerlo de dos maneras. Manualmente: Más → Libro diario profesional → Asiento. O escríbeme la operación aquí con el importe. Yo te propondré las cuentas, el Debe y el Haber y te dejaré crear el asiento con un botón.',
      );
    }

    if (_has(s, ['como agregar un gasto', 'como anadir un gasto', 'registrar gasto', 'meter un gasto']) && amount == null) {
      return const _BotReply(
        'Para un gasto sencillo puedes ir a Movimientos → Gasto, escoger la categoría, poner el importe y guardar. También puedes decírmelo aquí, por ejemplo: “Pagué \$35 de gasolina” o “Pagué \$900 de alquiler”, y te preparo el asiento.',
      );
    }

    if (_has(s, ['remesa', 'remesas']) && amount == null) {
      return const _BotReply(
        'Las remesas conviene registrarlas desde Plan → Remesas porque esa pantalla controla principal, comisión, pendiente y cobro. El libro diario se actualiza cuando registras y cuando cobras la remesa.',
      );
    }

    if (_has(s, ['le debo', 'yo debo', 'debo a ', 'tengo una deuda con']) &&
        amount != null &&
        !_has(s, ['me presto', 'me prestaron', 'prestamo', 'compre', 'compra', 'gasto', 'mercancia', 'inventario'])) {
      return _BotReply(
        'Entiendo que debes ${amount.toStringAsFixed(2)}, pero necesito saber el origen de la deuda. ¿Fue un préstamo que recibiste o una compra/gasto pendiente de pago?',
      );
    }

    if (_has(s, ['deuda', 'por pagar', 'me deben']) && amount == null) {
      return const _BotReply(
        'Para controlar una deuda por vencimiento usa Plan → Deudas. Ahí eliges “Yo debo pagar” o “Me deben pagar”. Si además quieres crear el asiento contable, dime qué originó la deuda y el importe; por ejemplo: “Compré \$400 de mercancía a crédito”.',
      );
    }

    if (amount == null || amount <= 0) {
      return const _BotReply(
        'Entiendo la idea, pero necesito un importe para proponerte un asiento. Escríbelo con el monto, por ejemplo: “Pagué \$60 de gasolina”, “Vendí \$250 en efectivo” o “Compré \$500 de mercancía a crédito”.',
      );
    }

    final onCredit = _has(s, ['a credito', 'fiado', 'por pagar', 'quede debiendo', 'debo pagar']);
    final creditCode = onCredit ? '2010' : '1010';
    final creditName = onCredit ? 'Cuentas por pagar' : 'Efectivo';

    if (_has(s, ['gasolina', 'combustible', 'taxi', 'uber', 'transporte'])) {
      return _proposal('Gasto de transporte / gasolina', amount, '6060', 'Transporte / gasolina', creditCode, creditName,
          onCredit ? 'Se reconoce el gasto ahora y queda una cuenta por pagar.' : 'El gasto aumenta por el Debe y el efectivo disminuye por el Haber.');
    }

    if (_has(s, ['vuelo', 'equipaje', 'hotel', 'hospedaje', 'viaje', 'envio por agencia'])) {
      return _proposal('Gasto de viaje / envío', amount, '6070', 'Viajes / envíos', creditCode, creditName,
          onCredit ? 'El costo queda pendiente de pago.' : 'Se registra como gasto operativo del viaje y salida de efectivo.');
    }

    if (_has(s, ['comida', 'almuerzo', 'cena', 'viatico', 'viaticos'])) {
      return _proposal('Comidas / viáticos', amount, '6080', 'Comidas / viáticos', creditCode, creditName, 'Se registra como gasto operativo.');
    }

    if (_has(s, ['salario', 'nomina', 'sueldo'])) {
      return _proposal('Pago de salarios', amount, '6010', 'Salarios', creditCode, creditName, 'Los salarios son un gasto operativo.');
    }

    if (_has(s, ['alquiler', 'renta del local', 'rent del local'])) {
      return _proposal('Pago de alquiler', amount, '6020', 'Alquiler', creditCode, creditName, 'El alquiler aumenta como gasto.');
    }

    if (_has(s, ['publicidad', 'anuncio', 'marketing'])) {
      return _proposal('Gasto de publicidad', amount, '6030', 'Publicidad', creditCode, creditName, 'La publicidad se reconoce como gasto operativo.');
    }

    if (_has(s, ['luz', 'agua', 'internet', 'telefono', 'servicio basico', 'electricidad'])) {
      return _proposal('Pago de servicios', amount, '6040', 'Servicios básicos', creditCode, creditName, 'Los servicios básicos se reconocen como gasto.');
    }

    if (_has(s, ['impuesto', 'tax'])) {
      return _proposal('Pago de impuestos', amount, '8010', 'Impuestos', creditCode, creditName, 'El impuesto aumenta como gasto y se reconoce la salida o deuda.');
    }

    if (_has(s, ['interes', 'intereses'])) {
      return _proposal('Pago de intereses', amount, '7010', 'Intereses', creditCode, creditName, 'Los intereses son gasto financiero.');
    }

    if (_has(s, ['compre mercancia', 'compre inventario', 'compra de mercancia', 'compra inventario', 'productos para vender', 'mercancia'])) {
      return _proposal('Compra de mercancía', amount, '1030', 'Inventario', creditCode, creditName,
          onCredit ? 'El inventario aumenta y nace una cuenta por pagar.' : 'El inventario aumenta y disminuye el efectivo.');
    }

    if (_has(s, ['maquinaria', 'equipo', 'computadora', 'laptop', 'activo fijo'])) {
      return _proposal('Compra de equipo / maquinaria', amount, '1500', 'Maquinaria', creditCode, creditName,
          onCredit ? 'Se reconoce el activo y una obligación pendiente.' : 'Se reconoce el activo y la salida de efectivo.',
          cashClass: onCredit ? 'noncash' : 'investing');
    }

    if (_has(s, ['cliente me pago', 'cliente pago', 'cobre al cliente', 'cobro de cliente', 'cobre una cuenta'])) {
      return _proposal('Cobro de cliente', amount, '1010', 'Efectivo', '1020', 'Cuentas por cobrar',
          'Entra efectivo y disminuye lo que el cliente debía.');
    }

    if (_has(s, ['pague proveedor', 'pague una deuda', 'pague cuenta por pagar', 'pago al proveedor'])) {
      return _proposal('Pago a proveedor', amount, '2010', 'Cuentas por pagar', '1010', 'Efectivo',
          'La deuda disminuye por el Debe y sale efectivo por el Haber.');
    }

    if (_has(s, ['recibi prestamo', 'prestamo recibido', 'me prestaron'])) {
      return _proposal('Préstamo recibido', amount, '1010', 'Efectivo', '2500', 'Préstamo bancario',
          'Aumenta el efectivo y también el pasivo por el préstamo.', cashClass: 'financing');
    }

    if (_has(s, ['pague prestamo', 'abono al prestamo', 'pago principal'])) {
      return _proposal('Pago de principal de préstamo', amount, '2500', 'Préstamo bancario', '1010', 'Efectivo',
          'Este asiento supone que todo el importe es principal. Si una parte es interés, registra esa parte por separado como gasto de intereses.',
          cashClass: 'financing');
    }

    if (_has(s, ['aporte', 'aporte de capital', 'puse dinero', 'inverti dinero en el negocio'])) {
      return _proposal('Aporte de capital', amount, '1010', 'Efectivo', '3010', 'Capital aportado',
          'Entra efectivo al negocio y aumenta el capital del propietario.', cashClass: 'financing');
    }

    if (_has(s, ['retiro', 'saque dinero', 'retire dinero', 'dinero para mi'])) {
      return _proposal('Retiro del propietario', amount, '3030', 'Dividendos / Retiros', '1010', 'Efectivo',
          'El retiro reduce el patrimonio disponible y el efectivo.', cashClass: 'financing');
    }

    if (_has(s, ['vendi', 'venta', 'cobre por envio', 'cobre envio', 'servicio de paqueteria', 'ingreso'])) {
      final creditSale = _has(s, ['a credito', 'me debe', 'por cobrar']);
      final service = _has(s, ['envio', 'paqueteria']);
      return _proposal(service ? 'Ingreso por envío / servicio' : 'Venta', amount,
          creditSale ? '1020' : '1010', creditSale ? 'Cuentas por cobrar' : 'Efectivo',
          service ? '4030' : '4010', service ? 'Ingresos por envíos y servicios' : 'Ventas',
          creditSale ? 'Se reconoce el ingreso y queda pendiente de cobro.' : 'Entra efectivo y se reconoce el ingreso.');
    }

    if (_has(s, ['gasto', 'pague', 'pago', 'compre'])) {
      return _proposal('Gasto operativo', amount, '6090', 'Otros gastos operativos', creditCode, creditName,
          'No identifiqué una categoría más específica, así que propongo Otros gastos operativos. Puedes cancelarlo y describirme el gasto con más detalle.');
    }

    return const _BotReply(
      'Puedo ayudarte mejor si describes qué ocurrió con el dinero. Por ejemplo: “Pagué \$40 de gasolina”, “Compré \$200 de mercancía a crédito”, “Vendí \$300 en efectivo” o “Un cliente me pagó \$150”.',
    );
  }

  _BotReply _proposal(
    String description,
    double amount,
    String debitCode,
    String debitName,
    String creditCode,
    String creditName,
    String explanation, {
    String cashClass = 'operating',
  }) {
    return _BotReply(
      explanation,
      proposal: _BotProposal(
        scope: 'business',
        description: description,
        amount: amount,
        debitCode: debitCode,
        debitName: debitName,
        creditCode: creditCode,
        creditName: creditName,
        cashClass: cashClass,
      ),
    );
  }

  Future<void> send([String? preset]) async {
    final text = (preset ?? input.text).trim();
    if (text.isEmpty || busy) return;
    input.clear();
    _globalCancelRequested = false;
    if (mounted) {
      setState(() {
        messages.add(_BotMessage(fromUser: true, text: text));
        busy = true;
      });
    } else {
      messages.add(_BotMessage(fromUser: true, text: text));
      busy = true;
    }
    await _saveAssistantMessages(isBusy: true);

    final reply = await _answer(text);
    final answer = _BotMessage(
      fromUser: false,
      text: reply.text,
      proposal: reply.proposal,
      knowledgeAction: reply.knowledgeAction,
    );
    messages.add(answer);
    busy = false;
    await _saveAssistantMessages(isBusy: false);
    if (mounted) {
      setState(() {});
      _scrollDown();
    }
  }

  Future<void> _stopGeneration() async {
    _globalCancelRequested = true;
    await FinanceAiService.cancelCurrent();
    busy = false;
    await _saveAssistantMessages(isBusy: false);
    if (mounted) setState(() {});
  }

  Future<void> _clearConversation() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Borrar conversación'),
        content: const Text(
          'Se borrará el historial de este Asistente financiero.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (busy) await _stopGeneration();
    messages
      ..clear()
      ..add(const _BotMessage(
        fromUser: false,
        text:
            'Soy tu asistente financiero con IA. Puedo trabajar con tus finanzas personales y las del negocio por separado.',
      ));
    await _saveAssistantMessages(isBusy: false);
    if (mounted) setState(() {});
  }

  Future<void> _showAddKnowledgeDialog() async {
    final title = TextEditingController();
    final body = TextEditingController();
    final tags = TextEditingController();
    var scope = 'both';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Agregar conocimiento'),
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
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tags,
                  decoration: const InputDecoration(
                    labelText: 'Etiquetas (opcional)',
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
    if (saved == true && body.text.trim().isNotEmpty) {
      await FinanceLearningStore.saveManual(
        title: title.text,
        text: body.text,
        tags: tags.text,
        scope: scope,
      );
      messages.add(const _BotMessage(
        fromUser: false,
        text:
            'Conocimiento agregado. Ya forma parte de la base que consulto para futuras respuestas.',
      ));
      await _saveAssistantMessages();
      if (mounted) setState(() {});
    }
    title.dispose();
    body.dispose();
    tags.dispose();
  }

  Future<void> createProposal(_BotProposal proposal) async {
    await _ensureExtraAccounts();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar asiento'),
        content: Text(
          'Ámbito: ${proposal.scope == 'personal' ? 'Personal' : 'Negocio'}\n${proposal.description}\n\nDebe: ${proposal.debitCode} · ${proposal.debitName}  \$${proposal.amount.toStringAsFixed(2)}\n'
          'Haber: ${proposal.creditCode} · ${proposal.creditName}  \$${proposal.amount.toStringAsFixed(2)}\n\n'
          'El bot no guardará nada hasta que confirmes.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Crear asiento')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final ref = 'BOT-${DateTime.now().millisecondsSinceEpoch}';

      Future<void> addBusiness(
        String description,
        String debitCode,
        String creditCode,
      ) async {
        final debitId = await AppDatabase.instance.accountId(debitCode);
        final creditId = await AppDatabase.instance.accountId(creditCode);
        await AppDatabase.instance.addTransaction(
          JournalTransaction(
            date: DateTime.now(),
            description: description,
            reference: ref,
            cashFlowClass: proposal.cashClass,
            lines: [
              JournalLine(accountId: debitId, debit: proposal.amount),
              JournalLine(accountId: creditId, credit: proposal.amount),
            ],
          ),
        );
      }

      if (proposal.scope == 'personal') {
        await PersonalFinanceStore.addTransaction(
          description: proposal.description,
          amount: proposal.amount,
          debitCode: proposal.debitCode,
          creditCode: proposal.creditCode,
          reference: ref,
        );
      } else {
        await addBusiness(
          proposal.description,
          proposal.debitCode,
          proposal.creditCode,
        );
      }

      if (proposal.linkedScope == 'personal') {
        await PersonalFinanceStore.addTransaction(
          description: proposal.linkedDescription.isEmpty
              ? 'Transferencia vinculada con Negocio'
              : proposal.linkedDescription,
          amount: proposal.amount,
          debitCode: proposal.linkedDebitCode,
          creditCode: proposal.linkedCreditCode,
          reference: ref,
        );
      } else if (proposal.linkedScope == 'business') {
        await addBusiness(
          proposal.linkedDescription.isEmpty
              ? 'Transferencia vinculada con Personal'
              : proposal.linkedDescription,
          proposal.linkedDebitCode,
          proposal.linkedCreditCode,
        );
      }
      widget.onChanged();
      if (!mounted) return;
      setState(() {
        messages.add(const _BotMessage(
          fromUser: false,
          text: 'Asiento creado correctamente en el ámbito correspondiente.',
        ));
      });
      await _saveAssistantMessages();
      _scrollDown();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No pude crear el asiento: $e')));
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Widget _entryRow(
    String side,
    String code,
    String name,
    double amount,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              side,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Text(
              '$code · $name',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _proposalCard(_BotProposal proposal) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Propuesta de asiento',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            proposal.scope == 'personal' ? 'PERSONAL' : 'NEGOCIO',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(proposal.description),
          const SizedBox(height: 6),
          Text(
            'Importe: \$${proposal.amount.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const Divider(height: 20),
          _entryRow(
            'DEBE',
            proposal.debitCode,
            proposal.debitName,
            proposal.amount,
          ),
          const Divider(height: 1),
          _entryRow(
            'HABER',
            proposal.creditCode,
            proposal.creditName,
            proposal.amount,
          ),
          if (proposal.linkedScope == 'personal' ||
              proposal.linkedScope == 'business') ...[
            const Divider(height: 20),
            Text(
              'Movimiento vinculado · ${proposal.linkedScope == 'personal' ? 'PERSONAL' : 'NEGOCIO'}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            _entryRow(
              'DEBE',
              proposal.linkedDebitCode,
              proposal.linkedDebitName,
              proposal.amount,
            ),
            _entryRow(
              'HABER',
              proposal.linkedCreditCode,
              proposal.linkedCreditName,
              proposal.amount,
            ),
          ],
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => createProposal(proposal),
            icon: const Icon(Icons.post_add),
            label: const Text('Revisar y crear asiento'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const suggestions = [
      '¿Cómo creo un asiento?',
      '¿Cómo añado un gasto?',
      'Pagué \$40 de gasolina',
      'Compré \$250 de mercancía a crédito',
      'Un cliente me pagó \$120',
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asistente financiero'),
        actions: [
          IconButton(
            tooltip: 'Borrar conversación',
            onPressed: _clearConversation,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              scrollDirection: Axis.horizontal,
              children: [
                for (final s in suggestions)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ActionChip(label: Text(s), onPressed: () => send(s)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              itemCount: messages.length,
              itemBuilder: (_, i) {
                final m = messages[i];
                return Align(
                  alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 560),
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: m.fromUser ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (m.text.trim().isNotEmpty) Text(m.text),
                        if (m.knowledgeAction) ...[
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: _showAddKnowledgeDialog,
                            icon: const Icon(Icons.library_add_outlined),
                            label: const Text('Agregar conocimiento a la base'),
                          ),
                        ],
                        if (m.proposal != null) _proposalCard(m.proposal!),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (busy) const LinearProgressIndicator(minHeight: 2),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => send(),
                      decoration: const InputDecoration(
                        hintText: 'Ej.: Pagué \$55 de gasolina...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: busy ? 'Detener' : 'Enviar',
                    onPressed: busy ? _stopGeneration : () => send(),
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

class _BotMessage {
  final bool fromUser;
  final String text;
  final _BotProposal? proposal;
  final bool knowledgeAction;
  const _BotMessage({
    required this.fromUser,
    required this.text,
    this.proposal,
    this.knowledgeAction = false,
  });

  Map<String, dynamic> toJson() => {
        'fromUser': fromUser,
        'text': text,
        'knowledgeAction': knowledgeAction,
        'proposal': proposal?.toJson(),
      };

  factory _BotMessage.fromJson(Map<String, dynamic> json) => _BotMessage(
        fromUser: json['fromUser'] == true,
        text: json['text']?.toString() ?? '',
        knowledgeAction: json['knowledgeAction'] == true,
        proposal: json['proposal'] is Map
            ? _BotProposal.fromJson(
                Map<String, dynamic>.from(json['proposal'] as Map),
              )
            : null,
      );
}

class _BotReply {
  final String text;
  final _BotProposal? proposal;
  final bool knowledgeAction;
  const _BotReply(
    this.text, {
    this.proposal,
    this.knowledgeAction = false,
  });
}

class _BotProposal {
  final String scope;
  final String description;
  final double amount;
  final String debitCode;
  final String debitName;
  final String creditCode;
  final String creditName;
  final String cashClass;
  final String linkedScope;
  final String linkedDescription;
  final String linkedDebitCode;
  final String linkedDebitName;
  final String linkedCreditCode;
  final String linkedCreditName;

  const _BotProposal({
    this.scope = 'business',
    required this.description,
    required this.amount,
    required this.debitCode,
    required this.debitName,
    required this.creditCode,
    required this.creditName,
    required this.cashClass,
    this.linkedScope = 'none',
    this.linkedDescription = '',
    this.linkedDebitCode = '',
    this.linkedDebitName = '',
    this.linkedCreditCode = '',
    this.linkedCreditName = '',
  });

  Map<String, dynamic> toJson() => {
        'scope': scope,
        'description': description,
        'amount': amount,
        'debitCode': debitCode,
        'debitName': debitName,
        'creditCode': creditCode,
        'creditName': creditName,
        'cashClass': cashClass,
        'linkedScope': linkedScope,
        'linkedDescription': linkedDescription,
        'linkedDebitCode': linkedDebitCode,
        'linkedDebitName': linkedDebitName,
        'linkedCreditCode': linkedCreditCode,
        'linkedCreditName': linkedCreditName,
      };

  factory _BotProposal.fromJson(Map<String, dynamic> json) => _BotProposal(
        scope: json['scope']?.toString() ?? 'business',
        description: json['description']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        debitCode: json['debitCode']?.toString() ?? '',
        debitName: json['debitName']?.toString() ?? '',
        creditCode: json['creditCode']?.toString() ?? '',
        creditName: json['creditName']?.toString() ?? '',
        cashClass: json['cashClass']?.toString() ?? 'operating',
        linkedScope: json['linkedScope']?.toString() ?? 'none',
        linkedDescription: json['linkedDescription']?.toString() ?? '',
        linkedDebitCode: json['linkedDebitCode']?.toString() ?? '',
        linkedDebitName: json['linkedDebitName']?.toString() ?? '',
        linkedCreditCode: json['linkedCreditCode']?.toString() ?? '',
        linkedCreditName: json['linkedCreditName']?.toString() ?? '',
      );
}
