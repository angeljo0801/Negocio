part of 'main.dart';

List<String> purchasePhotoPaths(Map<String, dynamic> purchase) {
  final out = <String>[];
  final raw = purchase['photoPaths'];
  if (raw is List) {
    for (final value in raw) {
      final path = '$value'.trim();
      if (path.isNotEmpty && !out.contains(path)) out.add(path);
    }
  }
  final legacy = '${purchase['photoPath'] ?? ''}'.trim();
  if (legacy.isNotEmpty && !out.contains(legacy)) out.add(legacy);
  final receipt = '${purchase['receiptPath'] ?? ''}'.trim();
  if (out.isEmpty && receipt.isNotEmpty) out.add(receipt);
  return out;
}

String purchasePhotoPath(Map<String, dynamic> purchase) {
  final photos = purchasePhotoPaths(purchase);
  return photos.isEmpty ? '' : photos.first;
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
    final ids = purchaseAllocations(p)
        .map((e) => '${e['clientId']}')
        .where((e) => e.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return clientName(clients, '${p['clientId']}');
    if (ids.length == 1) return clientName(clients, ids.first);
    return '${ids.length} clientes';
  }

  bool isUnassigned(Map<String, dynamic> p) {
    final direct = '${p['clientId'] ?? ''}'.trim();
    return direct.isEmpty && purchaseAllocations(p).isEmpty;
  }

  Future<void> assignClient(Map<String, dynamic> purchase) async {
    if (clients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero crea un cliente para poder asociar el pedido.'),
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              leading: Icon(Icons.person_add_alt_1),
              title: Text('Asociar pedido a un cliente'),
              subtitle: Text('Selecciona un cliente ya creado'),
            ),
            const Divider(height: 1),
            for (final c in clients)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text('${c['name']}'),
                subtitle: '${c['phone'] ?? ''}'.trim().isEmpty
                    ? null
                    : Text('${c['phone']}'),
                onTap: () => Navigator.pop(context, '${c['id']}'),
              ),
          ],
        ),
      ),
    );
    if (selected == null || selected.isEmpty) return;

    final rows = await Store.list('purchases');
    final index =
        rows.indexWhere((e) => '${e['id']}' == '${purchase['id']}');
    if (index < 0) return;

    final current = rows[index];
    final base = number(current['total']);
    final commissionPct = number(current['commissionPct']);
    final assignedItems = purchaseItems(current)
        .map((e) => {...e, 'clientId': selected})
        .toList();

    rows[index] = {
      ...current,
      'clientId': selected,
      'items': assignedItems,
      'allocations': [
        {
          'clientId': selected,
          'subtotal': base,
          'extras': 0.0,
          'commissionPct': commissionPct,
          'total': base * (1 + commissionPct / 100),
          'itemIds':
              assignedItems.map((e) => '${e['id']}').toList(),
        }
      ],
      'clientTotal': base * (1 + commissionPct / 100),
      'unassigned': false,
    };

    await Store.saveList('purchases', rows);
    if (!mounted) return;
    await load();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Pedido asociado a ${clientName(clients, selected)}.',
        ),
      ),
    );
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
                    title: Text(
                      '${p['store']} · ${money(isUnassigned(p) ? number(p['total']) : number(p['clientTotal']))}',
                    ),
                    subtitle: Text(
                      isUnassigned(p)
                          ? 'Sin cliente · Toca el icono de persona para asociarlo\n${p['status']} · ${p['description']}'
                          : '${buyers(p)} · ${p['status']}\n${p['description']}',
                    ),
                    isThreeLine: true,
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseEditPage(existing: p)));
                      load();
                    },
                    trailing: Wrap(mainAxisSize: MainAxisSize.min, children: [
                      if (isUnassigned(p))
                        IconButton(
                          tooltip: 'Asociar cliente',
                          icon: const Icon(Icons.person_add_alt_1),
                          onPressed: () => assignClient(p),
                        )
                      else
                        IconButton(
                          tooltip: 'Boletín',
                          icon: const Icon(Icons.receipt_long),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BulletinPage(purchase: p),
                            ),
                          ),
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
  final double shipping;
  final double discount;
  final String store;
  final String path;
  final String orderNumber;
  final List<Map<String, dynamic>> items;
  final int expectedItemCount;
  final double confidence;
  final List<String> warnings;
  final bool onlineStore;

  ReceiptResult({
    required this.text,
    required this.total,
    required this.subtotal,
    required this.tax,
    required this.shipping,
    required this.discount,
    required this.store,
    required this.path,
    required this.orderNumber,
    required this.items,
    required this.expectedItemCount,
    required this.confidence,
    required this.warnings,
    required this.onlineStore,
  });
}

Future<ReceiptResult?> pickReceipt(ImageSource source) async {
  // Keep screenshots at maximum quality: recompressing small online-store text
  // reduces ML Kit accuracy.
  final x = await ImagePicker().pickImage(source: source, imageQuality: 100);
  if (x == null) return null;
  final dir = await getApplicationDocumentsDirectory();
  final lower = x.path.toLowerCase();
  final ext = lower.endsWith('.png')
      ? 'png'
      : lower.endsWith('.webp')
          ? 'webp'
          : 'jpg';
  final target =
      '${dir.path}/receipt_${DateTime.now().millisecondsSinceEpoch}.${ext}';
  await File(x.path).copy(target);

  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final recognized =
        await recognizer.processImage(InputImage.fromFilePath(target));
    final parsed = StoreOcrParser.parse(recognized.text);
    return ReceiptResult(
      text: recognized.text,
      total: parsed.total,
      subtotal: parsed.subtotal,
      tax: parsed.tax,
      shipping: parsed.shipping,
      discount: parsed.discount,
      store: parsed.store,
      path: target,
      orderNumber: parsed.orderNumber,
      items: parsed.items,
      expectedItemCount: parsed.expectedItemCount,
      confidence: parsed.confidence,
      warnings: parsed.warnings,
      onlineStore: parsed.isOnlineStore,
    );
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
  String receiptPath = '', ocrText = '';
  Map<String, dynamic> ocrMeta = {};
  List<String> photoPaths = [];
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
      photoPaths = purchasePhotoPaths(widget.existing!);
      ocrText = '${widget.existing!['ocrText'] ?? ''}';
      final storedOcrMeta = widget.existing!['ocrMeta'];
      if (storedOcrMeta is Map) {
        ocrMeta = Map<String, dynamic>.from(storedOcrMeta);
      }
      items = purchaseItems(widget.existing!);
    }
    if (mounted) setState(() => loaded = true);
    if (widget.startWithReceipt && widget.existing == null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => importReceipt());
    }
  }

  Future<String> _copyPurchasePhoto(XFile picked) async {
    final dir = await getApplicationDocumentsDirectory();
    final lower = picked.path.toLowerCase();
    final ext = lower.endsWith('.png')
        ? 'png'
        : lower.endsWith('.webp')
            ? 'webp'
            : 'jpg';
    final target =
        '${dir.path}/purchase_photo_${DateTime.now().microsecondsSinceEpoch}_${photoPaths.length}.$ext';
    await File(picked.path).copy(target);
    return target;
  }

  Future<void> pickPurchasePhotos() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Tomar una foto'),
            subtitle: const Text('Puedes repetirlo cuantas veces quieras'),
            onTap: () => Navigator.pop(context, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.collections_outlined),
            title: const Text('Elegir una o varias de la galería'),
            subtitle: const Text('Selecciona todas las fotos que necesites'),
            onTap: () => Navigator.pop(context, 'gallery'),
          ),
        ]),
      ),
    );
    if (action == null) return;

    final picker = ImagePicker();
    final added = <String>[];
    if (action == 'camera') {
      final picked =
          await picker.pickImage(source: ImageSource.camera, imageQuality: 88);
      if (picked != null) added.add(await _copyPurchasePhoto(picked));
    } else {
      final picked = await picker.pickMultiImage(imageQuality: 88);
      for (final image in picked) {
        added.add(await _copyPurchasePhoto(image));
      }
    }
    if (!mounted || added.isEmpty) return;
    setState(() {
      for (final path in added) {
        if (!photoPaths.contains(path)) photoPaths.add(path);
      }
    });
  }

  Future<void> openPurchasePhoto(String path) async {
    if (!File(path).existsSync()) return;
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.7,
              maxScale: 5,
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> importReceipt() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(child: Wrap(children: [
        ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Tomar foto de compra / ticket'), onTap: () => Navigator.pop(context, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.image), title: const Text('Elegir screenshot / imagen'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
      ])),
    );
    if (source == null) return;
    final r = await pickReceipt(source);
    if (r == null || !mounted) return;
    setState(() {
      receiptPath = r.path;
      if (!photoPaths.contains(r.path)) photoPaths.add(r.path);
      ocrText = r.text;
      if (store.text.trim().isEmpty || store.text == 'Otra tienda') store.text = r.store;
      if (r.total > 0) total.text = r.total.toStringAsFixed(2);
      if (order.text.trim().isEmpty && r.orderNumber.isNotEmpty) order.text = r.orderNumber;
      items = r.items
          .map((e) => {...e, 'clientId': clientId ?? ''})
          .toList();
      ocrMeta = {
        'store': r.store,
        'subtotal': r.subtotal,
        'tax': r.tax,
        'shipping': r.shipping,
        'discount': r.discount,
        'expectedItems': r.expectedItemCount,
        'detectedItems': r.items.length,
        'confidence': r.confidence,
        'warnings': r.warnings,
      };
      type = r.onlineStore ? 'Online' : 'En tienda';
      status = 'Comprado';
    });

    final countText = r.expectedItemCount > 0
        ? '${r.items.length}/${r.expectedItemCount} artículos con nombre y precio'
        : '${r.items.length} artículo(s) con nombre y precio';
    final confidencePct = (r.confidence * 100).round();
    final warning = r.warnings.isEmpty ? '' : ' · ${r.warnings.first}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(
          'OCR ${r.store}: $countText · confianza $confidencePct%$warning. Revisa los campos antes de guardar.',
        ),
      ),
    );
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
    final hasAssignedItem =
        items.any((e) => '${e['clientId'] ?? ''}'.trim().isNotEmpty);
    final hasUnassignedItem =
        items.any((e) => '${e['clientId'] ?? ''}'.trim().isEmpty);
    final unassigned =
        clientId == null && allocations.isEmpty && !hasAssignedItem;

    if (!unassigned && allocations.isEmpty) {
      final message = hasAssignedItem && hasUnassignedItem
          ? 'Hay artículos sin cliente. Asígnalos todos o elige un cliente predeterminado.'
          : 'Selecciona un cliente para la compra o guárdala completamente sin cliente.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }

    final primaryClient =
        unassigned ? '' : (clientId ?? '${allocations.first['clientId']}');
    final clientTotal = unassigned
        ? 0.0
        : allocations.fold<double>(
            0,
            (a, e) => a + number(e['total']),
          );
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
      'photoPaths': photoPaths,
      'photoPath': photoPaths.isEmpty ? '' : photoPaths.first,
      'ocrText': ocrText,
      'ocrMeta': ocrMeta,
      'items': items,
      'allocations': allocations,
      'unassigned': unassigned,
      'deleted': false,
    };
    final i = rows.indexWhere((e) => e['id'] == item['id']);
    if (i >= 0) rows[i] = {...rows[i], ...item}; else rows.add(item);
    await Store.saveList('purchases', rows);
    if (!mounted) return;
    if (widget.existing == null && allocations.isNotEmpty) {
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
    if (mounted && unassigned) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pedido guardado sin cliente. Puedes asociarlo más adelante.',
          ),
        ),
      );
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
        Row(
          children: [
            Expanded(
              child: Text(
                'Fotos del pedido / compra',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            if (photoPaths.isNotEmpty)
              Text('${photoPaths.length} foto${photoPaths.length == 1 ? '' : 's'}'),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Opcional. Guarda todas las fotos, screenshots o tickets que necesites dentro del mismo pedido.',
        ),
        const SizedBox(height: 10),
        if (photoPaths.isNotEmpty) ...[
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: photoPaths.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (_, index) {
              final path = photoPaths[index];
              return Stack(
                fit: StackFit.expand,
                children: [
                  InkWell(
                    onTap: () => openPurchasePhoto(path),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: File(path).existsSync()
                          ? Image.file(File(path), fit: BoxFit.cover)
                          : Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: const Icon(Icons.broken_image_outlined),
                            ),
                    ),
                  ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: IconButton.filled(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Quitar esta foto',
                      onPressed: () =>
                          setState(() => photoPaths.removeAt(index)),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ),
                  Positioned(
                    left: 5,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
        ],
        FilledButton.tonalIcon(
          onPressed: pickPurchasePhotos,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(
            photoPaths.isEmpty ? 'Añadir fotos' : 'Añadir más fotos',
          ),
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
          if (!photoPaths.contains(receiptPath) && File(receiptPath).existsSync()) ...[
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(receiptPath), height: 130, fit: BoxFit.cover)),
          ],
        ],
        const SizedBox(height: 12),
        _drop(
          'Cliente predeterminado (opcional)',
          clientId,
          clients
              .map(
                (c) => DropdownMenuItem(
                  value: '${c['id']}',
                  child: Text('${c['name']}'),
                ),
              )
              .toList(),
          (v) => setState(() {
            clientId = v;
            for (final e in items) {
              if ('${e['clientId'] ?? ''}'.isEmpty) {
                e['clientId'] = v ?? '';
              }
            }
          }),
        ),
        const SizedBox(height: 6),
        const Text(
          'Puedes guardar el pedido sin cliente y asociarlo después desde Pedidos y compras.',
          style: TextStyle(fontSize: 12),
        ),
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
