import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'database.dart';

class FinanceBackupBridge {
  static const _channel = MethodChannel('com.angel.finanzas/backups');

  static Future<Map<String, dynamic>> write({
    required String fileName,
    required String content,
    bool overwrite = false,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'writeBackup',
      {
        'fileName': fileName,
        'content': content,
        'overwrite': overwrite,
      },
    );
    return Map<String, dynamic>.from(raw ?? const {});
  }

  static Future<List<Map<String, dynamic>>> list() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('listBackups');
    return (raw ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<String> read(String uri) async {
    return await _channel.invokeMethod<String>(
          'readBackup',
          {'uri': uri},
        ) ??
        '';
  }
}

class FinanceBackupService {
  static const _autoEnabledKey = 'finance_auto_backup_enabled';
  static const _lastAutoKey = 'finance_last_auto_backup_at';
  static const _formatVersion = 1;

  static bool _sensitivePref(String key) {
    final k = key.toLowerCase();
    return k.contains('api_key') ||
        k.contains('apikey') ||
        k.contains('password') ||
        k.contains('secret') ||
        k.contains('access_token') ||
        k.contains('refresh_token');
  }

  static dynamic _jsonValue(dynamic value) {
    if (value is Uint8List) {
      return {
        '__finance_type': 'bytes',
        'base64': base64Encode(value),
      };
    }
    return value;
  }

  static dynamic _dbValue(dynamic value) {
    if (value is Map && value['__finance_type'] == 'bytes') {
      final raw = value['base64']?.toString() ?? '';
      return base64Decode(raw);
    }
    return value;
  }

  static Future<Map<String, dynamic>> _buildPayload() async {
    final db = await AppDatabase.instance.db;
    final tableRows = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type='table' AND name NOT LIKE 'sqlite_%' "
      "ORDER BY name",
    );

    final tables = <String, dynamic>{};
    for (final item in tableRows) {
      final name = item['name']?.toString() ?? '';
      if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(name) ||
          name == 'android_metadata') {
        continue;
      }
      final rows = await db.query(name);
      tables[name] = [
        for (final row in rows)
          {
            for (final e in row.entries) e.key: _jsonValue(e.value),
          },
      ];
    }

    final prefs = await SharedPreferences.getInstance();
    final prefValues = <String, dynamic>{};
    final excluded = <String>[];
    for (final key in prefs.getKeys()) {
      if (_sensitivePref(key)) {
        excluded.add(key);
        continue;
      }
      final value = prefs.get(key);
      if (value is bool ||
          value is int ||
          value is double ||
          value is String) {
        prefValues[key] = value;
      } else if (value is List<String>) {
        prefValues[key] = value;
      }
    }

    return {
      'format': 'FinanzasDefinitivaBackup',
      'formatVersion': _formatVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'appData': {
        'tables': tables,
        'preferences': prefValues,
      },
      'excludedSensitivePreferences': excluded,
      'notes': {
        'modelsIncluded': false,
        'apiCredentialsIncluded': false,
        'paqueteriaPersonalIsolation': true,
      },
    };
  }

  static Future<Map<String, dynamic>> createManualBackup() async {
    final payload = await _buildPayload();
    final now = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    final name =
        'Finanzas-Backup-${now.year}${p(now.month)}${p(now.day)}-'
        '${p(now.hour)}${p(now.minute)}${p(now.second)}.json';
    return FinanceBackupBridge.write(
      fileName: name,
      content: jsonEncode(payload),
      overwrite: false,
    );
  }

  static Future<void> autoBackupIfDue() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_autoEnabledKey) ?? true;
    if (!enabled) return;
    final lastRaw = prefs.getString(_lastAutoKey);
    final last = lastRaw == null ? null : DateTime.tryParse(lastRaw);
    final now = DateTime.now();
    if (last != null && now.difference(last) < const Duration(hours: 24)) {
      return;
    }

    final payload = await _buildPayload();
    await FinanceBackupBridge.write(
      fileName: 'Finanzas-AutoBackup.json',
      content: jsonEncode(payload),
      overwrite: true,
    );
    await prefs.setString(_lastAutoKey, now.toIso8601String());
  }

  static Future<bool> autoEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoEnabledKey) ?? true;
  }

  static Future<void> setAutoEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoEnabledKey, value);
  }

  static Future<void> restoreFromUri(String uri) async {
    final content = await FinanceBackupBridge.read(uri);
    if (content.trim().isEmpty) throw Exception('La copia está vacía.');
    final decoded = jsonDecode(content);
    if (decoded is! Map ||
        decoded['format'] != 'FinanzasDefinitivaBackup') {
      throw Exception('El archivo no es una copia válida de Finanzas.');
    }
    final appData = decoded['appData'];
    if (appData is! Map) throw Exception('La copia no contiene datos.');
    final tablesRaw = appData['tables'];
    final prefsRaw = appData['preferences'];
    if (tablesRaw is! Map) {
      throw Exception('La copia no contiene tablas de datos.');
    }

    final db = await AppDatabase.instance.db;
    final existingRows = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    final existing = existingRows
        .map((e) => e['name']?.toString() ?? '')
        .where((e) => RegExp(r'^[A-Za-z0-9_]+$').hasMatch(e))
        .toSet();

    await db.transaction((txn) async {
      for (final entry in tablesRaw.entries) {
        final table = entry.key.toString();
        if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(table) ||
            !existing.contains(table) ||
            table == 'android_metadata') {
          continue;
        }
        final rows = entry.value;
        if (rows is! List) continue;

        final info = await txn.rawQuery('PRAGMA table_info("$table")');
        final columns =
            info.map((e) => e['name']?.toString() ?? '').toSet();
        await txn.rawDelete('DELETE FROM "$table"');

        for (final rawRow in rows) {
          if (rawRow is! Map) continue;
          final row = <String, Object?>{};
          for (final e in rawRow.entries) {
            final key = e.key.toString();
            if (!columns.contains(key)) continue;
            row[key] = _dbValue(e.value);
          }
          if (row.isNotEmpty) {
            await txn.insert(
              table,
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }
    });

    if (prefsRaw is Map) {
      final prefs = await SharedPreferences.getInstance();
      final keepAuto = prefs.getBool(_autoEnabledKey) ?? true;
      await prefs.clear();
      for (final e in prefsRaw.entries) {
        final key = e.key.toString();
        if (_sensitivePref(key)) continue;
        final value = e.value;
        if (value is bool) {
          await prefs.setBool(key, value);
        } else if (value is int) {
          await prefs.setInt(key, value);
        } else if (value is double) {
          await prefs.setDouble(key, value);
        } else if (value is String) {
          await prefs.setString(key, value);
        } else if (value is List) {
          await prefs.setStringList(
            key,
            value.map((e) => e.toString()).toList(),
          );
        }
      }
      if (!prefs.containsKey(_autoEnabledKey)) {
        await prefs.setBool(_autoEnabledKey, keepAuto);
      }
    }
  }
}

class FinanceBackupPage extends StatefulWidget {
  const FinanceBackupPage({super.key});

  @override
  State<FinanceBackupPage> createState() => _FinanceBackupPageState();
}

class _FinanceBackupPageState extends State<FinanceBackupPage> {
  bool loading = true;
  bool working = false;
  bool autoEnabled = true;
  List<Map<String, dynamic>> backups = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await FinanceBackupService.autoEnabled();
    final list = await FinanceBackupBridge.list();
    if (!mounted) return;
    setState(() {
      autoEnabled = enabled;
      backups = list;
      loading = false;
    });
  }

  Future<void> _create() async {
    setState(() => working = true);
    try {
      final result = await FinanceBackupService.createManualBackup();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Copia creada en Descargas/FinanzasDefinitiva: ' +
                (result['name']?.toString() ?? 'backup'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pude crear la copia: $e')),
      );
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _restore(Map<String, dynamic> item) async {
    final name = item['name']?.toString() ?? 'copia';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restaurar copia'),
        content: Text(
          'Se reemplazarán los datos actuales de Finanzas con "$name". '
          'La aplicación se cerrará al terminar para cargar la base restaurada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => working = true);
    try {
      await FinanceBackupService.restoreFromUri(
        item['uri']?.toString() ?? '',
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Copia restaurada'),
          content: const Text(
            'Los datos se restauraron correctamente. Finanzas se cerrará ahora; '
            'ábrela de nuevo para continuar.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                SystemNavigator.pop();
              },
              child: const Text('Cerrar Finanzas'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pude restaurar la copia: $e')),
      );
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  String _date(Map<String, dynamic> item) {
    final ms = (item['modifiedMs'] as num?)?.toInt();
    if (ms == null || ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)} '
        '${p(d.hour)}:${p(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Copias de seguridad')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Card(
                  child: SwitchListTile(
                    title: const Text('Copia automática diaria'),
                    subtitle: const Text(
                      'Se guarda fuera de la app en Descargas/FinanzasDefinitiva '
                      'para que sobreviva a una desinstalación.',
                    ),
                    value: autoEnabled,
                    onChanged: working
                        ? null
                        : (value) async {
                            await FinanceBackupService.setAutoEnabled(value);
                            if (mounted) {
                              setState(() => autoEnabled = value);
                            }
                          },
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: working ? null : _create,
                  icon: const Icon(Icons.backup_outlined),
                  label: Text(
                    working ? 'Procesando…' : 'Crear copia ahora',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'La copia incluye la base de datos, conversaciones y '
                  'preferencias no sensibles. No copia modelos GGUF ni claves '
                  'API/contraseñas.',
                ),
                const Divider(height: 28),
                Text(
                  'Copias disponibles',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                if (backups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'Todavía no hay copias en Descargas/FinanzasDefinitiva.',
                    ),
                  ),
                for (final item in backups)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.restore_outlined),
                      title: Text(item['name']?.toString() ?? 'Backup'),
                      subtitle: Text(_date(item)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: working ? null : () => _restore(item),
                    ),
                  ),
              ],
            ),
    );
  }
}
