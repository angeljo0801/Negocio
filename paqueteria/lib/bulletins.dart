part of 'main.dart';

List<Map<String, dynamic>> purchaseAllocations(Map<String, dynamic> purchase) {
  final raw = purchase['allocations'];
  if (raw is List && raw.isNotEmpty) {
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  final clientId = '${purchase['clientId'] ?? ''}';
  if (clientId.isEmpty) return [];
  return [
    {
      'clientId': clientId,
      'subtotal': number(purchase['total']),
      'extras': 0.0,
      'commissionPct': number(purchase['commissionPct']),
      'total': number(purchase['clientTotal']),
      'itemIds': <String>[],
    }
  ];
}

bool purchaseHasClient(Map<String, dynamic> purchase, String clientId) {
  if ('${purchase['clientId'] ?? ''}' == clientId) return true;
  return purchaseAllocations(purchase).any((a) => '${a['clientId'] ?? ''}' == clientId);
}

double purchaseAmountForClient(Map<String, dynamic> purchase, String clientId) {
  final a = purchaseAllocations(purchase).where((e) => '${e['clientId'] ?? ''}' == clientId).toList();
  if (a.isNotEmpty) return a.fold<double>(0, (s, e) => s + number(e['total']));
  if ('${purchase['clientId'] ?? ''}' == clientId) return number(purchase['clientTotal']);
  return 0;
}

List<Map<String, dynamic>> purchaseItems(Map<String, dynamic> purchase) {
  final raw = purchase['items'];
  if (raw is! List) return [];
  return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

List<Map<String, dynamic>> itemsForClient(Map<String, dynamic> purchase, String clientId) {
  return purchaseItems(purchase).where((e) => '${e['clientId'] ?? ''}' == clientId).toList();
}

class BulletinPage extends StatefulWidget {
  final Map<String, dynamic> purchase;
  final String? initialClientId;
  const BulletinPage({super.key, required this.purchase, this.initialClientId});

  @override
  State<BulletinPage> createState() => _BulletinPageState();
}

class _BulletinPageState extends State<BulletinPage> {
  List<Map<String, dynamic>> clients = [];
  String? clientId;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    clients = active(await Store.list('clients'));
    final ids = purchaseAllocations(widget.purchase).map((e) => '${e['clientId']}').where((e) => e.isNotEmpty).toList();
    clientId = widget.initialClientId ?? (ids.isNotEmpty ? ids.first : '${widget.purchase['clientId'] ?? ''}');
    if (mounted) setState(() => loading = false);
  }

  Map<String, dynamic>? get allocation {
    final list = purchaseAllocations(widget.purchase).where((e) => '${e['clientId']}' == clientId).toList();
    return list.isEmpty ? null : list.first;
  }

  String get name => clientName(clients, clientId);

  Future<File> _buildPdf() async {
    final a = allocation ?? <String, dynamic>{};
    final items = itemsForClient(widget.purchase, clientId ?? '');
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => [
          pw.Text('PAQUETERÍA', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
          pw.Text('Boletín de compra', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 16),
          pw.Text('Cliente: $name'),
          pw.Text('Tienda: ${widget.purchase['store'] ?? ''}'),
          pw.Text('Fecha: ${widget.purchase['date'] ?? ''}'),
          if ('${widget.purchase['orderNumber'] ?? ''}'.trim().isNotEmpty) pw.Text('Pedido: ${widget.purchase['orderNumber']}'),
          pw.SizedBox(height: 16),
          if (items.isNotEmpty)
            pw.Table.fromTextArray(
              headers: const ['Artículo', 'Cantidad', 'Precio'],
              data: items.map((e) => ['${e['name']}', '${e['qty'] ?? 1}', money(number(e['price']) * number(e['qty'] ?? 1))]).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
            )
          else
            pw.Text('${widget.purchase['description'] ?? 'Compra registrada'}'),
          pw.SizedBox(height: 16),
          pw.Divider(),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Subtotal'), pw.Text(money(number(a['subtotal'])))]),
          if (number(a['extras']) != 0)
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Impuestos / otros'), pw.Text(money(number(a['extras'])))]),
          if (number(a['commissionPct']) != 0)
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Comisión ${number(a['commissionPct']).toStringAsFixed(2)}%'), pw.Text(money(number(a['total']) - number(a['subtotal']) - number(a['extras'])))]),
          pw.SizedBox(height: 6),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('TOTAL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 15)), pw.Text(money(number(a['total'])), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 15))]),
          pw.SizedBox(height: 24),
          pw.Text('Generado por Paquetería · Herramientas de Negocio', style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
    final dir = await getApplicationDocumentsDirectory();
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final path = '${dir.path}/boletin_${safe}_${widget.purchase['id']}.pdf';
    final file = File(path);
    await file.writeAsBytes(await doc.save(), flush: true);
    return file;
  }

  Future<void> sharePdf() async {
    final f = await _buildPdf();
    await Share.shareXFiles([XFile(f.path)], text: 'Boletín de compra de $name · ${widget.purchase['store']}');
  }

  Future<void> shareText() async {
    final a = allocation ?? <String, dynamic>{};
    final items = itemsForClient(widget.purchase, clientId ?? '');
    final b = StringBuffer()
      ..writeln('PAQUETERÍA - BOLETÍN DE COMPRA')
      ..writeln('Cliente: $name')
      ..writeln('Tienda: ${widget.purchase['store']}')
      ..writeln('Fecha: ${widget.purchase['date']}')
      ..writeln('');
    if (items.isEmpty) {
      b.writeln('${widget.purchase['description']}');
    } else {
      for (final e in items) {
        b.writeln('• ${e['name']} x${e['qty'] ?? 1}: ${money(number(e['price']) * number(e['qty'] ?? 1))}');
      }
    }
    b
      ..writeln('')
      ..writeln('Subtotal: ${money(number(a['subtotal']))}')
      ..writeln('Impuestos/otros: ${money(number(a['extras']))}')
      ..writeln('TOTAL: ${money(number(a['total']))}');
    await Share.share(b.toString(), subject: 'Boletín de compra - $name');
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final allocations = purchaseAllocations(widget.purchase);
    final a = allocation ?? <String, dynamic>{};
    final items = itemsForClient(widget.purchase, clientId ?? '');
    return Scaffold(
      appBar: AppBar(title: const Text('Boletín del cliente')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (allocations.length > 1)
          _drop(
            'Cliente',
            clientId,
            allocations.map((e) => DropdownMenuItem(value: '${e['clientId']}', child: Text(clientName(clients, '${e['clientId']}')))).toList(),
            (v) => setState(() => clientId = v),
          ),
        if (allocations.length > 1) const SizedBox(height: 12),
        _sectionCard(context, 'Compra', Icons.receipt_long, [
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          Text('${widget.purchase['store']} · ${widget.purchase['date']}'),
          if ('${widget.purchase['orderNumber'] ?? ''}'.trim().isNotEmpty) Text('Pedido: ${widget.purchase['orderNumber']}'),
        ]),
        const SizedBox(height: 12),
        _sectionCard(context, 'Artículos', Icons.shopping_bag, [
          if (items.isEmpty) Text('${widget.purchase['description'] ?? 'Sin detalle de artículos.'}'),
          for (final e in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${e['name']}'),
              subtitle: Text('Cantidad: ${e['qty'] ?? 1}'),
              trailing: Text(money(number(e['price']) * number(e['qty'] ?? 1))),
            ),
        ]),
        const SizedBox(height: 12),
        _sectionCard(context, 'Total', Icons.payments, [
          _moneyRow('Subtotal', number(a['subtotal'])),
          _moneyRow('Impuestos / otros', number(a['extras'])),
          if (number(a['commissionPct']) != 0) _moneyRow('Comisión ${number(a['commissionPct']).toStringAsFixed(2)}%', number(a['total']) - number(a['subtotal']) - number(a['extras'])),
          const Divider(),
          _moneyRow('TOTAL CLIENTE', number(a['total']), bold: true),
        ]),
        const SizedBox(height: 14),
        FilledButton.icon(onPressed: sharePdf, icon: const Icon(Icons.picture_as_pdf), label: const Text('Compartir boletín PDF')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: shareText, icon: const Icon(Icons.share), label: const Text('Compartir como texto')),
      ]),
    );
  }

  Widget _moneyRow(String label, double value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null),
          Text(money(value), style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null),
        ]),
      );
}
