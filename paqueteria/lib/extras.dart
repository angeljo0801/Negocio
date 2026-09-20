part of 'main.dart';

class FinanceSyncService {
  static const String snapshotKey = 'finance_sync_snapshot';
  static const String syncedAtKey = 'finance_sync_updated_at';

  static Future<void> refreshSnapshot() async {
    try {
      final r = await Future.wait([
        Store.list('clients'),
        Store.list('recipients'),
        Store.list('purchases'),
        Store.list('packages'),
        Store.list('payments'),
        Store.list('trips'),
        Store.list('expenses'),
        Store.list('agencyShipments'),
        Store.list('agents'),
        Store.list('agentReports'),
        Store.settings(),
      ]);
      final clients = active(r[0] as List<Map<String, dynamic>>);
      final recipients = active(r[1] as List<Map<String, dynamic>>);
      final purchases = active(r[2] as List<Map<String, dynamic>>);
      final packages = active(r[3] as List<Map<String, dynamic>>);
      final payments = active(r[4] as List<Map<String, dynamic>>);
      final trips = active(r[5] as List<Map<String, dynamic>>);
      final expenses = active(r[6] as List<Map<String, dynamic>>);
      final agencyShipments = active(r[7] as List<Map<String, dynamic>>);
      final agents = active(r[8] as List<Map<String, dynamic>>);
      final agentReports = active(r[9] as List<Map<String, dynamic>>);
      final settings = Map<String, dynamic>.from(r[10] as Map);

      final clientBalances = <Map<String, dynamic>>[];
      for (final client in clients) {
        final id = '${client['id']}';
        final owed = purchases.fold<double>(0, (sum, p) => sum + purchaseAmountForClient(p, id));
        final paid = payments.where((p) => '${p['clientId']}' == id).fold<double>(0, (sum, p) => sum + number(p['amount']));
        clientBalances.add({
          'clientId': id,
          'name': '${client['name'] ?? ''}',
          'owed': owed,
          'paid': paid,
          'balance': owed - paid,
        });
      }

      double tripRevenue = 0, tripCosts = 0;
      for (final t in trips) {
        final ids = dynList(t['packageIds']).map((e) => '$e').toSet();
        final weight = packages.where((p) => ids.contains('${p['id']}')).fold<double>(0, (sum, p) => sum + number(p['billWeight']));
        tripRevenue += weight * number(t['ratePerLb']);
        tripCosts += tripExpenses(t);
      }

      double agencyRevenue = 0, agencyCosts = 0;
      for (final a in agencyShipments) {
        final ids = dynList(a['packageIds']).map((e) => '$e').toSet();
        final weight = packages.where((p) => ids.contains('${p['id']}')).fold<double>(0, (sum, p) => sum + number(p['billWeight']));
        agencyRevenue += weight * number(a['sellRatePerLb']);
        agencyCosts += weight * number(a['agencyCostPerLb']) + number(a['fuelCost']) + agencyOtherExpenses(a);
      }

      final agentBalances = <Map<String, dynamic>>[];
      for (final agent in agents) {
        final report = latestAgentReport('${agent['id']}', agentReports);
        agentBalances.add({
          'agentId': '${agent['id']}',
          'name': '${agent['name'] ?? ''}',
          'balance': agentBalanceFromReport(report),
          'shippingDue': agentShippingDue(report),
          'ordersDue': agentOrdersDue(report),
          'remittancesLiquidated': agentRemittancesLiquidated(report),
          'settled': agentSettled(report),
        });
      }

      final purchaseCost = purchases.fold<double>(0, (sum, e) => sum + number(e['total']));
      final purchaseClientTotal = purchases.fold<double>(0, (sum, e) => sum + number(e['clientTotal']));
      final paymentsTotal = payments.fold<double>(0, (sum, e) => sum + number(e['amount']));
      final expenseTotal = expenses.fold<double>(0, (sum, e) => sum + number(e['amount']));
      final packageWeight = packages.fold<double>(0, (sum, e) => sum + number(e['billWeight']));
      final receivables = clientBalances.fold<double>(0, (sum, e) => sum + (number(e['balance']) > 0 ? number(e['balance']) : 0));
      final agentReceivables = agentBalances.fold<double>(0, (sum, e) => sum + (number(e['balance']) > 0 ? number(e['balance']) : 0));

      final generatedAt = DateTime.now().toIso8601String();
      final snapshot = {
        'schema': 'alas-cargo-finance-sync-v1',
        'generatedAt': generatedAt,
        'settings': settings,
        'clients': clients,
        'recipients': recipients,
        'purchases': purchases,
        'packages': packages,
        'payments': payments,
        'trips': trips,
        'expenses': expenses,
        'agencyShipments': agencyShipments,
        'agents': agents,
        'agentReports': agentReports,
        'clientBalances': clientBalances,
        'agentBalances': agentBalances,
        'summary': {
          'purchaseCost': purchaseCost,
          'purchaseClientTotal': purchaseClientTotal,
          'purchaseMargin': purchaseClientTotal - purchaseCost,
          'payments': paymentsTotal,
          'clientReceivables': receivables,
          'agentReceivables': agentReceivables,
          'packageCount': packages.length,
          'packageWeightLb': packageWeight,
          'tripRevenueEstimated': tripRevenue,
          'tripCostsEstimated': tripCosts,
          'tripProfitEstimated': tripRevenue - tripCosts,
          'agencyRevenueEstimated': agencyRevenue,
          'agencyCostsEstimated': agencyCosts,
          'agencyProfitEstimated': agencyRevenue - agencyCosts,
          'generalExpenses': expenseTotal,
        },
      };
      final p = await SharedPreferences.getInstance();
      await p.setString(snapshotKey, jsonEncode(snapshot));
      await p.setString(syncedAtKey, generatedAt);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> currentSnapshot() async {
    await refreshSnapshot();
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(snapshotKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }
}

class FinanceSyncPage extends StatefulWidget {
  const FinanceSyncPage({super.key});
  @override
  State<FinanceSyncPage> createState() => _FinanceSyncPageState();
}

class _FinanceSyncPageState extends State<FinanceSyncPage> {
  Map<String, dynamic> data = {};
  bool busy = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) setState(() => busy = true);
    final d = await FinanceSyncService.currentSnapshot();
    if (!mounted) return;
    setState(() {
      data = d;
      busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = data['summary'] is Map ? Map<String, dynamic>.from(data['summary'] as Map) : <String, dynamic>{};
    final generated = '${data['generatedAt'] ?? ''}';
    return Scaffold(
      appBar: AppBar(title: const Text('Sincronización con Finanzas')),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _sectionCard(context, 'Conexión local', Icons.sync_alt, [
                    const Text('Finanzas Definitiva puede leer estos datos directamente cuando ambas APK están instaladas en este teléfono. No necesita internet.'),
                    const SizedBox(height: 8),
                    Text(generated.isEmpty ? 'Todavía no se ha generado un snapshot.' : 'Última actualización: $generated'),
                    const SizedBox(height: 10),
                    FilledButton.icon(onPressed: load, icon: const Icon(Icons.sync), label: const Text('Actualizar datos para Finanzas')),
                  ]),
                  const SizedBox(height: 12),
                  _sectionCard(context, 'Datos disponibles', Icons.storage, [
                    Text('Clientes: ${dynList(data['clients']).length}'),
                    Text('Compras: ${dynList(data['purchases']).length}'),
                    Text('Paquetes: ${dynList(data['packages']).length}'),
                    Text('Pagos: ${dynList(data['payments']).length}'),
                    Text('Viajes: ${dynList(data['trips']).length}'),
                    Text('Gastos: ${dynList(data['expenses']).length}'),
                    Text('Agentes: ${dynList(data['agents']).length}'),
                  ]),
                  const SizedBox(height: 12),
                  _sectionCard(context, 'Resumen que recibirá Finanzas', Icons.account_balance_wallet_outlined, [
                    Text('Costo de compras: ${money(number(summary['purchaseCost']))}'),
                    Text('Total a clientes por compras: ${money(number(summary['purchaseClientTotal']))}'),
                    Text('Pendiente de clientes: ${money(number(summary['clientReceivables']))}'),
                    Text('Pendiente de agentes: ${money(number(summary['agentReceivables']))}'),
                    Text('Peso de paquetes: ${number(summary['packageWeightLb']).toStringAsFixed(1)} lb'),
                    Text('Gastos generales: ${money(number(summary['generalExpenses']))}'),
                    Text('Resultado estimado de viajes: ${money(number(summary['tripProfitEstimated']))}'),
                    Text('Resultado estimado por agencias: ${money(number(summary['agencyProfitEstimated']))}'),
                  ]),
                ],
              ),
            ),
    );
  }
}


class ExpensesPage extends StatefulWidget{const ExpensesPage({super.key});@override State<ExpensesPage> createState()=>_ExpensesPageState();}
class _ExpensesPageState extends State<ExpensesPage>{List<Map<String,dynamic>>rows=[];@override void initState(){super.initState();load();}Future<void>load()async{rows=active(await Store.list('expenses'));if(mounted)setState((){});}Future<void>edit([Map<String,dynamic>?e])async{final n=TextEditingController(text:'${e?['name']??''}'),a=TextEditingController(text:'${e?['amount']??''}'),note=TextEditingController(text:'${e?['notes']??''}');final ok=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(title:Text(e==null?'Nuevo gasto general':'Editar gasto'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:n,decoration:const InputDecoration(labelText:'Concepto')),const SizedBox(height:8),TextField(controller:a,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Monto')),const SizedBox(height:8),TextField(controller:note,decoration:const InputDecoration(labelText:'Notas'))])),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Guardar'))]));if(ok==true&&n.text.trim().isNotEmpty){final all=await Store.list('expenses');final item={'id':e?['id']??newId(),'name':n.text.trim(),'amount':number(a.text),'notes':note.text.trim(),'date':e?['date']??today(),'deleted':false};final i=all.indexWhere((x)=>x['id']==item['id']);if(i>=0)all[i]={...all[i],...item};else all.add(item);await Store.saveList('expenses',all);load();}}
@override Widget build(BuildContext context){final total=rows.fold<double>(0,(a,e)=>a+number(e['amount']));return Scaffold(appBar:AppBar(title:const Text('Gastos del negocio')),body:ListView(padding:const EdgeInsets.all(12),children:[_sectionCard(context,'Total registrado',Icons.account_balance_wallet,[Text(money(total),style:Theme.of(context).textTheme.headlineSmall)]),for(final e in rows)ListTile(title:Text('${e['name']}'),subtitle:Text('${e['date']} · ${e['notes']}'),trailing:Text(money(number(e['amount']))),onTap:()=>edit(e))]),floatingActionButton:FloatingActionButton.extended(onPressed:()=>edit(),icon:const Icon(Icons.add),label:const Text('Gasto')));}}

class FinancePage extends StatefulWidget{const FinancePage({super.key});@override State<FinancePage> createState()=>_FinancePageState();}
class _FinancePageState extends State<FinancePage>{List<Map<String,dynamic>>purchases=[],payments=[],expenses=[],trips=[],packages=[];@override void initState(){super.initState();load();}Future<void>load()async{final r=await Future.wait([Store.list('purchases'),Store.list('payments'),Store.list('expenses'),Store.list('trips'),Store.list('packages')]);if(!mounted)return;setState((){purchases=active(r[0]);payments=active(r[1]);expenses=active(r[2]);trips=active(r[3]);packages=active(r[4]);});}@override Widget build(BuildContext context){final purchaseRevenue=purchases.fold<double>(0,(a,e)=>a+(number(e['clientTotal'])-number(e['total'])));final paid=payments.fold<double>(0,(a,e)=>a+number(e['amount']));final general=expenses.fold<double>(0,(a,e)=>a+number(e['amount']));double tripProfit=0;for(final t in trips){final ids=dynList(t['packageIds']).map((e)=>'$e').toSet();final w=packages.where((p)=>ids.contains('${p['id']}')).fold<double>(0,(a,e)=>a+number(e['billWeight']));tripProfit+=w*number(t['ratePerLb'])-tripExpenses(t);}return Scaffold(appBar:AppBar(title:const Text('Finanzas')),body:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(12),children:[_sectionCard(context,'Resumen',Icons.analytics,[Text('Pagos registrados: ${money(paid)}'),Text('Ganancia por comisión de compras: ${money(purchaseRevenue)}'),Text('Resultado estimado de viajes: ${money(tripProfit)}'),Text('Gastos generales: ${money(general)}'),const Divider(),Text('Resultado estimado: ${money(tripProfit+purchaseRevenue-general)}',style:const TextStyle(fontWeight:FontWeight.bold))])])));}}

class SettingsPage extends StatefulWidget{const SettingsPage({super.key});@override State<SettingsPage> createState()=>_SettingsPageState();}
class _SettingsPageState extends State<SettingsPage>{final rate=TextEditingController(),commission=TextEditingController();String weightRule='manual';bool loaded=false;@override void initState(){super.initState();load();}Future<void>load()async{final s=await Store.settings();rate.text='${s['ratePerLb']}';commission.text='${s['purchaseCommissionPct']}';weightRule='${s['weightRule']}';if(mounted)setState(()=>loaded=true);}Future<void>save()async{final s=await Store.settings();s['ratePerLb']=number(rate.text);s['purchaseCommissionPct']=number(commission.text);s['weightRule']=weightRule;await Store.saveSettings(s);if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Configuración guardada. Los registros antiguos conservan sus valores propios.')));}@override Widget build(BuildContext context){if(!loaded)return const Scaffold(body:Center(child:CircularProgressIndicator()));return Scaffold(appBar:AppBar(title:const Text('Configuración del negocio')),body:ListView(padding:const EdgeInsets.all(16),children:[TextField(controller:rate,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Tarifa general por libra')),const SizedBox(height:12),TextField(controller:commission,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Comisión predeterminada de compras %')),const SizedBox(height:12),_drop('Peso facturable predeterminado',weightRule,const [DropdownMenuItem(value:'manual',child:Text('Elegir manualmente')),DropdownMenuItem(value:'usa',child:Text('Peso EE. UU.')),DropdownMenuItem(value:'cuba',child:Text('Peso Cuba')),DropdownMenuItem(value:'max',child:Text('El mayor de los dos'))],(v)=>setState(()=>weightRule=v??weightRule)),const SizedBox(height:18),FilledButton.icon(onPressed:save,icon:const Icon(Icons.save),label:const Text('Guardar configuración'))]));}}

class TrashPage extends StatefulWidget{const TrashPage({super.key});@override State<TrashPage> createState()=>_TrashPageState();}
class _TrashPageState extends State<TrashPage>{final keys={'clients':'Clientes','recipients':'Destinatarios','purchases':'Compras','packages':'Paquetes','trips':'Viajes','payments':'Pagos','expenses':'Gastos','flightWatches':'Alertas de vuelos'};List<Map<String,dynamic>>deleted=[];@override void initState(){super.initState();load();}Future<void>load()async{final out=<Map<String,dynamic>>[];for(final entry in keys.entries){final rows=await Store.list(entry.key);for(final r in rows.where((e)=>e['deleted']==true)){out.add({...r,'_key':entry.key,'_type':entry.value});}}if(mounted)setState(()=>deleted=out);}String label(Map<String,dynamic>e)=>'${e['name']??e['tracking']??e['store']??e['origin']??e['amount']??e['id']}';Future<void>restore(Map<String,dynamic>e)async{final key='${e['_key']}';final rows=await Store.list(key);final i=rows.indexWhere((x)=>x['id']==e['id']);if(i>=0){rows[i]['deleted']=false;rows[i].remove('deletedAt');await Store.saveList(key,rows);}load();}Future<void>permanent(Map<String,dynamic>e)async{final key='${e['_key']}';final rows=await Store.list(key);rows.removeWhere((x)=>x['id']==e['id']);await Store.saveList(key,rows);load();}@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Papelera')),body:deleted.isEmpty?const Center(child:Text('Papelera vacía.')):ListView.builder(itemCount:deleted.length,itemBuilder:(_,i){final e=deleted[i];return ListTile(title:Text(label(e)),subtitle:Text('${e['_type']}'),trailing:PopupMenuButton<String>(onSelected:(v){if(v=='restore')restore(e);else permanent(e);},itemBuilder:(_)=>const [PopupMenuItem(value:'restore',child:Text('Restaurar')),PopupMenuItem(value:'delete',child:Text('Eliminar definitivamente'))]));}));}

class MorePage extends StatelessWidget{const MorePage({super.key});@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Herramientas')),body:ListView(children:[
_more(context,Icons.shopping_cart,'Pedidos y compras','Amazon, SHEIN, Temu, Walmart y compras físicas',const PurchasesPage()),
_more(context,Icons.flight_takeoff,'Vuelos y alertas','FLL/MIA → HAV y precios objetivo',const FlightWatchesPage()),
_more(context,Icons.receipt_long,'Gastos del negocio','Gastos generales fuera de un viaje',const ExpensesPage()),
_more(context,Icons.analytics,'Finanzas','Resumen de ingresos, gastos y ganancias',const FinancePage()),
_more(context,Icons.sync_alt,'Sincronizar con Finanzas','Compartir compras, paquetes, pendientes y gastos con Finanzas Definitiva',const FinanceSyncPage()),
_more(context,Icons.settings,'Configuración','Tarifa por libra, comisión y reglas',const SettingsPage()),
_more(context,Icons.delete_outline,'Papelera','Restaurar registros eliminados',const TrashPage()),
]));Widget _more(BuildContext context,IconData icon,String title,String sub,Widget page)=>ListTile(leading:Icon(icon),title:Text(title),subtitle:Text(sub),trailing:const Icon(Icons.chevron_right),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>page)));}
