part of 'main.dart';

class PackagesPage extends StatefulWidget {
  const PackagesPage({super.key});
  @override
  State<PackagesPage> createState() => _PackagesPageState();
}

class _PackagesPageState extends State<PackagesPage> {
  List<Map<String, dynamic>> rows = [], clients = [];
  String q = '';
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    final r = await Future.wait([Store.list('packages'), Store.list('clients')]);
    if (!mounted) return;
    setState(() { rows = active(r[0]); clients = active(r[1]); });
  }

  @override
  Widget build(BuildContext context) {
    final f = rows.where((p) => ('${p['tracking']} ${clientName(clients, '${p['clientId']}')} ${p['status']} ${p['carrier']}').toLowerCase().contains(q.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paquetes'),
        actions: [
          IconButton(
            tooltip: 'Escanear código',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () async {
              final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScannerPage()));
              if (code != null && mounted) {
                final existing = rows.where((e) => '${e['tracking']}' == code).firstOrNull;
                if (existing != null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Este código ya pertenece a ${clientName(clients, '${existing['clientId']}')}.')));
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => PackageEditPage(existing: existing)));
                } else {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => PackageEditPage(initialTracking: code)));
                }
                load();
              }
            },
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            onChanged: (v) => setState(() => q = v),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Tracking o nombre del cliente'),
          ),
        ),
        Expanded(
          child: f.isEmpty
              ? const Center(child: Text('No hay paquetes.'))
              : ListView.builder(
                  itemCount: f.length,
                  itemBuilder: (_, i) {
                    final p = f[i];
                    final remote = '${p['courierStatusEs'] ?? ''}'.trim();
                    return ListTile(
                      leading: const Icon(Icons.inventory_2),
                      title: Text('${p['tracking']}'),
                      subtitle: Text('${clientName(clients, '${p['clientId']}')} · ${p['carrier']}\n${remote.isNotEmpty ? remote : p['status']} · ${number(p['billWeight']).toStringAsFixed(1)} lb'),
                      isThreeLine: true,
                      onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => PackageEditPage(existing: p))); load(); },
                      trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { if (await confirmDelete(context, 'este paquete')) { await softDelete('packages', '${p['id']}'); load(); } }),
                    );
                  },
                ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const PackageEditPage())); load(); },
        icon: const Icon(Icons.add),
        label: const Text('Paquete'),
      ),
    );
  }
}

String inferCarrier(String tracking) {
  final t = tracking.trim().toUpperCase();
  if (t.startsWith('1Z')) return 'UPS';
  if (t.startsWith('TBA')) return 'Amazon';
  if (RegExp(r'^(94|93|92|95)\d{18,22}$').hasMatch(t)) return 'USPS';
  if (RegExp(r'^\d{12,15}$').hasMatch(t)) return 'FedEx';
  if (RegExp(r'^\d{10}$').hasMatch(t)) return 'DHL';
  return 'Auto / Otro';
}

List<String> trackingCandidates(String text) {
  final out = <String>{};
  final lines = text.toUpperCase().split('\n');
  final patterns = <RegExp>[
    RegExp(r'\b1Z[A-Z0-9]{16}\b'),
    RegExp(r'\bTBA[A-Z0-9]{8,24}\b'),
    RegExp(r'\b(?:94|93|92|95)\d{18,22}\b'),
    RegExp(r'\b\d{12,22}\b'),
    RegExp(r'\b[A-Z]{2}\d{9}[A-Z]{2}\b'),
  ];
  for (final raw in lines) {
    final line = raw.replaceAll(RegExp(r'[^A-Z0-9\s-]'), ' ');
    final compact = line.replaceAll(RegExp(r'[\s-]+'), '');
    for (final source in [line, compact]) {
      for (final p in patterns) {
        for (final m in p.allMatches(source)) {
          final v = m.group(0)?.replaceAll(RegExp(r'[\s-]'), '') ?? '';
          if (v.length >= 10 && v.length <= 34) out.add(v);
        }
      }
    }
  }
  return out.toList();
}

Future<String?> readTrackingFromImage(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (_) => SafeArea(child: Wrap(children: [
      ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Fotografiar etiqueta'), onTap: () => Navigator.pop(context, ImageSource.camera)),
      ListTile(leading: const Icon(Icons.image), title: const Text('Elegir foto / screenshot'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
    ])),
  );
  if (source == null) return null;
  final x = await ImagePicker().pickImage(source: source, imageQuality: 90);
  if (x == null) return null;
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(x.path));
    final candidates = trackingCandidates(result.text);
    if (candidates.isEmpty) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No pude detectar un número de rastreo. Puedes escribirlo manualmente.')));
      return null;
    }
    if (candidates.length == 1) return candidates.first;
    if (!context.mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Selecciona el tracking'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(shrinkWrap: true, children: [for (final c in candidates) ListTile(title: Text(c), subtitle: Text(inferCarrier(c)), onTap: () => Navigator.pop(context, c))]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
      ),
    );
  } finally {
    recognizer.close();
  }
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool done = false;
  final manual = TextEditingController();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Escanear paquete')),
        body: Column(children: [
          Expanded(
            child: MobileScanner(onDetect: (capture) {
              if (done) return;
              for (final b in capture.barcodes) {
                final v = b.rawValue;
                if (v != null && v.trim().isNotEmpty) {
                  done = true;
                  Navigator.pop(context, v.trim());
                  break;
                }
              }
            }),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                Expanded(child: TextField(controller: manual, decoration: const InputDecoration(labelText: 'O escribir tracking manualmente'))),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: () { if (manual.text.trim().isNotEmpty) Navigator.pop(context, manual.text.trim()); }, icon: const Icon(Icons.check)),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final c = await readTrackingFromImage(context);
                    if (c != null && context.mounted) Navigator.pop(context, c);
                  },
                  icon: const Icon(Icons.document_scanner),
                  label: const Text('Leer tracking impreso con OCR'),
                ),
              ),
            ]),
          ),
        ]),
      );
}

class PackageEditPage extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final String? initialTracking;
  const PackageEditPage({super.key, this.existing, this.initialTracking});
  @override
  State<PackageEditPage> createState() => _PackageEditPageState();
}

class _PackageEditPageState extends State<PackageEditPage> {
  final tracking = TextEditingController(), weightUs = TextEditingController(), weightCu = TextEditingController(), billWeight = TextEditingController(), notes = TextEditingController();
  List<Map<String, dynamic>> clients = [], purchases = [], recipients = [];
  String? clientId, purchaseId, recipientId;
  String carrier = 'Auto / Otro', status = 'Tracking creado';
  bool loaded = false, syncing = false;

  @override
  void initState() { super.initState(); init(); }

  Future<void> init() async {
    final r = await Future.wait([Store.list('clients'), Store.list('purchases'), Store.list('recipients'), Store.settings()]);
    clients = active(r[0]); purchases = active(r[1]); recipients = active(r[2]);
    tracking.text = '${widget.existing?['tracking'] ?? widget.initialTracking ?? ''}';
    carrier = '${widget.existing?['carrier'] ?? inferCarrier(tracking.text)}';
    status = '${widget.existing?['status'] ?? 'Tracking creado'}';
    clientId = widget.existing?['clientId']?.toString();
    purchaseId = widget.existing?['purchaseId']?.toString();
    recipientId = widget.existing?['recipientId']?.toString();
    weightUs.text = '${widget.existing?['weightUs'] ?? ''}';
    weightCu.text = '${widget.existing?['weightCu'] ?? ''}';
    billWeight.text = '${widget.existing?['billWeight'] ?? ''}';
    notes.text = '${widget.existing?['notes'] ?? ''}';
    if (mounted) setState(() => loaded = true);
  }

  void autoBillWeight() {
    final a = number(weightUs.text), b = number(weightCu.text);
    if (a > 0 || b > 0) billWeight.text = (a > 0 ? a : b).toStringAsFixed(2);
  }

  Future<void> openTracking() async {
    final t = Uri.encodeComponent(tracking.text.trim());
    late final Uri u;
    switch (carrier) {
      case 'UPS': u = Uri.parse('https://www.ups.com/track?tracknum=$t'); break;
      case 'FedEx': u = Uri.parse('https://www.fedex.com/fedextrack/?trknbr=$t'); break;
      case 'USPS': u = Uri.parse('https://tools.usps.com/go/TrackConfirmAction?tLabels=$t'); break;
      case 'DHL': u = Uri.parse('https://www.dhl.com/global-en/home/tracking.html?tracking-id=$t'); break;
      case 'Amazon': u = Uri.parse('https://www.amazon.com/progress-tracker/package/ref=ppx_yo_dt_b_track_package'); break;
      default: u = Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent('${tracking.text} tracking')}');
    }
    await launchUrl(u, mode: LaunchMode.externalApplication);
  }

  Future<void> syncCourier() async {
    setState(() => syncing = true);
    final r = await EasyPostService.syncAll();
    if (!mounted) return;
    setState(() => syncing = false);
    final all = await Store.list('packages');
    final fresh = all.where((e) => '${e['id']}' == '${widget.existing?['id']}').firstOrNull;
    if (fresh != null && mounted) {
      status = '${fresh['status'] ?? status}';
      setState(() {});
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'Revisados: ${r.checked} · Cambios: ${r.changed} · Errores: ${r.errors}')));
  }

  Future<void> save() async {
    final code = tracking.text.trim();
    if (code.isEmpty || clientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tracking y cliente son obligatorios.')));
      return;
    }
    final rows = await Store.list('packages');
    final duplicate = rows.where((e) => e['deleted'] != true && '${e['tracking']}' == code && '${e['id']}' != '${widget.existing?['id'] ?? ''}').firstOrNull;
    if (duplicate != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ese tracking ya existe.')));
      return;
    }
    final item = {
      'id': widget.existing?['id'] ?? newId(),
      'tracking': code,
      'carrier': carrier,
      'clientId': clientId,
      'purchaseId': purchaseId,
      'recipientId': recipientId,
      'weightUs': number(weightUs.text),
      'weightCu': number(weightCu.text),
      'billWeight': number(billWeight.text),
      'status': status,
      'notes': notes.text.trim(),
      'receivedAt': status == 'Recibido' ? (widget.existing?['receivedAt'] ?? DateTime.now().toIso8601String()) : widget.existing?['receivedAt'],
      'deleted': false,
    };
    final i = rows.indexWhere((e) => e['id'] == item['id']);
    if (i >= 0) rows[i] = {...rows[i], ...item}; else rows.add(item);
    await Store.saveList('packages', rows);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final cp = purchases.where((e) => clientId != null && purchaseHasClient(e, clientId!)).toList();
    final cr = recipients.where((e) => '${e['clientId']}' == clientId).toList();
    final remote = '${widget.existing?['courierStatusEs'] ?? ''}'.trim();
    final eta = '${widget.existing?['estimatedDelivery'] ?? ''}'.trim();
    final details = widget.existing?['courierDetails'] is List ? (widget.existing!['courierDetails'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Nuevo paquete' : 'Editar paquete'), actions: [if (tracking.text.trim().isNotEmpty) IconButton(tooltip: 'Rastrear en courier', onPressed: openTracking, icon: const Icon(Icons.local_shipping))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: tracking,
          onChanged: (v) { if (widget.existing == null) setState(() => carrier = inferCarrier(v)); },
          decoration: InputDecoration(
            labelText: 'Tracking / QR / código *',
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.document_scanner), tooltip: 'Leer texto de etiqueta', onPressed: () async {
                final c = await readTrackingFromImage(context);
                if (c != null) setState(() { tracking.text = c; carrier = inferCarrier(c); });
              }),
              IconButton(icon: const Icon(Icons.qr_code_scanner), tooltip: 'Escanear código', onPressed: () async {
                final c = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScannerPage()));
                if (c != null) setState(() { tracking.text = c; carrier = inferCarrier(c); });
              }),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        _drop('Courier', carrier, ['Auto / Otro', 'UPS', 'FedEx', 'USPS', 'DHL', 'Amazon'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(), (v) => setState(() => carrier = v ?? carrier)),
        const SizedBox(height: 12),
        _drop('Cliente *', clientId, clients.map((c) => DropdownMenuItem(value: '${c['id']}', child: Text('${c['name']}'))).toList(), (v) => setState(() { clientId = v; purchaseId = null; recipientId = null; })),
        const SizedBox(height: 12),
        _drop('Compra / pedido relacionado', purchaseId, cp.map((p) => DropdownMenuItem(value: '${p['id']}', child: Text('${p['store']} · ${p['description']}'))).toList(), (v) => setState(() => purchaseId = v)),
        const SizedBox(height: 12),
        _drop('Destinatario en Cuba', recipientId, cr.map((r) => DropdownMenuItem(value: '${r['id']}', child: Text('${r['name']} · ${r['province']}'))).toList(), (v) => setState(() => recipientId = v)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: weightUs, onChanged: (_) => autoBillWeight(), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Peso EE. UU. (lb)'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: weightCu, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Peso Cuba (lb)'))),
        ]),
        const SizedBox(height: 12),
        TextField(controller: billWeight, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Peso facturado (lb)')),
        const SizedBox(height: 12),
        _drop('Estado', status, ['Tracking creado', 'En tránsito', 'Sale para entrega', 'Recibido', 'Verificado', 'Listo para Cuba', 'Asignado a viaje', 'En tránsito a Cuba', 'Llegó a Cuba', 'Entregado', 'Problema'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(), (v) => setState(() => status = v ?? status)),
        const SizedBox(height: 12),
        TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notas')),
        if (widget.existing != null && (remote.isNotEmpty || details.isNotEmpty)) ...[
          const SizedBox(height: 16),
          _sectionCard(context, 'Estado del courier', Icons.local_shipping, [
            if (remote.isNotEmpty) Text(remote, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (eta.isNotEmpty && eta != 'null') Text('Entrega estimada: $eta'),
            for (final d in details.take(5)) Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('• ${d['message'] ?? d['status']} ${'${d['location'] ?? ''}'.isNotEmpty ? '· ${d['location']}' : ''}'),
            ),
          ]),
        ],
        const SizedBox(height: 14),
        if (tracking.text.trim().isNotEmpty) OutlinedButton.icon(onPressed: openTracking, icon: const Icon(Icons.open_in_new), label: const Text('Abrir tracking oficial')),
        if (widget.existing != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: syncing ? null : syncCourier, icon: syncing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync), label: const Text('Sincronizar con EasyPost')),
        ],
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: save, icon: const Icon(Icons.save), label: const Text('Guardar paquete')),
        const SizedBox(height: 60),
      ]),
    );
  }
}
