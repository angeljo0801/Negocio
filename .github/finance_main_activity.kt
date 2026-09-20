package com.angel.finanzas.finanzas_definitiva

import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        LocalAiManagerBridge.register(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.angel.finanzas/paqueteria_sync")
            .setMethodCallHandler { call, result ->
                if (call.method != "readSnapshot") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val uri = Uri.parse("content://com.angelapps.paqueteria.finance_sync/snapshot")
                    val stream = contentResolver.openInputStream(uri)
                    if (stream == null) {
                        result.error("PAQUETERIA_NOT_AVAILABLE", "No encontré la aplicación Paquetería o todavía no tiene datos para sincronizar.", null)
                    } else {
                        val text = stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
                        result.success(text)
                    }
                } catch (e: SecurityException) {
                    result.error("PAQUETERIA_PERMISSION", "Finanzas no tiene permiso para leer los datos locales de Paquetería. Actualiza ambas aplicaciones.", null)
                } catch (e: Exception) {
                    result.error("PAQUETERIA_NOT_AVAILABLE", "No pude leer Paquetería: " + (e.message ?: "error desconocido"), null)
                }
            }
    }
}
