part of 'main.dart';

class AgencyShipmentsPage extends StatefulWidget {
  const AgencyShipmentsPage({super.key});
  @override
  State<AgencyShipmentsPage> createState() => _AgencyShipmentsPageState();
}

class _AgencyShipmentsPageState extends State<AgencyShipmentsPage> {
  List<Map<String, dynamic>> rows = [], packages = [], clients = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = await Future.wait([
      Store.list('agencyShipments'),
      Store.list('packages'),
      Store.list('clients'),
    ]);
    if (!mounted) return;
    setState(() {
      rows = active(r[0]);
      packages = active(r[1]);
      clients = active(r[2]);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Envíos por agencia')),
        body: rows.isEmpty
            ? const Center(child: Text('Aún no hay envíos por agencia.'))
            : ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final a = rows[i];
                  final ids = dynList(a['packageIds']).map((e) => '$e').toSet();
                  final selected = packages.where((p) => ids.contains('${p['id']}')).toList();
                  final w = selected.fold<double>(0, (sum, p) => sum + number(p['billWeight']));
                  final revenue = w * number(a['sellRatePerLb']);
                  final agencyCost = w * number(a['agencyCostPerLb']);
                  final other = agencyOtherExpenses(a);
                  final profit = revenue - agencyCost - number(a['fuelCost']) - other;
                  return ListTile(
                    leading: const Icon(Icons.local_shipping),
                    title: Text('${a['agencyName']} · ${a['date']}'),
                    subtitle: Text('${w.toStringAsFixed(1)} lb · ${a['status']}\nGanancia estimada: ${money(profit)}'),
                    isThreeLine: true,
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => AgencyShipmentEditPage(existing: a)));
                      load();
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await confirmDelete(context, 'este envío por agencia')) {
                          await softDelete('agencyShipments', '${a['id']}');
                          load();
                        }
                      },
                    ),
                  );
                },
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const AgencyShipmentEditPage()));
            load();
          },
          icon: const Icon(Icons.add),
          label: const Text('Envío por agencia'),
        ),
      );
}

double agencyOtherExpenses(Map<String, dynamic> a) => dynList(a['otherExpenses']).fold<double>(
      0,
      (sum, e) => sum + number((e as Map)['amount']),
    );

class AgencyShipmentEditPage extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const AgencyShipmentEditPage({super.key, this.existing});

  @override
  State<AgencyShipmentEditPage> createState() => _AgencyShipmentEditPageState();
}

class _AgencyShipmentEditPageState extends State<AgencyShipmentEditPage> {
  final agencyName = TextEditingController();
  final date = TextEditingController();
  final agencyCost = TextEditingController();
  final sellRate = TextEditingController();
  final minLbAddress = TextEditingController();
  final fuel = TextEditingController();
  final notes = TextEditingController();

  List<Map<String, dynamic>> packages = [], clients = [], recipients = [];
  Set<String> selected = {};
  List<Map<String, dynamic>> other = [];
  String status = 'Preparando';
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    final r = await Future.wait([
      Store.list('packages'),
      Store.list('clients'),
      Store.list('recipients'),
      Store.settings(),
    ]);
    packages = active(r[0] as List<Map<String, dynamic>>);
    clients = active(r[1] as List<Map<String, dynamic>>);
    recipients = active(r[2] as List<Map<String, dynamic>>);
    final s = r[3] as Map<String, dynamic>;

    agencyName.text = '${widget.existing?['agencyName'] ?? s['defaultAgencyName'] ?? 'Javier'}';
    date.text = '${widget.existing?['date'] ?? today()}';
    agencyCost.text = '${widget.existing?['agencyCostPerLb'] ?? s['defaultAgencyCostPerLb'] ?? 3.75}';
    sellRate.text = '${widget.existing?['sellRatePerLb'] ?? s['ratePerLb'] ?? 5.0}';
    minLbAddress.text = '${widget.existing?['minimumLbPerAddress'] ?? s['defaultAgencyMinLbPerAddress'] ?? 10.0}';
    fuel.text = '${widget.existing?['fuelCost'] ?? s['defaultAgencyFuelCost'] ?? 20.0}';
    notes.text = '${widget.existing?['notes'] ?? ''}';
    status = '${widget.existing?['status'] ?? 'Preparando'}';
    selected = dynList(widget.existing?['packageIds']).map((e) => '$e').toSet();
    other = dynList(widget.existing?['otherExpenses']).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (mounted) setState(() => loaded = true);
  }

  Future<void> addOther() async {
    final name = TextEditingController();
    final amount = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Otro gasto de agencia'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Concepto')),
            const SizedBox(height: 8),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto'),
            ),
            const SizedBox(height: 8),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Notas')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Añadir')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty && number(amount.text) > 0) {
      setState(() => other.add({
            'id': newId(),
            'name': name.text.trim(),
            'amount': number(amount.text),
            'notes': note.text.trim(),
          }));
    }
  }

  Future<void> save() async {
    if (agencyName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escribe el nombre de la agencia.')));
      return;
    }
    final rows = await Store.list('agencyShipments');
    final item = <String, dynamic>{
      'id': widget.existing?['id'] ?? newId(),
      'agencyName': agencyName.text.trim(),
      'date': date.text.trim(),
      'agencyCostPerLb': number(agencyCost.text),
      'sellRatePerLb': number(sellRate.text),
      'minimumLbPerAddress': number(minLbAddress.text),
      'fuelCost': number(fuel.text),
      'otherExpenses': other,
      'packageIds': selected.toList(),
      'status': status,
      'notes': notes.text.trim(),
      'deleted': false,
    };
    final i = rows.indexWhere((e) => e['id'] == item['id']);
    if (i >= 0) {
      rows[i] = {...rows[i], ...item};
    } else {
      rows.add(item);
    }
    await Store.saveList('agencyShipments', rows);

    final allPackages = await Store.list('packages');
    var changed = false;
    for (var i = 0; i < allPackages.length; i++) {
      if (selected.contains('${allPackages[i]['id']}')) {
        if (['Recibido', 'Verificado', 'Listo para Cuba', 'Asignado a agencia'].contains(allPackages[i]['status'])) {
          allPackages[i]['status'] = status == 'Preparando' ? 'Asignado a agencia' : 'Enviado por agencia';
          allPackages[i]['agencyShipmentId'] = item['id'];
          changed = true;
        }
      }
    }
    if (changed) await Store.saveList('packages', allPackages);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final selectedPackages = packages.where((p) => selected.contains('${p['id']}')).toList();
    final weight = selectedPackages.fold<double>(0, (sum, p) => sum + number(p['billWeight']));
    final revenue = weight * number(sellRate.text);
    final agencyTotal = weight * number(agencyCost.text);
    final extra = other.fold<double>(0, (sum, e) => sum + number(e['amount']));
    final gross = revenue - agencyTotal;
    final profit = gross - number(fuel.text) - extra;
    final minLb = number(minLbAddress.text);
    final maxAddresses = minLb > 0 ? (weight / minLb).floor() : 0;
    final actualRecipients = selectedPackages
        .map((p) => '${p['recipientId'] ?? ''}')
        .where((id) => id.isNotEmpty && id != 'null')
        .toSet()
        .length;
    final addressWarning = actualRecipients > 0 && maxAddresses > 0 && actualRecipients > maxAddresses;

    final selectable = packages.where((p) => [
          'Recibido',
          'Verificado',
          'Listo para Cuba',
          'Asignado a agencia',
        ].contains(p['status']) || selected.contains('${p['id']}')).toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Nuevo envío por agencia' : 'Editar envío por agencia')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: agencyName, decoration: const InputDecoration(labelText: 'Agencia / persona')),
        const SizedBox(height: 12),
        TextField(controller: date, decoration: const InputDecoration(labelText: 'Fecha YYYY-MM-DD')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: agencyCost,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Costo agencia por lb'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: sellRate,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Tarifa cobrada por lb'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: minLbAddress,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Mínimo lb por dirección'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: fuel,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Gasolina / transporte'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        _drop(
          'Estado',
          status,
          ['Preparando', 'Enviado a agencia', 'En tránsito a Cuba', 'Completado']
              .map((x) => DropdownMenuItem(value: x, child: Text(x)))
              .toList(),
          (v) => setState(() => status = v ?? status),
        ),
        const SizedBox(height: 16),
        Text('Otros gastos', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        for (final e in other)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${e['name']}'),
            subtitle: Text('${money(number(e['amount']))}${'${e['notes'] ?? ''}'.trim().isNotEmpty ? ' · ${e['notes']}' : ''}'),
            trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => other.remove(e))),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: addOther, icon: const Icon(Icons.add), label: const Text('Añadir otro gasto')),
        ),
        const Divider(height: 28),
        Text('Asignar paquetes', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        if (selectable.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No hay paquetes listos para asignar.')),
        for (final p in selectable)
          CheckboxListTile(
            value: selected.contains('${p['id']}'),
            onChanged: (v) => setState(() {
              if (v == true) {
                selected.add('${p['id']}');
              } else {
                selected.remove('${p['id']}');
              }
            }),
            title: Text('${p['tracking']}'),
            subtitle: Text('${clientName(clients, '${p['clientId']}')} · ${number(p['billWeight']).toStringAsFixed(1)} lb'),
          ),
        const Divider(height: 28),
        _sectionCard(context, 'Rentabilidad por agencia', Icons.calculate, [
          Text('Peso asignado: ${weight.toStringAsFixed(1)} lb'),
          Text('Ingresos cobrados: ${money(revenue)}'),
          Text('Costo de agencia: ${money(agencyTotal)}'),
          Text('Utilidad bruta: ${money(gross)}'),
          Text('Gasolina / transporte: ${money(number(fuel.text))}'),
          Text('Otros gastos: ${money(extra)}'),
          const Divider(),
          Text('Ganancia operativa: ${money(profit)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (minLb > 0) Text('Direcciones posibles al mínimo de ${minLb.toStringAsFixed(minLb % 1 == 0 ? 0 : 1)} lb: $maxAddresses'),
          if (actualRecipients > 0) Text('Destinatarios distintos asignados: $actualRecipients'),
          if (addressWarning)
            const Text('Atención: hay más destinatarios que los permitidos por el mínimo de libras por dirección.', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 12),
        TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notas')),
        const SizedBox(height: 14),
        FilledButton.icon(onPressed: save, icon: const Icon(Icons.save), label: const Text('Guardar envío por agencia')),
        const SizedBox(height: 60),
      ]),
    );
  }
}
