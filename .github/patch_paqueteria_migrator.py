from pathlib import Path

manifest = Path('migrator/android/app/src/main/AndroidManifest.xml')
m = manifest.read_text()
open_tag = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
permission = 'com.angelapps.paqueteria.permission.FINANCE_SYNC'
if permission not in m:
    m = m.replace(open_tag, open_tag + f'\n    <uses-permission android:name="{permission}" />', 1)
if 'com.angelapps.paqueteria.finance_sync' not in m:
    queries = '''    <queries>
        <provider android:authorities="com.angelapps.paqueteria.finance_sync" />
    </queries>
'''
    m = m.replace('    <application', queries + '    <application', 1)
m = m.replace('android:label="paqueteria_migrator"', 'android:label="Paquetería Migrador"')
manifest.write_text(m)

kotlin = Path('migrator/android/app/src/main/kotlin/com/angelapps/migrator/paqueteria_migrator/MainActivity.kt')
kotlin.parent.mkdir(parents=True, exist_ok=True)
kotlin.write_text(r'''package com.angelapps.migrator.paqueteria_migrator

import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "paqueteria_legacy_migrator"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "readSnapshot" -> readSnapshot(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun readSnapshot(result: MethodChannel.Result) {
        try {
            val uri = Uri.parse("content://com.angelapps.paqueteria.finance_sync/snapshot")
            val stream = contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("No se pudo abrir el respaldo de Paquetería.")
            val text = stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            if (text.isBlank()) throw IllegalStateException("La Paquetería instalada devolvió un respaldo vacío.")
            result.success(text)
        } catch (security: SecurityException) {
            result.error("permission", "Android no permitió leer el respaldo local de Paquetería.", security.message)
        } catch (e: Exception) {
            result.error("read_failed", "No pude leer los datos de la Paquetería instalada. Ábrela una vez y vuelve a intentarlo.", e.message)
        }
    }
}
''')
print('Paqueteria migrator Android bridge patched')
