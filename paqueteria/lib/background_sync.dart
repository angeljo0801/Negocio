part of 'main.dart';

const String courierBackgroundTask = 'courierBackgroundSync';
const String courierPeriodicWork = 'paqueteria-courier-periodic';

@pragma('vm:entry-point')
void courierCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != courierBackgroundTask) return true;
    try {
      await NotificationService.initialize(requestPermission: false);
      await EasyPostService.syncAll();
      await NotificationService.publishPendingCourierChanges();
      return true;
    } catch (_) {
      return false;
    }
  });
}

class BackgroundCourierSync {
  static Future<void> initializeAndSchedule() async {
    await Workmanager().initialize(courierCallbackDispatcher);
    await schedule();
  }

  static Future<void> schedule() async {
    await Workmanager().registerPeriodicTask(
      courierPeriodicWork,
      courierBackgroundTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      tag: 'courier-sync',
    );
  }

  static Future<void> runSoon() async {
    await Workmanager().registerOneOffTask(
      'paqueteria-courier-now',
      courierBackgroundTask,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      tag: 'courier-sync-now',
    );
  }
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize({bool requestPermission = false}) async {
    if (!_initialized) {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _plugin.initialize(settings: settings);
      _initialized = true;
    }
    if (requestPermission) {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  static Future<void> publishPendingCourierChanges() async {
    final notices = await Store.list('courierNotifications');
    final clients = active(await Store.list('clients'));
    var dirty = false;

    for (final n in notices) {
      if (n['deleted'] == true || n['notificationSent'] == true) continue;
      final client = clientName(clients, '${n['clientId'] ?? ''}');
      final tracking = '${n['tracking'] ?? ''}';
      final state = '${n['newStatusEs'] ?? 'Actualización de tracking'}';
      final id = (number(n['id']) % 2147483647).toInt();
      const android = AndroidNotificationDetails(
        'courier_updates',
        'Actualizaciones de paquetes',
        channelDescription: 'Cambios de estado de UPS, USPS, FedEx y otros couriers',
        importance: Importance.high,
        priority: Priority.high,
      );
      const details = NotificationDetails(android: android);
      await _plugin.show(
        id: id,
        title: '📦 $client · $state',
        body: tracking.isEmpty ? 'El courier reportó un cambio.' : 'Tracking: $tracking',
        notificationDetails: details,
        payload: '${n['packageId'] ?? ''}',
      );
      n['notificationSent'] = true;
      n['notificationSentAt'] = DateTime.now().toIso8601String();
      dirty = true;
    }

    if (dirty) await Store.saveList('courierNotifications', notices);
  }
}
