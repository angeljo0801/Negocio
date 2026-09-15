part of 'main.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});
  @override State<PurchasesPage> createState()=>_PurchasesPageState();
}
class _PurchasesPageState extends State<PurchasesPage> {
  List<Map<String,dynamic>> rows=[], clients=[];
  @override void initState(){super.initState();load();}
  Future<void> load() async { final r=await Future.wait([Store.list('purchases'),Store.list('clients')]); if(!mounted)return; setState((){rows=active(r[0]);clients=active(r[1]);});}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Pedidos y compras')),body:rows.isEmpty?const Center(child:Text('No hay compras registradas.')):ListView.builder(itemCount:rows.length,itemBuilder:(_,i){final p=rows[i];return ListTile(leading:Icon(p['type']=='En tienda'?Icons.store:Icons.shopping_cart),title:Text('${p['store']} · ${money(number(p['clientTotal']))}'),subtitle:Text('${clientName(clients,'${p['clientId']}')} · ${p['status']}\n${p['description']}'),isThreeLine:true,onTap:()async{await Navigator.push(context,MaterialPageRoute(builder:(_)=>PurchaseEditPage(existing:p)));load();},trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{if(await confirmDelete(context,'esta compra')){await softDelete('purchases','${p['id']}');load();}}));}),floatingActionButton:FloatingActionButton.extended(onPressed:()async{await Navigator.push(context,MaterialPageRoute(builder:(_)=>const PurchaseEditPage()));load();},icon:const Icon(Icons.add),label:const Text('Compra')));
}

class ReceiptResult { final String text; final double total; final String store; final String path; ReceiptResult(this.text,this.total,this.store,this.path); }

Future<ReceiptResult?> pickReceipt(ImageSource source) async {
  final x = await ImagePicker().pickImage(source: source, imageQuality: 88);
  if (x == null) return null;
  final dir = await getApplicationDocumentsDirectory();
  final ext = x.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
  final target = '${dir.path}/receipt_${DateTime.now().millisecondsSinceEpoch}.$ext';
  await File(x.path).copy(target);
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(target));
    final text = result.text;
    final upper = text.toUpperCase();
    String store = 'Otra tienda';
    for (final s in ['WALMART','AMAZON','SHEIN','TEMU','COSTCO','TARGET']) { if (upper.contains(s)) { store = s[0] + s.substring(1).toLowerCase(); break; } }
    final lines = text.split('\n');
    double best = 0;
    for (final line in lines) {
      final u = line.toUpperCase();
      final matches = RegExp(r'\$?\s*(\d{1,5}[.,]\d{2})').allMatches(line);
      for (final m in matches) {
        final v = number(m.group(1)?.replaceAll(',', '.'));
        if (u.contains('TOTAL') || u.contains('AMOUNT') || u.contains('BALANCE')) { if (v > 0) best = v; }
        else if (best == 0 && v > best) best = v;
      }
    }
    if (best == 0) {
      for (final m in RegExp(r'\$?\s*(\d{1,5}[.,]\d{2})').allMatches(text)) { final v=number(m.group(1)?.replaceAll(',', '.')); if(v>best) best=v; }
    }
    return ReceiptResult(text,best,store,target);
  } finally { recognizer.close(); }
}

class PurchaseEditPage extends StatefulWidget {
  final Map<String,dynamic>? existing; final bool startWithReceipt;
  const PurchaseEditPage({super.key,this.existing,this.startWithReceipt=false});
  @override State<PurchaseEditPage> createState()=>_PurchaseEditPageState();
}
class _PurchaseEditPageState extends State<PurchaseEditPage> {
  final store=TextEditingController(),desc=TextEditingController(),total=TextEditingController(),order=TextEditingController();
  List<Map<String,dynamic>> clients=[]; String? clientId; String type='Online'; String status='Pendiente de comprar'; double commission=0; String receiptPath=''; String ocrText=''; bool loaded=false;
  @override void initState(){super.initState();init();}
  Future<void> init() async {
    clients=active(await Store.list('clients')); final s=await Store.settings(); commission=number(widget.existing?['commissionPct']??s['purchaseCommissionPct']);
    if(widget.existing!=null){clientId='${widget.existing!['clientId']}';type='${widget.existing!['type']}';status='${widget.existing!['status']}';store.text='${widget.existing!['store']}';desc.text='${widget.existing!['description']}';total.text='${widget.existing!['total']}';order.text='${widget.existing!['orderNumber']??''}';receiptPath='${widget.existing!['receiptPath']??''}';ocrText='${widget.existing!['ocrText']??''}';}
    if(mounted)setState(()=>loaded=true);
    if(widget.startWithReceipt && widget.existing==null && mounted){WidgetsBinding.instance.addPostFrameCallback((_)=>importReceipt());}
  }
  Future<void> importReceipt() async {
    final source=await showModalBottomSheet<ImageSource>(context:context,builder:(_)=>SafeArea(child:Wrap(children:[ListTile(leading:const Icon(Icons.camera_alt),title:const Text('Tomar foto del ticket'),onTap:()=>Navigator.pop(context,ImageSource.camera)),ListTile(leading:const Icon(Icons.image),title:const Text('Elegir screenshot / imagen'),onTap:()=>Navigator.pop(context,ImageSource.gallery))])));
    if(source==null)return; final r=await pickReceipt(source); if(r==null)return; if(!mounted)return; setState((){receiptPath=r.path;ocrText=r.text;if(store.text.trim().isEmpty||store.text=='Otra tienda')store.text=r.store;if(r.total>0)total.text=r.total.toStringAsFixed(2);type='En tienda';});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ticket leído. Revisa el total y los datos antes de guardar.')));
  }
  Future<void> save() async {
    if(clientId==null||store.text.trim().isEmpty||number(total.text)<=0){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Selecciona cliente, tienda y un total válido.')));return;}
    final rows=await Store.list('purchases'); final base=number(total.text); final clientTotal=base*(1+commission/100);
    final item={'id':widget.existing?['id']??newId(),'clientId':clientId,'type':type,'store':store.text.trim(),'description':desc.text.trim(),'total':base,'commissionPct':commission,'clientTotal':clientTotal,'status':status,'orderNumber':order.text.trim(),'date':widget.existing?['date']??today(),'receiptPath':receiptPath,'ocrText':ocrText,'deleted':false};
    final i=rows.indexWhere((e)=>e['id']==item['id']); if(i>=0)rows[i]={...rows[i],...item};else rows.add(item); await Store.saveList('purchases',rows); if(mounted)Navigator.pop(context);
  }
  @override Widget build(BuildContext context){if(!loaded)return const Scaffold(body:Center(child:CircularProgressIndicator()));return Scaffold(appBar:AppBar(title:Text(widget.existing==null?'Nueva compra':'Editar compra')),body:ListView(padding:const EdgeInsets.all(16),children:[
    FilledButton.tonalIcon(onPressed:importReceipt,icon:const Icon(Icons.document_scanner),label:Text(receiptPath.isEmpty?'Leer ticket / screenshot':'Volver a leer ticket')),
    if(receiptPath.isNotEmpty)...[const SizedBox(height:10),ClipRRect(borderRadius:BorderRadius.circular(12),child:Image.file(File(receiptPath),height:150,fit:BoxFit.cover)),const SizedBox(height:6),const Text('Revisa los datos detectados antes de guardar.',style:TextStyle(fontSize:12))],
    const SizedBox(height:12),_drop('Cliente',clientId,clients.map((c)=>DropdownMenuItem(value:'${c['id']}',child:Text('${c['name']}'))).toList(),(v)=>setState(()=>clientId=v)),
    const SizedBox(height:12),_drop('Tipo de compra',type,['Online','En tienda','Manual'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),(v)=>setState(()=>type=v??type)),
    const SizedBox(height:12),TextField(controller:store,decoration:const InputDecoration(labelText:'Tienda (Amazon, Walmart, SHEIN...)')),
    const SizedBox(height:12),TextField(controller:desc,maxLines:3,decoration:const InputDecoration(labelText:'Productos / descripción')),
    const SizedBox(height:12),TextField(controller:order,decoration:const InputDecoration(labelText:'Número de pedido (opcional)')),
    const SizedBox(height:12),TextField(controller:total,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Total pagado')),
    const SizedBox(height:12),TextFormField(initialValue:commission.toStringAsFixed(2),keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Comisión %'),onChanged:(v)=>commission=number(v)),
    const SizedBox(height:12),_drop('Estado',status,['Pendiente de comprar','Comprado','Cancelado','Reembolso pendiente','Cerrado'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),(v)=>setState(()=>status=v??status)),
    const SizedBox(height:18),FilledButton.icon(onPressed:save,icon:const Icon(Icons.save),label:const Text('Guardar compra')),
  ]));}
}

Widget _drop(String label,String? value,List<DropdownMenuItem<String>> items,ValueChanged<String?> onChanged)=>InputDecorator(decoration:InputDecoration(labelText:label),child:DropdownButtonHideUnderline(child:DropdownButton<String>(isExpanded:true,value:items.any((e)=>e.value==value)?value:null,items:items,onChanged:onChanged)));
