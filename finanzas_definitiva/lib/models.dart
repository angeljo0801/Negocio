enum AccountType { asset, liability, equity, revenue, expense }

class Account {
  final int? id;
  final String code;
  final String name;
  final AccountType type;
  final String subtype;
  const Account({this.id, required this.code, required this.name, required this.type, this.subtype = ''});
  Map<String, Object?> toMap() => {'id': id, 'code': code, 'name': name, 'type': type.name, 'subtype': subtype};
  factory Account.fromMap(Map<String, Object?> m) => Account(id: m['id'] as int?, code: m['code'] as String, name: m['name'] as String, type: AccountType.values.byName(m['type'] as String), subtype: (m['subtype'] ?? '') as String);
}

class JournalLine {
  final int? id;
  final int? transactionId;
  final int accountId;
  final double debit;
  final double credit;
  const JournalLine({this.id, this.transactionId, required this.accountId, this.debit = 0, this.credit = 0});
  Map<String, Object?> toMap(int txId) => {'id': id, 'transaction_id': txId, 'account_id': accountId, 'debit': debit, 'credit': credit};
}

class JournalTransaction {
  final int? id;
  final DateTime date;
  final String description;
  final String reference;
  final String cashFlowClass;
  final List<JournalLine> lines;
  const JournalTransaction({this.id, required this.date, required this.description, this.reference = '', this.cashFlowClass = 'operating', required this.lines});
}

class AccountBalance {
  final Account account;
  final double debit;
  final double credit;
  const AccountBalance(this.account, this.debit, this.credit);
  double get signed => switch (account.type) {
    AccountType.asset || AccountType.expense => debit - credit,
    _ => credit - debit,
  };
}

class ReportRow {
  final String label;
  final double amount;
  final bool total;
  const ReportRow(this.label, this.amount, {this.total = false});
}
