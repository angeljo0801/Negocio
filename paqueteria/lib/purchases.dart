part of 'main.dart';

String purchasePhotoPath(Map<String, dynamic> purchase) {
  final photo = '${purchase['photoPath'] ?? ''}'.trim();
  if (photo.isNotEmpty) return photo;
  return '${purchase['receiptPath'] ?? ''}'.trim();
}

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});
  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  List<Map<String, dynamic>> rows = [], clients = [];
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    final r = await Future.wait([Store.list('purchases'), Store.list('clients')]);
    if (!mounted) return;
    setState(() { rows = active(r[0]); clients = active(r[1]); });
  }

  String buyers(Map<String, dynamic> p) {
    final ids = purchaseAllocations(p).map((e) => '${e['clientId']}').where((e) => e.isNotEmpty).toSet();
    if (ids.isEmpty) return clientName(clients, '${p['clientId']}');
    if (ids.length == 1) return clientName(clients, ids.first);
    return '${ids.length} clientes';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Pedidos y compras')),
        body: rows.isEmpty
            ? const Center(child: Text('No hay compras registradas.'))
            : ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final p = rows[i];
                  return ListTile(
                    leading: Builder(builder: (_) {
                      final path = purchasePhotoPath(p);
                      if (path.isNotEmpty && File(path).existsSync()) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(File(path), width: 52, height: 52, fit: BoxFit.cover),
                        );
                      }
                      return SizedBox(
                        width: 52,
                        height: 52,
                        child: Icon(p['type'] == 'En tienda' ? Icons.store : Icons.shopping_cart),
                      );
                    }),
                    title: Text('${p['store']} · ${money(number(p['clientTotal']))}'),
                    subtitle: Text('${buyers(p)} · ${p['status']}\n${p['description']}'),
                    isThreeLine: true,
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseEditPage(existing: p)));
                      load();
                    },
                    trailing: Wrap(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Boletín',
                        icon: const Icon(Icons.receipt_long),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BulletinPage(purchase: p))),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await confirmDelete(context, 'esta compra')) {
                            await softDelete('purchases', '${p['id']}');
                            load();
                          }
                        },
                      ),
                    ]),
                  );
                },
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseEditPage()));
            load();
          },
          icon: const Icon(Icons.add),
          label: const Text('Compra'),
        ),
      );
}

class ReceiptResult {
  final String text;
  final double total;
  final double subtotal;
  final double tax;
  final String store;
  final String path;
  final String orderNumber;
  final List<Map<String, dynamic>> items;
  ReceiptResult({required this.text, required this.total, required this.subtotal, required this.tax, required this.store, required this.path, required this.orderNumber, required this.items});
}

String _cleanItemName(String raw) {
  return raw
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .replaceAll(RegExp(r'^[*#\-\s]+'), '')
      .trim();
}

Future<ReceiptResult?> pickReceipt(ImageSource source) async {
  final x = await ImagePicker().pickImage(source: source, imageQuality: 90);
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
    for (final s in ['WALMART', 'AMAZON', 'SHEIN', 'TEMU', 'COSTCO', 'TARGET', 'CVS', 'WALGREENS', 'PUBLIX']) {
      if (upper.contains(s)) { store = s[0] + s.substring(1).toLowerCase(); break; }
    }

    double total = 0, subtotal = 0, tax = 0;
    String orderNumber = '';
    final items = <Map<String, dynamic>>[];
    final lines = text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final amountAtEnd = RegExp(r'(?:\$\s*)?(-?\d{1,6}[.,]\d{2})\s*$');
    final totalWords = RegExp(r'\b(GRAND\s*TOTAL|TOTAL|AMOUNT\s*DUE|BALANCE\s*DUE)\b');
    final subtotalWords = RegExp(r'\b(SUBTOTAL|SUB\s*TOTAL)\b');
    final taxWords = RegExp(r'\b(TAX|SALES\s*TAX)\b');
    final ignoreWords = RegExp(r'\b(CASH|CHANGE|TENDER|PAYMENT|VISA|MASTERCARD|DEBIT|CREDIT|SAVINGS|DISCOUNT|COUPON)\b');

    for (final line in lines) {
      final u = line.toUpperCase();
      if (orderNumber.isEmpty && (u.contains('ORDER') || u.contains('PEDIDO'))) {
        final m = RegExp(r'(?:ORDER|PEDIDO)(?:\s*(?:NO|NUMBER|#|NRO)\.?\s*)?[:#\-]?\s*([A-Z0-9\-]{5,})', caseSensitive: false).firstMatch(line);
        if (m != null) orderNumber = m.group(1) ?? '';
      }
      final m = amountAtEnd.firstMatch(line);
      if (m == null) continue;
      final value = number((m.group(1) ?? '').replaceAll(',', '.'));
      if (subtotalWords.hasMatch(u)) { subtotal = value; continue; }
      if (taxWords.hasMatch(u)) { tax = value; continue; }
      if (totalWords.hasMatch(u)) { if (value.abs() >= total.abs()) total = value; continue; }
      if (ignoreWords.hasMatch(u)) continue;
      final rawName = line.substring(0, m.start).replaceAll(RegExp(r'\$\s*$'), '');
      final name = _cleanItemName(rawName);
      if (name.length < 2 || RegExp(r'^\d+$').hasMatch(name)) continue;
      items.add({'id': newId(), 'name': name, 'price': value, 'qty': 1.0, 'clientId': ''});
    }

    if (total == 0) {
      if (subtotal > 0) total = subtotal + tax;
      if (total == 0 && items.isNotEmpty) total = items.fold<double>(0, (a, e) => a + number(e['price']) * number(e['qty']));
    }
    if (subtotal == 0 && items.isNotEmpty) subtotal = items.fold<double>(0, (a, e) => a + number(e['price']) * number(e['qty']));
    return ReceiptResult(text: text, total: total, subtotal: subtotal, tax: tax, store: store, path: target, orderNumber: orderNumber, items: items);
  } finally {
    recognizer.close();
  }
}

class PurchaseEditPage extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final bool startWithReceipt;
  const PurchaseEditPage({super.key, this.existing, this.startWithReceipt = false});
  @override
  State<PurchaseEditPage> createState() => _PurchaseEditPageState();
}

class _PurchaseEditPageState extends State<PurchaseEditPage> {
  final store = TextEditingController(), desc = TextEditingController(), total = TextEditingController(), order = TextEditingController(), date = TextEditingController();
  List<Map<String, dynamic>> clients = [];
  List<Map<String, dynamic>> items = [];
  String? clientId;
  String type = 'Online', status = 'Pendiente de comprar';
  double commission = 0;
  String receiptPath = '', ocrText = '', photoPath = '';
  bool loaded = false;

  @override
  void initState() { super.initState(); init(); }

  Future<void> init() async {
    clients = active(await Store.list('clients'));
    final s = await Store.settings();
    commission = number(widget.existing?['commissionPct'] ?? s['purchaseCommissionPct']);
    date.text = '${widget.existing?['date'] ?? today()}';
    if (widget.existing != null) {
      clientId = '${widget.existing!['clientId'] ?? ''}';
      if (clientId!.isEmpty) clientId = null;
      type = '${widget.existing!['type'] ?? 'Online'}';
      status = '${widget.existing!['status'] ?? 'Comprado'}';
      store.text = '${widget.existing!['store'] ?? ''}';
      desc.text = '${widget.existing!['description'] ?? ''}';
      total.text = '${widget.existing!['total'] ?? ''}';
      order.text = '${widget.existing!['orderNumber'] ?? ''}';
      receiptPath = '${widget.existing!['receiptPath'] ?? ''}';
      photoPath = '${widget.existing!['photoPath'] ?? ''}';
      ocrText = '${widget.existing!['ocrText'] ?? ''}';
      items = purchaseItems(widget.existing!);
    }
    if (mounted) setState(() => loaded = true);
    if (widget.startWithReceipt && widget.existing == null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => importReceipt());
    }
  }

  Future<void> pickPurchasePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Tomar foto'),
            subtitle: const Text('Foto del producto, compra o ticket'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Elegir de galería'),
            subtitle: const Text('Screenshot, ticket o foto de la compra'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 88);
    if (picked == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final lower = picked.path.toLowerCase();
    final ext = lower.endsWith('.png') ? 'png' : lower.endsWith('.webp') ? 'webp' : 'jpg';
    final target = '${dir.path}/purchase_photo_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await File(picked.path).copy(target);
    if (!mounted) return;
    setState(() => photoPath = target);
  }

  Future<void> importReceipt() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(child: Wrap(children: [
        ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Tomar foto del ticket'), onTap: () => Navigator.pop(context, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.image), title: const Text('Elegir screenshot / imagen'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
      ])),
    );
    if (source == null) return;
    final r = await pickReceipt(source);
    if (r == null || !mounted) return;
    setState(() {
      receiptPath = r.path;
      if (photoPath.isEmpty) photoPath = r.path;
      ocrText = r.text;
      if (store.text.trim().isEmpty || store.text == 'Otra tienda') store.text = r.store;
      if (r.total > 0) total.text = r.total.toStringAsFixed(2);
      if (order.text.trim().isEmpty && r.orderNumber.isNotEmpty) order.text = r.orderNumber;
      items = r.items.map((e) => {...e, 'clientId': clientId ?? ''}).toList();
      type = 'En tienda';
      status = 'Comprado';
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ticket leído: ${items.length} artículo(s) detectado(s). Revisa nombres, precios y cliente.')));
  }

  Future<void> editItem([Map<String, dynamic>? item]) async {
    final name = TextEditingController(text: '${item?['name'] ?? ''}');
    final price = TextEditingController(text: '${item?['price'] ?? ''}');
    final qty = TextEditingController(text: '${item?['qty'] ?? 1}');
    String? assigned = '${item?['clientId'] ?? clientId ?? ''}';
    if (assigned.isEmpty) assigned = null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (context, setD) => AlertDialog(
        title: Text(item == null ? 'Añadir artículo' : 'Editar artículo'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Artículo')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio unitario'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Cantidad'))),
          ]),
          const SizedBox(height: 8),
          _drop('Cliente', assigned, clients.map((c) => DropdownMenuItem(value: '${c['id']}', child: Text('${c['name']}'))).toList(), (v) => setD(() => assigned = v)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      )),
    );
    if (ok != true || name.text.trim().isEmpty || number(price.text) == 0) return;
    final updated = {
      'id': item?['id'] ?? newId(),
      'name': name.text.trim(),
      'price': number(price.text),
      'qty': number(qty.text) <= 0 ? 1.0 : number(qty.text),
      'clientId': assigned ?? '',
    };
    setState(() {
      final i = item == null ? -1 : items.indexWhere((e) => e['id'] == item['id']);
      if (i >= 0) items[i] = updated; else items.add(updated);
    });
  }

  List<Map<String, dynamic>> buildAllocations(double base) {
    if (items.isEmpty) {
      if (clientId == null) return [];
      return [{
        'clientId': clientId,
        'subtotal': base,
        'extras': 0.0,
        'commissionPct': commission,
        'total': base * (1 + commission / 100),
        'itemIds': <String>[],
      }];
    }
    for (final e in items) {
      if ('${e['clientId'] ?? ''}'.isEmpty && clientId != null) e['clientId'] = clientId;
    }
    final valid = items.where((e) => '${e['clientId'] ?? ''}'.isNotEmpty).toList();
    if (valid.length != items.length) return [];
    final itemSum = valid.fold<double>(0, (a, e) => a + number(e['price']) * number(e['qty'] ?? 1));
    final extras = base - itemSum;
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final e in valid) grouped.putIfAbsent('${e['clientId']}', () => []).add(e);
    final out = <Map<String, dynamic>>[];
    for (final entry in grouped.entries) {
      final sub = entry.value.fold<double>(0, (a, e) => a + number(e['price']) * number(e['qty'] ?? 1));
      final extraShare = itemSum == 0 ? 0.0 : extras * (sub / itemSum);
      final beforeCommission = sub + extraShare;
      out.add({
        'clientId': entry.key,
        'subtotal': sub,
        'extras': extraShare,
        'commissionPct': commission,
        'total': beforeCommission * (1 + commission / 100),
        'itemIds': entry.value.map((e) => '${e['id']}').toList(),
      });
    }
    return out;
  }

  Future<void> save() async {
    final base = number(total.text);
    if (store.text.trim().isEmpty || base <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La tienda y un total válido son obligatorios.')));
      return;
    }
    final allocations = buildAllocations(base);
    if (allocations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona un cliente para la compra o para cada artículo.')));
      return;
    }
    final primaryClient = clientId ?? '${allocations.first['clientId']}';
    final clientTotal = allocations.fold<double>(0, (a, e) => a + number(e['total']));
    final rows = await Store.list('purchases');
    final item = {
      'id': widget.existing?['id'] ?? newId(),
      'clientId': primaryClient,
      'type': type,
      'store': store.text.trim(),
      'description': desc.text.trim().isEmpty && items.isNotEmpty ? items.take(4).map((e) => e['name']).join(', ') : desc.text.trim(),
      'total': base,
      'commissionPct': commission,
      'clientTotal': clientTotal,
      'status': status,
      'orderNumber': order.text.trim(),
      'date': date.text.trim().isEmpty ? today() : date.text.trim(),
      'receiptPath': receiptPath,
      'photoPath': photoPath,
      'ocrText': ocrText,
      'items': items,
      'allocations': allocations,
      'deleted': false,
    };
    final i = rows.indexWhere((e) => e['id'] == item['id']);
    if (i >= 0) rows[i] = {...rows[i], ...item}; else rows.add(item);
    await Store.saveList('purchases', rows);
    if (!mounted) return;
    if (widget.existing == null) {
      final openBulletin = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Compra guardada'),
          content: Text(allocations.length > 1 ? 'Se crearon ${allocations.length} boletines, uno por cliente. ¿Quieres abrirlos ahora?' : '¿Quieres abrir el boletín del cliente ahora?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Después')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Abrir boletín')),
          ],
        ),
      );
      if (openBulletin == true && mounted) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => BulletinPage(purchase: item)));
      }
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Nueva compra' : 'Editar compra'),
        actions: [
          if (widget.existing != null)
            IconButton(tooltip: 'Boletín', icon: const Icon(Icons.receipt_long), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BulletinPage(purchase: widget.existing!)))),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Foto del pedido / compra', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Opcional. Puedes guardar una foto del producto, screenshot de la compra o ticket para tenerla junto al registro.'),
        const SizedBox(height: 10),
        if (photoPath.isNotEmpty && File(photoPath).existsSync()) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(File(photoPath), height: 210, width: double.infinity, fit: BoxFit.cover),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: pickPurchasePhoto,
                icon: const Icon(Icons.change_circle_outlined),
                label: const Text('Cambiar foto'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() => photoPath = ''),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Quitar'),
            ),
          ]),
        ] else
          FilledButton.tonalIcon(
            onPressed: pickPurchasePhoto,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Añadir foto (opcional)'),
          ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: importReceipt,
          icon: const Icon(Icons.document_scanner),
          label: Text(receiptPath.isEmpty ? 'Leer ticket / screenshot con OCR' : 'Volver a leer ticket con OCR'),
        ),
        if (receiptPath.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Text('El OCR puede equivocarse. Revisa artículos, precios y total antes de guardar.', style: TextStyle(fontSize: 12)),
          if (receiptPath != photoPath && File(receiptPath).existsSync()) ...[
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(receiptPath), height: 130, fit: BoxFit.cover)),
          ],
        ],
        const SizedBox(height: 12),
        _drop('Cliente predeterminado', clientId, clients.map((c) => DropdownMenuItem(value: '${c['id']}', child: Text('${c['name']}'))).toList(), (v) => setState(() {
          clientId = v;
          for (final e in items) {
            if ('${e['clientId'] ?? ''}'.isEmpty) e['clientId'] = v ?? '';
          }
        })),
        const SizedBox(height: 12),
        _drop('Tipo de compra', type, ['Online', 'En tienda', 'Manual'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(), (v) => setState(() => type = v ?? type)),
        const SizedBox(height: 12),
        TextField(controller: store, decoration: const InputDecoration(labelText: 'Tienda (Amazon, Walmart, SHEIN...)')),
        const SizedBox(height: 12),
        TextField(controller: desc, maxLines: 2, decoration: const InputDecoration(labelText: 'Descripción general')),
        const SizedBox(height: 12),
        TextField(controller: order, decoration: const InputDecoration(labelText: 'Número de pedido (opcional)')),
        const SizedBox(height: 12),
        TextField(controller: date, decoration: const InputDecoration(labelText: 'Fecha (AAAA-MM-DD)')),
        const SizedBox(height: 12),
        TextField(controller: total, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Total del ticket / compra')),
        const SizedBox(height: 12),
        TextFormField(initialValue: commission.toStringAsFixed(2), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Comisión %'), onChanged: (v) => commission = number(v)),
        const SizedBox(height: 12),
        _drop('Estado', status, ['Pendiente de comprar', 'Comprado', 'Cancelado', 'Reembolso pendiente', 'Cerrado'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(), (v) => setState(() => status = v ?? status)),
        const Divider(height: 28),
        Row(children: [
          Expanded(child: Text('Artículos del ticket', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
          TextButton.icon(onPressed: () => editItem(), icon: const Icon(Icons.add), label: const Text('Añadir')),
        ]),
        if (items.isEmpty) const Text('No hay artículos separados. Puedes añadirlos manualmente o leer un ticket.'),
        for (final e in items)
          Card(
            child: ListTile(
              title: Text('${e['name']}'),
              subtitle: Text('${clientName(clients, '${e['clientId']}')} · x${number(e['qty']).toStringAsFixed(number(e['qty']) % 1 == 0 ? 0 : 2)}'),
              trailing: Wrap(mainAxisSize: MainAxisSize.min, children: [
                Text(money(number(e['price']) * number(e['qty'] ?? 1))),
                IconButton(icon: const Icon(Icons.edit), onPressed: () => editItem(e)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => items.removeWhere((x) => x['id'] == e['id']))),
              ]),
            ),
          ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Puedes asignar cada artículo a un cliente diferente. El impuesto/descuento restante del ticket se reparte proporcionalmente.'),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: save, icon: const Icon(Icons.save), label: const Text('Guardar compra')),
        const SizedBox(height: 60),
      ]),
    );
  }
}

Widget _drop(String label, String? value, List<DropdownMenuItem<String>> items, ValueChanged<String?> onChanged) => InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButtonHideUnderline(child: DropdownButton<String>(isExpanded: true, value: items.any((e) => e.value == value) ? value : null, items: items, onChanged: onChanged)),
    );
