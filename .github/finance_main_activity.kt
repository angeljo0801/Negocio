package com.angel.finanzas.finanzas_definitiva

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Notification
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import java.util.Calendar
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object CardReminderScheduler {
    private const val PREFS = "personal_card_reminders"
    private const val CHANNEL_ID = "credit_card_payments"

    private fun requestCode(id: Int): Int = 410000 + (id % 100000)

    private fun nextReminderMillis(dueDay: Int, daysBefore: Int): Long {
        val now = Calendar.getInstance()
        fun candidate(monthOffset: Int): Calendar {
            val due = Calendar.getInstance()
            due.set(Calendar.SECOND, 0)
            due.set(Calendar.MILLISECOND, 0)
            due.set(Calendar.HOUR_OF_DAY, 9)
            due.set(Calendar.MINUTE, 0)
            due.add(Calendar.MONTH, monthOffset)
            val maxDay = due.getActualMaximum(Calendar.DAY_OF_MONTH)
            due.set(Calendar.DAY_OF_MONTH, dueDay.coerceIn(1, maxDay))
            due.add(Calendar.DAY_OF_MONTH, -daysBefore.coerceIn(0, 30))
            return due
        }
        var target = candidate(0)
        if (target.timeInMillis <= now.timeInMillis + 60_000L) {
            target = candidate(1)
        }
        return target.timeInMillis
    }

    fun schedule(
        context: Context,
        id: Int,
        title: String,
        bank: String,
        dueDay: Int,
        daysBefore: Int,
        persist: Boolean = true
    ) {
        if (dueDay !in 1..31) return
        if (persist) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(
                    id.toString(),
                    listOf(title, bank, dueDay.toString(), daysBefore.toString())
                        .joinToString("\u001f")
                )
                .apply()
        }

        val intent = Intent(context, CardPaymentReminderReceiver::class.java).apply {
            putExtra("id", id)
            putExtra("title", title)
            putExtra("bank", bank)
            putExtra("dueDay", dueDay)
            putExtra("daysBefore", daysBefore)
        }
        val pending = PendingIntent.getBroadcast(
            context,
            requestCode(id),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            nextReminderMillis(dueDay, daysBefore),
            pending
        )
    }

    fun cancel(context: Context, id: Int) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(id.toString())
            .apply()
        val intent = Intent(context, CardPaymentReminderReceiver::class.java)
        val pending = PendingIntent.getBroadcast(
            context,
            requestCode(id),
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        if (pending != null) {
            val alarmManager =
                context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.cancel(pending)
            pending.cancel()
        }
    }

    fun rescheduleAll(context: Context) {
        val all = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).all
        all.forEach { (key, value) ->
            val id = key.toIntOrNull() ?: return@forEach
            val parts = value?.toString()?.split("\u001f") ?: return@forEach
            if (parts.size < 4) return@forEach
            val dueDay = parts[2].toIntOrNull() ?: return@forEach
            val daysBefore = parts[3].toIntOrNull() ?: 1
            schedule(
                context,
                id,
                parts[0],
                parts[1],
                dueDay,
                daysBefore,
                persist = false
            )
        }
    }

    fun showNotification(
        context: Context,
        id: Int,
        title: String,
        bank: String,
        dueDay: Int,
        daysBefore: Int
    ) {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Pagos de tarjetas",
            NotificationManager.IMPORTANCE_HIGH
        )
        channel.description = "Recordatorios de vencimiento de tarjetas de crédito"
        manager.createNotificationChannel(channel)

        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentIntent = if (launch != null) {
            PendingIntent.getActivity(
                context,
                requestCode(id) + 100000,
                launch,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else null

        val whenText = when (daysBefore) {
            0 -> "vence hoy"
            1 -> "vence mañana"
            else -> "vence en $daysBefore días"
        }
        val bankText = if (bank.isBlank()) "" else "$bank · "
        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle("Pago de tarjeta · $title")
            .setContentText("$bankText$whenText · día de pago $dueDay")
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()
        manager.notify(requestCode(id), notification)
    }
}

class CardPaymentReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", 0)
        val title = intent.getStringExtra("title") ?: "Tarjeta de crédito"
        val bank = intent.getStringExtra("bank") ?: ""
        val dueDay = intent.getIntExtra("dueDay", 0)
        val daysBefore = intent.getIntExtra("daysBefore", 1)
        if (id == 0 || dueDay !in 1..31) return

        if (Build.VERSION.SDK_INT < 33 ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        ) {
            CardReminderScheduler.showNotification(
                context,
                id,
                title,
                bank,
                dueDay,
                daysBefore
            )
        }
        CardReminderScheduler.schedule(
            context,
            id,
            title,
            bank,
            dueDay,
            daysBefore,
            persist = false
        )
    }
}

class ReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            CardReminderScheduler.rescheduleAll(context)
        }
    }
}

class MainActivity : FlutterActivity() {
    private var notificationPermissionResult: MethodChannel.Result? = null
    private val notificationPermissionRequest = 9021

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        LocalAiManagerBridge.register(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.angel.finanzas/paqueteria_sync"
        ).setMethodCallHandler { call, result ->
            if (call.method != "readSnapshot") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                val uri = Uri.parse(
                    "content://com.angelapps.paqueteria.finance_sync/snapshot"
                )
                val stream = contentResolver.openInputStream(uri)
                if (stream == null) {
                    result.error(
                        "PAQUETERIA_NOT_AVAILABLE",
                        "No encontré la aplicación Paquetería o todavía no tiene datos para sincronizar.",
                        null
                    )
                } else {
                    val text =
                        stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
                    result.success(text)
                }
            } catch (e: SecurityException) {
                result.error(
                    "PAQUETERIA_PERMISSION",
                    "Finanzas no tiene permiso para leer los datos locales de Paquetería. Actualiza ambas aplicaciones.",
                    null
                )
            } catch (e: Exception) {
                result.error(
                    "PAQUETERIA_NOT_AVAILABLE",
                    "No pude leer Paquetería: " +
                        (e.message ?: "error desconocido"),
                    null
                )
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.angel.finanzas/personal_reminders"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT < 33 ||
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                            PackageManager.PERMISSION_GRANTED
                    ) {
                        result.success(true)
                    } else {
                        if (notificationPermissionResult != null) {
                            result.error(
                                "PERMISSION_PENDING",
                                "Ya hay una solicitud de permiso activa.",
                                null
                            )
                        } else {
                            notificationPermissionResult = result
                            requestPermissions(
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                notificationPermissionRequest
                            )
                        }
                    }
                }
                "schedule" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val title = call.argument<String>("title") ?: "Tarjeta de crédito"
                    val bank = call.argument<String>("bank") ?: ""
                    val dueDay = call.argument<Int>("dueDay") ?: 0
                    val daysBefore = call.argument<Int>("daysBefore") ?: 1
                    if (id <= 0 || dueDay !in 1..31) {
                        result.error(
                            "INVALID_REMINDER",
                            "Faltan datos válidos para programar la alarma.",
                            null
                        )
                    } else {
                        CardReminderScheduler.schedule(
                            applicationContext,
                            id,
                            title,
                            bank,
                            dueDay,
                            daysBefore
                        )
                        result.success(true)
                    }
                }
                "cancel" -> {
                    val id = call.argument<Int>("id") ?: 0
                    if (id > 0) {
                        CardReminderScheduler.cancel(applicationContext, id)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notificationPermissionRequest) {
            val granted =
                grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            notificationPermissionResult?.success(granted)
            notificationPermissionResult = null
        }
    }
}
