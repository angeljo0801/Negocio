from pathlib import Path

p = Path('app/lib/packages.dart')
s = p.read_text()
anchor = "  void autoBillWeight() {"
if anchor not in s:
    raise SystemExit('autoBillWeight anchor missing')
methods = r'''  Future<void> manageCarriers() async {
    final ctrl = TextEditingController(text: carriers.where((e) => e != 'Auto / Otro').join('\n'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Agencias / couriers'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: ctrl,
            minLines: 8,
            maxLines: 14,
            decoration: const InputDecoration(
              labelText: 'Un nombre por línea',
              helperText: 'Puedes añadir nombres nuevos. SpeedX y GOFO vienen incluidos.',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    final next = <String>['Auto / Otro'];
    for (final line in ctrl.text.split('\n')) {
      final name = line.trim();
      if (name.isNotEmpty && !next.contains(name)) next.add(name);
    }
    final settings = await Store.settings();
    settings['courierNames'] = next.where((e) => e != 'Auto / Otro').toList();
    await Store.saveSettings(settings);
    if (!mounted) return;
    setState(() {
      carriers = next;
      if (!carriers.contains(carrier)) carrier = 'Auto / Otro';
    });
  }

  Future<void> reconstructFromGmail({bool auto = false}) async {
    final code = tracking.text.trim();
    if (code.isEmpty || reconstructing) return;
    setState(() => reconstructing = true);
    try {
      final r = await GmailReconstructionService.byTracking(code);
      if (!r.found) {
        if (!auto && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No encontré ese tracking en Gmail.')));
        }
        return;
      }
      final allPurchases = await Store.list('purchases');
      Map<String, dynamic>? linked;
      if (r.orderNumber.isNotEmpty) {
        linked = active(allPurchases)
            .where((x) => normalizeOrderNumber('${x['orderNumber'] ?? ''}') == normalizeOrderNumber(r.orderNumber))
            .firstOrNull;
      }
      linked ??= active(allPurchases).where((x) {
        final values = x['trackingNumbers'];
        return values is List && values.any((v) => normalizeTracking('$v') == normalizeTracking(code));
      }).firstOrNull;

      if (linked == null) {
        Map<String, dynamic>? matchedClient;
        if (r.shipToName.isNotEmpty) {
          matchedClient = clients.where((c) {
            final name = '${c['name'] ?? ''}'.trim().toLowerCase();
            return name.isNotEmpty && r.shipToName.toLowerCase().contains(name);
          }).firstOrNull;
        }
        final created = <String, dynamic>{
          'id': newId(),
          'clientId': matchedClient?['id']?.toString() ?? '',
          'type': 'Online',
          'store': r.store,
          'description': r.items.take(4).map((e) => '${e['name']}').join(', '),
          'total': r.total,
          'commissionPct': 0.0,
          'clientTotal': 0.0,
          'status': r.status.isEmpty ? 'Comprado' : r.status,
          'emailStatus': r.status,
          'orderNumber': r.orderNumber,
          'trackingNumbers': r.trackingNumbers,
          'date': today(),
          'subtotal': r.subtotal,
          'tax': r.tax,
          'shipping': r.shipping,
          'discount': r.discount,
          'currency': r.currency,
          'estimatedDelivery': r.estimatedDelivery,
          'shipToName': r.shipToName,
          'emailPhotoPaths': r.emailPhotoPaths,
          'emailPhotoUrls': r.emailPhotoUrls,
          'emailSubjects': r.subjects,
          'emailFrom': r.senders,
          'lastEmailDate': r.lastEmailDate,
          'gmailSyncedAt': r.syncedAt,
          'items': r.items,
          'allocations': <Map<String, dynamic>>[],
          'unassigned': matchedClient == null,
          'deleted': false,
        };
        allPurchases.add(created);
        linked = created;
      } else {
        final i = allPurchases.indexWhere((x) => '${x['id']}' == '${linked!['id']}');
        if (i >= 0) {
          final current = allPurchases[i];
          allPurchases[i] = {
            ...current,
            if ('${current['store'] ?? ''}'.trim().isEmpty && r.store.isNotEmpty) 'store': r.store,
            if ('${current['orderNumber'] ?? ''}'.trim().isEmpty && r.orderNumber.isNotEmpty) 'orderNumber': r.orderNumber,
            if (number(current['total']) <= 0 && r.total > 0) 'total': r.total,
            if ((current['items'] is! List || (current['items'] as List).isEmpty) && r.items.isNotEmpty) 'items': r.items,
            'emailStatus': r.status,
            'trackingNumbers': {...dynList(current['trackingNumbers']).map((e) => '$e'), ...r.trackingNumbers}.toList(),
            'estimatedDelivery': r.estimatedDelivery,
            'shipToName': r.shipToName,
            'emailPhotoPaths': {...dynList(current['emailPhotoPaths']).map((e) => '$e'), ...r.emailPhotoPaths}.toList(),
            'emailPhotoUrls': {...dynList(current['emailPhotoUrls']).map((e) => '$e'), ...r.emailPhotoUrls}.toList(),
            'emailSubjects': r.subjects,
            'emailFrom': r.senders,
            'lastEmailDate': r.lastEmailDate,
            'gmailSyncedAt': r.syncedAt,
          };
          linked = allPurchases[i];
        }
      }
      await Store.saveList('purchases', allPurchases);
      if (!mounted) return;
      setState(() {
        purchases = active(allPurchases);
        purchaseId = '${linked!['id']}';
        final linkedClient = '${linked!['clientId'] ?? ''}'.trim();
        if (clientId == null && linkedClient.isNotEmpty) clientId = linkedClient;
        if (r.carrier.isNotEmpty) {
          carrier = r.carrier;
          if (!carriers.contains(carrier)) carriers.add(carrier);
        }
        if (storeCtrl.text.trim().isEmpty) storeCtrl.text = r.store;
        if (orderCtrl.text.trim().isEmpty) orderCtrl.text = r.orderNumber;
        emailStatusCtrl.text = r.status;
        etaCtrl.text = r.estimatedDelivery;
        emailPhotoPaths = {...emailPhotoPaths, ...r.emailPhotoPaths}.toList();
        emailPhotoUrls = {...emailPhotoUrls, ...r.emailPhotoUrls}.toList();
      });
      if (!auto && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Compra reconstruida desde Gmail${r.store.isEmpty ? '' : ' · ${r.store}'}')));
      }
    } catch (e) {
      if (!auto && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => reconstructing = false);
    }
  }

'''
s = s.replace(anchor, methods + anchor)
p.write_text(s)
print('package Gmail methods patched')
