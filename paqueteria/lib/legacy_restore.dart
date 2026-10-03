part of 'main.dart';

class LegacyRestorePage extends StatefulWidget {
  const LegacyRestorePage({super.key});

  @override
  State<LegacyRestorePage> createState() => _LegacyRestorePageState();
}

class _LegacyRestorePageState extends State<LegacyRestorePage> {
  Map<String, dynamic>? snapshot;
  String fileName = '';
  String message = '';
  bool busy = false;

  static const listKeys = <String>[
    'clients',
    'recipients',
    'purchases',
    'packages',
    'payments',
    'trips',
    'expenses',
    'agencyShipments',
    'agents',
    'agentReports',
  ];

  Future<void> chooseFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    try {
      final raw = f.bytes != null
          ? utf8.decode(f.bytes!)
          : (f.path == null ? '' : await File(f.path!).readAsString());
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('El archivo no contiene un respaldo válido.');
      final data = Map<String, dynamic>.from(decoded);
      final schema = '${data['schema'] ?? ''}';
      if (schema != 'alas-cargo-finance-sync-v1') {
        throw const FormatException('Este archivo no es una migración de Paquetería compatible.');
      }
      if (!mounted) return;
      setState(() {
        snapshot = data;
        fileName = f.name;
        message = 'Respaldo válido. Revisa las cantidades antes de restaurar.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        snapshot = null;
        message = e.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  int count(String key) => dynList(snapshot?[key]).length;

  Future<void> restore() async {
    final data = snapshot;
    if (data == null || busy) return;
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Restaurar datos antiguos'),
            content: const Text(
              'Los registros se combinarán por ID con los que ya existan. No se borra ningún registro que ya tengas en esta instalación.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restaurar')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    setState(() => busy = true);
    try {
      for (final key in listKeys) {
        final incoming = dynList(data[key])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (incoming.isEmpty) continue;
        final current = await Store.list(key);
        final index = <String, int>{};
        for (var i = 0; i < current.length; i++) {
          final id = '${current[i]['id'] ?? ''}'.trim();
          if (id.isNotEmpty) index[id] = i;
        }
        for (final row in incoming) {
          _preserveLegacyPhotoMetadata(row);
          final id = '${row['id'] ?? ''}'.trim();
          if (id.isNotEmpty && index.containsKey(id)) {
            current[index[id]!] = {...current[index[id]!]!, ...row};
          } else {
            current.add(row);
            if (id.isNotEmpty) index[id] = current.length - 1;
          }
        }
        await Store.saveList(key, current);
      }

      final incomingSettings = data['settings'];
      if (incomingSettings is Map) {
        final current = await Store.settings();
        current.addAll(Map<String, dynamic>.from(incomingSettings));
        current['legacyRestoredAt'] = DateTime.now().toIso8601String();
        await Store.saveSettings(current);
      }
      await FinanceSyncService.refreshSnapshot();
      if (!mounted) return;
      setState(() => message = 'Migración restaurada correctamente. Ya puedes revisar Clientes, Pedidos y Paquetes.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datos antiguos restaurados.')),
      );
    } catch (e) {
      if (mounted) setState(() => message = 'No se pudo restaurar: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _preserveLegacyPhotoMetadata(Map<String, dynamic> row) {
    final paths = dynList(row['photoPaths']).map((e) => '$e').where((e) => e.trim().isNotEmpty).toList();
    if (paths.isNotEmpty) {
      row['legacyPhotoPaths'] = paths;
      row['photoPaths'] = paths.where((p) {
        try {
          return File(p).existsSync();
        } catch (_) {
          return false;
        }
      }).toList();
    }
    final emailPaths = dynList(row['emailPhotoPaths']).map((e) => '$e').where((e) => e.trim().isNotEmpty).toList();
    if (emailPaths.isNotEmpty) {
      row['legacyEmailPhotoPaths'] = emailPaths;
      row['emailPhotoPaths'] = emailPaths.where((p) {
        try {
          return File(p).existsSync();
        } catch (_) {
          return false;
        }
      }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('Restaurar Paquetería anterior')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Usa aquí el archivo JSON creado por Paquetería Migrador antes de desinstalar la app antigua.',
          ),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: busy ? null : chooseFile,
            icon: const Icon(Icons.folder_open),
            label: const Text('Seleccionar respaldo de migración'),
          ),
          if (fileName.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(fileName, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
          if (message.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(message),
          ],
          if (data != null) ...[
            const SizedBox(height: 16),
            _sectionCard(context, 'Contenido encontrado', Icons.inventory_2_outlined, [
              Text('Clientes: ${count('clients')}'),
              Text('Destinatarios: ${count('recipients')}'),
              Text('Pedidos / compras: ${count('purchases')}'),
              Text('Paquetes: ${count('packages')}'),
              Text('Pagos: ${count('payments')}'),
              Text('Viajes: ${count('trips')}'),
              Text('Gastos: ${count('expenses')}'),
              Text('Agentes: ${count('agents')}'),
              const SizedBox(height: 8),
              const Text(
                'Las fotos guardadas dentro de la carpeta privada de la app antigua no pueden cruzar la desinstalación de Android. Sus rutas se conservan como referencia, pero los registros y datos sí se migran.',
                style: TextStyle(fontSize: 12),
              ),
            ]),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: busy ? null : restore,
              icon: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.restore),
              label: Text(busy ? 'Restaurando...' : 'Restaurar datos'),
            ),
          ],
        ],
      ),
    );
  }
}
