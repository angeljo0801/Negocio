import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const MigratorApp());

class MigratorApp extends StatelessWidget {
  const MigratorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Paquetería Migrador',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
        home: const MigratorPage(),
      );
}

class MigratorPage extends StatefulWidget {
  const MigratorPage({super.key});

  @override
  State<MigratorPage> createState() => _MigratorPageState();
}

class _MigratorPageState extends State<MigratorPage> {
  static const channel = MethodChannel('paqueteria_legacy_migrator');
  Map<String, dynamic>? snapshot;
  String message = 'Mantén instalada tu Paquetería actual mientras haces esta copia.';
  bool busy = false;

  int count(String key) {
    final value = snapshot?[key];
    return value is List ? value.length : 0;
  }

  Future<void> readOldApp() async {
    if (busy) return;
    setState(() {
      busy = true;
      message = 'Leyendo los datos de la Paquetería instalada...';
    });
    try {
      final raw = await channel.invokeMethod<String>('readSnapshot') ?? '';
      if (raw.trim().isEmpty) throw Exception('La app antigua no devolvió datos.');
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw Exception('El respaldo recibido no es válido.');
      final data = Map<String, dynamic>.from(decoded);
      if ('${data['schema'] ?? ''}' != 'alas-cargo-finance-sync-v1') {
        throw Exception('La versión instalada no expone un respaldo compatible.');
      }
      if (!mounted) return;
      setState(() {
        snapshot = data;
        message = 'Datos encontrados. Ahora guarda el archivo antes de desinstalar la app antigua.';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => message = e.message ?? 'No pude leer la Paquetería instalada.');
    } catch (e) {
      if (!mounted) return;
      setState(() => message = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> saveBackup() async {
    final data = snapshot;
    if (data == null || busy) return;
    setState(() => busy = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}/Paqueteria-migracion-$stamp.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data), flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'Respaldo de migración de Paquetería',
        text: 'Guarda este archivo. Lo necesitarás para restaurar tus datos en la Paquetería nueva.',
      );
      if (mounted) {
        setState(() => message = 'Archivo creado. Guárdalo en Archivos, Drive u otro lugar antes de quitar la app antigua.');
      }
    } catch (e) {
      if (mounted) setState(() => message = 'No se pudo crear el archivo: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('Paquetería Migrador')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Icon(Icons.move_down, size: 72),
          const SizedBox(height: 12),
          const Text(
            'Este migrador copia los registros de la Paquetería que tienes instalada sin modificarla.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: busy ? null : readOldApp,
            icon: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.content_copy),
            label: const Text('Leer datos de la Paquetería instalada'),
          ),
          if (data != null) ...[
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Datos encontrados', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Clientes: ${count('clients')}'),
                    Text('Destinatarios: ${count('recipients')}'),
                    Text('Pedidos / compras: ${count('purchases')}'),
                    Text('Paquetes: ${count('packages')}'),
                    Text('Pagos: ${count('payments')}'),
                    Text('Viajes: ${count('trips')}'),
                    Text('Gastos: ${count('expenses')}'),
                    Text('Agentes: ${count('agents')}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: busy ? null : saveBackup,
              icon: const Icon(Icons.save_alt),
              label: const Text('Guardar / compartir respaldo JSON'),
            ),
            const SizedBox(height: 10),
            const Text(
              'No desinstales la Paquetería antigua hasta que hayas guardado este archivo y verificado que tiene tus cantidades correctas.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }
}
