part of 'main.dart';

class GmailPurchaseReconstruction {
  final bool found;
  final String store;
  final String orderNumber;
  final List<String> trackingNumbers;
  final String carrier;
  final String status;
  final String estimatedDelivery;
  final String shipToName;
  final double subtotal;
  final double tax;
  final double shipping;
  final double discount;
  final double total;
  final String currency;
  final List<Map<String, dynamic>> items;
  final List<String> emailPhotoUrls;
  final List<String> emailPhotoPaths;
  final List<String> subjects;
  final List<String> senders;
  final String lastEmailDate;
  final String syncedAt;

  const GmailPurchaseReconstruction({
    required this.found,
    required this.store,
    required this.orderNumber,
    required this.trackingNumbers,
    required this.carrier,
    required this.status,
    required this.estimatedDelivery,
    required this.shipToName,
    required this.subtotal,
    required this.tax,
    required this.shipping,
    required this.discount,
    required this.total,
    required this.currency,
    required this.items,
    required this.emailPhotoUrls,
    required this.emailPhotoPaths,
    required this.subjects,
    required this.senders,
    required this.lastEmailDate,
    required this.syncedAt,
  });

  factory GmailPurchaseReconstruction.fromJson(Map<String, dynamic> json) {
    List<String> strings(dynamic value) => value is List
        ? value.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toSet().toList()
        : <String>[];
    List<Map<String, dynamic>> maps(dynamic value) => value is List
        ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    return GmailPurchaseReconstruction(
      found: json['found'] == true,
      store: '${json['store'] ?? ''}'.trim(),
      orderNumber: '${json['orderNumber'] ?? ''}'.trim(),
      trackingNumbers: strings(json['trackingNumbers']),
      carrier: '${json['carrier'] ?? 'Auto / Otro'}'.trim(),
      status: '${json['status'] ?? ''}'.trim(),
      estimatedDelivery: '${json['estimatedDelivery'] ?? ''}'.trim(),
      shipToName: '${json['shipToName'] ?? ''}'.trim(),
      subtotal: number(json['subtotal']),
      tax: number(json['tax']),
      shipping: number(json['shipping']),
      discount: number(json['discount']),
      total: number(json['total']),
      currency: '${json['currency'] ?? 'USD'}'.trim(),
      items: maps(json['items']).map((e) => {
        ...e,
        'id': '${e['id'] ?? ''}'.trim().isEmpty ? newId() : '${e['id']}',
        'received': e['received'] == true,
      }).toList(),
      emailPhotoUrls: strings(json['emailPhotoUrls']),
      emailPhotoPaths: strings(json['emailPhotoPaths']),
      subjects: strings(json['emailSubjects']),
      senders: strings(json['emailFrom']),
      lastEmailDate: '${json['lastEmailDate'] ?? ''}'.trim(),
      syncedAt: '${json['syncedAt'] ?? ''}'.trim(),
    );
  }
}

class GmailReconstructionService {
  static const _secure = FlutterSecureStorage();
  static const _defaultBackend = 'https://wasbot-backend-production.up.railway.app';
  static const _backendKey = 'gmail_reconstruction_backend_url';
  static const _apiKeyKey = 'gmail_reconstruction_api_key';

  static Future<String> backendUrl() async {
    final stored = (await _secure.read(key: _backendKey) ?? '').trim();
    return (stored.isEmpty ? _defaultBackend : stored).replaceAll(RegExp(r'/+$'), '');
  }

  static Future<String> apiKey() async {
    for (final key in const [
      _apiKeyKey,
      'whatsbot_api_key',
      'app_api_key',
      'sync_api_key',
    ]) {
      final value = (await _secure.read(key: key) ?? '').trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static Future<void> saveConnection({required String backend, required String apiKey}) async {
    await _secure.write(key: _backendKey, value: backend.trim());
    await _secure.write(key: _apiKeyKey, value: apiKey.trim());
  }

  static Future<Map<String, String>> _headers() async {
    final key = await apiKey();
    return {
      'Accept': 'application/json',
      if (key.isNotEmpty) 'x-api-key': key,
    };
  }

  static Future<Map<String, dynamic>> gmailStatus() async {
    final base = await backendUrl();
    final response = await http
        .get(Uri.parse('$base/api/gmail/status'), headers: await _headers())
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_error(response));
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  static Future<Uri> authorizationUrl() async {
    final base = await backendUrl();
    final response = await http
        .get(Uri.parse('$base/api/gmail/auth-url'), headers: await _headers())
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_error(response));
    }
    final body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    final url = '${body['url'] ?? ''}'.trim();
    if (url.isEmpty) throw Exception('El servidor no devolvió la autorización de Gmail.');
    return Uri.parse(url);
  }

  static Future<GmailPurchaseReconstruction> byOrder(String orderNumber) =>
      _reconstruct(orderNumber: orderNumber);

  static Future<GmailPurchaseReconstruction> byTracking(String tracking) =>
      _reconstruct(tracking: tracking);

  static Future<GmailPurchaseReconstruction> _reconstruct({
    String orderNumber = '',
    String tracking = '',
  }) async {
    final base = await backendUrl();
    final uri = Uri.parse('$base/api/gmail/reconstruct').replace(queryParameters: {
      if (orderNumber.trim().isNotEmpty) 'order_number': orderNumber.trim(),
      if (tracking.trim().isNotEmpty) 'tracking': tracking.trim(),
    });
    final response = await http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_error(response));
    }
    final raw = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    final downloaded = <String>[];
    final attachmentRows = raw['emailAttachmentImages'];
    if (attachmentRows is List) {
      for (final row in attachmentRows.whereType<Map>()) {
        final relative = '${row['url'] ?? ''}'.trim();
        if (relative.isEmpty) continue;
        try {
          final path = await _downloadProtectedImage(relative);
          if (path.isNotEmpty) downloaded.add(path);
        } catch (_) {}
      }
    }
    raw['emailPhotoPaths'] = downloaded;
    return GmailPurchaseReconstruction.fromJson(raw);
  }

  static Future<String> _downloadProtectedImage(String relativeOrAbsolute) async {
    final base = await backendUrl();
    final uri = relativeOrAbsolute.startsWith('http')
        ? Uri.parse(relativeOrAbsolute)
        : Uri.parse('$base${relativeOrAbsolute.startsWith('/') ? '' : '/'}$relativeOrAbsolute');
    final response = await http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) return '';
    final type = response.headers['content-type'] ?? '';
    final ext = type.contains('png')
        ? 'png'
        : type.contains('webp')
            ? 'webp'
            : 'jpg';
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/gmail_photo_${DateTime.now().microsecondsSinceEpoch}.$ext');
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file.path;
  }

  static String _error(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['detail'] != null) return '${body['detail']}';
    } catch (_) {}
    return 'Error HTTP ${response.statusCode}';
  }
}

String normalizeTracking(String value) => value
    .trim()
    .toUpperCase()
    .replaceAll(RegExp(r'[^A-Z0-9]'), '');

String normalizeOrderNumber(String value) => value
    .trim()
    .toUpperCase()
    .replaceAll(RegExp(r'[^A-Z0-9]'), '');

class GmailConnectionPage extends StatefulWidget {
  const GmailConnectionPage({super.key});
  @override
  State<GmailConnectionPage> createState() => _GmailConnectionPageState();
}

class _GmailConnectionPageState extends State<GmailConnectionPage> {
  final backend = TextEditingController();
  final apiKeyCtrl = TextEditingController();
  bool loading = true, busy = false, obscure = true;
  Map<String, dynamic> status = {};
  String message = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    backend.text = await GmailReconstructionService.backendUrl();
    apiKeyCtrl.text = await GmailReconstructionService.apiKey();
    try {
      status = await GmailReconstructionService.gmailStatus();
      message = status['connected'] == true
          ? 'Gmail conectado${'${status['email'] ?? ''}'.trim().isEmpty ? '' : ': ${status['email']}'}'
          : 'Gmail todavía no está conectado.';
    } catch (e) {
      message = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> saveAndConnect() async {
    setState(() => busy = true);
    await GmailReconstructionService.saveConnection(
      backend: backend.text,
      apiKey: apiKeyCtrl.text,
    );
    try {
      final url = await GmailReconstructionService.authorizationUrl();
      await launchUrl(url, mode: LaunchMode.externalApplication);
      message = 'Autoriza Gmail en el navegador y vuelve a esta pantalla; después toca Actualizar estado.';
    } catch (e) {
      message = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Gmail · Reconstrucción de compras')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
                const Text(
                  'Paquetería usa acceso de solo lectura a Gmail para localizar pedidos por número de orden o tracking y reconstruir tienda, artículos, precios, fotos y estado.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: backend,
                  decoration: const InputDecoration(labelText: 'Servidor de sincronización'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: apiKeyCtrl,
                  obscureText: obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'API key',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => obscure = !obscure),
                      icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: busy ? null : saveAndConnect,
                  icon: const Icon(Icons.mail_outline),
                  label: const Text('Guardar y conectar Gmail'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualizar estado'),
                ),
              ]),
      );
}
