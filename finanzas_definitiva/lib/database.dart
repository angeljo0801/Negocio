import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'accounting_engine.dart';
import 'models.dart';

class AppDatabase {
  AppDatabase._();
  static final instance = AppDatabase._();
  Database? _db;
  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async => openDatabase(join(await getDatabasesPath(), 'finanzas_definitiva.db'), version: 1, onCreate: (d, _) async {
    await d.execute('CREATE TABLE accounts(id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT UNIQUE, name TEXT, type TEXT, subtype TEXT)');
    await d.execute('CREATE TABLE transactions(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, description TEXT, reference TEXT, cash_flow_class TEXT)');
    await d.execute('CREATE TABLE journal_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, transaction_id INTEGER, account_id INTEGER, debit REAL, credit REAL, FOREIGN KEY(transaction_id) REFERENCES transactions(id))');
    await d.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)');
    await _seed(d);
  });

  Future<void> _seed(Database d) async {
    final accounts = <Account>[
      const Account(code:'1010',name:'Efectivo',type:AccountType.asset,subtype:'cash'),
      const Account(code:'1020',name:'Cuentas por cobrar',type:AccountType.asset,subtype:'receivable'),
      const Account(code:'1030',name:'Inventario',type:AccountType.asset,subtype:'inventory'),
      const Account(code:'1500',name:'Maquinaria',type:AccountType.asset,subtype:'fixed_asset'),
      const Account(code:'1590',name:'Depreciación acumulada',type:AccountType.asset,subtype:'contra_asset'),
      const Account(code:'2010',name:'Cuentas por pagar',type:AccountType.liability,subtype:'payable'),
      const Account(code:'2500',name:'Préstamo bancario',type:AccountType.liability,subtype:'loan'),
      const Account(code:'3010',name:'Capital aportado',type:AccountType.equity,subtype:'capital'),
      const Account(code:'3020',name:'Utilidades acumuladas',type:AccountType.equity,subtype:'retained'),
      const Account(code:'3030',name:'Dividendos / Retiros',type:AccountType.equity,subtype:'drawings'),
      const Account(code:'4010',name:'Ventas',type:AccountType.revenue,subtype:'sales'),
      const Account(code:'5010',name:'Costo de ventas',type:AccountType.expense,subtype:'cogs'),
      const Account(code:'6010',name:'Salarios',type:AccountType.expense,subtype:'operating'),
      const Account(code:'6020',name:'Alquiler',type:AccountType.expense,subtype:'operating'),
      const Account(code:'6030',name:'Publicidad',type:AccountType.expense,subtype:'operating'),
      const Account(code:'6040',name:'Servicios básicos',type:AccountType.expense,subtype:'operating'),
      const Account(code:'6050',name:'Depreciación',type:AccountType.expense,subtype:'depreciation'),
      const Account(code:'7010',name:'Intereses',type:AccountType.expense,subtype:'interest'),
      const Account(code:'8010',name:'Impuestos',type:AccountType.expense,subtype:'tax'),
    ];
    for(final a in accounts) { final m=a.toMap()..remove('id'); await d.insert('accounts',m); }
    await d.insert('settings', {'key':'company','value':'Mi Empresa'});
    await d.insert('settings', {'key':'currency','value':'USD'});
  }

  Future<List<Account>> accounts() async => (await (await db).query('accounts',orderBy:'code')).map(Account.fromMap).toList();
  Future<List<JournalTransaction>> transactions() async {
    final d=await db; final txRows=await d.query('transactions',orderBy:'date DESC,id DESC'); final result=<JournalTransaction>[];
    for(final t in txRows){
      final lines=(await d.query('journal_lines',where:'transaction_id=?',whereArgs:[t['id']])).map((l)=>JournalLine(id:l['id'] as int,transactionId:l['transaction_id'] as int,accountId:l['account_id'] as int,debit:(l['debit'] as num).toDouble(),credit:(l['credit'] as num).toDouble())).toList();
      result.add(JournalTransaction(id:t['id'] as int,date:DateTime.parse(t['date'] as String),description:t['description'] as String,reference:t['reference'] as String,cashFlowClass:t['cash_flow_class'] as String,lines:lines));
    } return result;
  }
  Future<void> addTransaction(JournalTransaction tx) async {
    AccountingEngine().validate(tx); final d=await db;
    await d.transaction((b) async { final id=await b.insert('transactions',{'date':tx.date.toIso8601String(),'description':tx.description,'reference':tx.reference,'cash_flow_class':tx.cashFlowClass}); for(final l in tx.lines) await b.insert('journal_lines',l.toMap(id)..remove('id')); });
  }
  Future<void> deleteTransaction(int id) async { final d=await db; await d.transaction((b) async {await b.delete('journal_lines',where:'transaction_id=?',whereArgs:[id]);await b.delete('transactions',where:'id=?',whereArgs:[id]);}); }
  Future<String> setting(String key) async { final rows=await (await db).query('settings',where:'key=?',whereArgs:[key]); return rows.isEmpty ? '' : (rows.first['value'] as String? ?? ''); }
  Future<void> setSetting(String key,String value) async => (await db).insert('settings',{'key':key,'value':value},conflictAlgorithm:ConflictAlgorithm.replace);
  Future<void> clearAll() async { final d=await db; await d.transaction((b) async {await b.delete('journal_lines');await b.delete('transactions');}); }
  Future<void> loadDemo() async {
    await clearAll();
    Future<void> add(String text,String cls,List<JournalLine> lines)=>addTransaction(JournalTransaction(date:DateTime(2026,12,31),description:text,cashFlowClass:cls,lines:lines));
    await add('Aporte inicial','financing',[const JournalLine(accountId:1,debit:50000),const JournalLine(accountId:8,credit:50000)]);
    await add('Préstamo bancario recibido','financing',[const JournalLine(accountId:1,debit:20000),const JournalLine(accountId:7,credit:20000)]);
    await add('Compra de maquinaria','investing',[const JournalLine(accountId:4,debit:30000),const JournalLine(accountId:1,credit:30000)]);
    await add('Compra de inventario','operating',[const JournalLine(accountId:3,debit:48000),const JournalLine(accountId:1,credit:45000),const JournalLine(accountId:6,credit:3000)]);
    await add('Ventas cobradas y a crédito','operating',[const JournalLine(accountId:1,debit:90000),const JournalLine(accountId:2,debit:10000),const JournalLine(accountId:11,credit:100000)]);
    await add('Costo de productos vendidos','noncash',[const JournalLine(accountId:12,debit:40000),const JournalLine(accountId:3,credit:40000)]);
    await add('Gastos operativos pagados','operating',[const JournalLine(accountId:13,debit:18000),const JournalLine(accountId:14,debit:12000),const JournalLine(accountId:15,debit:4000),const JournalLine(accountId:16,debit:3000),const JournalLine(accountId:1,credit:37000)]);
    await add('Depreciación del año','noncash',[const JournalLine(accountId:17,debit:6000),const JournalLine(accountId:5,credit:6000)]);
    await add('Intereses pagados','operating',[const JournalLine(accountId:18,debit:2000),const JournalLine(accountId:1,credit:2000)]);
    await add('Impuestos pagados','operating',[const JournalLine(accountId:19,debit:5000),const JournalLine(accountId:1,credit:5000)]);
    await add('Pago de principal del préstamo','financing',[const JournalLine(accountId:7,debit:5000),const JournalLine(accountId:1,credit:5000)]);
    await add('Dividendos a propietarios','financing',[const JournalLine(accountId:10,debit:4000),const JournalLine(accountId:1,credit:4000)]);
  }
}
