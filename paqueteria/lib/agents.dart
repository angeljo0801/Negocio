part of 'main.dart';

const double _agentOwnerRatePerLb = 5.0;

Map<String, dynamic> _reportData(Map<String, dynamic>? report) {
  if (report == null || report['data'] is! Map) return <String, dynamic>{};
  return Map<String, dynamic>.from(report['data'] as Map);
}

List<Map<String, dynamic>> _reportList(Map<String, dynamic> data, String key) {
  final v = data[key];
  if (v is! List) return <Map<String, dynamic>>[];
  return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).where((e) => e['deleted'] != true).toList();
}

Map<String, dynamic>? latestAgentReport(String agentId, List<Map<String, dynamic>> reports) {
  final matches = reports.where((e) => e['deleted'] != true && '${e['agentId']}' == agentId).toList();
  if (matches.isEmpty) return null;
  matches.sort((a, b) => '${b['reportedAt'] ?? b['importedAt'] ?? ''}'.compareTo('${a['reportedAt'] ?? a['importedAt'] ?? ''}'));
  return matches.first;
}

double agentShippingDue(Map<String, dynamic>? report) {
  final data = _reportData(report);
  return _reportList(data, 'packages').fold<double>(0, (sum, p) {
    final rate = number(p['ownerRate']) > 0 ? number(p['ownerRate']) : _agentOwnerRatePerLb;
    return sum + number(p['weightLb']) * rate;
  });
}

double agentOrdersDue(Map<String, dynamic>? report) =>
    _reportList(_reportData(report), 'orders').fold<double>(0, (sum, e) => sum + number(e['ownerDue']));

double agentRemittancesDue(Map<String, dynamic>? report) =>
    _reportList(_reportData(report), 'remittances').fold<double>(0, (sum, e) => sum + number(e['ownerDue']));

double agentSettled(Map<String, dynamic>? report) =>
    _reportList(_reportData(report), 'settlements').fold<double>(0, (sum, e) => sum + number(e['amount']));

double agentBalanceFromReport(Map<String, dynamic>? report) =>
    agentShippingDue(report) + agentOrdersDue(report) + agentRemittancesDue(report) - agentSettled(report);

double agentPackageWeight(Map<String, dynamic>? report) =>
    _reportList(_reportData(report), 'packages').fold<double>(0, (sum, e) => sum + number(e['weightLb']));

String _agentClientName(Map<String, dynamic> data, dynamic id) {
  final clients = _reportList(data, 'clients');
  final found = clients.where((e) => '${e['id']}' == '${id ?? ''}').firstOrNull;
  return found == null ? 'Sin cliente' : '${found['name']}';
}

class AgentsPage extends StatefulWidget {
  const AgentsPage({super.key});
  @override
  State<AgentsPage> createState() => _AgentsPageState();
}

class _AgentsPageState extends State<AgentsPage> {
  List<Map<String, dynamic>> agents = [], reports = [];
  bool importing = false;
  String q = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = await Future.wait([Store.list('agents'), Store.list('agentReports')]);
    if (!mounted) return;
    setState(() {
      agents = active(r[0]);
      reports = active(r[1]);
    });
  }

  Future<void> editAgent([Map<String, dynamic>? agent]) async {
    final name = TextEditingController(text: '${agent?['name'] ?? ''}');
    final phone = TextEditingController(text: '${agent?['phone'] ?? ''}');
    final notes = TextEditingController(text: '${agent?['notes'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(agent == null ? 'Nuevo agente' : 'Editar agente'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre *')),
            const SizedBox(height: 10),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'Teléfono / WhatsApp')),
            const SizedBox(height: 10),
            TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notas')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final all = await Store.list('agents');
    final item = {
      'id': agent?['id'] ?? newId(),
      'name': name.text.trim(),
      'phone': phone.text.trim(),
      'notes': notes.text.trim(),
      'createdAt': agent?['createdAt'] ?? DateTime.now().toIso8601String(),
      'deleted': false,
    };
    final i = all.indexWhere((e) => e['id'] == item['id']);
    if (i >= 0) {
      all[i] = {...all[i], ...item};
    } else {
      all.add(item);
    }
    await Store.saveList('agents', all);
    await load();
  }

  Future<Map<String, dynamic>?> _readReportFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;
    final file = picked.files.single;
    try {
      late final String raw;
      if (file.bytes != null) {
        raw = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        raw = await File(file.path!).readAsString();
      } else {
        throw const FormatException('No se pudo leer el archivo.');
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('El archivo no contiene un informe válido.');
      final data = Map<String, dynamic>.from(decoded);
      final schema = '${data['schema'] ?? ''}';
      final hasExpectedData = data['settings'] is Map && data['packages'] is List && data['remittances'] is List;
      if (!schema.startsWith('alas-cargo-agent') && !hasExpectedData) {
        throw const FormatException('Este JSON no parece ser un informe de Alas Cargo Agentes.');
      }
      return {'data': data, 'fileName': file.name};
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No pude importar el informe: $e')));
      }
      return null;
    }
  }

  Future<String?> _selectExistingAgent() async {
    if (agents.isEmpty) return null;
    String? selected = agents.first['id']?.toString();
    return showDialog<String>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: const Text('Selecciona el agente'),
          content: DropdownButtonFormField<String>(
            initialValue: selected,
            decoration: const InputDecoration(labelText: 'Agente'),
            items: agents.map((a) => DropdownMenuItem(value: '${a['id']}', child: Text('${a['name']}'))).toList(),
            onChanged: (v) => setD(() => selected = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, selected), child: const Text('Usar agente')),
          ],
        ),
      ),
    );
  }

  Future<void> importReport({String? forcedAgentId}) async {
    if (importing) return;
    setState(() => importing = true);
    try {
      final picked = await _readReportFile();
      if (picked == null) return;
      final data = Map<String, dynamic>.from(picked['data'] as Map);
      final settings = data['settings'] is Map ? Map<String, dynamic>.from(data['settings'] as Map) : <String, dynamic>{};
      final reportName = '${settings['agentName'] ?? ''}'.trim();
      final reportPhone = '${settings['phone'] ?? ''}'.trim();

      String? agentId = forcedAgentId;
      Map<String, dynamic>? chosen;

      if (agentId != null) {
        chosen = agents.where((a) => '${a['id']}' == agentId).firstOrNull;
        if (chosen != null && reportName.isNotEmpty && '${chosen['name']}'.trim().toLowerCase() != reportName.toLowerCase()) {
          final proceed = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('El nombre no coincide'),
              content: Text('Este informe dice que pertenece a “$reportName”, pero estás dentro de “${chosen!['name']}”. ¿Quieres importarlo aquí de todas formas?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Importar aquí')),
              ],
            ),
          );
          if (proceed != true) return;
        }
      } else {
        if (reportName.isNotEmpty) {
          chosen = agents.where((a) => '${a['name']}'.trim().toLowerCase() == reportName.toLowerCase()).firstOrNull;
        }
        if (chosen == null && reportPhone.isNotEmpty) {
          chosen = agents.where((a) => '${a['phone']}'.trim() == reportPhone).firstOrNull;
        }
        agentId = chosen?['id']?.toString();

        if (agentId == null && reportName.isNotEmpty) {
          final create = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Agente nuevo detectado'),
              content: Text('El informe pertenece a “$reportName”. ¿Quieres crear este agente automáticamente?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Elegir existente')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Crear agente')),
              ],
            ),
          );
          if (create == true) {
            final allAgents = await Store.list('agents');
            final a = {
              'id': newId(),
              'name': reportName,
              'phone': reportPhone,
              'notes': 'Creado automáticamente al importar un informe.',
              'createdAt': DateTime.now().toIso8601String(),
              'deleted': false,
            };
            allAgents.add(a);
            await Store.saveList('agents', allAgents);
            agentId = '${a['id']}';
          } else {
            agentId = await _selectExistingAgent();
          }
        } else if (agentId == null) {
          agentId = await _selectExistingAgent();
        }
      }

      if (agentId == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se seleccionó ningún agente.')));
        return;
      }

      final allReports = await Store.list('agentReports');
      final reportedAt = '${data['generatedAt'] ?? DateTime.now().toIso8601String()}';
      final duplicate = allReports.any((r) =>
          r['deleted'] != true &&
          '${r['agentId']}' == agentId &&
          '${r['reportedAt']}' == reportedAt);
      if (duplicate) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ese informe ya fue importado.')));
        return;
      }

      allReports.add({
        'id': newId(),
        'agentId': agentId,
        'reportedAt': reportedAt,
        'importedAt': DateTime.now().toIso8601String(),
        'sourceFile': picked['fileName'],
        'schema': data['schema'] ?? 'alas-cargo-agent',
        'data': data,
        'deleted': false,
      });
      await Store.saveList('agentReports', allReports);
      await load();

      if (mounted) {
        final agent = agents.where((a) => '${a['id']}' == agentId).firstOrNull;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Informe importado para ${agent?['name'] ?? reportName}.')));
      }
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = agents.where((a) => '${a['name']} ${a['phone'] ?? ''}'.toLowerCase().contains(q.toLowerCase())).toList();
    final totalDue = agents.fold<double>(0, (sum, a) => sum + agentBalanceFromReport(latestAgentReport('${a['id']}', reports)));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agentes'),
        actions: [
          IconButton(
            tooltip: 'Importar informe JSON',
            onPressed: importing ? null : importReport,
            icon: importing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${agents.length} agente(s)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  Text('Saldo total reportado: ${money(totalDue)}'),
                ])),
                FilledButton.icon(
                  onPressed: importing ? null : importReport,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Importar'),
                ),
              ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: TextField(
            onChanged: (v) => setState(() => q = v),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar agente'),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('Aún no hay agentes. Crea uno o importa un informe.'))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final a = filtered[i];
                    final latest = latestAgentReport('${a['id']}', reports);
                    final due = agentBalanceFromReport(latest);
                    final data = _reportData(latest);
                    final packageCount = _reportList(data, 'packages').length;
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.badge_outlined)),
                      title: Text('${a['name']}'),
                      subtitle: Text(
                        latest == null
                            ? 'Sin informes importados'
                            : '$packageCount paquete(s) · ${agentPackageWeight(latest).toStringAsFixed(1)} lb\nSaldo contigo: ${money(due)}',
                      ),
                      isThreeLine: latest != null,
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'edit') {
                            await editAgent(a);
                          } else if (v == 'import') {
                            await importReport(forcedAgentId: '${a['id']}');
                          } else if (v == 'delete') {
                            if (await confirmDelete(context, 'este agente')) {
                              await softDelete('agents', '${a['id']}');
                              await load();
                            }
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'import', child: Text('Importar informe')),
                          PopupMenuItem(value: 'edit', child: Text('Editar agente')),
                          PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                        ],
                      ),
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => AgentDetailPage(agentId: '${a['id']}')));
                        await load();
                      },
                    );
                  },
                ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editAgent(),
        icon: const Icon(Icons.person_add),
        label: const Text('Agente'),
      ),
    );
  }
}

class AgentDetailPage extends StatefulWidget {
  final String agentId;
  const AgentDetailPage({super.key, required this.agentId});
  @override
  State<AgentDetailPage> createState() => _AgentDetailPageState();
}

class _AgentDetailPageState extends State<AgentDetailPage> {
  Map<String, dynamic>? agent;
  List<Map<String, dynamic>> reports = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = await Future.wait([Store.list('agents'), Store.list('agentReports')]);
    final agents = active(r[0]);
    final allReports = active(r[1]);
    final found = agents.where((e) => '${e['id']}' == widget.agentId).firstOrNull;
    final own = allReports.where((e) => '${e['agentId']}' == widget.agentId).toList()
      ..sort((a, b) => '${b['reportedAt'] ?? b['importedAt'] ?? ''}'.compareTo('${a['reportedAt'] ?? a['importedAt'] ?? ''}'));
    if (!mounted) return;
    setState(() {
      agent = found;
      reports = own;
      loading = false;
    });
  }

  Future<void> importHere() async {
    final pageState = context.findAncestorStateOfType<_AgentsPageState>();
    if (pageState != null) {
      await pageState.importReport(forcedAgentId: widget.agentId);
      await load();
      return;
    }
    // Normally this page is opened from AgentsPage. This fallback keeps the action clear.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Regresa a Agentes y usa “Importar informe” en el menú del agente.')));
    }
  }

  Future<void> deleteReport(Map<String, dynamic> report) async {
    if (!await confirmDelete(context, 'este informe')) return;
    await softDelete('agentReports', '${report['id']}');
    await load();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (agent == null) return const Scaffold(body: Center(child: Text('Agente no encontrado.')));
    final latest = reports.firstOrNull;
    final data = _reportData(latest);
    final packages = _reportList(data, 'packages');
    final orders = _reportList(data, 'orders');
    final remittances = _reportList(data, 'remittances');
    final settlements = _reportList(data, 'settlements');
    final clients = _reportList(data, 'clients');

    return Scaffold(
      appBar: AppBar(title: Text('${agent!['name']}')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        _sectionCard(context, 'Agente', Icons.badge, [
          Text('${agent!['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          if ('${agent!['phone'] ?? ''}'.trim().isNotEmpty) Text('Teléfono: ${agent!['phone']}'),
          if ('${agent!['notes'] ?? ''}'.trim().isNotEmpty) Text('${agent!['notes']}'),
        ]),
        const SizedBox(height: 10),
        if (latest == null)
          _sectionCard(context, 'Informes', Icons.description_outlined, [
            const Text('Este agente todavía no tiene informes importados.'),
            const SizedBox(height: 10),
            const Text('Desde la pantalla Agentes, abre el menú de este agente y selecciona “Importar informe”.'),
          ])
        else ...[
          _sectionCard(context, 'Último informe', Icons.analytics_outlined, [
            Text('Reportado: ${latest['reportedAt']}'),
            Text('Importado: ${latest['importedAt']}'),
            Text('Archivo: ${latest['sourceFile']}'),
            const Divider(),
            Text('Clientes del agente: ${clients.length}'),
            Text('Paquetes: ${packages.length} · ${agentPackageWeight(latest).toStringAsFixed(1)} lb'),
            Text('Pedidos: ${orders.length}'),
            Text('Remesas: ${remittances.length}'),
            const Divider(),
            Text('Por libras: ${money(agentShippingDue(latest))}'),
            Text('Por pedidos: ${money(agentOrdersDue(latest))}'),
            Text('Por remesas: ${money(agentRemittancesDue(latest))}'),
            Text('Liquidado: ${money(agentSettled(latest))}'),
            Text('Saldo contigo: ${money(agentBalanceFromReport(latest))}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 10),
          ExpansionTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text('Paquetes (${packages.length})'),
            children: [
              for (final p in packages)
                ListTile(
                  title: Text('${p['tracking'] ?? 'Sin tracking'}'),
                  subtitle: Text('${_agentClientName(data, p['clientId'])} · ${number(p['weightLb']).toStringAsFixed(1)} lb · ${p['status'] ?? ''}'),
                  trailing: Text(money(number(p['weightLb']) * (number(p['ownerRate']) > 0 ? number(p['ownerRate']) : _agentOwnerRatePerLb))),
                ),
            ],
          ),
          ExpansionTile(
            leading: const Icon(Icons.shopping_bag_outlined),
            title: Text('Pedidos (${orders.length})'),
            children: [
              for (final e in orders)
                ListTile(
                  title: Text('${_agentClientName(data, e['clientId'])} · ${e['store'] ?? ''}'),
                  subtitle: Text('${e['description'] ?? ''}\n${e['status'] ?? ''}'),
                  isThreeLine: true,
                  trailing: Text('Debe: ${money(number(e['ownerDue']))}'),
                ),
            ],
          ),
          ExpansionTile(
            leading: const Icon(Icons.send_outlined),
            title: Text('Remesas (${remittances.length})'),
            children: [
              for (final e in remittances)
                ListTile(
                  title: Text('${_agentClientName(data, e['clientId'])} → ${e['beneficiary'] ?? ''}'),
                  subtitle: Text('${e['status'] ?? ''}'),
                  trailing: Text('Debe: ${money(number(e['ownerDue']))}'),
                ),
            ],
          ),
          ExpansionTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text('Liquidaciones (${settlements.length})'),
            children: [
              for (final e in settlements)
                ListTile(
                  title: Text(money(number(e['amount']))),
                  subtitle: Text('${e['date'] ?? ''} · ${e['method'] ?? ''}\n${e['notes'] ?? ''}'),
                  isThreeLine: true,
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Text('Historial de informes', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        if (reports.isEmpty)
          const Padding(padding: EdgeInsets.all(12), child: Text('Sin informes.'))
        else
          for (final r in reports)
            ListTile(
              leading: const Icon(Icons.description),
              title: Text('${r['reportedAt']}'),
              subtitle: Text('${r['sourceFile']} · Saldo: ${money(agentBalanceFromReport(r))}'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AgentReportPage(agent: agent!, report: r))),
              trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => deleteReport(r)),
            ),
        const SizedBox(height: 80),
      ]),
    );
  }
}

class AgentReportPage extends StatelessWidget {
  final Map<String, dynamic> agent;
  final Map<String, dynamic> report;
  const AgentReportPage({super.key, required this.agent, required this.report});

  @override
  Widget build(BuildContext context) {
    final data = _reportData(report);
    final packages = _reportList(data, 'packages');
    final orders = _reportList(data, 'orders');
    final remittances = _reportList(data, 'remittances');
    final settlements = _reportList(data, 'settlements');
    final clients = _reportList(data, 'clients');
    return Scaffold(
      appBar: AppBar(title: Text('Informe · ${agent['name']}')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        _sectionCard(context, 'Resumen', Icons.summarize, [
          Text('Reportado: ${report['reportedAt']}'),
          Text('Archivo: ${report['sourceFile']}'),
          const Divider(),
          Text('Clientes: ${clients.length}'),
          Text('Paquetes: ${packages.length} · ${agentPackageWeight(report).toStringAsFixed(1)} lb'),
          Text('Pedidos: ${orders.length}'),
          Text('Remesas: ${remittances.length}'),
          Text('Liquidaciones: ${settlements.length}'),
          const Divider(),
          Text('Libras para Alas Cargo: ${money(agentShippingDue(report))}'),
          Text('Pedidos para Alas Cargo: ${money(agentOrdersDue(report))}'),
          Text('Remesas para Alas Cargo: ${money(agentRemittancesDue(report))}'),
          Text('Pagado a Alas Cargo: ${money(agentSettled(report))}'),
          Text('Saldo: ${money(agentBalanceFromReport(report))}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        for (final p in packages)
          ListTile(
            leading: const Icon(Icons.inventory_2),
            title: Text('${p['tracking'] ?? 'Sin tracking'}'),
            subtitle: Text('${_agentClientName(data, p['clientId'])} · ${number(p['weightLb']).toStringAsFixed(1)} lb · ${p['status'] ?? ''}'),
          ),
        if (orders.isNotEmpty) ...[
          const Divider(),
          Text('Pedidos', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          for (final e in orders)
            ListTile(
              title: Text('${_agentClientName(data, e['clientId'])} · ${e['store'] ?? ''}'),
              subtitle: Text('${e['description'] ?? ''}'),
              trailing: Text(money(number(e['ownerDue']))),
            ),
        ],
        if (remittances.isNotEmpty) ...[
          const Divider(),
          Text('Remesas', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          for (final e in remittances)
            ListTile(
              title: Text('${_agentClientName(data, e['clientId'])} → ${e['beneficiary'] ?? ''}'),
              subtitle: Text('${e['status'] ?? ''}'),
              trailing: Text(money(number(e['ownerDue']))),
            ),
        ],
      ]),
    );
  }
}
