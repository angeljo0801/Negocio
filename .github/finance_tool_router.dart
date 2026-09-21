import 'dart:convert';

import 'database.dart';
import 'personal_finance.dart';

class FinanceToolRouter {
  static const _stop = <String>{
    'que','qué','como','cómo','cuanto','cuánto','cual','cuál','cuales','cuáles',
    'dime','quiero','necesito','busca','buscar','encuentra','muestra','mostrar',
    'todos','todas','todo','los','las','del','de','la','el','en','un','una',
    'por','para','con','sin','y','o','me','mi','mis','se','es','fue','han',
    'this','that','show','find','search','all','the','my','in','of','for','and',
  };

  static String _norm(String value) {
    var s = value.toLowerCase();
    const from = 'áéíóúüñ';
    const to = 'aeiouun';
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    return s;
  }

  static List<String> _terms(String question) {
    final words = _norm(question)
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && !_stop.contains(w))
        .toList();
    final result = <String>[];
    for (final w in words) {
      if (!result.contains(w)) result.add(w);
      if (result.length >= 6) break;
    }
    return result;
  }

  static bool _has(String s, List<String> words) => words.any(s.contains);

  static ({String? from, String? to}) _dateRange(String question) {
    final normalized = _norm(question);
    final exact = RegExp(r'\b(20\d{2})-(\d{2})-(\d{2})\b')
        .allMatches(normalized)
        .map((m) => m.group(0)!)
        .toList();
    if (exact.length >= 2) return (from: exact.first, to: exact[1]);
    if (exact.length == 1) return (from: exact.first, to: exact.first);

    const months = <String, int>{
      'enero': 1, 'january': 1,
      'febrero': 2, 'february': 2,
      'marzo': 3, 'march': 3,
      'abril': 4, 'april': 4,
      'mayo': 5, 'may': 5,
      'junio': 6, 'june': 6,
      'julio': 7, 'july': 7,
      'agosto': 8, 'august': 8,
      'septiembre': 9, 'setiembre': 9, 'september': 9,
      'octubre': 10, 'october': 10,
      'noviembre': 11, 'november': 11,
      'diciembre': 12, 'december': 12,
    };
    final found = <int>[];
    for (final e in months.entries) {
      if (RegExp('\\b${e.key}\\b').hasMatch(normalized)) {
        found.add(e.value);
      }
    }
    if (found.isEmpty) return (from: null, to: null);
    found.sort();

    final yearMatch = RegExp(r'\b(20\d{2})\b').firstMatch(normalized);
    final year = int.tryParse(yearMatch?.group(1) ?? '') ?? DateTime.now().year;
    final first = found.first;
    final last = found.last;
    final from = DateTime(year, first, 1);
    final end = DateTime(year, last + 1, 1).subtract(const Duration(days: 1));
    String ymd(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return (from: ymd(from), to: ymd(end));
  }

  static String _whereSearch(
    List<String> columns,
    List<String> terms,
    List<Object?> args,
  ) {
    if (terms.isEmpty) return '';
    final groups = <String>[];
    for (final term in terms) {
      groups.add('(' + columns.map((c) => 'LOWER(COALESCE($c,\'\')) LIKE ?').join(' OR ') + ')');
      for (var i = 0; i < columns.length; i++) {
        args.add('%$term%');
      }
    }
    return groups.join(' AND ');
  }

  static Future<String> query(String question) async {
    final d = await AppDatabase.instance.db;
    await PersonalFinanceStore.ensureSchema();

    final q = _norm(question);
    final terms = _terms(question);
    final range = _dateRange(question);
    final broad = _has(q, [
      'todo', 'todas', 'todos', 'cualquier', 'buscar', 'busca', 'encuentra',
      'historial', 'historico', 'historico', 'aplicacion', 'datos',
    ]);

    final wantsPersonal = broad || _has(q, [
      'personal', 'personales', 'mio', 'mia', 'mios', 'mias',
      'tarjeta personal', 'dinero personal',
    ]);
    final wantsBusiness = broad || _has(q, [
      'negocio', 'empresa', 'ventas', 'venta', 'gasto', 'gastos', 'ingreso',
      'ingresos', 'transaccion', 'transacciones', 'movimiento', 'movimientos',
      'cliente', 'proveedor', 'asiento',
    ]);
    final wantsBalances = broad || _has(q, [
      'saldo', 'saldos', 'cuenta', 'cuentas', 'patrimonio', 'efectivo',
      'balance',
    ]);
    final wantsDebts = broad || _has(q, [
      'deuda', 'deudas', 'debo', 'deben', 'cobrar', 'pagar', 'pendiente',
    ]);
    final wantsRemittances = broad || _has(q, [
      'remesa', 'remesas', 'remittance',
    ]);
    final wantsPaq = broad || _has(q, [
      'paqueteria', 'paquete', 'paquetes', 'pedido', 'pedidos', 'agente',
      'agentes', 'tracking', 'compra', 'compras',
    ]);

    final nothingSpecific = !wantsPersonal &&
        !wantsBusiness &&
        !wantsBalances &&
        !wantsDebts &&
        !wantsRemittances &&
        !wantsPaq;

    final b = StringBuffer();
    b.writeln('RESULTADOS DEL TOOL ROUTER DE FINANZAS');
    b.writeln('Consulta: $question');
    if (range.from != null || range.to != null) {
      b.writeln('Rango interpretado: ${range.from ?? 'inicio'} → ${range.to ?? 'fin'}');
    }
    if (terms.isNotEmpty) b.writeln('Términos: ${terms.join(', ')}');

    if (wantsBusiness || nothingSpecific) {
      final args = <Object?>[];
      final where = <String>['t.deleted_at IS NULL'];
      final search = _whereSearch(
        ['t.description', 't.reference'],
        terms,
        args,
      );
      if (search.isNotEmpty) where.add(search);
      if (range.from != null) {
        where.add('date(t.date) >= date(?)');
        args.add(range.from);
      }
      if (range.to != null) {
        where.add('date(t.date) <= date(?)');
        args.add(range.to);
      }
      final rows = await d.rawQuery('''
        SELECT t.id,t.date,t.description,t.reference,t.cash_flow_class
        FROM transactions t
        WHERE ${where.join(' AND ')}
        ORDER BY t.date DESC,t.id DESC
        LIMIT 150
      ''', args);
      b.writeln('\n[TOOL: NEGOCIO · MOVIMIENTOS] ${rows.length} resultado(s)');
      for (final tx in rows) {
        final lines = await d.rawQuery('''
          SELECT a.code,a.name,j.debit,j.credit
          FROM journal_lines j
          JOIN accounts a ON a.id=j.account_id
          WHERE j.transaction_id=?
          ORDER BY j.id
        ''', [tx['id']]);
        b.writeln('- ${tx['date']} · ${tx['description']} · ref ${tx['reference'] ?? ''}');
        for (final l in lines) {
          b.writeln(
            '  ${l['code']} ${l['name']} | Debe ${l['debit']} | Haber ${l['credit']}',
          );
        }
      }
    }

    if (wantsPersonal || nothingSpecific) {
      final args = <Object?>[];
      final where = <String>['1=1'];
      final search = _whereSearch(
        ['t.description', 't.reference'],
        terms,
        args,
      );
      if (search.isNotEmpty) where.add(search);
      if (range.from != null) {
        where.add('date(t.date) >= date(?)');
        args.add(range.from);
      }
      if (range.to != null) {
        where.add('date(t.date) <= date(?)');
        args.add(range.to);
      }
      final rows = await d.rawQuery('''
        SELECT t.id,t.date,t.description,t.reference
        FROM personal_transactions t
        WHERE ${where.join(' AND ')}
        ORDER BY t.date DESC,t.id DESC
        LIMIT 150
      ''', args);
      b.writeln('\n[TOOL: PERSONAL · MOVIMIENTOS] ${rows.length} resultado(s)');
      for (final tx in rows) {
        final lines = await d.rawQuery('''
          SELECT a.code,a.name,l.debit,l.credit
          FROM personal_journal_lines l
          JOIN personal_accounts a ON a.id=l.account_id
          WHERE l.transaction_id=?
          ORDER BY l.id
        ''', [tx['id']]);
        b.writeln('- ${tx['date']} · ${tx['description']} · ref ${tx['reference'] ?? ''}');
        for (final l in lines) {
          b.writeln(
            '  ${l['code']} ${l['name']} | Debe ${l['debit']} | Haber ${l['credit']}',
          );
        }
      }
    }

    if (wantsBalances || nothingSpecific) {
      final business = await d.rawQuery('''
        SELECT a.code,a.name,a.type,
          COALESCE(SUM(CASE WHEN t.deleted_at IS NULL THEN j.debit-j.credit ELSE 0 END),0) AS net
        FROM accounts a
        LEFT JOIN journal_lines j ON j.account_id=a.id
        LEFT JOIN transactions t ON t.id=j.transaction_id
        GROUP BY a.id
        ORDER BY a.code
      ''');
      b.writeln('\n[TOOL: NEGOCIO · SALDOS]');
      for (final row in business) {
        final n = (row['net'] as num?)?.toDouble() ?? 0;
        if (n.abs() >= 0.005) {
          b.writeln('- ${row['code']} · ${row['name']}: ${n.toStringAsFixed(2)}');
        }
      }

      final personal = await d.rawQuery('''
        SELECT a.code,a.name,a.type,
          COALESCE(SUM(l.debit-l.credit),0) AS net
        FROM personal_accounts a
        LEFT JOIN personal_journal_lines l ON l.account_id=a.id
        GROUP BY a.id
        ORDER BY a.code
      ''');
      b.writeln('\n[TOOL: PERSONAL · SALDOS]');
      for (final row in personal) {
        final n = (row['net'] as num?)?.toDouble() ?? 0;
        if (n.abs() >= 0.005) {
          b.writeln('- ${row['code']} · ${row['name']}: ${n.toStringAsFixed(2)}');
        }
      }
    }

    if (wantsDebts || nothingSpecific) {
      final args = <Object?>[];
      final where = <String>['paid=0'];
      final search = _whereSearch(['name', 'note', 'kind'], terms, args);
      if (search.isNotEmpty) where.add(search);
      final rows = await d.query(
        'debts',
        where: where.join(' AND '),
        whereArgs: args,
        orderBy: 'due_date ASC',
        limit: 120,
      );
      b.writeln('\n[TOOL: NEGOCIO · DEUDAS/COBROS] ${rows.length} resultado(s)');
      for (final row in rows) {
        b.writeln(
          '- ${row['kind']} · ${row['name']} · ${row['amount']} · vence ${row['due_date']} · nota ${row['note'] ?? ''}',
        );
      }
    }

    if (wantsRemittances || nothingSpecific) {
      final args = <Object?>[];
      final search = _whereSearch(['client', 'status'], terms, args);
      final rows = await d.query(
        'remittances',
        where: search.isEmpty ? null : search,
        whereArgs: search.isEmpty ? null : args,
        orderBy: 'created_at DESC',
        limit: 120,
      );
      b.writeln('\n[TOOL: NEGOCIO · REMESAS] ${rows.length} resultado(s)');
      for (final row in rows) {
        b.writeln(
          '- ${row['created_at']} · ${row['client']} · principal ${row['principal']} · esperado ${row['expected']} · estado ${row['status']}',
        );
      }
    }

    if (wantsPaq || nothingSpecific) {
      final raw = await AppDatabase.instance.setting('paqueteria_snapshot');
      b.writeln('\n[TOOL: PAQUETERÍA · SOLO NEGOCIO]');
      if (raw.trim().isEmpty) {
        b.writeln('No hay snapshot sincronizado.');
      } else {
        try {
          final decoded = jsonDecode(raw);
          final matches = <String>[];
          void scan(dynamic value, [String path = 'root']) {
            if (matches.length >= 120) return;
            if (value is Map) {
              for (final e in value.entries) {
                scan(e.value, '$path.${e.key}');
                if (matches.length >= 120) return;
              }
            } else if (value is List) {
              for (var i = 0; i < value.length; i++) {
                final item = value[i];
                final text = jsonEncode(item).toLowerCase();
                final ok = terms.isEmpty || terms.every(text.contains);
                if (ok) {
                  matches.add('$path[$i]: ${jsonEncode(item)}');
                } else {
                  scan(item, '$path[$i]');
                }
                if (matches.length >= 120) return;
              }
            }
          }

          if (decoded is Map) {
            b.writeln('Resumen: ${jsonEncode(decoded['summary'] ?? const {})}');
            scan(decoded);
          } else {
            scan(decoded);
          }
          for (final m in matches) {
            if (m.length > 900) {
              b.writeln('- ${m.substring(0, 900)}…');
            } else {
              b.writeln('- $m');
            }
          }
          if (matches.isEmpty) b.writeln('No encontré coincidencias en Paquetería.');
        } catch (_) {
          b.writeln('El snapshot existe, pero no pude interpretarlo.');
        }
      }
    }

    var result = b.toString();
    // Keep local-model prompts manageable while retaining the most relevant
    // direct database results.
    if (result.length > 24000) {
      result = '${result.substring(0, 24000)}\n[Resultados truncados por tamaño]';
    }
    return result;
  }
}
