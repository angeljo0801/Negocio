part of 'main.dart';

class FlightWatchesPage extends StatefulWidget {
  const FlightWatchesPage({super.key});
  @override
  State<FlightWatchesPage> createState() => _FlightWatchesPageState();
}

class _FlightWatchesPageState extends State<FlightWatchesPage> {
  List<Map<String, dynamic>> rows = [];
  bool syncing = false;

  @override
  void initState() { super.initState(); load(); }

  String d(DateTime x) => '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';

  Future<void> load() async {
    rows = active(await Store.list('flightWatches'));
    final start = DateTime.now().add(const Duration(days: 14));
    final end = start.add(const Duration(days: 7));
    if (rows.isEmpty) {
      rows = [
        {'id': newId(), 'origin': 'FLL', 'destination': 'HAV', 'targetPrice': 180.0, 'lastPrice': 0.0, 'fromDate': d(start), 'toDate': d(end), 'deleted': false},
        {'id': newId(), 'origin': 'MIA', 'destination': 'HAV', 'targetPrice': 180.0, 'lastPrice': 0.0, 'fromDate': d(start), 'toDate': d(end), 'deleted': false},
      ];
      await Store.saveList('flightWatches', rows);
    } else {
      var dirty = false;
      for (final r in rows) {
        if ('${r['fromDate'] ?? ''}'.isEmpty) { r['fromDate'] = d(start); dirty = true; }
        if ('${r['toDate'] ?? ''}'.isEmpty) { r['toDate'] = d(end); dirty = true; }
      }
      if (dirty) await Store.saveList('flightWatches', rows);
    }
    if (mounted) setState(() {});
  }

  Future<void> edit([Map<String, dynamic>? e]) async {
    final start = DateTime.now().add(const Duration(days: 14));
    final end = start.add(const Duration(days: 7));
    final o = TextEditingController(text: '${e?['origin'] ?? 'FLL'}');
    final dest = TextEditingController(text: '${e?['destination'] ?? 'HAV'}');
    final target = TextEditingController(text: '${e?['targetPrice'] ?? 180}');
    final from = TextEditingController(text: '${e?['fromDate'] ?? d(start)}');
    final to = TextEditingController(text: '${e?['toDate'] ?? d(end)}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Vigilar ruta'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: TextField(controller: o, decoration: const InputDecoration(labelText: 'Origen'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: dest, decoration: const InputDecoration(labelText: 'Destino'))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: target, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Avisarme si baja de')),
          const SizedBox(height: 8),
          TextField(controller: from, decoration: const InputDecoration(labelText: 'Desde YYYY-MM-DD')),
          const SizedBox(height: 8),
          TextField(controller: to, decoration: const InputDecoration(labelText: 'Hasta YYYY-MM-DD (máx. 21 días)')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    if (DateTime.tryParse(from.text.trim()) == null || DateTime.tryParse(to.text.trim()) == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Revisa las fechas. Usa formato YYYY-MM-DD.')));
      return;
    }
    final all = await Store.list('flightWatches');
    final item = {
      'id': e?['id'] ?? newId(),
      'origin': o.text.trim().toUpperCase(),
      'destination': dest.text.trim().toUpperCase(),
      'targetPrice': number(target.text),
      'lastPrice': e?['lastPrice'] ?? 0.0,
      'fromDate': from.text.trim(),
      'toDate': to.text.trim(),
      'bestDate': e?['bestDate'],
      'bestAirline': e?['bestAirline'],
      'bestDeparture': e?['bestDeparture'],
      'deleted': false,
    };
    final i = all.indexWhere((x) => x['id'] == item['id']);
    if (i >= 0) all[i] = {...all[i], ...item}; else all.add(item);
    await Store.saveList('flightWatches', all);
    load();
  }

  Future<void> syncFlights() async {
    setState(() => syncing = true);
    final r = await FlightService.syncAll();
    await NotificationService.publishPendingFlightChanges();
    if (!mounted) return;
    setState(() => syncing = false);
    await load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'Rutas revisadas: ${r.checked} · Alertas: ${r.changed} · Errores: ${r.errors}')));
  }

  Future<void> searchFlight(Map<String, dynamic> e) async {
    final q = Uri.encodeComponent('${e['origin']} ${e['destination']} ${e['fromDate']} cheap flights');
    await launchUrl(Uri.parse('https://www.google.com/travel/flights?q=$q'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Vuelos y alertas'),
          actions: [
            IconButton(tooltip: 'Proveedor de vuelos', icon: const Icon(Icons.key), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FlightApiPage()))),
            IconButton(tooltip: 'Buscar precios ahora', icon: syncing ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh), onPressed: syncing ? null : syncFlights),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('Puedes vigilar FLL → HAV, MIA → HAV o cualquier otra ruta. Con credenciales de Amadeus, Paquetería consulta los precios del rango guardado y genera una alerta cuando encuentra un precio igual o menor a tu objetivo.'),
            ),
          ),
          for (final e in rows)
            Card(
              child: ListTile(
                leading: const Icon(Icons.flight_takeoff),
                title: Text('${e['origin']} → ${e['destination']}'),
                subtitle: Text(
                  '${e['fromDate']} a ${e['toDate']}\nObjetivo: ${money(number(e['targetPrice']))} · Mejor: ${number(e['lastPrice']) > 0 ? money(number(e['lastPrice'])) : '—'}'
                  '${'${e['bestDate'] ?? ''}'.isNotEmpty ? '\nFecha más barata: ${e['bestDate']} ${'${e['bestAirline'] ?? ''}'.isNotEmpty ? '· ${e['bestAirline']}' : ''}' : ''}',
                ),
                isThreeLine: true,
                trailing: Wrap(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.search), tooltip: 'Abrir Google Flights', onPressed: () => searchFlight(e)),
                  IconButton(icon: const Icon(Icons.edit), onPressed: () => edit(e)),
                  IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { if (await confirmDelete(context, 'esta alerta de vuelo')) { await softDelete('flightWatches', '${e['id']}'); load(); } }),
                ]),
              ),
            ),
        ]),
        floatingActionButton: FloatingActionButton(onPressed: () => edit(), child: const Icon(Icons.add)),
      );
}
