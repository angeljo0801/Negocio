part of 'main.dart';

class FlightSyncResult {
  final int checked;
  final int changed;
  final int errors;
  final String? message;
  const FlightSyncResult({this.checked = 0, this.changed = 0, this.errors = 0, this.message});
}

class FlightService {
  static const _secure = FlutterSecureStorage();
  static const _clientIdKey = 'amadeus_client_id';
  static const _clientSecretKey = 'amadeus_client_secret';
  static const _base = 'https://api.amadeus.com';

  static Future<String> clientId() async => (await _secure.read(key: _clientIdKey) ?? '').trim();
  static Future<String> clientSecret() async => (await _secure.read(key: _clientSecretKey) ?? '').trim();

  static Future<void> saveCredentials(String id, String secret) async {
    if (id.trim().isEmpty) await _secure.delete(key: _clientIdKey); else await _secure.write(key: _clientIdKey, value: id.trim());
    if (secret.trim().isEmpty) await _secure.delete(key: _clientSecretKey); else await _secure.write(key: _clientSecretKey, value: secret.trim());
  }

  static Future<String> _token() async {
    final id = await clientId(), secret = await clientSecret();
    if (id.isEmpty || secret.isEmpty) throw Exception('Faltan las credenciales de Amadeus.');
    final r = await http.post(
      Uri.parse('$_base/v1/security/oauth2/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'grant_type': 'client_credentials', 'client_id': id, 'client_secret': secret},
    ).timeout(const Duration(seconds: 25));
    if (r.statusCode < 200 || r.statusCode >= 300) throw Exception('Amadeus rechazó las credenciales (HTTP ${r.statusCode}).');
    final body = jsonDecode(r.body) as Map;
    final token = '${body['access_token'] ?? ''}';
    if (token.isEmpty) throw Exception('Amadeus no devolvió un token.');
    return token;
  }

  static Future<bool> testConnection() async {
    try { await _token(); return true; } catch (_) { return false; }
  }

  static List<DateTime> _dates(String from, String to) {
    final a = DateTime.tryParse(from), b = DateTime.tryParse(to);
    if (a == null) return [];
    final end = b == null || b.isBefore(a) ? a : b;
    final out = <DateTime>[];
    var d = a;
    while (!d.isAfter(end) && out.length < 21) {
      out.add(d);
      d = d.add(const Duration(days: 1));
    }
    return out;
  }

  static String _date(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<Map<String, dynamic>?> _searchDay(String token, Map<String, dynamic> watch, DateTime date) async {
    final params = {
      'originLocationCode': '${watch['origin']}',
      'destinationLocationCode': '${watch['destination']}',
      'departureDate': _date(date),
      'adults': '1',
      'currencyCode': 'USD',
      'max': '20',
    };
    final uri = Uri.parse('$_base/v2/shopping/flight-offers').replace(queryParameters: params);
    final r = await http.get(uri, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 30));
    if (r.statusCode < 200 || r.statusCode >= 300) throw Exception('Error de vuelos HTTP ${r.statusCode}');
    final body = jsonDecode(r.body) as Map;
    final data = body['data'];
    if (data is! List || data.isEmpty) return null;
    Map<String, dynamic>? best;
    double bestPrice = double.infinity;
    for (final raw in data) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final price = m['price'] is Map ? Map<String, dynamic>.from(m['price']) : <String, dynamic>{};
      final p = number(price['grandTotal']);
      if (p > 0 && p < bestPrice) { bestPrice = p; best = m; }
    }
    if (best == null) return null;
    final itinerary = (best['itineraries'] is List && (best['itineraries'] as List).isNotEmpty) ? (best['itineraries'] as List).first : null;
    String airline = '';
    String departure = '';
    if (itinerary is Map && itinerary['segments'] is List && (itinerary['segments'] as List).isNotEmpty) {
      final seg = Map<String, dynamic>.from((itinerary['segments'] as List).first as Map);
      airline = '${seg['carrierCode'] ?? ''}';
      if (seg['departure'] is Map) departure = '${(seg['departure'] as Map)['at'] ?? ''}';
    }
    return {'price': bestPrice, 'date': _date(date), 'airline': airline, 'departure': departure, 'offerId': '${best['id'] ?? ''}'};
  }

  static Future<FlightSyncResult> syncAll() async {
    final id = await clientId(), secret = await clientSecret();
    if (id.isEmpty || secret.isEmpty) return const FlightSyncResult(message: 'Faltan las credenciales de Amadeus para buscar vuelos automáticamente.');
    String token;
    try { token = await _token(); } catch (e) { return FlightSyncResult(errors: 1, message: e.toString().replaceFirst('Exception: ', '')); }
    final watches = await Store.list('flightWatches');
    final notices = await Store.list('flightNotifications');
    var checked = 0, changed = 0, errors = 0;
    for (var i = 0; i < watches.length; i++) {
      final w = watches[i];
      if (w['deleted'] == true) continue;
      final dates = _dates('${w['fromDate'] ?? ''}', '${w['toDate'] ?? w['fromDate'] ?? ''}');
      if (dates.isEmpty) continue;
      checked++;
      try {
        Map<String, dynamic>? best;
        for (final d in dates) {
          final x = await _searchDay(token, w, d);
          if (x != null && (best == null || number(x['price']) < number(best['price']))) best = x;
        }
        if (best == null) continue;
        final old = number(w['lastPrice']);
        final now = number(best['price']);
        w['lastPrice'] = now;
        w['bestDate'] = best['date'];
        w['bestAirline'] = best['airline'];
        w['bestDeparture'] = best['departure'];
        w['lastCheckedAt'] = DateTime.now().toIso8601String();
        final target = number(w['targetPrice']);
        final interesting = target > 0 && now <= target;
        final lowered = old <= 0 || now < old - 0.01;
        if (interesting && lowered) {
          changed++;
          notices.add({
            'id': newId(),
            'watchId': '${w['id']}',
            'origin': '${w['origin']}',
            'destination': '${w['destination']}',
            'price': now,
            'date': '${best['date']}',
            'airline': '${best['airline']}',
            'createdAt': DateTime.now().toIso8601String(),
            'notificationSent': false,
            'deleted': false,
          });
        }
        watches[i] = w;
      } catch (e) {
        errors++;
        w['flightError'] = e.toString().replaceFirst('Exception: ', '');
        watches[i] = w;
      }
    }
    await Store.saveList('flightWatches', watches);
    await Store.saveList('flightNotifications', notices);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastFlightBackgroundSync', DateTime.now().toIso8601String());
    return FlightSyncResult(checked: checked, changed: changed, errors: errors);
  }

  static Future<FlightSyncResult> syncIfDue() async {
    final prefs = await SharedPreferences.getInstance();
    final last = DateTime.tryParse(prefs.getString('lastFlightBackgroundSync') ?? '');
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 6)) return const FlightSyncResult(message: 'La revisión de vuelos aún no corresponde.');
    return syncAll();
  }
}

class FlightApiPage extends StatefulWidget {
  const FlightApiPage({super.key});
  @override
  State<FlightApiPage> createState() => _FlightApiPageState();
}

class _FlightApiPageState extends State<FlightApiPage> {
  final id = TextEditingController(), secret = TextEditingController();
  bool loading = true, testing = false, obscure = true;
  String status = 'Sin comprobar';
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    id.text = await FlightService.clientId();
    secret.text = await FlightService.clientSecret();
    if (mounted) setState(() => loading = false);
  }
  Future<void> saveAndTest() async {
    setState(() => testing = true);
    await FlightService.saveCredentials(id.text, secret.text);
    final ok = await FlightService.testConnection();
    if (!mounted) return;
    setState(() { testing = false; status = ok ? 'Conectado correctamente' : 'No se pudo conectar'; });
  }
  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Proveedor de vuelos')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _sectionCard(context, 'Amadeus Flight Offers', Icons.flight_takeoff, [
          const Text('Permite consultar precios reales de las rutas vigiladas. Necesitas credenciales de producción de Amadeus for Developers.'),
          const SizedBox(height: 12),
          TextField(controller: id, decoration: const InputDecoration(labelText: 'Client ID / API Key')),
          const SizedBox(height: 10),
          TextField(controller: secret, obscureText: obscure, autocorrect: false, enableSuggestions: false, decoration: InputDecoration(labelText: 'Client Secret', suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility : Icons.visibility_off)))),
          const SizedBox(height: 10),
          Text(status, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: testing ? null : saveAndTest, icon: testing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link), label: const Text('Guardar y probar')),
        ]),
      ]),
    );
  }
}
