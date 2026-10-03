from pathlib import Path

service = Path('app/lib/gmail_reconstruction.dart')
s = service.read_text()
s = s.replace(
    "  static Future<GmailPurchaseReconstruction> byOrder(String orderNumber) =>\n      _reconstruct(orderNumber: orderNumber);",
    "  static Future<GmailPurchaseReconstruction> byOrder(String orderNumber, {bool downloadImages = true}) =>\n      _reconstruct(orderNumber: orderNumber, downloadImages: downloadImages);",
)
s = s.replace(
    "  static Future<GmailPurchaseReconstruction> _reconstruct({\n    String orderNumber = '',\n    String tracking = '',\n  }) async {",
    "  static Future<GmailPurchaseReconstruction> _reconstruct({\n    String orderNumber = '',\n    String tracking = '',\n    bool downloadImages = true,\n  }) async {",
)
s = s.replace(
    "    if (attachmentRows is List) {\n      for (final row in attachmentRows.whereType<Map>()) {",
    "    if (downloadImages && attachmentRows is List) {\n      for (final row in attachmentRows.whereType<Map>()) {",
)
append = r'''

class GmailBackgroundPurchaseSync {
  static Future<void> syncIfDue() async {
    final settings = await Store.settings();
    final last = DateTime.tryParse('${settings['gmailLastBackgroundSync'] ?? ''}');
    if (last != null && DateTime.now().difference(last).inMinutes < 60) return;
    try {
      final status = await GmailReconstructionService.gmailStatus();
      if (status['connected'] != true) return;
    } catch (_) {
      return;
    }

    final rows = await Store.list('purchases');
    var dirty = false;
    var checked = 0;
    for (var i = 0; i < rows.length && checked < 50; i++) {
      final purchase = rows[i];
      if (purchase['deleted'] == true) continue;
      final order = '${purchase['orderNumber'] ?? ''}'.trim();
      if (order.isEmpty) continue;
      checked++;
      try {
        final result = await GmailReconstructionService.byOrder(order, downloadImages: false);
        if (!result.found) continue;
        final currentStatus = '${purchase['status'] ?? ''}';
        final emailManaged = {
          'Pendiente de comprar',
          'Comprado',
          'Preparando envío',
          'En tránsito',
          'Sale para entrega',
          'Entregado',
        }.contains(currentStatus);
        rows[i] = {
          ...purchase,
          'emailStatus': result.status,
          if (emailManaged && result.status.isNotEmpty) 'status': result.status,
          if (result.store.isNotEmpty && '${purchase['store'] ?? ''}'.trim().isEmpty) 'store': result.store,
          'trackingNumbers': {
            ...dynList(purchase['trackingNumbers']).map((e) => '$e'),
            ...result.trackingNumbers,
          }.toList(),
          if (result.estimatedDelivery.isNotEmpty) 'estimatedDelivery': result.estimatedDelivery,
          'gmailSyncedAt': result.syncedAt,
        };
        dirty = true;
      } catch (_) {}
    }
    if (dirty) await Store.saveList('purchases', rows);
    settings['gmailLastBackgroundSync'] = DateTime.now().toIso8601String();
    await Store.saveSettings(settings);
  }
}
'''
if 'class GmailBackgroundPurchaseSync' not in s:
    s += append
service.write_text(s)

background = Path('app/lib/background_sync.dart')
b = background.read_text()
old = "      await EasyPostService.syncAll();\n      await NotificationService.publishPendingCourierChanges();"
new = "      await EasyPostService.syncAll();\n      await GmailBackgroundPurchaseSync.syncIfDue();\n      await NotificationService.publishPendingCourierChanges();"
if old not in b:
    raise SystemExit('background courier anchor missing')
background.write_text(b.replace(old, new))
print('Gmail background purchase sync patched')
