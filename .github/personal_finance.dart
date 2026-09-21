import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'database.dart';

class PersonalReminderBridge {
  static const _channel =
      MethodChannel('com.angel.finanzas/personal_reminders');

  static Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> schedule({
    required int accountId,
    required String title,
    required String bank,
    required int dueDay,
    required int daysBefore,
  }) async {
    await _channel.invokeMethod('schedule', {
      'id': accountId,
      'title': title,
      'bank': bank,
      'dueDay': dueDay,
      'daysBefore': daysBefore,
    });
  }

  static Future<void> cancel(int accountId) async {
    try {
      await _channel.invokeMethod('cancel', {'id': accountId});
    } catch (_) {}
  }
}

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

  static const _systemKinds = <String, String>{
    'P1010': 'cash',
    'P1020': 'checking',
    'P1030': 'savings',
    'P1040': 'receivable',
    'P1050': 'investment',
    'P2010': 'credit_card',
    'P2020': 'debt',
    'P3010': 'equity',
    'P3900': 'transfer_equity',
    'P4010': 'income',
    'P4020': 'income',
    'P4030': 'income',
    'P5010': 'expense',
    'P5020': 'expense',
    'P5030': 'expense',
    'P5040': 'expense',
    'P5050': 'expense',
    'P5060': 'expense',
    'P5070': 'expense',
    'P5080': 'expense',
    'P5090': 'expense',
  };

  static Future<void> _ensureColumn(
    dynamic db,
    String name,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info(personal_accounts)');
    final exists = columns.any((row) => row['name']?.toString() == name);
    if (!exists) {
      await db.execute(
        'ALTER TABLE personal_accounts ADD COLUMN $name $definition',
      );
    }
  }

  static Future<void> ensureSchema() async {
    final d = await AppDatabase.instance.db;
    await d.execute('''
      CREATE TABLE IF NOT EXISTS personal_accounts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        bank_name TEXT NOT NULL DEFAULT '',
        account_kind TEXT NOT NULL DEFAULT 'generic',
        credit_limit REAL NOT NULL DEFAULT 0,
        payment_due_day INTEGER NOT NULL DEFAULT 0,
        reminder_enabled INTEGER NOT NULL DEFAULT 0,
        reminder_days_before INTEGER NOT NULL DEFAULT 1,
        rewards_type TEXT NOT NULL DEFAULT 'none',
        rewards_balance REAL NOT NULL DEFAULT 0,
        rewards_percent REAL NOT NULL DEFAULT 0,
        bank_id INTEGER,
        is_system INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await _ensureColumn(d, 'bank_name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
      d,
      'account_kind',
      "TEXT NOT NULL DEFAULT 'generic'",
    );
    await _ensureColumn(d, 'credit_limit', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(d, 'payment_due_day', 'INTEGER NOT NULL DEFAULT 0');
    await _ensureColumn(d, 'reminder_enabled', 'INTEGER NOT NULL DEFAULT 0');
    await _ensureColumn(
      d,
      'reminder_days_before',
      'INTEGER NOT NULL DEFAULT 1',
    );
    await _ensureColumn(d, 'rewards_type', "TEXT NOT NULL DEFAULT 'none'");
    await _ensureColumn(d, 'rewards_balance', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(d, 'rewards_percent', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(d, 'bank_id', 'INTEGER');
    await _ensureColumn(d, 'is_system', 'INTEGER NOT NULL DEFAULT 1');

    await d.execute('''
      CREATE TABLE IF NOT EXISTS personal_banks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL
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
        'INSERT OR IGNORE INTO personal_accounts(code,name,type,is_system) VALUES(?,?,?,1)',
        a,
      );
    }
    for (final entry in _systemKinds.entries) {
      await d.update(
        'personal_accounts',
        {
          'account_kind': entry.value,
          'is_system': 1,
        },
        where: 'code=?',
        whereArgs: [entry.key],
      );
    }

    final namedBanks = await d.rawQuery('''
      SELECT DISTINCT bank_name FROM personal_accounts
      WHERE TRIM(COALESCE(bank_name,'')) <> ''
    ''');
    for (final row in namedBanks) {
      final name = row['bank_name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      await d.rawInsert(
        'INSERT OR IGNORE INTO personal_banks(name,created_at) VALUES(?,?)',
        [name, DateTime.now().toIso8601String()],
      );
      final bankRows = await d.query(
        'personal_banks',
        columns: ['id'],
        where: 'name=?',
        whereArgs: [name],
        limit: 1,
      );
      if (bankRows.isNotEmpty) {
        await d.update(
          'personal_accounts',
          {'bank_id': bankRows.first['id']},
          where: "bank_name=? AND bank_id IS NULL",
          whereArgs: [name],
        );
      }
    }
  }

  static Future<int?> createBank(String name) async {
    await ensureSchema();
    final clean = name.trim();
    if (clean.isEmpty) throw Exception('Escribe el nombre del banco.');
    final d = await AppDatabase.instance.db;
    await d.rawInsert(
      'INSERT OR IGNORE INTO personal_banks(name,created_at) VALUES(?,?)',
      [clean, DateTime.now().toIso8601String()],
    );
    final rows = await d.query(
      'personal_banks',
      columns: ['id'],
      where: 'name=?',
      whereArgs: [clean],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as int?;
  }

  static Future<List<Map<String, dynamic>>> banks() async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    return d.rawQuery('''
      SELECT b.id,b.name,b.created_at,COUNT(a.id) AS account_count
      FROM personal_banks b
      LEFT JOIN personal_accounts a ON a.bank_id=b.id
      GROUP BY b.id
      ORDER BY LOWER(b.name)
    ''');
  }

  static Future<List<Map<String, dynamic>>> allAccounts() async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    return d.query('personal_accounts', orderBy: 'code');
  }

  static Future<String> catalogText() async {
    final rows = await allAccounts();
    return rows
        .map(
          (r) =>
              '${r['code']}|${r['name']}|${r['type']}|${r['account_kind']}|${r['bank_name']}|personal',
        )
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
        'reference':
            reference ?? 'AI-P-${DateTime.now().millisecondsSinceEpoch}',
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

  static Future<String> _nextCode(String kind) async {
    final rows = await allAccounts();
    final used = rows.map((e) => e['code']?.toString() ?? '').toSet();
    final base = kind == 'savings'
        ? 1100
        : kind == 'checking'
            ? 1200
            : kind == 'credit_card'
                ? 2100
                : 1300;
    for (var i = 1; i < 800; i++) {
      final code = 'P${(base + i).toString().padLeft(4, '0')}';
      if (!used.contains(code)) return code;
    }
    throw Exception('No pude generar un código para la nueva cuenta.');
  }

  static Future<int> createFinancialAccount({
    required String name,
    required String bankName,
    required String kind,
    double creditLimit = 0,
    double initialBalance = 0,
    int paymentDueDay = 0,
    bool reminderEnabled = false,
    int reminderDaysBefore = 1,
    String rewardsType = 'none',
    double rewardsBalance = 0,
    double rewardsPercent = 0,
    DateTime? initialDate,
  }) async {
    await ensureSchema();
    final cleanName = name.trim();
    final cleanBank = bankName.trim();
    if (cleanName.isEmpty) {
      throw Exception('Escribe un nombre para la cuenta.');
    }
    if (!const {'savings', 'checking', 'credit_card', 'cash'}.contains(kind)) {
      throw Exception('Tipo de cuenta no válido.');
    }

    final d = await AppDatabase.instance.db;
    final bankId = cleanBank.isEmpty ? null : await createBank(cleanBank);
    final code = await _nextCode(kind);
    final type = kind == 'credit_card' ? 'liability' : 'asset';
    final id = await d.insert('personal_accounts', {
      'code': code,
      'name': cleanName,
      'type': type,
      'bank_name': cleanBank,
      'bank_id': bankId,
      'account_kind': kind,
      'credit_limit': kind == 'credit_card' ? creditLimit : 0.0,
      'payment_due_day':
          kind == 'credit_card' ? paymentDueDay.clamp(0, 31) : 0,
      'reminder_enabled':
          kind == 'credit_card' && reminderEnabled ? 1 : 0,
      'reminder_days_before':
          kind == 'credit_card' ? reminderDaysBefore.clamp(0, 30) : 1,
      'rewards_type': kind == 'credit_card' ? rewardsType : 'none',
      'rewards_balance': kind == 'credit_card' ? rewardsBalance : 0.0,
      'rewards_percent': kind == 'credit_card' ? rewardsPercent : 0.0,
      'is_system': 0,
    });

    if (initialBalance > 0.005) {
      if (kind == 'credit_card') {
        await addTransaction(
          description: 'Saldo inicial · $cleanName',
          amount: initialBalance,
          debitCode: 'P3010',
          creditCode: code,
          reference: 'INIT-P-${DateTime.now().millisecondsSinceEpoch}',
          date: initialDate,
        );
      } else {
        await addTransaction(
          description: 'Saldo inicial · $cleanName',
          amount: initialBalance,
          debitCode: code,
          creditCode: 'P3010',
          reference: 'INIT-P-${DateTime.now().millisecondsSinceEpoch}',
          date: initialDate,
        );
      }
    }

    if (kind == 'credit_card' &&
        reminderEnabled &&
        paymentDueDay >= 1 &&
        paymentDueDay <= 31) {
      await PersonalReminderBridge.schedule(
        accountId: id,
        title: cleanName,
        bank: cleanBank,
        dueDay: paymentDueDay,
        daysBefore: reminderDaysBefore,
      );
    }
    return id;
  }

  static Future<void> updateFinancialAccount({
    required int id,
    required String name,
    required String bankName,
    required String kind,
    double creditLimit = 0,
    int paymentDueDay = 0,
    bool reminderEnabled = false,
    int reminderDaysBefore = 1,
    String rewardsType = 'none',
    double rewardsBalance = 0,
    double rewardsPercent = 0,
  }) async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    final cleanBank = bankName.trim();
    final bankId = cleanBank.isEmpty ? null : await createBank(cleanBank);
    await d.update(
      'personal_accounts',
      {
        'name': name.trim(),
        'bank_name': cleanBank,
        'bank_id': bankId,
        'credit_limit': kind == 'credit_card' ? creditLimit : 0.0,
        'payment_due_day':
            kind == 'credit_card' ? paymentDueDay.clamp(0, 31) : 0,
        'reminder_enabled':
            kind == 'credit_card' && reminderEnabled ? 1 : 0,
        'reminder_days_before':
            kind == 'credit_card' ? reminderDaysBefore.clamp(0, 30) : 1,
        'rewards_type': kind == 'credit_card' ? rewardsType : 'none',
        'rewards_balance': kind == 'credit_card' ? rewardsBalance : 0.0,
        'rewards_percent': kind == 'credit_card' ? rewardsPercent : 0.0,
      },
      where: 'id=?',
      whereArgs: [id],
    );

    await PersonalReminderBridge.cancel(id);
    if (kind == 'credit_card' &&
        reminderEnabled &&
        paymentDueDay >= 1 &&
        paymentDueDay <= 31) {
      await PersonalReminderBridge.schedule(
        accountId: id,
        title: name.trim(),
        bank: bankName.trim(),
        dueDay: paymentDueDay,
        daysBefore: reminderDaysBefore,
      );
    }
  }

  static Future<void> payCreditCard({
    required String cardCode,
    required String sourceCode,
    required double amount,
    DateTime? date,
  }) async {
    if (amount <= 0) {
      throw Exception('El pago debe ser mayor que cero.');
    }
    final card = await accountByCode(cardCode);
    final source = await accountByCode(sourceCode);
    if (card == null || card['account_kind'] != 'credit_card') {
      throw Exception('La tarjeta seleccionada no existe.');
    }
    if (source == null ||
        !const {'cash', 'checking', 'savings'}
            .contains(source['account_kind']?.toString())) {
      throw Exception('Selecciona una cuenta personal válida para pagar.');
    }
    final summaries = await accountSummaries();
    Map<String, dynamic>? current;
    for (final row in summaries) {
      if (row['code'] == cardCode) {
        current = row;
        break;
      }
    }
    final debt = current == null ? 0.0 : displayBalance(current);
    if (amount > debt + 0.005) {
      throw Exception(
        'El pago no puede ser mayor que la deuda actual (' +
            debt.toStringAsFixed(2) +
            ').',
      );
    }
    await addTransaction(
      description: 'Pago parcial · ' + card['name'].toString(),
      amount: amount,
      debitCode: cardCode,
      creditCode: sourceCode,
      reference: 'PAY-CC-' + DateTime.now().millisecondsSinceEpoch.toString(),
      date: date,
    );
  }

  static Future<List<Map<String, dynamic>>> accountSummaries() async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    return d.rawQuery('''
      SELECT
        a.id,a.code,a.name,a.type,a.bank_name,a.bank_id,a.account_kind,
        a.credit_limit,a.payment_due_day,a.reminder_enabled,
        a.reminder_days_before,a.rewards_type,a.rewards_balance,
        a.rewards_percent,a.is_system,
        COALESCE(SUM(l.debit),0) AS debit_total,
        COALESCE(SUM(l.credit),0) AS credit_total,
        MAX(t.date) AS last_date
      FROM personal_accounts a
      LEFT JOIN personal_journal_lines l ON l.account_id=a.id
      LEFT JOIN personal_transactions t ON t.id=l.transaction_id
      WHERE a.account_kind IN ('cash','checking','savings','credit_card')
      GROUP BY a.id
      ORDER BY
        CASE a.account_kind
          WHEN 'savings' THEN 1
          WHEN 'checking' THEN 2
          WHEN 'credit_card' THEN 3
          ELSE 4
        END,
        a.bank_name,a.name
    ''');
  }

  static double displayBalance(Map<String, dynamic> row) {
    final debit = (row['debit_total'] as num?)?.toDouble() ?? 0;
    final credit = (row['credit_total'] as num?)?.toDouble() ?? 0;
    return row['type'] == 'liability' ? credit - debit : debit - credit;
  }

  static Future<String> contextText() async {
    await ensureSchema();
    final balances = await accountBalances();
    final recentRows = await recent();
    final b = StringBuffer('FINANZAS PERSONALES DEL USUARIO\n');
    b.writeln('SALDOS PERSONALES:');
    for (final row in balances) {
      final net = (row['net'] as num?)?.toDouble() ?? 0;
      if (net.abs() < 0.005) continue;
      final bank = row['bank_name']?.toString().trim() ?? '';
      final kind = row['account_kind']?.toString() ?? '';
      final display = row['type'] == 'liability' ? -net : net;
      final rewardsType = row['rewards_type']?.toString() ?? 'none';
      final rewardsBalance =
          (row['rewards_balance'] as num?)?.toDouble() ?? 0;
      final rewardsPercent =
          (row['rewards_percent'] as num?)?.toDouble() ?? 0;
      b.write(
        '- ${row['code']} · ${row['name']}'
        '${bank.isEmpty ? '' : ' · banco $bank'}'
        ' · $kind: ${display.toStringAsFixed(2)}',
      );
      if (kind == 'credit_card') {
        b.write(
          ' · rewards $rewardsType'
          ' · ${rewardsPercent.toStringAsFixed(2)}%'
          ' · saldo rewards ${rewardsBalance.toStringAsFixed(2)}',
        );
      }
      b.writeln();
    }
    b.writeln('TRANSACCIONES PERSONALES RECIENTES:');
    for (final tx in recentRows.take(8)) {
      b.writeln('- ${tx['date']} · ${tx['description']}');
    }
    return b.toString();
  }

  static Future<List<Map<String, dynamic>>> accountBalances() async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    return d.rawQuery('''
      SELECT a.id,a.code,a.name,a.type,a.bank_name,a.bank_id,a.account_kind,
        a.credit_limit,a.payment_due_day,a.reminder_enabled,
        a.reminder_days_before,a.rewards_type,a.rewards_balance,
        a.rewards_percent,a.is_system,
        COALESCE(SUM(l.debit-l.credit),0) AS net
      FROM personal_accounts a
      LEFT JOIN personal_journal_lines l ON l.account_id=a.id
      GROUP BY a.id
      ORDER BY a.code
    ''');
  }

  static Future<List<Map<String, dynamic>>> balances() => accountBalances();

  static Future<List<Map<String, dynamic>>> recent() async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    return d.rawQuery('''
      SELECT t.id,t.date,t.description,t.reference,
             COALESCE(SUM(l.debit),0) AS amount
      FROM personal_transactions t
      LEFT JOIN personal_journal_lines l ON l.transaction_id=t.id
      GROUP BY t.id
      ORDER BY t.date DESC,t.id DESC LIMIT 40
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

  Future<void> _openAccounts() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PersonalAccountsPage()),
    );
    await _load();
  }

  Future<void> _openBalanceSheet() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PersonalBalanceSheetPage()),
    );
    await _load();
  }

  String _shortDate(Object? value) {
    final raw = value?.toString() ?? '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}';
  }

  double _shownBalance(Map<String, dynamic> row) {
    final net = (row['net'] as num?)?.toDouble() ?? 0;
    return row['type'] == 'liability' ? -net : net;
  }

  @override
  Widget build(BuildContext context) {
    final nonZero = balances.where(
      (r) => (_shownBalance(r).abs() >= 0.005),
    );
    final assets = balances
        .where((r) => r['type'] == 'asset')
        .fold<double>(0, (sum, row) => sum + _shownBalance(row));
    final liabilities = balances
        .where((r) => r['type'] == 'liability')
        .fold<double>(0, (sum, row) => sum + _shownBalance(row));
    final netWorth = assets - liabilities;

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
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.account_balance_wallet_outlined),
                      title: const Text('Patrimonio neto personal'),
                      subtitle: Text(
                        'Activos ${assets.toStringAsFixed(2)} · '
                        'Pasivos ${liabilities.toStringAsFixed(2)}',
                      ),
                      trailing: Text(
                        netWorth.toStringAsFixed(2),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _addMovement,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Registrar movimiento manual'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _openAccounts,
                    icon: const Icon(Icons.account_balance_outlined),
                    label: const Text('Billetera · bancos y tarjetas'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _openBalanceSheet,
                    icon: const Icon(Icons.balance_outlined),
                    label: const Text('Balance General personal'),
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
                      leading: Icon(
                        row['type'] == 'liability'
                            ? Icons.credit_card_outlined
                            : Icons.account_balance_wallet_outlined,
                      ),
                      title: Text(
                        '${row['code']} · ${row['name']}',
                      ),
                      subtitle:
                          (row['bank_name']?.toString().trim().isNotEmpty ??
                                  false)
                              ? Text(row['bank_name'].toString())
                              : null,
                      trailing: Text(
                        _shownBalance(row).toStringAsFixed(2),
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

class PersonalAccountsPage extends StatefulWidget {
  const PersonalAccountsPage({super.key});

  @override
  State<PersonalAccountsPage> createState() => _PersonalAccountsPageState();
}

class _PersonalAccountsPageState extends State<PersonalAccountsPage> {
  bool loading = true;
  List<Map<String, dynamic>> rows = const [];
  List<Map<String, dynamic>> bankRows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await PersonalFinanceStore.accountSummaries();
    final banks = await PersonalFinanceStore.banks();
    if (!mounted) return;
    setState(() {
      rows = data;
      bankRows = banks;
      loading = false;
    });
  }

  Future<void> _addBank() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Agregar banco'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nombre del banco',
            hintText: 'Ej.: Chase, Capital One, Bank of America',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    final name = controller.text.trim();
    controller.dispose();
    if (ok == true && name.isNotEmpty) {
      await PersonalFinanceStore.createBank(name);
      await _load();
    }
  }

  Future<void> _openEditor({
    Map<String, dynamic>? existing,
    String? initialBankName,
  }) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PersonalFinancialAccountEditorPage(
          existing: existing,
          initialBankName: initialBankName,
        ),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _payCard(Map<String, dynamic> card) async {
    final accounts = await PersonalFinanceStore.allAccounts();
    final sources = accounts
        .where(
          (a) => const {'cash', 'checking', 'savings'}
              .contains(a['account_kind']?.toString()),
        )
        .toList();
    if (!mounted) return;
    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero crea una cuenta personal desde la cual pagar.'),
        ),
      );
      return;
    }

    final debt = PersonalFinanceStore.displayBalance(card);
    final amountController = TextEditingController();
    var sourceCode = sources.first['code'].toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('Pago parcial · ' + card['name'].toString()),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Deuda actual: ' + debt.toStringAsFixed(2),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Importe del pago',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: sourceCode,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Pagar desde',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final a in sources)
                      DropdownMenuItem(
                        value: a['code'].toString(),
                        child: Text(
                          a['name'].toString() +
                              ((a['bank_name']?.toString().trim().isNotEmpty ??
                                      false)
                                  ? ' · ' + a['bank_name'].toString()
                                  : ''),
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialog(() => sourceCode = v);
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
              child: const Text('Registrar pago'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      final amount = double.tryParse(
        amountController.text.trim().replaceAll(',', '.'),
      );
      amountController.dispose();
      if (amount == null || amount <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Escribe un importe válido.')),
        );
        return;
      }
      try {
        await PersonalFinanceStore.payCreditCard(
          cardCode: card['code'].toString(),
          sourceCode: sourceCode,
          amount: amount,
        );
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pago parcial registrado.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } else {
      amountController.dispose();
    }
  }

  String _date(Object? raw) {
    final d = DateTime.tryParse(raw?.toString() ?? '');
    if (d == null) return '—';
    return d.year.toString().padLeft(4, '0') +
        '-' +
        d.month.toString().padLeft(2, '0') +
        '-' +
        d.day.toString().padLeft(2, '0');
  }

  String _kindName(String kind) {
    switch (kind) {
      case 'savings':
        return 'Ahorro';
      case 'checking':
        return 'Cuenta bancaria';
      case 'credit_card':
        return 'Tarjeta de crédito';
      case 'cash':
        return 'Efectivo';
      default:
        return kind;
    }
  }

  Widget _accountTile(Map<String, dynamic> row) {
    final kind = row['account_kind']?.toString() ?? '';
    final balance = PersonalFinanceStore.displayBalance(row);
    final lastDate = _date(row['last_date']);
    if (kind == 'credit_card') {
      final limit = (row['credit_limit'] as num?)?.toDouble() ?? 0;
      final available = (limit - balance).clamp(0, double.infinity);
      final due = (row['payment_due_day'] as num?)?.toInt() ?? 0;
      final rewardType = row['rewards_type']?.toString() ?? 'none';
      final rewardBalance =
          (row['rewards_balance'] as num?)?.toDouble() ?? 0;
      final rewardPercent =
          (row['rewards_percent'] as num?)?.toDouble() ?? 0;
      final rewardText = rewardType == 'none'
          ? 'Sin rewards'
          : rewardType +
              ' · ' +
              rewardPercent.toStringAsFixed(2) +
              '% · ' +
              rewardBalance.toStringAsFixed(2);

      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.credit_card_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      row['name'].toString(),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar tarjeta',
                    onPressed: () => _openEditor(existing: row),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
              Text('Deuda: ' + balance.toStringAsFixed(2)),
              Text(
                'Límite: ' +
                    limit.toStringAsFixed(2) +
                    ' · Disponible: ' +
                    available.toStringAsFixed(2),
              ),
              Text('Rewards: ' + rewardText),
              Text(
                'Pago: ' +
                    (due > 0 ? 'día ' + due.toString() : 'sin fecha') +
                    (row['reminder_enabled'] == 1 ? ' · alarma activa' : ''),
              ),
              Text('Último movimiento: ' + lastDate),
              if (balance > 0.005) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _payCard(row),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Hacer pago parcial'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (kind == 'savings') {
      final contributed =
          (row['debit_total'] as num?)?.toDouble() ?? 0;
      final withdrawn =
          (row['credit_total'] as num?)?.toDouble() ?? 0;
      return Card(
        child: ListTile(
          leading: const Icon(Icons.savings_outlined),
          title: Text(row['name'].toString()),
          subtitle: Text(
            'Saldo ' +
                balance.toStringAsFixed(2) +
                ' · Aportado ' +
                contributed.toStringAsFixed(2) +
                ' · Retirado ' +
                withdrawn.toStringAsFixed(2) +
                '\nÚltimo movimiento: ' +
                lastDate,
          ),
          isThreeLine: true,
          trailing: IconButton(
            tooltip: 'Editar cuenta',
            onPressed: () => _openEditor(existing: row),
            icon: const Icon(Icons.edit_outlined),
          ),
        ),
      );
    }

    return Card(
      child: ListTile(
        leading: Icon(
          kind == 'cash'
              ? Icons.account_balance_wallet_outlined
              : Icons.account_balance_outlined,
        ),
        title: Text(row['name'].toString()),
        subtitle: Text(
          _kindName(kind) +
              ' · Saldo ' +
              balance.toStringAsFixed(2) +
              '\nÚltimo movimiento: ' +
              lastDate,
        ),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: 'Editar cuenta',
          onPressed: () => _openEditor(existing: row),
          icon: const Icon(Icons.edit_outlined),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final savings = rows
        .where((e) => e['account_kind'] == 'savings')
        .fold<double>(
          0,
          (sum, row) => sum + PersonalFinanceStore.displayBalance(row),
        );
    final unassigned = rows.where(
      (e) =>
          e['bank_id'] == null &&
          e['code'] != 'P2010' &&
          const {'cash', 'checking', 'savings', 'credit_card'}
              .contains(e['account_kind']?.toString()),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Billetera personal'),
        actions: [
          IconButton(
            tooltip: 'Agregar banco',
            onPressed: _addBank,
            icon: const Icon(Icons.add_business_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Nueva cuenta'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.savings_outlined),
                      title: const Text('Ahorros totales'),
                      subtitle: const Text(
                        'Suma de todas tus cuentas de ahorro personales',
                      ),
                      trailing: Text(
                        savings.toStringAsFixed(2),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _addBank,
                    icon: const Icon(Icons.add_business_outlined),
                    label: const Text('Agregar otro banco'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PersonalInternalAccountsPage(),
                      ),
                    ),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Ver cuentas internas'),
                  ),
                  const SizedBox(height: 10),
                  for (final bank in bankRows) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.account_balance_outlined),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    bank['name'].toString(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () => _openEditor(
                                    initialBankName: bank['name'].toString(),
                                  ),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Añadir'),
                                ),
                              ],
                            ),
                            for (final row in rows.where(
                              (r) => r['bank_id'] == bank['id'],
                            ))
                              _accountTile(row),
                            if (!rows.any(
                              (r) => r['bank_id'] == bank['id'],
                            ))
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  'Todavía no hay cuentas o tarjetas en este banco.',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (unassigned.isNotEmpty) ...[
                    Text(
                      'Sin banco',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    for (final row in unassigned) _accountTile(row),
                  ],
                  if (bankRows.isEmpty && unassigned.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Agrega tu primer banco y después crea sus cuentas de ahorro, cuentas bancarias o tarjetas de crédito.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class PersonalInternalAccountsPage extends StatefulWidget {
  const PersonalInternalAccountsPage({super.key});

  @override
  State<PersonalInternalAccountsPage> createState() =>
      _PersonalInternalAccountsPageState();
}

class _PersonalInternalAccountsPageState
    extends State<PersonalInternalAccountsPage> {
  bool loading = true;
  List<Map<String, dynamic>> rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await PersonalFinanceStore.accountBalances();
    if (!mounted) return;
    setState(() {
      rows = data
          .where(
            (e) =>
                e['is_system'] == 1 &&
                const {'P2010', 'P2020', 'P1040', 'P3010', 'P3900'}
                    .contains(e['code']?.toString()),
          )
          .toList();
      loading = false;
    });
  }

  double _shown(Map<String, dynamic> row) {
    final net = (row['net'] as num?)?.toDouble() ?? 0;
    return row['type'] == 'liability' ? -net : net;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cuentas internas')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                const Text(
                  'Estas cuentas sirven para compatibilidad contable y casos '
                  'temporales. No representan necesariamente una cuenta o '
                  'tarjeta real de un banco.',
                ),
                const SizedBox(height: 12),
                for (final row in rows)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(
                        row['code'].toString() +
                            ' · ' +
                            row['name'].toString(),
                      ),
                      subtitle: Text(
                        row['code'] == 'P2010'
                            ? 'Agrupa temporalmente deuda de tarjetas cuando '
                                'todavía no sabes cuál tarjeta real corresponde.'
                            : 'Cuenta interna del sistema personal.',
                      ),
                      trailing: Text(_shown(row).toStringAsFixed(2)),
                    ),
                  ),
              ],
            ),
    );
  }
}

class PersonalFinancialAccountEditorPage extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final String? initialBankName;
  const PersonalFinancialAccountEditorPage({
    super.key,
    this.existing,
    this.initialBankName,
  });

  @override
  State<PersonalFinancialAccountEditorPage> createState() =>
      _PersonalFinancialAccountEditorPageState();
}

class _PersonalFinancialAccountEditorPageState
    extends State<PersonalFinancialAccountEditorPage> {
  late final TextEditingController nameController;
  late final TextEditingController bankController;
  final initialController = TextEditingController();
  late final TextEditingController limitController;
  late final TextEditingController rewardsBalanceController;
  late final TextEditingController rewardsPercentController;

  late String kind;
  late String rewardsType;
  late int dueDay;
  late bool reminderEnabled;
  late int reminderDaysBefore;
  bool saving = false;

  bool get editing => widget.existing != null;
  bool get isCard => kind == 'credit_card';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    kind = e?['account_kind']?.toString() ?? 'savings';
    nameController = TextEditingController(text: e?['name']?.toString() ?? '');
    bankController = TextEditingController(
      text: e?['bank_name']?.toString() ?? widget.initialBankName ?? '',
    );
    limitController = TextEditingController(
      text: ((e?['credit_limit'] as num?)?.toDouble() ?? 0) > 0
          ? ((e?['credit_limit'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)
          : '',
    );
    rewardsBalanceController = TextEditingController(
      text: ((e?['rewards_balance'] as num?)?.toDouble() ?? 0) > 0
          ? ((e?['rewards_balance'] as num?)?.toDouble() ?? 0)
              .toStringAsFixed(2)
          : '',
    );
    rewardsPercentController = TextEditingController(
      text: ((e?['rewards_percent'] as num?)?.toDouble() ?? 0) > 0
          ? ((e?['rewards_percent'] as num?)?.toDouble() ?? 0)
              .toStringAsFixed(2)
          : '',
    );
    rewardsType = e?['rewards_type']?.toString() ?? 'none';
    dueDay = (e?['payment_due_day'] as num?)?.toInt() ?? 0;
    reminderEnabled = e?['reminder_enabled'] == 1;
    reminderDaysBefore =
        (e?['reminder_days_before'] as num?)?.toInt() ?? 1;
  }

  @override
  void dispose() {
    nameController.dispose();
    bankController.dispose();
    initialController.dispose();
    limitController.dispose();
    rewardsBalanceController.dispose();
    rewardsPercentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final initial =
        double.tryParse(initialController.text.trim().replaceAll(',', '.')) ??
            0;
    final limit =
        double.tryParse(limitController.text.trim().replaceAll(',', '.')) ?? 0;
    final rewardBalance = double.tryParse(
          rewardsBalanceController.text.trim().replaceAll(',', '.'),
        ) ??
        0;
    final rewardPercent = double.tryParse(
          rewardsPercentController.text.trim().replaceAll(',', '.'),
        ) ??
        0;

    if (nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe un nombre para la cuenta.')),
      );
      return;
    }
    if (initial < 0 || limit < 0 || rewardBalance < 0 || rewardPercent < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Los importes no pueden ser negativos.')),
      );
      return;
    }
    if (isCard && dueDay != 0 && (dueDay < 1 || dueDay > 31)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El día de pago debe estar entre 1 y 31.')),
      );
      return;
    }

    var effectiveReminder = reminderEnabled;
    if (isCard && reminderEnabled) {
      if (dueDay == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Selecciona el día de pago antes de activar la alarma.',
            ),
          ),
        );
        return;
      }
      final granted = await PersonalReminderBridge.requestPermission();
      if (!granted) {
        effectiveReminder = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No se concedió permiso de notificaciones. Guardaré la tarjeta sin alarma.',
              ),
            ),
          );
        }
      }
    }

    if (!mounted) return;
    setState(() => saving = true);
    try {
      if (editing) {
        await PersonalFinanceStore.updateFinancialAccount(
          id: widget.existing!['id'] as int,
          name: nameController.text,
          bankName: bankController.text,
          kind: kind,
          creditLimit: limit,
          paymentDueDay: dueDay,
          reminderEnabled: effectiveReminder,
          reminderDaysBefore: reminderDaysBefore,
          rewardsType: rewardsType,
          rewardsBalance: rewardBalance,
          rewardsPercent: rewardPercent,
        );
      } else {
        await PersonalFinanceStore.createFinancialAccount(
          name: nameController.text,
          bankName: bankController.text,
          kind: kind,
          creditLimit: limit,
          initialBalance: initial,
          paymentDueDay: dueDay,
          reminderEnabled: effectiveReminder,
          reminderDaysBefore: reminderDaysBefore,
          rewardsType: rewardsType,
          rewardsBalance: rewardBalance,
          rewardsPercent: rewardPercent,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pude guardar la cuenta: ' + e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Editar cuenta personal' : 'Nueva cuenta personal'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          DropdownButtonFormField<String>(
            initialValue: kind,
            decoration: const InputDecoration(
              labelText: 'Tipo',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'savings',
                child: Text('Cuenta de ahorro'),
              ),
              DropdownMenuItem(
                value: 'checking',
                child: Text('Cuenta bancaria / corriente'),
              ),
              DropdownMenuItem(
                value: 'credit_card',
                child: Text('Tarjeta de crédito'),
              ),
              DropdownMenuItem(
                value: 'cash',
                child: Text('Efectivo'),
              ),
            ],
            onChanged: editing || saving
                ? null
                : (v) {
                    if (v != null) setState(() => kind = v);
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: bankController,
            decoration: const InputDecoration(
              labelText: 'Banco',
              hintText: 'Puedes escribir un banco nuevo',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: isCard ? 'Nombre de la tarjeta' : 'Nombre de la cuenta',
              hintText:
                  isCard ? 'Ej.: Freedom Unlimited' : 'Ej.: Fondo de emergencia',
              border: const OutlineInputBorder(),
            ),
          ),
          if (!editing) ...[
            const SizedBox(height: 12),
            TextField(
              controller: initialController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText:
                    isCard ? 'Deuda actual inicial' : 'Saldo actual inicial',
                prefixText: '\$ ',
                helperText:
                    'Carga tu situación actual sin registrarla como ingreso nuevo.',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          if (isCard) ...[
            const SizedBox(height: 12),
            TextField(
              controller: limitController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Límite de crédito',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: rewardsType,
              decoration: const InputDecoration(
                labelText: 'Tipo de rewards',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('Sin rewards')),
                DropdownMenuItem(value: 'cashback', child: Text('Cashback')),
                DropdownMenuItem(value: 'points', child: Text('Puntos')),
                DropdownMenuItem(value: 'miles', child: Text('Millas')),
                DropdownMenuItem(value: 'other', child: Text('Otro')),
              ],
              onChanged: saving
                  ? null
                  : (v) {
                      if (v != null) setState(() => rewardsType = v);
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rewardsPercentController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '% de rewards',
                suffixText: '%',
                hintText: 'Ej.: 1.5, 2, 3',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rewardsBalanceController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Rewards acumulados',
                helperText:
                    'No se suman al patrimonio hasta que realmente los canjees.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: dueDay,
              decoration: const InputDecoration(
                labelText: 'Día de pago / vencimiento',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: 0, child: Text('Sin fecha')),
                for (var day = 1; day <= 31; day++)
                  DropdownMenuItem(value: day, child: Text('Día ' + day.toString())),
              ],
              onChanged: saving
                  ? null
                  : (v) {
                      if (v != null) setState(() => dueDay = v);
                    },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Programar alarma de pago'),
              subtitle: const Text(
                'La notificación se programa localmente en este teléfono.',
              ),
              value: reminderEnabled,
              onChanged: saving
                  ? null
                  : (v) => setState(() => reminderEnabled = v),
            ),
            if (reminderEnabled)
              DropdownButtonFormField<int>(
                initialValue: reminderDaysBefore,
                decoration: const InputDecoration(
                  labelText: 'Avisarme',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('El mismo día')),
                  DropdownMenuItem(value: 1, child: Text('1 día antes')),
                  DropdownMenuItem(value: 3, child: Text('3 días antes')),
                  DropdownMenuItem(value: 7, child: Text('7 días antes')),
                ],
                onChanged: saving
                    ? null
                    : (v) {
                        if (v != null) {
                          setState(() => reminderDaysBefore = v);
                        }
                      },
              ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: saving ? null : _save,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(saving ? 'Guardando…' : 'Guardar cuenta'),
          ),
        ],
      ),
    );
  }
}

class PersonalBalanceSheetPage extends StatefulWidget {
  const PersonalBalanceSheetPage({super.key});

  @override
  State<PersonalBalanceSheetPage> createState() =>
      _PersonalBalanceSheetPageState();
}

class _PersonalBalanceSheetPageState extends State<PersonalBalanceSheetPage> {
  bool loading = true;
  List<Map<String, dynamic>> rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await PersonalFinanceStore.accountBalances();
    if (!mounted) return;
    setState(() {
      rows = data;
      loading = false;
    });
  }

  double _balance(Map<String, dynamic> row) {
    final net = (row['net'] as num?)?.toDouble() ?? 0;
    return row['type'] == 'liability' ? -net : net;
  }

  Widget _section(
    String title,
    List<Map<String, dynamic>> data,
    double total,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  total.toStringAsFixed(2),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const Divider(),
            for (final row in data)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(row['name'].toString()),
                subtitle:
                    (row['bank_name']?.toString().trim().isNotEmpty ?? false)
                        ? Text(row['bank_name'].toString())
                        : Text(row['code'].toString()),
                trailing: Text(_balance(row).toStringAsFixed(2)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assets = rows
        .where((r) => r['type'] == 'asset' && _balance(r).abs() >= 0.005)
        .toList();
    final liabilities = rows
        .where(
          (r) => r['type'] == 'liability' && _balance(r).abs() >= 0.005,
        )
        .toList();
    final totalAssets =
        assets.fold<double>(0, (sum, row) => sum + _balance(row));
    final totalLiabilities =
        liabilities.fold<double>(0, (sum, row) => sum + _balance(row));
    final netWorth = totalAssets - totalLiabilities;

    return Scaffold(
      appBar: AppBar(title: const Text('Balance General personal')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _section('ACTIVOS', assets, totalAssets),
                  _section('PASIVOS', liabilities, totalLiabilities),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.balance_outlined),
                      title: const Text(
                        'PATRIMONIO NETO PERSONAL',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: const Text('Activos − Pasivos'),
                      trailing: Text(
                        netWorth.toStringAsFixed(2),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
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

  List<Map<String, dynamic>> accountRows = const [];
  bool loadingAccounts = true;
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

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final rows = await PersonalFinanceStore.allAccounts();
    if (!mounted) return;
    setState(() {
      accountRows = rows;
      loadingAccounts = false;
    });
    _resetAccounts();
  }

  @override
  void dispose() {
    amountController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  String _accountName(String code) {
    for (final row in accountRows) {
      if (row['code'] == code) return row['name'].toString();
    }
    for (final row in PersonalFinanceStore.accounts) {
      if (row[0] == code) return row[1];
    }
    return code;
  }

  List<String> _codesWhere(bool Function(Map<String, dynamic>) test) =>
      accountRows.where(test).map((e) => e['code'].toString()).toList();

  List<String> _allCodes() =>
      accountRows.map((e) => e['code'].toString()).toList();

  List<String> _liquidCodes() => _codesWhere(
        (r) => const {'cash', 'checking', 'savings'}
            .contains(r['account_kind']?.toString()),
      );

  List<String> _liabilityCodes() => _codesWhere(
        (r) => r['type'] == 'liability',
      );

  List<String> _expenseCodes() => _codesWhere(
        (r) => r['type'] == 'expense',
      );

  List<String> _revenueCodes() => _codesWhere(
        (r) => r['type'] == 'revenue',
      );

  List<String> _assetCodes() => _codesWhere(
        (r) => r['type'] == 'asset',
      );

  List<String> _debitOptions() {
    switch (kind) {
      case 'expense':
        return _expenseCodes();
      case 'income':
        return _liquidCodes();
      case 'transfer':
        return _liquidCodes();
      case 'debt':
        return debtMode == 'pay'
            ? _liabilityCodes()
            : [..._expenseCodes(), ..._assetCodes()];
      default:
        return _allCodes();
    }
  }

  List<String> _creditOptions() {
    switch (kind) {
      case 'expense':
        return [..._liquidCodes(), ..._liabilityCodes()];
      case 'income':
        return _revenueCodes();
      case 'transfer':
        return _liquidCodes();
      case 'debt':
        return debtMode == 'pay' ? _liquidCodes() : _liabilityCodes();
      default:
        return _allCodes();
    }
  }

  String _firstOr(List<String> values, String fallback) =>
      values.isEmpty ? fallback : values.first;

  void _resetAccounts() {
    if (accountRows.isEmpty) return;
    switch (kind) {
      case 'expense':
        debitCode = _firstOr(_expenseCodes(), 'P5010');
        creditCode = _firstOr(_liquidCodes(), 'P1010');
        break;
      case 'income':
        debitCode = _firstOr(_liquidCodes(), 'P1020');
        creditCode = _firstOr(_revenueCodes(), 'P4010');
        break;
      case 'transfer':
        final liquids = _liquidCodes();
        debitCode = _firstOr(liquids, 'P1020');
        creditCode = liquids.length > 1 ? liquids[1] : 'P1010';
        break;
      case 'debt':
        if (debtMode == 'pay') {
          debitCode = _firstOr(_liabilityCodes(), 'P2020');
          creditCode = _firstOr(_liquidCodes(), 'P1020');
        } else {
          debitCode = _firstOr(_expenseCodes(), 'P5040');
          creditCode = _firstOr(_liabilityCodes(), 'P2020');
        }
        break;
      default:
        debitCode = 'P1010';
        creditCode = 'P3010';
    }
    if (mounted) setState(() {});
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
        return debtMode == 'pay'
            ? 'Pago de deuda personal'
            : 'Nueva deuda personal';
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
            'MAN-P-${DateTime.now().millisecondsSinceEpoch}',
        date: date,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pude guardar el movimiento: $e')),
      );
    }
  }

  Widget _accountDropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    final safe = options.contains(value)
        ? value
        : options.isNotEmpty
            ? options.first
            : null;
    return DropdownButtonFormField<String>(
      initialValue: safe,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final code in options)
          DropdownMenuItem(
            value: code,
            child: Text('$code · ${_accountName(code)}'),
          ),
      ],
      onChanged: saving || options.isEmpty ? null : onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loadingAccounts) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final debitOptions = _debitOptions();
    final creditOptions = _creditOptions();
    if (debitOptions.isNotEmpty && !debitOptions.contains(debitCode)) {
      debitCode = debitOptions.first;
    }
    if (creditOptions.isNotEmpty && !creditOptions.contains(creditCode)) {
      creditCode = creditOptions.first;
    }

    final dateText = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

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
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
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
                'Vista previa\n\nDEBE  $debitCode · ${_accountName(debitCode)}'
                '\nHABER  $creditCode · ${_accountName(creditCode)}',
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
