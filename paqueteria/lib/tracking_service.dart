part of 'main.dart';

class CourierSyncResult {
  final int checked;
  final int changed;
  final int errors;
  final String? message;
  const CourierSyncResult({this.checked = 0, this.changed = 0, this.errors = 0, this.message});
}

class EasyPostService {
  static const _secure = FlutterSecureStorage();
  static const _keyName = 'easypost_api_key';
  static const _base = 'https://api.easypost.com/v2';

  static Future<String?> apiKey() => _secure.read(key: _keyName);

  static Future<void> saveApiKey(String value) async {
    final v = value.trim();
    if (v.isEmpty) {
      await _secure.delete(key: _keyName);
    } else {
      await _secure.write(key: _keyName, value: v);
    }
  }

  static Map<String, String> _headers(String key) => {
        'Authorization': 'Basic ${base64Encode(utf8.encode('$key:'))}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  static Future<bool> testConnection([String? supplied]) async {
    final key = (supplied ?? await apiKey())?.trim() ?? '';
    if (key.isEmpty) return false;
    try {
      final r = await http
          .get(Uri.parse('$_base/trackers?page_size=1'), headers: _headers(key))
          .timeout(const Duration(seconds: 20));
      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  static String? _carrierCode(String? carrier) {
    switch ((carrier ?? '').trim()) {
      case 'UPS':
        return 'UPS';
      case 'USPS':
        return 'USPS';
      case 'FedEx':
        return 'FedEx';
      default:
        return null; // EasyPost auto-detects DHL, Amazon and other compatible carriers.
    }
  }

  static Future<Map<String, dynamic>> _createTracker(String key, Map<String, dynamic> package) async {
    final tracker = <String, dynamic>{'tracking_code': '${package['tracking']}'.trim()};
    final carrier = _carrierCode('${package['carrier'] ?? ''}');
    if (carrier != null) tracker['carrier'] = carrier;
    final r = await http
        .post(Uri.parse('$_base/trackers'), headers: _headers(key), body: jsonEncode({'tracker': tracker}))
        .timeout(const Duration(seconds: 30));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception(_apiError(r));
    }
    return Map<String, dynamic>.from(jsonDecode(r.body) as Map);
  }

  static Future<Map<String, dynamic>> _getTracker(String key, String id) async {
    final r = await http
        .get(Uri.parse('$_base/trackers/$id'), headers: _headers(key))
        .timeout(const Duration(seconds: 30));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception(_apiError(r));
    }
    return Map<String, dynamic>.from(jsonDecode(r.body) as Map);
  }

  static String _apiError(http.Response r) {
    try {
      final body = jsonDecode(r.body);
      if (body is Map && body['error'] != null) {
        final e = body['error'];
        if (e is Map) return '${e['message'] ?? e['code'] ?? e}';
        return '$e';
      }
    } catch (_) {}
    return 'Error HTTP ${r.statusCode}';
  }

  static String statusEs(String? status) {
    switch (status) {
      case 'pre_transit':
        return 'Información recibida';
      case 'in_transit':
        return 'En tránsito';
      case 'out_for_delivery':
        return 'Sale para entrega';
      case 'available_for_pickup':
        return 'Disponible para recoger';
      case 'delivered':
        return 'Entregado por el courier';
      case 'return_to_sender':
        return 'Devuelto al remitente';
      case 'failure':
        return 'Entrega fallida';
      case 'cancelled':
        return 'Cancelado';
      case 'error':
        return 'Error de tracking';
      case 'unknown':
      default:
        return 'Sin información';
    }
  }

  static String _businessStatus(String remote, String current) {
    const managed = {'Tracking creado', 'En tránsito', 'Sale para entrega', 'Problema'};
    if (!managed.contains(current)) return current;
    switch (remote) {
      case 'pre_transit':
      case 'unknown':
        return 'Tracking creado';
      case 'in_transit':
      case 'available_for_pickup':
        return 'En tránsito';
      case 'out_for_delivery':
        return 'Sale para entrega';
      case 'delivered':
        return 'Recibido';
      case 'failure':
      case 'return_to_sender':
      case 'error':
      case 'cancelled':
        return 'Problema';
      default:
        return current;
    }
  }

  static List<Map<String, dynamic>> _details(dynamic raw) {
    if (raw is! List) return [];
    return raw.reversed.take(12).map((e) {
      final m = e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};
      final loc = m['tracking_location'] is Map ? Map<String, dynamic>.from(m['tracking_location']) : <String, dynamic>{};
      final location = [loc['city'], loc['state'], loc['country']]
          .where((x) => x != null && '$x'.trim().isNotEmpty)
          .map((x) => '$x')
          .join(', ');
      return {
        'status': '${m['status'] ?? ''}',
        'message': '${m['message'] ?? ''}',
        'datetime': '${m['datetime'] ?? ''}',
        'location': location,
      };
    }).toList();
  }

  static Future<CourierSyncResult> syncAll({bool createMissing = true}) async {
    final key = (await apiKey())?.trim() ?? '';
    if (key.isEmpty) return const CourierSyncResult(message: 'Falta configurar la API key de EasyPost.');

    final rows = await Store.list('packages');
    final notices = await Store.list('courierNotifications');
    var checked = 0, changed = 0, errors = 0;

    for (var i = 0; i < rows.length; i++) {
      final p = rows[i];
      if (p['deleted'] == true) continue;
      final tracking = '${p['tracking'] ?? ''}'.trim();
      if (tracking.isEmpty) continue;
      if (['Entregado'].contains('${p['status']}')) continue;
      checked++;
      try {
        Map<String, dynamic> remote;
        final trackerId = '${p['easyPostTrackerId'] ?? ''}'.trim();
        if (trackerId.isEmpty) {
          if (!createMissing) continue;
          remote = await _createTracker(key, p);
          p['easyPostTrackerId'] = '${remote['id'] ?? ''}';
        } else {
          remote = await _getTracker(key, trackerId);
        }

        final oldRemote = '${p['courierStatus'] ?? ''}';
        final newRemote = '${remote['status'] ?? 'unknown'}';
        p['courierStatus'] = newRemote;
        p['courierStatusEs'] = statusEs(newRemote);
        p['lastCourierSync'] = DateTime.now().toIso8601String();
        p['estimatedDelivery'] = remote['est_delivery_date'];
        p['publicTrackingUrl'] = remote['public_url'];
        p['courierDetails'] = _details(remote['tracking_details']);
        if (remote['carrier'] != null && '${remote['carrier']}'.trim().isNotEmpty) {
          p['carrierRemote'] = '${remote['carrier']}';
        }
        p.remove('courierError');

        final current = '${p['status'] ?? 'Tracking creado'}';
        final next = _businessStatus(newRemote, current);
        if (next != current) {
          p['status'] = next;
          if (next == 'Recibido' && p['receivedAt'] == null) {
            p['receivedAt'] = DateTime.now().toIso8601String();
          }
        }

        if (oldRemote.isNotEmpty && oldRemote != newRemote) {
          changed++;
          notices.add({
            'id': newId(),
            'packageId': '${p['id']}',
            'tracking': tracking,
            'clientId': '${p['clientId'] ?? ''}',
            'oldStatus': oldRemote,
            'newStatus': newRemote,
            'newStatusEs': statusEs(newRemote),
            'createdAt': DateTime.now().toIso8601String(),
            'read': false,
            'deleted': false,
          });
        }
        rows[i] = p;
      } catch (e) {
        errors++;
        p['courierError'] = e.toString().replaceFirst('Exception: ', '');
        p['lastCourierSync'] = DateTime.now().toIso8601String();
        rows[i] = p;
      }
    }

    await Store.saveList('packages', rows);
    await Store.saveList('courierNotifications', notices);
    return CourierSyncResult(checked: checked, changed: changed, errors: errors);
  }
}

class CourierPage extends StatefulWidget {
  const CourierPage({super.key});
  @override
  State<CourierPage> createState() => _CourierPageState();
}

class _CourierPageState extends State<CourierPage> {
  final keyCtrl = TextEditingController();
  bool loading = true, testing = false, syncing = false, obscure = true;
  String status = 'Sin comprobar';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    keyCtrl.text = await EasyPostService.apiKey() ?? '';
    if (mounted) setState(() => loading = false);
  }

  Future<void> saveAndTest() async {
    setState(() => testing = true);
    await EasyPostService.saveApiKey(keyCtrl.text);
    final ok = await EasyPostService.testConnection();
    if (!mounted) return;
    setState(() {
      testing = false;
      status = ok ? 'Conectado correctamente' : 'No se pudo conectar';
    });
  }

  Future<void> syncNow() async {
    await EasyPostService.saveApiKey(keyCtrl.text);
    setState(() => syncing = true);
    final r = await EasyPostService.syncAll();
    if (!mounted) return;
    setState(() => syncing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.message ?? 'Revisados: ${r.checked} · Cambios: ${r.changed} · Errores: ${r.errors}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Conexión con couriers')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _sectionCard(context, 'EasyPost', Icons.cloud_sync, [
          const Text('Conecta los trackings de Paquetería con UPS, USPS, FedEx y otros couriers compatibles.'),
          const SizedBox(height: 12),
          TextField(
            controller: keyCtrl,
            obscureText: obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Production API Key de EasyPost',
              suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility : Icons.visibility_off)),
            ),
          ),
          const SizedBox(height: 10),
          Text(status, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: testing ? null : saveAndTest, icon: testing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link), label: const Text('Guardar y probar'))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton.icon(onPressed: syncing ? null : syncNow, icon: syncing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync), label: const Text('Sincronizar'))),
          ]),
        ]),
        const SizedBox(height: 12),
        _sectionCard(context, 'Importante', Icons.info_outline, const [
          Text('• Usa una clave de producción para rastreos reales.'),
          Text('• FedEx y Amazon Shipping pueden requerir que conectes tus credenciales del carrier dentro de EasyPost.'),
          Text('• La clave se guarda en el almacenamiento seguro de Android y no se incluye dentro del APK.'),
          Text('• EasyPost cobra los trackers independientes por uso.'),
        ]),
      ]),
    );
  }
}
