import 'models.dart';

class AccountingEngine {
  static const epsilon = 0.005;

  void validate(JournalTransaction tx) {
    if (tx.description.trim().isEmpty) throw const FormatException('La descripción es obligatoria.');
    if (tx.lines.length < 2) throw const FormatException('Un asiento necesita al menos dos líneas.');
    final debit = tx.lines.fold<double>(0, (s, l) => s + l.debit);
    final credit = tx.lines.fold<double>(0, (s, l) => s + l.credit);
    if (tx.lines.any((l) => l.debit < 0 || l.credit < 0 || (l.debit > 0 && l.credit > 0))) {
      throw const FormatException('Cada línea debe tener débito o crédito positivo, no ambos.');
    }
    if ((debit - credit).abs() > epsilon || debit <= 0) {
      throw FormatException('El asiento no cuadra. Débitos: ${debit.toStringAsFixed(2)}; créditos: ${credit.toStringAsFixed(2)}.');
    }
  }

  List<AccountBalance> trialBalance(List<Account> accounts, List<JournalTransaction> transactions, {DateTime? from, DateTime? to}) {
    final sums = <int, List<double>>{};
    for (final tx in transactions) {
      if (from != null && tx.date.isBefore(from)) continue;
      if (to != null && tx.date.isAfter(to)) continue;
      for (final l in tx.lines) {
        final pair = sums.putIfAbsent(l.accountId, () => [0, 0]);
        pair[0] += l.debit; pair[1] += l.credit;
      }
    }
    return accounts.map((a) => AccountBalance(a, sums[a.id]?[0] ?? 0, sums[a.id]?[1] ?? 0)).toList();
  }

  List<ReportRow> incomeStatement(List<AccountBalance> b) {
    final revenues = b.where((x) => x.account.type == AccountType.revenue).fold<double>(0, (s, x) => s + x.signed);
    double exp(String subtype) => b.where((x) => x.account.type == AccountType.expense && x.account.subtype == subtype).fold<double>(0, (s, x) => s + x.signed);
    final cogs = exp('cogs');
    final operating = exp('operating');
    final depreciation = exp('depreciation');
    final interest = exp('interest');
    final tax = exp('tax');
    final other = b.where((x) => x.account.type == AccountType.expense && !['cogs','operating','depreciation','interest','tax'].contains(x.account.subtype)).fold<double>(0, (s,x)=>s+x.signed);
    final gross = revenues - cogs;
    final ebit = gross - operating - depreciation - other;
    final pretax = ebit - interest;
    return [
      ReportRow('Ingresos / Ventas', revenues), ReportRow('(-) Costo de ventas', -cogs),
      ReportRow('UTILIDAD BRUTA', gross, total: true), ReportRow('(-) Gastos operativos', -operating),
      ReportRow('(-) Depreciación', -depreciation), ReportRow('(-) Otros gastos', -other),
      ReportRow('UTILIDAD OPERATIVA (EBIT)', ebit, total: true), ReportRow('(-) Intereses', -interest),
      ReportRow('UTILIDAD ANTES DE IMPUESTOS', pretax, total: true), ReportRow('(-) Impuestos', -tax),
      ReportRow('UTILIDAD NETA', pretax - tax, total: true),
    ];
  }

  Map<String, List<ReportRow>> balanceSheet(List<AccountBalance> b) {
    List<ReportRow> rows(AccountType type) => b.where((x) => x.account.type == type && x.signed.abs() > epsilon).map((x) => ReportRow(x.account.name, x.signed)).toList();
    final assets = rows(AccountType.asset), liabilities = rows(AccountType.liability), equity = rows(AccountType.equity);
    double sum(List<ReportRow> r) => r.fold(0, (s, x) => s + x.amount);
    return {
      'Activos': [...assets, ReportRow('TOTAL ACTIVOS', sum(assets), total: true)],
      'Pasivos': [...liabilities, ReportRow('TOTAL PASIVOS', sum(liabilities), total: true)],
      'Patrimonio': [...equity, ReportRow('TOTAL PATRIMONIO', sum(equity), total: true)],
    };
  }

  List<ReportRow> cashFlow(List<Account> accounts, List<JournalTransaction> txs) {
    final cashIds = accounts.where((a) => a.subtype == 'cash').map((a) => a.id).toSet();
    double cashEffect(JournalTransaction tx) => tx.lines.where((l) => cashIds.contains(l.accountId)).fold(0, (s,l)=>s+l.debit-l.credit);
    double cls(String value) => txs.where((t) => t.cashFlowClass == value).fold(0, (s,t)=>s+cashEffect(t));
    final op=cls('operating'), inv=cls('investing'), fin=cls('financing');
    return [ReportRow('Actividades operativas',op),ReportRow('Actividades de inversión',inv),ReportRow('Actividades de financiamiento',fin),ReportRow('CAMBIO NETO EN EFECTIVO',op+inv+fin,total:true)];
  }

  List<ReportRow> equityStatement(List<AccountBalance> b) {
    double st(String subtype) => b.where((x)=>x.account.type==AccountType.equity && x.account.subtype==subtype).fold(0,(s,x)=>s+x.signed);
    final capital=st('capital'), retained=st('retained'), drawings=st('drawings');
    final net=incomeStatement(b).last.amount;
    return [ReportRow('Aportes de propietarios',capital),ReportRow('Utilidades acumuladas anteriores',retained),ReportRow('Utilidad neta del período',net),ReportRow('(-) Dividendos o retiros',drawings),ReportRow('PATRIMONIO FINAL',capital+retained+net+drawings,total:true)];
  }
}
