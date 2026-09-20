import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'database.dart';

List<Map<String, dynamic>> _paqRows(dynamic value) {
  if (value is! List) return <Map<String, dynamic>>[];
  return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

double _paqNumber(dynamic value) => double.tryParse('${value ?? ''}'.replaceAll(',', '').replaceAll(r'$', '').trim()) ?? 0;

DateTime _paqDate(dynamic value) => DateTime.tryParse('${value ?? ''}') ?? DateTime.now();

class PaqueteriaSyncResult {
  final int purchases;
  final int payments;
  final int expenses;
  final int debts;
  final String generatedAt;
  const PaqueteriaSyncResult({required this.purchases, required this.payments, required this.expenses, required this.debts, required this.generatedAt});
}

class PaqueteriaSyncService {
  static const MethodChannel _channel = MethodChannel('com.angel.finanzas/paqueteria_sync');

  static Future<PaqueteriaSyncResult?> sync({bool silent = false}) async {
    try {
      final raw = await _channel.invokeMethod<String>('readSnapshot');
      if (raw == null || raw.trim().isEmpty || raw.trim() == '{}') return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('Los datos de Paquetería no son válidos.');
      final snapshot = Map<String, dynamic>.from(decoded);
      if ('${snapshot['schema'] ?? ''}' != 'alas-cargo-finance-sync-v1') {
        throw const FormatException('Versión de sincronización no compatible.');
      }
      return AppDatabase.instance.importPaqueteriaSnapshot(snapshot);
    } on PlatformException catch (e) {
      if (!silent) rethrow;
      if (e.code == 'PAQUETERIA_NOT_AVAILABLE' || e.code == 'PAQUETERIA_PERMISSION') return null;
      return null;
    } catch (_) {
      if (!silent) rethrow;
      return null;
    }
  }
}

extension PaqueteriaSyncDatabase on AppDatabase {
  Future<PaqueteriaSyncResult> importPaqueteriaSnapshot(Map<String, dynamic> snapshot) async {
    final database = await db;
    final cash = await accountId('1010');
    final receivable = await accountId('1020');
    final sales = await accountId('4010');
    final cogs = await accountId('5010');
    final operatingExpense = await accountId('6040');

    final purchases = _paqRows(snapshot['purchases']);
    final payments = _paqRows(snapshot['payments']);
    final expenses = _paqRows(snapshot['expenses']);
    final clientBalances = _paqRows(snapshot['clientBalances']);
    final agentBalances = _paqRows(snapshot['agentBalances']);
    int purchaseCount = 0, paymentCount = 0, expenseCount = 0, debtCount = 0;

    await database.transaction((b) async {
      final old = await b.query('transactions', columns: ['id'], where: "reference LIKE 'PAQ-%'");
      for (final row in old) {
        await b.delete('journal_lines', where: 'transaction_id=?', whereArgs: [row['id']]);
      }
      await b.delete('transactions', where: "reference LIKE 'PAQ-%'");
      await b.delete('debts', where: "note LIKE 'SYNC:PAQ:%'");

      Future<void> addTx({required DateTime date, required String description, required String reference, required List<Map<String, dynamic>> lines}) async {
        final txId = await b.insert('transactions', {
          'date': date.toIso8601String(),
          'description': description,
          'reference': reference,
          'cash_flow_class': 'operating',
          'deleted_at': null,
        });
        for (final line in lines) {
          final debit = _paqNumber(line['debit']);
          final credit = _paqNumber(line['credit']);
          if (debit == 0 && credit == 0) continue;
          await b.insert('journal_lines', {
            'transaction_id': txId,
            'account_id': line['accountId'],
            'debit': debit,
            'credit': credit,
          });
        }
      }

      for (final p in purchases) {
        final status = '${p['status'] ?? ''}';
        if (status == 'Pendiente de comprar' || status == 'Cancelado') continue;
        final storeCost = _paqNumber(p['total']);
        var clientTotal = _paqNumber(p['clientTotal']);
        if (storeCost <= 0 && clientTotal <= 0) continue;
        if (clientTotal <= 0) clientTotal = storeCost;
        final margin = clientTotal - storeCost;
        final lines = <Map<String, dynamic>>[
          {'accountId': receivable, 'debit': clientTotal, 'credit': 0.0},
          {'accountId': cash, 'debit': 0.0, 'credit': storeCost},
        ];
        if (margin > 0.005) {
          lines.add({'accountId': sales, 'debit': 0.0, 'credit': margin});
        } else if (margin < -0.005) {
          lines.add({'accountId': cogs, 'debit': -margin, 'credit': 0.0});
        }
        await addTx(
          date: _paqDate(p['date']),
          description: 'Paquetería · Compra ${p['store'] ?? ''}${'${p['orderNumber'] ?? ''}'.trim().isEmpty ? '' : ' · ${p['orderNumber']}'}',
          reference: 'PAQ-PUR-${p['id']}',
          lines: lines,
        );
        purchaseCount++;
      }

      for (final p in payments) {
        final amount = _paqNumber(p['amount']);
        if (amount <= 0) continue;
        await addTx(
          date: _paqDate(p['date']),
          description: 'Paquetería · Cobro de cliente',
          reference: 'PAQ-PAY-${p['id']}',
          lines: [
            {'accountId': cash, 'debit': amount, 'credit': 0.0},
            {'accountId': receivable, 'debit': 0.0, 'credit': amount},
          ],
        );
        paymentCount++;
      }

      for (final e in expenses) {
        final amount = _paqNumber(e['amount']);
        if (amount <= 0) continue;
        await addTx(
          date: _paqDate(e['date']),
          description: 'Paquetería · Gasto · ${e['name'] ?? ''}',
          reference: 'PAQ-EXP-${e['id']}',
          lines: [
            {'accountId': operatingExpense, 'debit': amount, 'credit': 0.0},
            {'accountId': cash, 'debit': 0.0, 'credit': amount},
          ],
        );
        expenseCount++;
      }

      final dueDate = DateTime.now().add(const Duration(days: 30)).toIso8601String();
      for (final row in clientBalances) {
        final balance = _paqNumber(row['balance']);
        if (balance <= 0.005) continue;
        await b.insert('debts', {
          'name': 'Cliente · ${row['name'] ?? ''}',
          'kind': 'receivable',
          'amount': balance,
          'due_date': dueDate,
          'paid': 0,
          'note': 'SYNC:PAQ:CLIENT:${row['clientId'] ?? ''}',
        });
        debtCount++;
      }
      for (final row in agentBalances) {
        final balance = _paqNumber(row['balance']);
        if (balance <= 0.005) continue;
        await b.insert('debts', {
          'name': 'Agente · ${row['name'] ?? ''}',
          'kind': 'receivable',
          'amount': balance,
          'due_date': dueDate,
          'paid': 0,
          'note': 'SYNC:PAQ:AGENT:${row['agentId'] ?? ''}',
        });
        debtCount++;
      }

      final generatedAt = '${snapshot['generatedAt'] ?? DateTime.now().toIso8601String()}';
      await b.insert('settings', {'key': 'paqueteria_snapshot', 'value': jsonEncode(snapshot)}, conflictAlgorithm: ConflictAlgorithm.replace);
      await b.insert('settings', {'key': 'paqueteria_sync_at', 'value': generatedAt}, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    return PaqueteriaSyncResult(
      purchases: purchaseCount,
      payments: paymentCount,
      expenses: expenseCount,
      debts: debtCount,
      generatedAt: '${snapshot['generatedAt'] ?? ''}',
    );
  }

  Future<Map<String, dynamic>> paqueteriaSnapshot() async {
    final raw = await setting('paqueteria_snapshot');
    if (raw.trim().isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }
}

class PaqueteriaSyncPage extends StatefulWidget {
  final VoidCallback onChanged;
  const PaqueteriaSyncPage({super.key, required this.onChanged});
  @override
  State<PaqueteriaSyncPage> createState() => _PaqueteriaSyncPageState();
}

class _PaqueteriaSyncPageState extends State<PaqueteriaSyncPage> {
  bool busy = false;
  Map<String, dynamic> snapshot = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final data = await AppDatabase.instance.paqueteriaSnapshot();
    if (mounted) setState(() => snapshot = data);
  }

  Future<void> syncNow() async {
    setState(() => busy = true);
    try {
      final result = await PaqueteriaSyncService.sync();
      await load();
      widget.onChanged();
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No encontré datos de Paquetería. Abre Paquetería una vez y vuelve a intentar.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sincronizado: ${result.purchases} compras, ${result.payments} pagos y ${result.expenses} gastos.')));
      }
    } on PlatformException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'No se pudo conectar con Paquetería.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo sincronizar: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = snapshot['summary'] is Map ? Map<String, dynamic>.from(snapshot['summary'] as Map) : <String, dynamic>{};
    final clients = _paqRows(snapshot['clientBalances']);
    final agents = _paqRows(snapshot['agentBalances']);
    final packages = _paqRows(snapshot['packages']);
    return Scaffold(
      appBar: AppBar(title: const Text('Paquetería sincronizada')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Conexión local', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Lee los datos directamente de la APK Paquetería instalada en este teléfono. No usa internet.'),
          const SizedBox(height: 8),
          Text(snapshot.isEmpty ? 'Sin sincronización todavía.' : 'Última actualización de Paquetería: ${snapshot['generatedAt'] ?? ''}'),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: busy ? null : syncNow, icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync), label: const Text('Sincronizar ahora')),
        ]))),
        const SizedBox(height: 12),
        if (snapshot.isNotEmpty) ...[
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Resumen de Paquetería', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Compras: ${_paqRows(snapshot['purchases']).length} · costo ${_money(_paqNumber(summary['purchaseCost']))}'),
            Text('Cobrado/registrado a clientes: ${_money(_paqNumber(summary['purchaseClientTotal']))}'),
            Text('Pendiente de clientes: ${_money(_paqNumber(summary['clientReceivables']))}'),
            Text('Pendiente de agentes: ${_money(_paqNumber(summary['agentReceivables']))}'),
            Text('Paquetes: ${packages.length} · ${_paqNumber(summary['packageWeightLb']).toStringAsFixed(1)} lb'),
            Text('Gastos generales: ${_money(_paqNumber(summary['generalExpenses']))}'),
            Text('Resultado estimado de viajes: ${_money(_paqNumber(summary['tripProfitEstimated']))}'),
            Text('Resultado estimado por agencias: ${_money(_paqNumber(summary['agencyProfitEstimated']))}'),
          ]))),
          const SizedBox(height: 12),
          Card(child: ExpansionTile(title: Text('Pendientes de clientes (${clients.where((e) => _paqNumber(e['balance']) > 0.005).length})'), children: [
            for (final c in clients.where((e) => _paqNumber(e['balance']) > 0.005))
              ListTile(title: Text('${c['name']}'), trailing: Text(_money(_paqNumber(c['balance'])))),
          ])),
          Card(child: ExpansionTile(title: Text('Pendientes de agentes (${agents.where((e) => _paqNumber(e['balance']) > 0.005).length})'), children: [
            for (final a in agents.where((e) => _paqNumber(e['balance']) > 0.005))
              ListTile(title: Text('${a['name']}'), trailing: Text(_money(_paqNumber(a['balance'])))),
          ])),
          Card(child: ExpansionTile(title: Text('Paquetes (${packages.length})'), children: [
            for (final p in packages.take(50))
              ListTile(title: Text('${p['tracking'] ?? 'Sin tracking'}'), subtitle: Text('${p['status'] ?? ''} · ${_paqNumber(p['billWeight']).toStringAsFixed(1)} lb')),
          ])),
          const SizedBox(height: 8),
          const Text('Los viajes y envíos por agencia se muestran como estimados y no se convierten automáticamente en asientos contables. Las compras realizadas, pagos de clientes y gastos generales sí se actualizan en la contabilidad con referencias PAQ- para evitar duplicados.', style: TextStyle(fontSize: 12)),
        ],
      ]),
    );
  }

  String _money(double value) => 'USD ${value.toStringAsFixed(2)}';
}
