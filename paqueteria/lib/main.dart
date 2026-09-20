import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

part 'clients.dart';
part 'purchases.dart';
part 'packages.dart';
part 'trips.dart';
part 'flights.dart';
part 'extras.dart';
part 'tracking_service.dart';
part 'agents.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PaqueteriaApp());
}

class PaqueteriaApp extends StatelessWidget {
  const PaqueteriaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Paquetería',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B65D8), brightness: Brightness.dark),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: const SplashPage(),
    );
  }
}

class Store {
  static Future<List<Map<String, dynamic>>> list(String key) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveList(String key, List<Map<String, dynamic>> value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, jsonEncode(value));
    await FinanceSyncService.refreshSnapshot();
  }

  static Future<Map<String, dynamic>> settings() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('settings');
    if (raw == null) {
      return {'ratePerLb': 5.0, 'purchaseCommissionPct': 0.0, 'weightRule': 'manual', 'trashDays': 30};
    }
    try {
      final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      m.putIfAbsent('ratePerLb', () => 5.0);
      m.putIfAbsent('purchaseCommissionPct', () => 0.0);
      m.putIfAbsent('weightRule', () => 'manual');
      m.putIfAbsent('trashDays', () => 30);
      return m;
    } catch (_) {
      return {'ratePerLb': 5.0, 'purchaseCommissionPct': 0.0, 'weightRule': 'manual', 'trashDays': 30};
    }
  }

  static Future<void> saveSettings(Map<String, dynamic> value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('settings', jsonEncode(value));
    await FinanceSyncService.refreshSnapshot();
  }
}

String newId() => DateTime.now().microsecondsSinceEpoch.toString();
String money(num n) => '\$${n.toStringAsFixed(2)}';
List<dynamic> dynList(dynamic v) => v is List ? v : const [];

double number(dynamic s) => double.tryParse('${s ?? ''}'.replaceAll(',', '').replaceAll('\$', '').trim()) ?? 0;
String today() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

List<Map<String, dynamic>> active(List<Map<String, dynamic>> rows) => rows.where((e) => e['deleted'] != true).toList();
String clientName(List<Map<String, dynamic>> clients, String? id) {
  final found = clients.where((e) => e['id'] == id).toList();
  return found.isEmpty ? 'Sin cliente' : '${found.first['name']}';
}

Future<void> softDelete(String key, String id) async {
  final rows = await Store.list(key);
  final i = rows.indexWhere((e) => e['id'] == id);
  if (i >= 0) {
    rows[i]['deleted'] = true;
    rows[i]['deletedAt'] = DateTime.now().toIso8601String();
    await Store.saveList(key, rows);
  }
}

Future<bool> confirmDelete(BuildContext context, String what) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Enviar a papelera'),
          content: Text('¿Quieres eliminar $what? Podrás restaurarlo desde Papelera.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
          ],
        ),
      ) ??
      false;
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    FinanceSyncService.refreshSnapshot();
    Timer(const Duration(milliseconds: 1350), () {
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeShell()));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            ClipRRect(borderRadius: BorderRadius.circular(30), child: Image.asset('assets/icon.png', width: 180, height: 180)),
            const SizedBox(height: 24),
            Text('Paquetería', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Herramientas de Negocio'),
          ]),
        ),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  final pages = const [DashboardPage(), ClientsPage(), PackagesPage(), TripsPage(), MorePage()];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Clientes'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Paquetes'),
          NavigationDestination(icon: Icon(Icons.flight_outlined), selectedIcon: Icon(Icons.flight), label: 'Viajes'),
          NavigationDestination(icon: Icon(Icons.apps), label: 'Más'),
        ],
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool loading = true;
  bool courierSyncing = false;
  List<Map<String, dynamic>> clients = [], purchases = [], packages = [], trips = [], payments = [], watches = [], agents = [], agentReports = [];
  Map<String, dynamic> settings = {};

  @override
  void initState() {
    super.initState();
    load(syncCourier: true);
  }

  Future<void> load({bool syncCourier = false}) async {
    if (syncCourier) {
      if (mounted) setState(() => courierSyncing = true);
      await EasyPostService.syncAll();
      if (mounted) setState(() => courierSyncing = false);
    }
    final r = await Future.wait([
      Store.list('clients'),
      Store.list('purchases'),
      Store.list('packages'),
      Store.list('trips'),
      Store.list('payments'),
      Store.list('flightWatches'),
      Store.list('agents'),
      Store.list('agentReports'),
      Store.settings(),
    ]);
    if (!mounted) return;
    setState(() {
      clients = active(r[0] as List<Map<String, dynamic>>);
      purchases = active(r[1] as List<Map<String, dynamic>>);
      packages = active(r[2] as List<Map<String, dynamic>>);
      trips = active(r[3] as List<Map<String, dynamic>>);
      payments = active(r[4] as List<Map<String, dynamic>>);
      watches = active(r[5] as List<Map<String, dynamic>>);
      agents = active(r[6] as List<Map<String, dynamic>>);
      agentReports = active(r[7] as List<Map<String, dynamic>>);
      settings = r[8] as Map<String, dynamic>;
      loading = false;
    });
  }

  Future<void> openCourier() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const CourierPage()));
    if (mounted) await load(syncCourier: true);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final pendingPurchases = purchases.where((e) => e['status'] == 'Pendiente de comprar').length;
    final inTransit = packages.where((e) => ['En tránsito', 'Sale para entrega', 'Tracking creado'].contains(e['status'])).length;
    final received = packages.where((e) => e['status'] == 'Recibido').toList();
    final readyLb = received.fold<double>(0, (a, e) => a + number(e['billWeight']));
    final due = clients.fold<double>(0, (a, c) => a + clientDue('${c['id']}', purchases, payments));
    final cheap = watches.where((e) => number(e['lastPrice']) > 0 && number(e['lastPrice']) <= number(e['targetPrice'])).length;
    final courierErrors = packages.where((e) => '${e['courierError'] ?? ''}'.trim().isNotEmpty).length;
    final agentDue = agents.fold<double>(0, (sum, a) => sum + agentBalanceFromReport(latestAgentReport('${a['id']}', agentReports)));
    final tasks = <String>[];
    if (pendingPurchases > 0) tasks.add('Comprar $pendingPurchases pedido(s) pendiente(s).');
    if (inTransit > 0) tasks.add('Revisar $inTransit paquete(s) actualmente en tránsito.');
    if (courierErrors > 0) tasks.add('$courierErrors paquete(s) necesitan revisar la conexión con el courier.');
    if (due > 0) tasks.add('Hay ${money(due)} pendientes de cobro.');
    if (readyLb > 0) tasks.add('Tienes ${readyLb.toStringAsFixed(1)} lb recibidas listas para organizar en un viaje.');
    if (cheap > 0) tasks.add('Hay $cheap ruta(s) con precio observado por debajo de tu objetivo.');
    if (agentDue > 0) tasks.add('Tus agentes reportan ${money(agentDue)} pendientes de liquidar contigo.');
    if (tasks.isEmpty) tasks.add('No hay pendientes críticos registrados.');

    return Scaffold(
      appBar: AppBar(title: const Text('Paquetería'), actions: [
        IconButton(tooltip: 'Conexión courier', onPressed: openCourier, icon: const Icon(Icons.cloud_sync)),
        IconButton(
          tooltip: 'Actualizar datos y couriers',
          onPressed: courierSyncing ? null : () => load(syncCourier: true),
          icon: courierSyncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
        ),
      ]),
      body: RefreshIndicator(
        onRefresh: () => load(syncCourier: true),
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Text('Centro de operaciones', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _quick(context, Icons.qr_code_scanner, 'Escanear paquete', () async {
              final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScannerPage()));
              if (code != null && context.mounted) {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => PackageEditPage(initialTracking: code)));
                load(syncCourier: true);
              }
            }),
            _quick(context, Icons.shopping_cart_checkout, 'Nuevo pedido', () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseEditPage()));
              load();
            }),
            _quick(context, Icons.person_add_alt_1, 'Nuevo cliente', () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientEditPage()));
              load();
            }),
            _quick(context, Icons.receipt_long, 'Registrar compra', () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseEditPage(startWithReceipt: true)));
              load();
            }),
            _quick(context, Icons.cloud_sync, 'Couriers', openCourier),
            _quick(context, Icons.badge_outlined, 'Agentes', () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const AgentsPage()));
              load();
            }),
          ]),
          const SizedBox(height: 16),
          _sectionCard(context, '¿Qué debo hacer ahora?', Icons.assignment_turned_in, tasks.map((e) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text('• $e'))).toList()),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.55,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: [
              _stat('En tránsito', '$inTransit', Icons.local_shipping),
              _stat('Por comprar', '$pendingPurchases', Icons.shopping_bag),
              _stat('Carga recibida', '${readyLb.toStringAsFixed(1)} lb', Icons.inventory),
              _stat('Por cobrar', money(due), Icons.payments),
              _stat('Agentes', '${agents.length}', Icons.badge_outlined),
              _stat('Saldo agentes', money(agentDue), Icons.account_balance_wallet_outlined),
            ],
          ),
          const SizedBox(height: 12),
          if (trips.isNotEmpty) _tripSummary(trips.last),
          if (cheap > 0) ...[
            const SizedBox(height: 12),
            _sectionCard(context, 'Vuelos baratos detectados', Icons.flight_takeoff, [Text('$cheap ruta(s) tienen un precio observado menor o igual al objetivo configurado.')]),
          ],
          const SizedBox(height: 80),
        ]),
      ),
    );
  }

  Widget _quick(BuildContext context, IconData icon, String text, VoidCallback onTap) => SizedBox(
        width: (MediaQuery.of(context).size.width - 40) / 2,
        child: FilledButton.tonalIcon(onPressed: onTap, icon: Icon(icon), label: Text(text)),
      );

  Widget _stat(String label, String value, IconData icon) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon), const Spacer(), Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), Text(label)]),
        ),
      );

  Widget _tripSummary(Map<String, dynamic> trip) {
    final rate = number(trip['ratePerLb']);
    final assigned = (trip['packageIds'] as List? ?? []).map((e) => '$e').toSet();
    final weight = packages.where((e) => assigned.contains('${e['id']}')).fold<double>(0, (a, e) => a + number(e['billWeight']));
    final income = weight * rate;
    final expense = tripExpenses(trip);
    return _sectionCard(context, 'Próximo / último viaje', Icons.flight, [
      Text('${trip['origin']} → ${trip['destination']} · ${trip['date']}'),
      Text('${weight.toStringAsFixed(1)} / ${number(trip['capacityLb']).toStringAsFixed(1)} lb asignadas'),
      Text('Ingresos estimados: ${money(income)}'),
      Text('Gastos estimados: ${money(expense)}'),
      Text('Ganancia estimada: ${money(income - expense)}', style: const TextStyle(fontWeight: FontWeight.bold)),
    ]);
  }
}

Widget _sectionCard(BuildContext context, String title, IconData icon, List<Widget> children) => Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon), const SizedBox(width: 8), Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)))]),
          const SizedBox(height: 10),
          ...children,
        ]),
      ),
    );

double clientDue(String clientId, List<Map<String, dynamic>> purchases, List<Map<String, dynamic>> payments) {
  final owed = purchases.where((e) => '${e['clientId']}' == clientId).fold<double>(0, (a, e) => a + number(e['clientTotal']));
  final paid = payments.where((e) => '${e['clientId']}' == clientId).fold<double>(0, (a, e) => a + number(e['amount']));
  return owed - paid;
}
