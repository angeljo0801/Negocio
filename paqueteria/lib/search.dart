part of 'main.dart';

class BusinessSearchPage extends StatefulWidget {
  const BusinessSearchPage({super.key});
  @override
  State<BusinessSearchPage> createState() => _BusinessSearchPageState();
}

class _BusinessSearchPageState extends State<BusinessSearchPage> {
  final q = TextEditingController();
  List<Map<String, dynamic>> clients = [], packages = [], purchases = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = await Future.wait([Store.list('clients'), Store.list('packages'), Store.list('purchases')]);
    if (!mounted) return;
    setState(() {
      clients = active(r[0]);
      packages = active(r[1]);
      purchases = active(r[2]);
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final needle = q.text.trim().toLowerCase();
    final matchingClients = needle.isEmpty
        ? <Map<String, dynamic>>[]
        : clients.where((c) => '${c['name']} ${c['phone'] ?? ''}'.toLowerCase().contains(needle)).toList();
    final matchingPackages = needle.isEmpty
        ? <Map<String, dynamic>>[]
        : packages.where((p) {
            final name = clientName(clients, '${p['clientId'] ?? ''}');
            return '${p['tracking'] ?? ''} $name ${p['carrier'] ?? ''} ${p['status'] ?? ''}'.toLowerCase().contains(needle);
          }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Buscar')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: q,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Número de rastreo o nombre del cliente',
                    suffixIcon: q.text.isEmpty
                        ? null
                        : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(q.clear)),
                  ),
                ),
              ),
              Expanded(
                child: needle.isEmpty
                    ? const Center(child: Text('Escribe un tracking o el nombre de un cliente.'))
                    : (matchingClients.isEmpty && matchingPackages.isEmpty)
                        ? const Center(child: Text('No se encontraron resultados.'))
                        : ListView(children: [
                            if (matchingClients.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                                child: Text('Clientes', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                              ),
                            for (final c in matchingClients)
                              ListTile(
                                leading: const CircleAvatar(child: Icon(Icons.person)),
                                title: Text('${c['name']}'),
                                subtitle: Text('${c['phone'] ?? ''}'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () async {
                                  await Navigator.push(context, MaterialPageRoute(builder: (_) => ClientDetailPage(clientId: '${c['id']}')));
                                  load();
                                },
                              ),
                            if (matchingPackages.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                                child: Text('Paquetes', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                              ),
                            for (final p in matchingPackages)
                              ListTile(
                                leading: const Icon(Icons.inventory_2),
                                title: Text('${p['tracking']}'),
                                subtitle: Text('${clientName(clients, '${p['clientId']}')} · ${p['carrier']}\n${p['status']}'),
                                isThreeLine: true,
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () async {
                                  await Navigator.push(context, MaterialPageRoute(builder: (_) => PackageEditPage(existing: p)));
                                  load();
                                },
                              ),
                          ]),
              ),
            ]),
    );
  }
}
