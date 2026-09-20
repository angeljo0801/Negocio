
import 'dart:convert';

import 'package:flutter/material.dart';

import 'database.dart';
import 'finance_ai_service.dart';
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
      text: 'Soy tu asistente financiero con IA. Uso el modelo que elegiste en Ajustes de IA. Escríbeme como hablas normalmente: interpretaré la operación, te pediré solo los datos que falten y te mostraré el asiento antes de guardar nada.',
    ),
  ];
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _ensureExtraAccounts();
  }

  Future<void> _ensureExtraAccounts() async {
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

    if (_has(s, ['deuda', 'por pagar', 'me deben']) && amount == null) {
      return const _BotReply(
        'Para controlar una deuda por vencimiento usa Plan → Deudas. Ahí eliges “Yo debo pagar” o “Me deben cobrar”. Si además quieres crear el asiento contable, dime qué originó la deuda y el importe; por ejemplo: “Compré \$400 de mercancía a crédito”.',
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
      '$explanation\n\nPropuesta:\nDebe: $debitCode · $debitName — \$${amount.toStringAsFixed(2)}\nHaber: $creditCode · $creditName — \$${amount.toStringAsFixed(2)}',
      proposal: _BotProposal(
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
    setState(() {
      messages.add(_BotMessage(fromUser: true, text: text));
      busy = true;
    });
    final reply = await _answer(text);
    if (!mounted) return;
    setState(() {
      messages.add(_BotMessage(fromUser: false, text: reply.text, proposal: reply.proposal));
      busy = false;
    });
    _scrollDown();
  }

  Future<void> createProposal(_BotProposal proposal) async {
    await _ensureExtraAccounts();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar asiento'),
        content: Text(
          '${proposal.description}\n\nDebe: ${proposal.debitCode} · ${proposal.debitName}  \$${proposal.amount.toStringAsFixed(2)}\n'
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
      final debitId = await AppDatabase.instance.accountId(proposal.debitCode);
      final creditId = await AppDatabase.instance.accountId(proposal.creditCode);
      await AppDatabase.instance.addTransaction(
        JournalTransaction(
          date: DateTime.now(),
          description: proposal.description,
          reference: 'BOT-${DateTime.now().millisecondsSinceEpoch}',
          cashFlowClass: proposal.cashClass,
          lines: [
            JournalLine(accountId: debitId, debit: proposal.amount),
            JournalLine(accountId: creditId, credit: proposal.amount),
          ],
        ),
      );
      widget.onChanged();
      if (!mounted) return;
      setState(() {
        messages.add(const _BotMessage(
          fromUser: false,
          text: 'Asiento creado correctamente. Ya forma parte de tus estados financieros. Si fue un error, puedes moverlo a Papelera desde el Libro diario.',
        ));
      });
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
      appBar: AppBar(title: const Text('Asistente financiero')),
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
                        Text(m.text),
                        if (m.proposal != null) ...[
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: () => createProposal(m.proposal!),
                            icon: const Icon(Icons.post_add),
                            label: const Text('Revisar y crear asiento'),
                          ),
                        ],
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
                    tooltip: 'Enviar',
                    onPressed: busy ? null : () => send(),
                    icon: const Icon(Icons.send),
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
  const _BotMessage({required this.fromUser, required this.text, this.proposal});
}

class _BotReply {
  final String text;
  final _BotProposal? proposal;
  const _BotReply(this.text, {this.proposal});
}

class _BotProposal {
  final String description;
  final double amount;
  final String debitCode;
  final String debitName;
  final String creditCode;
  final String creditName;
  final String cashClass;
  const _BotProposal({
    required this.description,
    required this.amount,
    required this.debitCode,
    required this.debitName,
    required this.creditCode,
    required this.creditName,
    required this.cashClass,
  });
}
