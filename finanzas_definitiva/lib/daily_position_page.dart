import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'accounting_engine.dart';
import 'database.dart';
import 'models.dart';

class DailyPositionPage extends StatefulWidget {
  const DailyPositionPage({super.key});
  @override
  State<DailyPositionPage> createState() => _DailyPositionPageState();
}

class _DailyPositionPageState extends State<DailyPositionPage> {
  DateTime selected = DateTime.now();

  DateTime get start => DateTime(selected.year, selected.month, selected.day);
  DateTime get end => start.add(const Duration(days: 1)).subtract(const Duration(microseconds: 1));

  Future<_DailyData> load() async {
    final db = AppDatabase.instance;
    final accounts = await db.accounts();
    final txs = await db.transactions();
    final currency = await db.setting('currency');
    final engine = AccountingEngine();

    final throughDate = engine.trialBalance(accounts, txs, to: end);
    final throughYesterday = engine.trialBalance(accounts, txs, to: start.subtract(const Duration(microseconds: 1)));
    final today = engine.trialBalance(accounts, txs, from: start, to: end);

    double balanceBySubtype(List<AccountBalance> balances, String subtype) => balances
        .where((b) => b.account.subtype == subtype)
        .fold(0, (sum, b) => sum + b.signed);
    double typeTotal(List<AccountBalance> balances, AccountType type) => balances
        .where((b) => b.account.type == type)
        .fold(0, (sum, b) => sum + b.signed);

    final cash = balanceBySubtype(throughDate, 'cash');
    final previousCash = balanceBySubtype(throughYesterday, 'cash');
    final assets = typeTotal(throughDate, AccountType.asset);
    final liabilities = typeTotal(throughDate, AccountType.liability);
    final directEquity = typeTotal(throughDate, AccountType.equity);
    final accumulatedProfit = engine.incomeStatement(throughDate).last.amount;
    final incomeToday = typeTotal(today, AccountType.revenue);
    final expensesToday = typeTotal(today, AccountType.expense);

    final cashIds = accounts.where((a) => a.subtype == 'cash').map((a) => a.id).toSet();
    double inflows = 0, outflows = 0;
    for (final tx in txs.where((t) => !t.date.isBefore(start) && !t.date.isAfter(end))) {
      for (final line in tx.lines.where((l) => cashIds.contains(l.accountId))) {
        inflows += line.debit;
        outflows += line.credit;
      }
    }

    return _DailyData(
      currency: currency,
      cash: cash,
      previousCash: previousCash,
      assets: assets,
      liabilities: liabilities,
      equity: directEquity + accumulatedProfit,
      receivables: balanceBySubtype(throughDate, 'receivable'),
      payables: balanceBySubtype(throughDate, 'payable'),
      inventory: balanceBySubtype(throughDate, 'inventory'),
      incomeToday: incomeToday,
      expensesToday: expensesToday,
      inflows: inflows,
      outflows: outflows,
    );
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selected,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => selected = picked);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Posición diaria')),
        body: FutureBuilder<_DailyData>(
          key: ValueKey(selected),
          future: load(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final d = snapshot.data!;
            final change = d.cash - d.previousCash;
            final profitToday = d.incomeToday - d.expensesToday;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: const Color(0xffecfeff),
                  child: ListTile(
                    leading: const Icon(Icons.calendar_month, color: Color(0xff0e7490)),
                    title: const Text('Posición al cierre de'),
                    subtitle: Text(DateFormat('dd/MM/yyyy').format(selected), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    trailing: const Icon(Icons.edit_calendar),
                    onTap: pickDate,
                  ),
                ),
                const SizedBox(height: 10),
                _HeroAmount('Dinero disponible', d.cash, d.currency, change),
                const SizedBox(height: 14),
                const _SectionTitle('Situación acumulada'),
                _MoneyRow('Activos totales', d.assets, d.currency),
                _MoneyRow('Pasivos totales', d.liabilities, d.currency),
                _MoneyRow('Patrimonio', d.equity, d.currency, strong: true),
                _MoneyRow('Cuentas por cobrar', d.receivables, d.currency),
                _MoneyRow('Cuentas por pagar', d.payables, d.currency),
                _MoneyRow('Inventario', d.inventory, d.currency),
                const SizedBox(height: 14),
                const _SectionTitle('Actividad de ese día'),
                _MoneyRow('Ingresos reconocidos', d.incomeToday, d.currency),
                _MoneyRow('Gastos reconocidos', d.expensesToday, d.currency),
                _MoneyRow('Resultado del día', profitToday, d.currency, strong: true),
                const SizedBox(height: 14),
                const _SectionTitle('Movimiento de dinero del día'),
                _MoneyRow('Entradas de efectivo', d.inflows, d.currency, color: Colors.green.shade700),
                _MoneyRow('Salidas de efectivo', -d.outflows, d.currency, color: Colors.red.shade700),
                _MoneyRow('Flujo neto diario', d.inflows - d.outflows, d.currency, strong: true),
                const SizedBox(height: 16),
                Card(
                  color: const Color(0xfffffbeb),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('El dinero disponible y el patrimonio no son lo mismo. Comprar maquinaria reduce el efectivo, pero cambia efectivo por otro activo y no reduce inmediatamente el patrimonio.'),
                  ),
                ),
              ],
            );
          },
        ),
      );
}

class _HeroAmount extends StatelessWidget {
  final String label, currency;
  final double amount, change;
  const _HeroAmount(this.label, this.amount, this.currency, this.change);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: const Color(0xff164e63), borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text('$currency ${amount.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('${change >= 0 ? '+' : ''}$currency ${change.toStringAsFixed(2)} frente al día anterior', style: TextStyle(color: change >= 0 ? Colors.greenAccent : Colors.orangeAccent)),
        ]),
      );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)));
}

class _MoneyRow extends StatelessWidget {
  final String label, currency;
  final double amount;
  final bool strong;
  final Color? color;
  const _MoneyRow(this.label, this.amount, this.currency, {this.strong = false, this.color});
  @override
  Widget build(BuildContext context) => Container(
        color: strong ? const Color(0xffdbeafe) : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: strong ? FontWeight.bold : null))),
          Text('$currency ${amount.toStringAsFixed(2)}', style: TextStyle(fontWeight: strong ? FontWeight.bold : null, color: color)),
        ]),
      );
}

class _DailyData {
  final String currency;
  final double cash, previousCash, assets, liabilities, equity, receivables, payables, inventory, incomeToday, expensesToday, inflows, outflows;
  const _DailyData({required this.currency, required this.cash, required this.previousCash, required this.assets, required this.liabilities, required this.equity, required this.receivables, required this.payables, required this.inventory, required this.incomeToday, required this.expensesToday, required this.inflows, required this.outflows});
}
