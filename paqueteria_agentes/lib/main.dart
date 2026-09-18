import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const double alasCargoRatePerLb = 5.0;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AgentApp());
}

class AgentApp extends StatelessWidget {
  const AgentApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Alas Cargo Agentes',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF123B6D), brightness: Brightness.dark),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    ),
    home: const HomeShell(),
  );
}

class Store {
  static Future<List<Map<String,dynamic>>> list(String key) async {
    final p=await SharedPreferences.getInstance();
    final raw=p.getString(key);
    if(raw==null||raw.isEmpty)return [];
    try{return (jsonDecode(raw) as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();}catch(_){return [];}
  }
  static Future<void> save(String key,List<Map<String,dynamic>> rows) async {
    final p=await SharedPreferences.getInstance();
    await p.setString(key,jsonEncode(rows));
  }
  static Future<Map<String,dynamic>> settings() async {
    final p=await SharedPreferences.getInstance();
    final raw=p.getString('agent_settings');
    if(raw==null)return {'agentName':'','phone':'','defaultClientRate':6.0,'remittanceThreshold':100.0,'remittanceFlatFee':10.0,'remittanceAgentSharePct':100.0};
    try{
      final m=Map<String,dynamic>.from(jsonDecode(raw) as Map);
      m.putIfAbsent('agentName',()=> '');
      m.putIfAbsent('phone',()=> '');
      m.putIfAbsent('defaultClientRate',()=>6.0);
      m.putIfAbsent('remittanceThreshold',()=>100.0);
      m.putIfAbsent('remittanceFlatFee',()=>10.0);
      m.putIfAbsent('remittanceAgentSharePct',()=>100.0);
      return m;
    }catch(_){return {'agentName':'','phone':'','defaultClientRate':6.0,'remittanceThreshold':100.0,'remittanceFlatFee':10.0,'remittanceAgentSharePct':100.0};}
  }
  static Future<void> saveSettings(Map<String,dynamic> m) async {
    final p=await SharedPreferences.getInstance();
    await p.setString('agent_settings',jsonEncode(m));
  }
}

String newId()=>DateTime.now().microsecondsSinceEpoch.toString();
double numv(dynamic v)=>double.tryParse('${v??''}'.replaceAll(',','').replaceAll('\$','').trim())??0;
String money(num v)=>'\$${v.toStringAsFixed(2)}';
String today(){final d=DateTime.now();return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';}
double remittanceReturned(Map<String,dynamic> e)=>numv(e['returnedToAlasCargo']??e['ownerDue']);
double remittanceGrossProfit(Map<String,dynamic> e)=>e.containsKey('grossProfit')?numv(e['grossProfit']):remittanceReturned(e)-numv(e['cupAmount']);
double remittanceAgentProfit(Map<String,dynamic> e)=>e.containsKey('agentMargin')?numv(e['agentMargin']):remittanceGrossProfit(e);
double remittanceAlasCargoProfit(Map<String,dynamic> e)=>e.containsKey('alasCargoMargin')?numv(e['alasCargoMargin']):0;
double remittanceGrossProfit(Map<String,dynamic> e){if(e.containsKey('grossProfit'))return numv(e['grossProfit']);return remittanceReturned(e)-numv(e['cupAmount']);}
double remittanceAgentMargin(Map<String,dynamic> e){if(e.containsKey('agentMargin'))return numv(e['agentMargin']);return remittanceGrossProfit(e);}
double remittanceAlasMargin(Map<String,dynamic> e){if(e.containsKey('alasCargoMargin'))return numv(e['alasCargoMargin']);return remittanceGrossProfit(e)-remittanceAgentMargin(e);}
List<Map<String,dynamic>> active(List<Map<String,dynamic>> r)=>r.where((e)=>e['deleted']!=true).toList();
String clientName(List<Map<String,dynamic>> cs,String? id)=>cs.where((e)=>'${e['id']}'=='${id??''}').map((e)=>'${e['name']}').firstOrNull??'Sin cliente';

extension FirstOrNull<E> on Iterable<E>{E? get firstOrNull=>isEmpty?null:first;}

Future<bool> confirmDelete(BuildContext context) async => await showDialog<bool>(
  context:context,
  builder:(_)=>AlertDialog(
    title:const Text('Eliminar'),
    content:const Text('¿Quieres enviar este registro a la papelera?'),
    actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Eliminar'))],
  ),
)??false;

Future<void> softDelete(String key,String id) async {
  final rows=await Store.list(key);
  final i=rows.indexWhere((e)=>'${e['id']}'==id);
  if(i>=0){rows[i]['deleted']=true;await Store.save(key,rows);}
}

class HomeShell extends StatefulWidget{const HomeShell({super.key});@override State<HomeShell> createState()=>_HomeShellState();}
class _HomeShellState extends State<HomeShell>{
  int index=0;
  final pages=const [DashboardPage(),ClientsPage(),OrdersPage(),PackagesPage(),MorePage()];
  @override Widget build(BuildContext context)=>Scaffold(
    body:pages[index],
    bottomNavigationBar:NavigationBar(
      selectedIndex:index,
      onDestinationSelected:(v)=>setState(()=>index=v),
      destinations:const [
        NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home),label:'Inicio'),
        NavigationDestination(icon:Icon(Icons.people_outline),selectedIcon:Icon(Icons.people),label:'Clientes'),
        NavigationDestination(icon:Icon(Icons.shopping_bag_outlined),selectedIcon:Icon(Icons.shopping_bag),label:'Pedidos'),
        NavigationDestination(icon:Icon(Icons.inventory_2_outlined),selectedIcon:Icon(Icons.inventory_2),label:'Paquetes'),
        NavigationDestination(icon:Icon(Icons.apps),label:'Más'),
      ],
    ),
  );
}

class DashboardPage extends StatefulWidget{const DashboardPage({super.key});@override State<DashboardPage> createState()=>_DashboardPageState();}
class _DashboardPageState extends State<DashboardPage>{
  List<Map<String,dynamic>> clients=[],orders=[],packages=[],remittances=[],settlements=[];
  Map<String,dynamic> settings={};
  bool loading=true;
  @override void initState(){super.initState();load();}
  Future<void> load() async {
    final r=await Future.wait([Store.list('clients'),Store.list('orders'),Store.list('packages'),Store.list('remittances'),Store.list('settlements'),Store.settings()]);
    if(!mounted)return;
    setState((){
      clients=active(r[0] as List<Map<String,dynamic>>);orders=active(r[1] as List<Map<String,dynamic>>);packages=active(r[2] as List<Map<String,dynamic>>);
      remittances=active(r[3] as List<Map<String,dynamic>>);settlements=active(r[4] as List<Map<String,dynamic>>);settings=r[5] as Map<String,dynamic>;loading=false;
    });
  }
  double get shippingOwnerDue=>packages.fold(0,(a,e)=>a+numv(e['weightLb'])*alasCargoRatePerLb);
  double get shippingClient=>packages.fold(0,(a,e)=>a+numv(e['weightLb'])*numv(e['clientRate']));
  double get orderOwnerDue=>orders.fold(0,(a,e)=>a+numv(e['storeCost']));
  double get remittancesLiquidated=>remittances.fold(0,(a,e)=>a+remittanceReturned(e));
  double get settled=>settlements.fold(0,(a,e)=>a+numv(e['amount']));
  double get balanceToOwner=>shippingOwnerDue+orderOwnerDue-remittancesLiquidated-settled;
  double get shippingMargin=>shippingClient-shippingOwnerDue;
  double get orderMargin=>orders.fold(0,(a,e)=>a+(numv(e['clientTotal'])-numv(e['storeCost'])));
  double get remitMargin=>remittances.fold(0,(a,e)=>a+remittanceAgentMargin(e));
  @override Widget build(BuildContext context){
    if(loading)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    return Scaffold(
      appBar:AppBar(title:const Text('Alas Cargo · Agentes'),actions:[IconButton(onPressed:load,icon:const Icon(Icons.refresh))]),
      body:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(14),children:[
        Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(settings['agentName'].toString().trim().isEmpty?'Configura tu perfil':'Agente: ${settings['agentName']}',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),
          const SizedBox(height:6),Text('Tarifa de Alas Cargo: ${money(alasCargoRatePerLb)} / lb'),
          Text('Tu tarifa predeterminada: ${money(numv(settings['defaultClientRate']))} / lb'),
        ]))),
        const SizedBox(height:10),
        Row(children:[
          Expanded(child:_metric(context,'Clientes','${clients.length}',Icons.people)),
          const SizedBox(width:8),
          Expanded(child:_metric(context,'Pedidos','${orders.length}',Icons.shopping_bag)),
        ]),
        const SizedBox(height:8),
        Row(children:[
          Expanded(child:_metric(context,'Paquetes','${packages.length}',Icons.inventory_2)),
          const SizedBox(width:8),
          Expanded(child:_metric(context,'Remesas','${remittances.length}',Icons.send)),
        ]),
        const SizedBox(height:12),
        Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Cuenta con Alas Cargo',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.bold)),
          const SizedBox(height:8),
          Text('Libras a liquidar: ${money(shippingOwnerDue)}'),
          Text('Pedidos a liquidar: ${money(orderOwnerDue)}'),
          Text('Remesas liquidadas: ${money(remittancesLiquidated)}'),
          Text('Pagado a Alas Cargo: ${money(settled)}'),
          const Divider(),
          Text('Saldo por liquidar: ${money(balanceToOwner)}',style:const TextStyle(fontWeight:FontWeight.bold)),
        ]))),
        Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Margen del agente',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.bold)),
          const SizedBox(height:8),
          Text('Margen por libras: ${money(shippingMargin)}'),
          Text('Margen por pedidos: ${money(orderMargin)}'),
          Text('Margen por remesas: ${money(remitMargin)}'),
          const Divider(),Text('Margen bruto registrado: ${money(shippingMargin+orderMargin+remitMargin)}',style:const TextStyle(fontWeight:FontWeight.bold)),
        ]))),
      ])),
    );
  }
}

Widget _metric(BuildContext c,String title,String value,IconData icon)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(children:[Icon(icon),const SizedBox(height:6),Text(value,style:Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),Text(title)])));

class ClientsPage extends StatefulWidget{const ClientsPage({super.key});@override State<ClientsPage> createState()=>_ClientsPageState();}
class _ClientsPageState extends State<ClientsPage>{
  List<Map<String,dynamic>> rows=[];String q='';
  @override void initState(){super.initState();load();}
  Future<void>load()async{rows=active(await Store.list('clients'));if(mounted)setState((){});}
  Future<void>edit([Map<String,dynamic>?e])async{
    final name=TextEditingController(text:'${e?['name']??''}'),phone=TextEditingController(text:'${e?['phone']??''}'),rate=TextEditingController(text:'${e?['rate']??''}'),notes=TextEditingController(text:'${e?['notes']??''}');
    if(rate.text.isEmpty){final s=await Store.settings();rate.text='${s['defaultClientRate']??6.0}';}
    if(!mounted)return;
    final ok=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(title:Text(e==null?'Nuevo cliente':'Editar cliente'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      TextField(controller:name,decoration:const InputDecoration(labelText:'Nombre *')),const SizedBox(height:8),
      TextField(controller:phone,decoration:const InputDecoration(labelText:'Teléfono / WhatsApp')),const SizedBox(height:8),
      TextField(controller:rate,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Tarifa del cliente por libra')),const SizedBox(height:8),
      TextField(controller:notes,maxLines:2,decoration:const InputDecoration(labelText:'Notas')),
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Guardar'))]));
    if(ok==true&&name.text.trim().isNotEmpty){
      final all=await Store.list('clients');final item={'id':e?['id']??newId(),'name':name.text.trim(),'phone':phone.text.trim(),'rate':numv(rate.text),'notes':notes.text.trim(),'deleted':false};
      final i=all.indexWhere((x)=>x['id']==item['id']);if(i>=0)all[i]={...all[i],...item};else all.add(item);await Store.save('clients',all);load();
    }
  }
  @override Widget build(BuildContext context){final f=rows.where((e)=>'${e['name']} ${e['phone']}'.toLowerCase().contains(q.toLowerCase())).toList();return Scaffold(
    appBar:AppBar(title:const Text('Mis clientes')),
    body:Column(children:[Padding(padding:const EdgeInsets.all(12),child:TextField(onChanged:(v)=>setState(()=>q=v),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Buscar cliente'))),Expanded(child:f.isEmpty?const Center(child:Text('No hay clientes.')):ListView.builder(itemCount:f.length,itemBuilder:(_,i){final e=f[i];return ListTile(
      leading:const CircleAvatar(child:Icon(Icons.person)),title:Text('${e['name']}'),subtitle:Text('${e['phone']} · ${money(numv(e['rate']))}/lb'),
      onTap:()=>edit(e),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{if(await confirmDelete(context)){await softDelete('clients','${e['id']}');load();}})
    );}))]),
    floatingActionButton:FloatingActionButton.extended(onPressed:()=>edit(),icon:const Icon(Icons.add),label:const Text('Cliente')),
  );}
}

class OrdersPage extends StatefulWidget{const OrdersPage({super.key});@override State<OrdersPage> createState()=>_OrdersPageState();}
class _OrdersPageState extends State<OrdersPage>{
  List<Map<String,dynamic>>rows=[],clients=[];@override void initState(){super.initState();load();}
  Future<void>load()async{final r=await Future.wait([Store.list('orders'),Store.list('clients')]);rows=active(r[0]);clients=active(r[1]);if(mounted)setState((){});}
  Future<void>edit([Map<String,dynamic>?e])async{
    String? cid=e?['clientId']?.toString();final store=TextEditingController(text:'${e?['store']??''}'),desc=TextEditingController(text:'${e?['description']??''}'),cost=TextEditingController(text:'${e?['storeCost']??''}'),total=TextEditingController(text:'${e?['clientTotal']??''}');final owner=TextEditingController(text:'${e?['storeCost']??e?['ownerDue']??0}');String status='${e?['status']??'Pendiente'}';
    final ok=await showDialog<bool>(context:context,builder:(_)=>StatefulBuilder(builder:(context,setD)=>AlertDialog(title:Text(e==null?'Nuevo pedido':'Editar pedido'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      DropdownButtonFormField<String>(value:cid,decoration:const InputDecoration(labelText:'Cliente *'),items:clients.map((c)=>DropdownMenuItem(value:'${c['id']}',child:Text('${c['name']}'))).toList(),onChanged:(v)=>setD(()=>cid=v)),const SizedBox(height:8),
      TextField(controller:store,decoration:const InputDecoration(labelText:'Tienda')),const SizedBox(height:8),TextField(controller:desc,maxLines:2,decoration:const InputDecoration(labelText:'Descripción / artículos')),const SizedBox(height:8),
      TextField(controller:cost,onChanged:(v)=>setD(()=>owner.text=numv(v).toStringAsFixed(2)),keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Costo real de compra (pagado por Alas Cargo)')),const SizedBox(height:8),
      TextField(controller:total,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Total cobrado o a cobrar al cliente')),const SizedBox(height:8),
      InputDecorator(decoration:const InputDecoration(labelText:'Monto a liquidar con Alas Cargo'),child:Text(money(numv(owner.text)))),const SizedBox(height:8),
      DropdownButtonFormField<String>(value:status,decoration:const InputDecoration(labelText:'Estado'),items:['Pendiente','Comprado','Recibido','Entregado','Cancelado'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>setD(()=>status=v??status)),
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Guardar'))])));
    if(ok==true&&cid!=null){final all=await Store.list('orders');final item={'id':e?['id']??newId(),'clientId':cid,'store':store.text.trim(),'description':desc.text.trim(),'storeCost':numv(cost.text),'clientTotal':numv(total.text),'ownerDue':numv(cost.text),'status':status,'date':e?['date']??today(),'deleted':false};final i=all.indexWhere((x)=>x['id']==item['id']);if(i>=0)all[i]={...all[i],...item};else all.add(item);await Store.save('orders',all);load();}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Pedidos y compras')),body:rows.isEmpty?const Center(child:Text('No hay pedidos.')):ListView.builder(itemCount:rows.length,itemBuilder:(_,i){final e=rows[i];return ListTile(
    leading:const Icon(Icons.shopping_bag),title:Text('${clientName(clients,'${e['clientId']}')} · ${e['store']}'),subtitle:Text('${e['description']}\nTotal cliente: ${money(numv(e['clientTotal']))} · ${e['status']}'),isThreeLine:true,onTap:()=>edit(e),
    trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{if(await confirmDelete(context)){await softDelete('orders','${e['id']}');load();}})
  );}),floatingActionButton:FloatingActionButton.extended(onPressed:()=>edit(),icon:const Icon(Icons.add),label:const Text('Pedido')));
}

class PackagesPage extends StatefulWidget{const PackagesPage({super.key});@override State<PackagesPage> createState()=>_PackagesPageState();}
class _PackagesPageState extends State<PackagesPage>{
  List<Map<String,dynamic>>rows=[],clients=[];String q='';
  @override void initState(){super.initState();load();}
  Future<void>load()async{final r=await Future.wait([Store.list('packages'),Store.list('clients')]);rows=active(r[0]);clients=active(r[1]);if(mounted)setState((){});}
  Future<void>scan()async{final code=await Navigator.push<String>(context,MaterialPageRoute(builder:(_)=>const ScannerPage()));if(code!=null&&mounted){await edit(null,code);load();}}
  Future<void>edit([Map<String,dynamic>?e,String? initial])async{
    String? cid=e?['clientId']?.toString();final tracking=TextEditingController(text:'${e?['tracking']??initial??''}'),weight=TextEditingController(text:'${e?['weightLb']??''}'),rate=TextEditingController(text:'${e?['clientRate']??''}'),notes=TextEditingController(text:'${e?['notes']??''}');String status='${e?['status']??'Registrado'}';
    if(rate.text.isEmpty&&cid!=null){final c=clients.where((x)=>'${x['id']}'==cid).firstOrNull;if(c!=null)rate.text='${c['rate']}';}
    final ok=await showDialog<bool>(context:context,builder:(_)=>StatefulBuilder(builder:(context,setD)=>AlertDialog(title:Text(e==null?'Nuevo paquete':'Editar paquete'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      TextField(controller:tracking,decoration:const InputDecoration(labelText:'Tracking *')),const SizedBox(height:8),
      DropdownButtonFormField<String>(value:cid,decoration:const InputDecoration(labelText:'Cliente *'),items:clients.map((c)=>DropdownMenuItem(value:'${c['id']}',child:Text('${c['name']}'))).toList(),onChanged:(v){setD(()=>cid=v);final c=clients.where((x)=>'${x['id']}'==v).firstOrNull;if(c!=null)rate.text='${c['rate']}';}),const SizedBox(height:8),
      TextField(controller:weight,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Peso facturable (lb)')),const SizedBox(height:8),
      TextField(controller:rate,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Tu tarifa al cliente por lb')),const SizedBox(height:8),
      InputDecorator(decoration:const InputDecoration(labelText:'Tarifa que recibirá Alas Cargo'),child:Text('${money(alasCargoRatePerLb)} / lb')),const SizedBox(height:8),
      DropdownButtonFormField<String>(value:status,decoration:const InputDecoration(labelText:'Estado'),items:['Registrado','En tránsito','Recibido','Listo para entregar a Alas Cargo','Entregado a Alas Cargo','En Cuba','Entregado al cliente'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>setD(()=>status=v??status)),const SizedBox(height:8),
      TextField(controller:notes,maxLines:2,decoration:const InputDecoration(labelText:'Notas')),
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Guardar'))])));
    if(ok==true&&cid!=null&&tracking.text.trim().isNotEmpty){final all=await Store.list('packages');final duplicate=all.where((x)=>x['deleted']!=true&&'${x['tracking']}'==tracking.text.trim()&&'${x['id']}'!='${e?['id']??''}').isNotEmpty;if(duplicate){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ese tracking ya existe.')));return;}final item={'id':e?['id']??newId(),'clientId':cid,'tracking':tracking.text.trim(),'weightLb':numv(weight.text),'clientRate':numv(rate.text),'ownerRate':alasCargoRatePerLb,'status':status,'notes':notes.text.trim(),'date':e?['date']??today(),'deleted':false};final i=all.indexWhere((x)=>x['id']==item['id']);if(i>=0)all[i]={...all[i],...item};else all.add(item);await Store.save('packages',all);load();}
  }
  @override Widget build(BuildContext context){final f=rows.where((e)=>'${e['tracking']} ${clientName(clients,'${e['clientId']}')}'.toLowerCase().contains(q.toLowerCase())).toList();return Scaffold(appBar:AppBar(title:const Text('Paquetes'),actions:[IconButton(onPressed:scan,icon:const Icon(Icons.qr_code_scanner))]),body:Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:TextField(onChanged:(v)=>setState(()=>q=v),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Tracking o cliente'))),
    Expanded(child:f.isEmpty?const Center(child:Text('No hay paquetes.')):ListView.builder(itemCount:f.length,itemBuilder:(_,i){final e=f[i],w=numv(e['weightLb']),r=numv(e['clientRate']);return ListTile(leading:const Icon(Icons.inventory_2),title:Text('${e['tracking']}'),subtitle:Text('${clientName(clients,'${e['clientId']}')} · ${w.toStringAsFixed(1)} lb\nCliente: ${money(w*r)} · Alas Cargo: ${money(w*alasCargoRatePerLb)}'),isThreeLine:true,onTap:()=>edit(e),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{if(await confirmDelete(context)){await softDelete('packages','${e['id']}');load();}}));}))
  ]),floatingActionButton:FloatingActionButton.extended(onPressed:()=>edit(),icon:const Icon(Icons.add),label:const Text('Paquete')));}
}

class ScannerPage extends StatefulWidget{const ScannerPage({super.key});@override State<ScannerPage> createState()=>_ScannerPageState();}
class _ScannerPageState extends State<ScannerPage>{bool done=false;final manual=TextEditingController();@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Escanear tracking')),body:Column(children:[
  Expanded(child:MobileScanner(onDetect:(c){if(done)return;for(final b in c.barcodes){final v=b.rawValue;if(v!=null&&v.trim().isNotEmpty){done=true;Navigator.pop(context,v.trim());break;}}})),
  Padding(padding:const EdgeInsets.all(12),child:Row(children:[Expanded(child:TextField(controller:manual,decoration:const InputDecoration(labelText:'O escribir tracking'))),const SizedBox(width:8),IconButton.filled(onPressed:(){if(manual.text.trim().isNotEmpty)Navigator.pop(context,manual.text.trim());},icon:const Icon(Icons.check))]))
]));}

class RemittancesPage extends StatefulWidget{const RemittancesPage({super.key});@override State<RemittancesPage> createState()=>_RemittancesPageState();}
class _RemittancesPageState extends State<RemittancesPage>{
  List<Map<String,dynamic>>rows=[],clients=[];@override void initState(){super.initState();load();}
  Future<void>load()async{final r=await Future.wait([Store.list('remittances'),Store.list('clients')]);rows=active(r[0]);clients=active(r[1]);if(mounted)setState((){});}
  Future<void>edit([Map<String,dynamic>?e])async{
    final s=await Store.settings();
    final configuredLimit=numv(s['remittanceFixedLimit'])>0?numv(s['remittanceFixedLimit']):100.0;
    final configuredFee=numv(s['remittanceFixedFee']);
    final configuredPercent=numv(s['remittanceAgentPercent']).clamp(0,100).toDouble();
    final limit=e!=null&&e.containsKey('ruleLimit')?numv(e['ruleLimit']):configuredLimit;
    final fixedFee=e!=null&&e.containsKey('fixedFee')?numv(e['fixedFee']):configuredFee;
    final agentPercent=e!=null&&e.containsKey('agentPercent')?numv(e['agentPercent']).clamp(0,100).toDouble():configuredPercent;
    String? cid=e?['clientId']?.toString();
    final beneficiary=TextEditingController(text:'${e?['beneficiary']??''}'),phone=TextEditingController(text:'${e?['beneficiaryPhone']??''}'),returned=TextEditingController(text:'${e?['returnedToAlasCargo']??e?['ownerDue']??''}'),cup=TextEditingController(text:'${e?['cupAmount']??''}'),notes=TextEditingController(text:'${e?['notes']??''}');
    String status='${e?['status']??'Pendiente'}';
    final ok=await showDialog<bool>(context:context,builder:(_)=>StatefulBuilder(builder:(context,setD){
      final delivered=numv(cup.text);
      final fixedMode=delivered>0&&delivered<limit;
      final received=numv(returned.text);
      final gross=fixedMode?fixedFee:received-delivered;
      final agentMargin=gross*agentPercent/100;
      final alasMargin=gross-agentMargin;
      return AlertDialog(title:Text(e==null?'Nueva remesa':'Editar remesa'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<String>(value:cid,decoration:const InputDecoration(labelText:'Cliente / remitente *'),items:clients.map((c)=>DropdownMenuItem(value:'${c['id']}',child:Text('${c['name']}'))).toList(),onChanged:(v)=>setD(()=>cid=v)),const SizedBox(height:8),
        TextField(controller:beneficiary,decoration:const InputDecoration(labelText:'Beneficiario en Cuba *')),const SizedBox(height:8),
        TextField(controller:phone,decoration:const InputDecoration(labelText:'Teléfono del beneficiario')),const SizedBox(height:8),
        TextField(controller:cup,onChanged:(v){final d=numv(v);if(d>0&&d<limit){returned.text=(d+fixedFee).toStringAsFixed(2);}else if(e==null){returned.clear();}setD((){});},keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Monto entregado en Cuba (USD)')),const SizedBox(height:8),
        TextField(controller:returned,readOnly:fixedMode,onChanged:(_)=>setD((){}),keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:fixedMode?'Total a cobrar/recibir (automático)':'Dinero recibido / devuelto a Alas Cargo (USD)')),const SizedBox(height:8),
        Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(fixedMode?'Regla: tarifa fija por debajo de ${money(limit)}':'Regla: diferencia entre recibido y entregado',style:const TextStyle(fontWeight:FontWeight.bold)),
          if(fixedMode)Text('Tarifa fija: ${money(fixedFee)}'),
          Text('Ganancia bruta: ${money(gross)}'),
          Text('Margen del agente (${agentPercent.toStringAsFixed(agentPercent%1==0?0:1)}%): ${money(agentMargin)}'),
          Text('Margen Alas Cargo: ${money(alasMargin)}'),
        ]))),const SizedBox(height:8),
        DropdownButtonFormField<String>(value:status,decoration:const InputDecoration(labelText:'Estado'),items:['Pendiente','En proceso','Enviada','Entregada','Cancelada'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>setD(()=>status=v??status)),const SizedBox(height:8),
        TextField(controller:notes,maxLines:2,decoration:const InputDecoration(labelText:'Notas')),
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Guardar'))]);
    }));
    if(ok==true&&cid!=null&&beneficiary.text.trim().isNotEmpty){
      final delivered=numv(cup.text),fixedMode=delivered>0&&delivered<limit;
      if(fixedMode)returned.text=(delivered+fixedFee).toStringAsFixed(2);
      final received=numv(returned.text),gross=fixedMode?fixedFee:received-delivered,agentMargin=gross*agentPercent/100,alasMargin=gross-agentMargin;
      final all=await Store.list('remittances');
      final item={'id':e?['id']??newId(),'clientId':cid,'beneficiary':beneficiary.text.trim(),'beneficiaryPhone':phone.text.trim(),'clientTotal':received,'returnedToAlasCargo':received,'ownerDue':received,'cupAmount':delivered,'grossProfit':gross,'agentMargin':agentMargin,'alasCargoMargin':alasMargin,'agentPercent':agentPercent,'ruleLimit':limit,'fixedFee':fixedFee,'ruleType':fixedMode?'fixed':'difference','status':status,'notes':notes.text.trim(),'date':e?['date']??today(),'deleted':false};
      final i=all.indexWhere((x)=>x['id']==item['id']);if(i>=0)all[i]={...all[i],...item};else all.add(item);await Store.save('remittances',all);load();
    }
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Remesas')),body:rows.isEmpty?const Center(child:Text('No hay remesas.')):ListView.builder(itemCount:rows.length,itemBuilder:(_,i){final e=rows[i];return ListTile(leading:const Icon(Icons.send),title:Text('${clientName(clients,'${e['clientId']}')} → ${e['beneficiary']}'),subtitle:Text('Recibido: ${money(remittanceReturned(e))} · Cuba: ${money(numv(e['cupAmount']))}\nAgente: ${money(remittanceAgentProfit(e))} · Alas Cargo: ${money(remittanceAlasCargoProfit(e))} · ${e['status']}'),isThreeLine:true,onTap:()=>edit(e),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{if(await confirmDelete(context)){await softDelete('remittances','${e['id']}');load();}}));}),floatingActionButton:FloatingActionButton.extended(onPressed:()=>edit(),icon:const Icon(Icons.add),label:const Text('Remesa')));
}

class SettlementsPage extends StatefulWidget{const SettlementsPage({super.key});@override State<SettlementsPage> createState()=>_SettlementsPageState();}
class _SettlementsPageState extends State<SettlementsPage>{
  List<Map<String,dynamic>>rows=[];@override void initState(){super.initState();load();}Future<void>load()async{rows=active(await Store.list('settlements'));if(mounted)setState((){});}
  Future<void>add()async{final amount=TextEditingController(),method=TextEditingController(),notes=TextEditingController();final ok=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(title:const Text('Pago a Alas Cargo'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Monto')),const SizedBox(height:8),TextField(controller:method,decoration:const InputDecoration(labelText:'Método / referencia')),const SizedBox(height:8),TextField(controller:notes,decoration:const InputDecoration(labelText:'Notas'))])),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Guardar'))]));if(ok==true&&numv(amount.text)>0){final all=await Store.list('settlements');all.add({'id':newId(),'amount':numv(amount.text),'method':method.text.trim(),'notes':notes.text.trim(),'date':today(),'deleted':false});await Store.save('settlements',all);load();}}
  @override Widget build(BuildContext context){final total=rows.fold<double>(0,(a,e)=>a+numv(e['amount']));return Scaffold(appBar:AppBar(title:const Text('Liquidaciones')),body:ListView(padding:const EdgeInsets.all(12),children:[Card(child:Padding(padding:const EdgeInsets.all(16),child:Text('Total pagado a Alas Cargo: ${money(total)}',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.bold)))),for(final e in rows)ListTile(title:Text(money(numv(e['amount']))),subtitle:Text('${e['date']} · ${e['method']}\n${e['notes']}'),isThreeLine:true)]),floatingActionButton:FloatingActionButton.extended(onPressed:add,icon:const Icon(Icons.add),label:const Text('Registrar pago')));}
}

class ReportPage extends StatefulWidget{const ReportPage({super.key});@override State<ReportPage> createState()=>_ReportPageState();}
class _ReportPageState extends State<ReportPage>{
  bool busy=false;
  Future<Map<String,dynamic>>data()async{
    final r=await Future.wait([Store.settings(),Store.list('clients'),Store.list('orders'),Store.list('packages'),Store.list('remittances'),Store.list('settlements')]);
    final orders=active(r[2] as List<Map<String,dynamic>>).map((e)=>{...e,'ownerDue':numv(e['storeCost'])}).toList();final remittances=active(r[4] as List<Map<String,dynamic>>).map((e)=>{...e,'returnedToAlasCargo':remittanceReturned(e),'ownerDue':remittanceReturned(e)}).toList();return {'settings':r[0],'clients':active(r[1] as List<Map<String,dynamic>>),'orders':orders,'packages':active(r[3] as List<Map<String,dynamic>>),'remittances':remittances,'settlements':active(r[5] as List<Map<String,dynamic>>),'generatedAt':DateTime.now().toIso8601String(),'schema':'alas-cargo-agent-v4'};
  }
  Future<void>shareReport()async{
    setState(()=>busy=true);try{
      final d=await data(),s=d['settings'] as Map<String,dynamic>,packages=d['packages'] as List<Map<String,dynamic>>,orders=d['orders'] as List<Map<String,dynamic>>,rem=d['remittances'] as List<Map<String,dynamic>>,sett=d['settlements'] as List<Map<String,dynamic>>,clients=d['clients'] as List<Map<String,dynamic>>;
      final ship=packages.fold<double>(0,(a,e)=>a+numv(e['weightLb'])*alasCargoRatePerLb),ord=orders.fold<double>(0,(a,e)=>a+numv(e['storeCost'])),rr=rem.fold<double>(0,(a,e)=>a+remittanceReturned(e)),paid=sett.fold<double>(0,(a,e)=>a+numv(e['amount'])),remGross=rem.fold<double>(0,(a,e)=>a+remittanceGrossProfit(e)),remAgent=rem.fold<double>(0,(a,e)=>a+remittanceAgentMargin(e)),remAlas=rem.fold<double>(0,(a,e)=>a+remittanceAlasMargin(e));
      final pdf=pw.Document();pdf.addPage(pw.MultiPage(pageFormat:PdfPageFormat.letter,build:(_)=>[
        pw.Text('ALAS CARGO - REPORTE DE AGENTE',style:pw.TextStyle(fontSize:20,fontWeight:pw.FontWeight.bold)),
        pw.SizedBox(height:8),pw.Text('Agente: ${s['agentName']}'),pw.Text('Telefono: ${s['phone']}'),pw.Text('Fecha: ${today()}'),
        pw.SizedBox(height:12),pw.Text('RESUMEN',style:pw.TextStyle(fontWeight:pw.FontWeight.bold)),pw.Text('Clientes: ${clients.length}'),pw.Text('Pedidos: ${orders.length}'),pw.Text('Paquetes: ${packages.length}'),pw.Text('Remesas: ${rem.length}'),
        pw.SizedBox(height:8),pw.Text('Libras a liquidar: ${money(ship)}'),pw.Text('Pedidos a liquidar: ${money(ord)}'),pw.Text('Remesas liquidadas: ${money(rr)}'),pw.Text('Ganancia bruta remesas: ${money(remGross)}'),pw.Text('Margen agente remesas: ${money(remAgent)}'),pw.Text('Margen Alas Cargo remesas: ${money(remAlas)}'),pw.Text('Pagado: ${money(paid)}'),pw.Text('SALDO CON ALAS CARGO: ${money(ship+ord-rr-paid)}',style:pw.TextStyle(fontWeight:pw.FontWeight.bold)),
        pw.SizedBox(height:14),pw.Text('PAQUETES',style:pw.TextStyle(fontWeight:pw.FontWeight.bold)),
        ...packages.map((e)=>pw.Text('${e['tracking']} · ${clientName(clients,'${e['clientId']}')} · ${numv(e['weightLb']).toStringAsFixed(1)} lb · Alas Cargo ${money(numv(e['weightLb'])*alasCargoRatePerLb)}')),
        pw.SizedBox(height:14),pw.Text('REMESAS',style:pw.TextStyle(fontWeight:pw.FontWeight.bold)),
        ...rem.map((e)=>pw.Text('${clientName(clients,'${e['clientId']}')} → ${e['beneficiary']} · Recibido ${money(numv(e['clientTotal']))} · Cuba ${money(numv(e['cupAmount']))} · Ganancia ${money(remittanceGrossProfit(e))} · Agente ${money(remittanceAgentMargin(e))} · Alas Cargo ${money(remittanceAlasMargin(e))} · ${e['status']}')),
      ]));
      final dir=await getTemporaryDirectory(),pdfFile=File('${dir.path}/Reporte_Agente_${today()}.pdf'),jsonFile=File('${dir.path}/Reporte_Agente_${today()}.json');
      await pdfFile.writeAsBytes(await pdf.save());await jsonFile.writeAsString(const JsonEncoder.withIndent('  ').convert(d));
      await Share.shareXFiles([XFile(pdfFile.path),XFile(jsonFile.path)],text:'Reporte de agente Alas Cargo - ${s['agentName']}');
    }finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Enviar reporte')),body:ListView(padding:const EdgeInsets.all(16),children:[const Text('Genera un PDF legible y un archivo JSON con tus clientes, pedidos, paquetes, remesas y liquidaciones. Puedes enviarlos al administrador de Alas Cargo por WhatsApp, correo u otra app.'),const SizedBox(height:18),FilledButton.icon(onPressed:busy?null:shareReport,icon:busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.share),label:const Text('Generar y compartir reporte'))]));}

class SettingsPage extends StatefulWidget{const SettingsPage({super.key});@override State<SettingsPage> createState()=>_SettingsPageState();}
class _SettingsPageState extends State<SettingsPage>{
  final name=TextEditingController(),phone=TextEditingController(),rate=TextEditingController(),remLimit=TextEditingController(),remFee=TextEditingController(),remPercent=TextEditingController();bool loading=true;
  @override void initState(){super.initState();load();}
  Future<void>load()async{final s=await Store.settings();name.text='${s['agentName']}';phone.text='${s['phone']}';rate.text='${s['defaultClientRate']}';remLimit.text='${s['remittanceFixedLimit']}';remFee.text='${s['remittanceFixedFee']}';remPercent.text='${s['remittanceAgentPercent']}';if(mounted)setState(()=>loading=false);}
  Future<void>save()async{final s=await Store.settings();s['agentName']=name.text.trim();s['phone']=phone.text.trim();s['defaultClientRate']=numv(rate.text);s['remittanceFixedLimit']=numv(remLimit.text)>0?numv(remLimit.text):100.0;s['remittanceFixedFee']=numv(remFee.text);s['remittanceAgentPercent']=numv(remPercent.text).clamp(0,100).toDouble();await Store.saveSettings(s);if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Configuración guardada.')));}
  @override Widget build(BuildContext context){if(loading)return const Scaffold(body:Center(child:CircularProgressIndicator()));return Scaffold(appBar:AppBar(title:const Text('Perfil y tarifas')),body:ListView(padding:const EdgeInsets.all(16),children:[
    TextField(controller:name,decoration:const InputDecoration(labelText:'Nombre del agente')),const SizedBox(height:12),
    TextField(controller:phone,decoration:const InputDecoration(labelText:'Teléfono')),const SizedBox(height:12),
    TextField(controller:rate,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Tarifa predeterminada que cobras a tus clientes por lb')),const SizedBox(height:12),
    InputDecorator(decoration:const InputDecoration(labelText:'Tarifa fija para Alas Cargo'),child:Text('${money(alasCargoRatePerLb)} / lb')),const SizedBox(height:8),
    const Text('Si cobras más de \\$5/lb, la diferencia queda como margen del agente.'),const SizedBox(height:20),const Divider(),
    Text('Ajustes de remesas',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:8),
    const Text('Estas reglas se aplican automáticamente al crear nuevas remesas.'),const SizedBox(height:12),
    TextField(controller:remLimit,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Aplicar tarifa fija por debajo de (USD)')),const SizedBox(height:12),
    TextField(controller:remFee,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Tarifa fija por debajo del límite (USD)')),const SizedBox(height:12),
    TextField(controller:remPercent,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Porcentaje de la ganancia para el agente (%)')),const SizedBox(height:8),
    const Text('Ejemplo: 100% = toda la ganancia para el agente. 50% = mitad para el agente y mitad para Alas Cargo.'),const SizedBox(height:18),
    FilledButton.icon(onPressed:save,icon:const Icon(Icons.save),label:const Text('Guardar')),
  ]));}
}

class TrashPage extends StatefulWidget{const TrashPage({super.key});@override State<TrashPage> createState()=>_TrashPageState();}
class _TrashPageState extends State<TrashPage>{
  final keys={'clients':'Cliente','orders':'Pedido','packages':'Paquete','remittances':'Remesa','settlements':'Liquidación'};List<Map<String,dynamic>>rows=[];
  @override void initState(){super.initState();load();}Future<void>load()async{final out=<Map<String,dynamic>>[];for(final e in keys.entries){for(final x in (await Store.list(e.key)).where((r)=>r['deleted']==true)){out.add({...x,'_key':e.key,'_type':e.value});}}if(mounted)setState(()=>rows=out);}
  Future<void>restore(Map<String,dynamic>e)async{final all=await Store.list('${e['_key']}');final i=all.indexWhere((x)=>x['id']==e['id']);if(i>=0){all[i]['deleted']=false;await Store.save('${e['_key']}',all);}load();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Papelera')),body:rows.isEmpty?const Center(child:Text('Papelera vacía.')):ListView.builder(itemCount:rows.length,itemBuilder:(_,i){final e=rows[i];return ListTile(title:Text('${e['name']??e['tracking']??e['beneficiary']??e['store']??e['amount']??e['id']}'),subtitle:Text('${e['_type']}'),trailing:IconButton(icon:const Icon(Icons.restore),onPressed:()=>restore(e)));}));
}

class MorePage extends StatelessWidget{const MorePage({super.key});@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Más')),body:ListView(children:[
  _more(context,Icons.send,'Remesas','Registrar y controlar remesas',const RemittancesPage()),
  _more(context,Icons.payments,'Liquidaciones','Pagos realizados a Alas Cargo',const SettlementsPage()),
  _more(context,Icons.summarize,'Enviar reporte','PDF + JSON para Alas Cargo',const ReportPage()),
  _more(context,Icons.manage_accounts,'Perfil y tarifas','Datos del agente y tarifa a clientes',const SettingsPage()),
  _more(context,Icons.delete_outline,'Papelera','Restaurar registros eliminados',const TrashPage()),
]));Widget _more(BuildContext c,IconData i,String t,String s,Widget p)=>ListTile(leading:Icon(i),title:Text(t),subtitle:Text(s),trailing:const Icon(Icons.chevron_right),onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>p)));}
