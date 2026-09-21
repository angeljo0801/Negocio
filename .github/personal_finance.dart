import 'package:flutter/material.dart';

import 'database.dart';

class PersonalFinanceStore {
  static const accounts = <List<String>>[
    ['P1010', 'Efectivo personal', 'asset'],
    ['P1020', 'Banco personal', 'asset'],
    ['P1030', 'Ahorros personales', 'asset'],
    ['P1040', 'Cuentas por cobrar personales', 'asset'],
    ['P1050', 'Inversión en el negocio', 'asset'],
    ['P2010', 'Tarjetas personales por pagar', 'liability'],
    ['P2020', 'Deudas personales', 'liability'],
    ['P3010', 'Patrimonio personal', 'equity'],
    ['P3900', 'Transferencias Personal ↔ Negocio', 'equity'],
    ['P4010', 'Ingresos personales', 'revenue'],
    ['P4020', 'Sueldo / salario personal', 'revenue'],
    ['P4030', 'Otros ingresos personales', 'revenue'],
    ['P5010', 'Alimentación personal', 'expense'],
    ['P5020', 'Vivienda personal', 'expense'],
    ['P5030', 'Transporte personal', 'expense'],
    ['P5040', 'Compras personales', 'expense'],
    ['P5050', 'Suscripciones personales', 'expense'],
    ['P5060', 'Salud personal', 'expense'],
    ['P5070', 'Educación personal', 'expense'],
    ['P5080', 'Entretenimiento personal', 'expense'],
    ['P5090', 'Otros gastos personales', 'expense'],
  ];

  static Future<void> ensureSchema() async {
    final d = await AppDatabase.instance.db;
    await d.execute('''
      CREATE TABLE IF NOT EXISTS personal_accounts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        type TEXT NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS personal_transactions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        description TEXT NOT NULL,
        reference TEXT
      )
    ''');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS personal_journal_lines(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER NOT NULL,
        account_id INTEGER NOT NULL,
        debit REAL NOT NULL DEFAULT 0,
        credit REAL NOT NULL DEFAULT 0
      )
    ''');
    for (final a in accounts) {
      await d.rawInsert(
        'INSERT OR IGNORE INTO personal_accounts(code,name,type) VALUES(?,?,?)',
        a,
      );
    }
  }

  static Future<String> catalogText() async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    final rows = await d.query('personal_accounts', orderBy: 'code');
    return rows
        .map((r) => '${r['code']}|${r['name']}|${r['type']}|personal')
        .join('\n');
  }

  static Future<Map<String, dynamic>?> accountByCode(String code) async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    final rows = await d.query(
      'personal_accounts',
      where: 'code=?',
      whereArgs: [code],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<void> addTransaction({
    required String description,
    required double amount,
    required String debitCode,
    required String creditCode,
    String? reference,
    DateTime? date,
  }) async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    final debit = await accountByCode(debitCode);
    final credit = await accountByCode(creditCode);
    if (debit == null || credit == null) {
      throw Exception('La cuenta personal seleccionada no existe.');
    }
    await d.transaction((txn) async {
      final txId = await txn.insert('personal_transactions', {
        'date': (date ?? DateTime.now()).toIso8601String(),
        'description': description,
        'reference': reference ?? 'AI-P-${DateTime.now().millisecondsSinceEpoch}',
      });
      await txn.insert('personal_journal_lines', {
        'transaction_id': txId,
        'account_id': debit['id'],
        'debit': amount,
        'credit': 0.0,
      });
      await txn.insert('personal_journal_lines', {
        'transaction_id': txId,
        'account_id': credit['id'],
        'debit': 0.0,
        'credit': amount,
      });
    });
  }

  static Future<String> contextText() async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    final balances = await d.rawQuery('''
      SELECT a.code,a.name,a.type,
        COALESCE(SUM(l.debit-l.credit),0) AS net
      FROM personal_accounts a
      LEFT JOIN personal_journal_lines l ON l.account_id=a.id
      GROUP BY a.id
      ORDER BY a.code
    ''');
    final recent = await d.rawQuery('''
      SELECT t.id,t.date,t.description,t.reference
      FROM personal_transactions t
      ORDER BY t.id DESC LIMIT 8
    ''');
    final b = StringBuffer('FINANZAS PERSONALES DEL USUARIO\n');
    b.writeln('SALDOS PERSONALES:');
    for (final row in balances) {
      final net = (row['net'] as num?)?.toDouble() ?? 0;
      if (net.abs() < 0.005) continue;
      b.writeln('- ${row['code']} · ${row['name']}: ${net.toStringAsFixed(2)}');
    }
    b.writeln('TRANSACCIONES PERSONALES RECIENTES:');
    for (final tx in recent) {
      b.writeln('- ${tx['date']} · ${tx['description']}');
    }
    return b.toString();
  }

  static Future<List<Map<String, dynamic>>> balances() async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    return d.rawQuery('''
      SELECT a.code,a.name,a.type,
        COALESCE(SUM(l.debit-l.credit),0) AS net
      FROM personal_accounts a
      LEFT JOIN personal_journal_lines l ON l.account_id=a.id
      GROUP BY a.id
      ORDER BY a.code
    ''');
  }

  static Future<List<Map<String, dynamic>>> recent() async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    return d.rawQuery('''
      SELECT t.id,t.date,t.description,t.reference,
             COALESCE(SUM(l.debit),0) AS amount
      FROM personal_transactions t
      LEFT JOIN personal_journal_lines l ON l.transaction_id=t.id
      GROUP BY t.id
      ORDER BY t.id DESC LIMIT 25
    ''');
  }
}

class PersonalFinancePage extends StatefulWidget {
  const PersonalFinancePage({super.key});

  @override
  State<PersonalFinancePage> createState() => _PersonalFinancePageState();
}

class _PersonalFinancePageState extends State<PersonalFinancePage> {
  bool loading = true;
  List<Map<String, dynamic>> balances = const [];
  List<Map<String, dynamic>> recent = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await PersonalFinanceStore.balances();
    final r = await PersonalFinanceStore.recent();
    if (!mounted) return;
    setState(() {
      balances = b;
      recent = r;
      loading = false;
    });
  }

  Future<void> _addMovement() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const PersonalMovementEditorPage(),
      ),
    );
    if (saved == true) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Movimiento personal guardado.')),
      );
    }
  }

  String _shortDate(Object? value) {
    final raw = value?.toString() ?? '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return parsed.year.toString().padLeft(4, '0') +
        '-' +
        parsed.month.toString().padLeft(2, '0') +
        '-' +
        parsed.day.toString().padLeft(2, '0');
  }

  @override
  Widget build(BuildContext context) {
    final nonZero = balances.where(
      (r) => (((r['net'] as num?)?.toDouble() ?? 0).abs() >= 0.005),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Finanzas personales')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMovement,
        icon: const Icon(Icons.add),
        label: const Text('Agregar movimiento'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
                children: [
                  Text(
                    'Tu dinero personal',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Separado del negocio. Paquetería nunca entra aquí automáticamente.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _addMovement,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Registrar movimiento manual'),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Saldos',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  for (final row in nonZero)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.account_balance_wallet_outlined),
                      title: Text(
                        row['code'].toString() + ' · ' + row['name'].toString(),
                      ),
                      trailing: Text(
                        ((row['net'] as num?)?.toDouble() ?? 0)
                            .toStringAsFixed(2),
                      ),
                    ),
                  if (nonZero.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Todavía no hay saldos personales registrados.',
                      ),
                    ),
                  const Divider(height: 28),
                  Text(
                    'Movimientos personales recientes',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  for (final tx in recent)
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(tx['description'].toString()),
                      subtitle: Text(_shortDate(tx['date'])),
                      trailing: Text(
                        ((tx['amount'] as num?)?.toDouble() ?? 0)
                            .toStringAsFixed(2),
                      ),
                    ),
                  if (recent.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Todavía no hay movimientos. Puedes registrarlos aquí manualmente o desde el Asistente financiero.',
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class PersonalMovementEditorPage extends StatefulWidget {
  const PersonalMovementEditorPage({super.key});

  @override
  State<PersonalMovementEditorPage> createState() =>
      _PersonalMovementEditorPageState();
}

class _PersonalMovementEditorPageState
    extends State<PersonalMovementEditorPage> {
  final amountController = TextEditingController();
  final descriptionController = TextEditingController();

  String kind = 'expense';
  String debtMode = 'new';
  String debitCode = 'P5010';
  String creditCode = 'P1010';
  DateTime date = DateTime.now();
  bool saving = false;

  static const kinds = <String, String>{
    'expense': 'Gasto',
    'income': 'Ingreso',
    'transfer': 'Transferencia',
    'debt': 'Deuda',
    'manual': 'Asiento manual',
  };

  static const assetCodes = ['P1010', 'P1020', 'P1030', 'P1040', 'P1050'];
  static const liquidCodes = ['P1010', 'P1020', 'P1030'];
  static const liabilityCodes = ['P2010', 'P2020'];
  static const revenueCodes = ['P4010', 'P4020', 'P4030'];
  static const expenseCodes = [
    'P5010',
    'P5020',
    'P5030',
    'P5040',
    'P5050',
    'P5060',
    'P5070',
    'P5080',
    'P5090',
  ];

  @override
  void dispose() {
    amountController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  String _accountName(String code) {
    for (final row in PersonalFinanceStore.accounts) {
      if (row[0] == code) return row[1];
    }
    return code;
  }

  List<String> _allCodes() =>
      PersonalFinanceStore.accounts.map((e) => e[0]).toList();

  List<String> _debitOptions() {
    switch (kind) {
      case 'expense':
        return expenseCodes;
      case 'income':
        return liquidCodes;
      case 'transfer':
        return liquidCodes;
      case 'debt':
        if (debtMode == 'pay') return liabilityCodes;
        return [...expenseCodes, ...assetCodes];
      default:
        return _allCodes();
    }
  }

  List<String> _creditOptions() {
    switch (kind) {
      case 'expense':
        return [...liquidCodes, ...liabilityCodes];
      case 'income':
        return revenueCodes;
      case 'transfer':
        return liquidCodes;
      case 'debt':
        if (debtMode == 'pay') return liquidCodes;
        return liabilityCodes;
      default:
        return _allCodes();
    }
  }

  void _resetAccounts() {
    switch (kind) {
      case 'expense':
        debitCode = 'P5010';
        creditCode = 'P1010';
        break;
      case 'income':
        debitCode = 'P1020';
        creditCode = 'P4010';
        break;
      case 'transfer':
        debitCode = 'P1020';
        creditCode = 'P1010';
        break;
      case 'debt':
        if (debtMode == 'pay') {
          debitCode = 'P2020';
          creditCode = 'P1020';
        } else {
          debitCode = 'P5040';
          creditCode = 'P2020';
        }
        break;
      default:
        debitCode = 'P1010';
        creditCode = 'P3010';
    }
  }

  String _debitLabel() {
    switch (kind) {
      case 'expense':
        return 'Categoría del gasto';
      case 'income':
        return 'Dónde entró el dinero';
      case 'transfer':
        return 'Cuenta destino';
      case 'debt':
        return debtMode == 'pay' ? 'Deuda que disminuye' : 'Uso / destino';
      default:
        return 'Cuenta Debe';
    }
  }

  String _creditLabel() {
    switch (kind) {
      case 'expense':
        return 'Cómo se pagó';
      case 'income':
        return 'Tipo de ingreso';
      case 'transfer':
        return 'Cuenta origen';
      case 'debt':
        return debtMode == 'pay' ? 'Cómo se pagó' : 'Tipo de deuda';
      default:
        return 'Cuenta Haber';
    }
  }

  String _defaultDescription() {
    switch (kind) {
      case 'expense':
        return 'Gasto personal';
      case 'income':
        return 'Ingreso personal';
      case 'transfer':
        return 'Transferencia entre cuentas personales';
      case 'debt':
        return debtMode == 'pay' ? 'Pago de deuda personal' : 'Nueva deuda personal';
      default:
        return 'Asiento personal manual';
    }
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) {
      setState(() => date = selected);
    }
  }

  Future<void> _save() async {
    final amount = double.tryParse(
      amountController.text.trim().replaceAll(',', '.'),
    );
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe un importe válido.')),
      );
      return;
    }
    if (debitCode == creditCode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La cuenta Debe y la cuenta Haber deben ser distintas.'),
        ),
      );
      return;
    }

    setState(() => saving = true);
    try {
      await PersonalFinanceStore.addTransaction(
        description: descriptionController.text.trim().isEmpty
            ? _defaultDescription()
            : descriptionController.text.trim(),
        amount: amount,
        debitCode: debitCode,
        creditCode: creditCode,
        reference:
            'MAN-P-' + DateTime.now().millisecondsSinceEpoch.toString(),
        date: date,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pude guardar el movimiento: ' + e.toString())),
      );
    }
  }

  Widget _accountDropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: options.contains(value) ? value : options.first,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final code in options)
          DropdownMenuItem(
            value: code,
            child: Text(code + ' · ' + _accountName(code)),
          ),
      ],
      onChanged: saving ? null : onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final debitOptions = _debitOptions();
    final creditOptions = _creditOptions();
    if (!debitOptions.contains(debitCode)) debitCode = debitOptions.first;
    if (!creditOptions.contains(creditCode)) creditCode = creditOptions.first;

    final dateText = date.year.toString().padLeft(4, '0') +
        '-' +
        date.month.toString().padLeft(2, '0') +
        '-' +
        date.day.toString().padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(title: const Text('Agregar movimiento personal')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 110),
        children: [
          DropdownButtonFormField<String>(
            initialValue: kind,
            decoration: const InputDecoration(
              labelText: 'Tipo de movimiento',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final e in kinds.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: saving
                ? null
                : (v) {
                    if (v == null) return;
                    setState(() {
                      kind = v;
                      _resetAccounts();
                    });
                  },
          ),
          if (kind == 'debt') ...[
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'new', label: Text('Nueva deuda')),
                ButtonSegment(value: 'pay', label: Text('Pagar deuda')),
              ],
              selected: {debtMode},
              onSelectionChanged: saving
                  ? null
                  : (values) {
                      if (values.isEmpty) return;
                      setState(() {
                        debtMode = values.first;
                        _resetAccounts();
                      });
                    },
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Importe',
              prefixText: '\$ ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: descriptionController,
            decoration: InputDecoration(
              labelText: 'Descripción',
              hintText: _defaultDescription(),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Fecha'),
            subtitle: Text(dateText),
            trailing: const Icon(Icons.chevron_right),
            onTap: saving ? null : _pickDate,
          ),
          const SizedBox(height: 12),
          _accountDropdown(
            label: _debitLabel(),
            value: debitCode,
            options: debitOptions,
            onChanged: (v) {
              if (v != null) setState(() => debitCode = v);
            },
          ),
          const SizedBox(height: 12),
          _accountDropdown(
            label: _creditLabel(),
            value: creditCode,
            options: creditOptions,
            onChanged: (v) {
              if (v != null) setState(() => creditCode = v);
            },
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Vista previa\n\nDEBE  ' +
                    debitCode +
                    ' · ' +
                    _accountName(debitCode) +
                    '\nHABER  ' +
                    creditCode +
                    ' · ' +
                    _accountName(creditCode),
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: saving ? null : _save,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(saving ? 'Guardando…' : 'Guardar movimiento'),
          ),
        ],
      ),
    );
  }
}
