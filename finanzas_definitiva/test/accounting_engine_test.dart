import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas_definitiva/accounting_engine.dart';
import 'package:finanzas_definitiva/models.dart';

void main(){test('rechaza asientos descuadrados',(){final tx=JournalTransaction(date:DateTime(2026),description:'Prueba',lines:const [JournalLine(accountId:1,debit:100),JournalLine(accountId:2,credit:90)]);expect(()=>AccountingEngine().validate(tx),throwsFormatException);});test('calcula utilidad neta',(){const accounts=[Account(id:1,code:'4',name:'Ventas',type:AccountType.revenue),Account(id:2,code:'5',name:'Costo',type:AccountType.expense,subtype:'cogs')];const tx=[JournalTransaction(date:DateTime(2026),description:'Venta',lines:[JournalLine(accountId:1,credit:100),JournalLine(accountId:2,debit:40)])];final b=AccountingEngine().trialBalance(accounts,tx);expect(AccountingEngine().incomeStatement(b).last.amount,60);});}
