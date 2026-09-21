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
        'date': DateTime.now().toIso8601String(),
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

  @override
  Widget build(BuildContext context) {
    final nonZero = balances.where(
      (r) => (((r['net'] as num?)?.toDouble() ?? 0).abs() >= 0.005),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Finanzas personales')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(14),
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
                  const SizedBox(height: 16),
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
                      title: Text('${row['code']} · ${row['name']}'),
                      trailing: Text(
                        ((row['net'] as num?)?.toDouble() ?? 0)
                            .toStringAsFixed(2),
                      ),
                    ),
                  if (nonZero.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Todavía no hay saldos personales registrados.'),
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
                      subtitle: Text(tx['date'].toString()),
                      trailing: Text(
                        ((tx['amount'] as num?)?.toDouble() ?? 0)
                            .toStringAsFixed(2),
                      ),
                    ),
                  if (recent.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Puedes registrar movimientos personales desde el Asistente financiero.',
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
