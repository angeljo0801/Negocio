from pathlib import Path

p = Path('app/lib/purchases.dart')
s = p.read_text()
anchor = "  Future<void> editItem([Map<String, dynamic>? item]) async {"
if anchor not in s:
    raise SystemExit('editItem anchor missing')
methods = r'''  List<String> currentTrackingNumbers() => trackingCtrl.text
      .split(RegExp(r'[\s,;]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

  Future<void> reconstructFromGmail({bool silent = false}) async {
    final value = order.text.trim();
    if (value.isEmpty || gmailLoading) {
      if (!silent && value.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escribe primero el número de orden.')));
      }
      return;
    }
    setState(() => gmailLoading = true);
    try {
      final r = await GmailReconstructionService.byOrder(value);
      if (!r.found) {
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No encontré correos para ese número de orden.')));
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        if (store.text.trim().isEmpty && r.store.isNotEmpty) store.text = r.store;
        if (r.orderNumber.isNotEmpty) order.text = r.orderNumber;
        if (number(total.text) <= 0 && r.total > 0) total.text = r.total.toStringAsFixed(2);
        if (number(subtotalCtrl.text) <= 0 && r.subtotal > 0) subtotalCtrl.text = r.subtotal.toStringAsFixed(2);
        if (number(taxCtrl.text) <= 0 && r.tax > 0) taxCtrl.text = r.tax.toStringAsFixed(2);
        if (number(shippingCtrl.text) <= 0 && r.shipping > 0) shippingCtrl.text = r.shipping.toStringAsFixed(2);
        if (number(discountCtrl.text) <= 0 && r.discount > 0) discountCtrl.text = r.discount.toStringAsFixed(2);
        if (r.currency.isNotEmpty) currencyCtrl.text = r.currency;
        emailStatusCtrl.text = r.status;
        etaCtrl.text = r.estimatedDelivery;
        if (shipToCtrl.text.trim().isEmpty) shipToCtrl.text = r.shipToName;
        trackingCtrl.text = {...currentTrackingNumbers(), ...r.trackingNumbers}.join(', ');
        emailPhotoPaths = {...emailPhotoPaths, ...r.emailPhotoPaths}.toList();
        emailPhotoUrls = {...emailPhotoUrls, ...r.emailPhotoUrls}.toList();
        if (items.isEmpty && r.items.isNotEmpty) {
          items = r.items.map((e) => {...e, 'clientId': clientId ?? '', 'received': e['received'] == true}).toList();
        }
        if (r.status.isNotEmpty && ['Pendiente de comprar', 'Comprado', 'Preparando envío', 'En tránsito', 'Sale para entrega'].contains(status)) {
          status = r.status;
        }
        ocrMeta = {
          ...ocrMeta,
          'gmail': true,
          'gmailSyncedAt': r.syncedAt,
          'emailSubjects': r.subjects,
          'emailFrom': r.senders,
          'lastEmailDate': r.lastEmailDate,
        };
      });
      if (widget.existing != null) await syncPackagesFromGmail(r);
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Actualizado desde Gmail${r.store.isEmpty ? '' : ' · ${r.store}'}')));
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => gmailLoading = false);
    }
  }

  Future<void> syncPackagesFromGmail(
    GmailPurchaseReconstruction r, {
    String? purchaseIdOverride,
  }) async {
    final targetPurchaseId = purchaseIdOverride ?? '${widget.existing?['id'] ?? ''}';
    if (targetPurchaseId.isEmpty || r.trackingNumbers.isEmpty) return;
    final rows = await Store.list('packages');
    var dirty = false;
    for (final code in r.trackingNumbers) {
      final normalized = normalizeTracking(code);
      final i = rows.indexWhere(
        (x) => x['deleted'] != true && normalizeTracking('${x['tracking'] ?? ''}') == normalized,
      );
      if (i >= 0) {
        final current = rows[i];
        rows[i] = {
          ...current,
          'purchaseId': targetPurchaseId,
          if ('${current['clientId'] ?? ''}'.trim().isEmpty && clientId != null) 'clientId': clientId,
          if ('${current['carrier'] ?? ''}'.trim().isEmpty || current['carrier'] == 'Auto / Otro') 'carrier': r.carrier,
          if ('${current['store'] ?? ''}'.trim().isEmpty) 'store': r.store,
          if ('${current['orderNumber'] ?? ''}'.trim().isEmpty) 'orderNumber': r.orderNumber,
          'emailStatus': r.status,
          'estimatedDelivery': r.estimatedDelivery,
        };
        dirty = true;
      } else if (clientId != null) {
        rows.add({
          'id': newId(),
          'tracking': code,
          'carrier': r.carrier.isEmpty ? inferCarrier(code) : r.carrier,
          'clientId': clientId,
          'purchaseId': targetPurchaseId,
          'recipientId': null,
          'weightUs': 0.0,
          'weightCu': 0.0,
          'billWeight': 0.0,
          'status': r.status == 'Sale para entrega'
              ? 'Sale para entrega'
              : (r.status == 'En tránsito' ? 'En tránsito' : 'Tracking creado'),
          'store': r.store,
          'orderNumber': r.orderNumber,
          'emailStatus': r.status,
          'estimatedDelivery': r.estimatedDelivery,
          'notes': '',
          'deleted': false,
        });
        dirty = true;
      }
    }
    if (dirty) await Store.saveList('packages', rows);
  }

'''
s = s.replace(anchor, methods + anchor)

old = "    await Store.saveList('purchases', rows);\n    if (!mounted) return;"
new = """    await Store.saveList('purchases', rows);
    if (currentTrackingNumbers().isNotEmpty) {
      final rebuilt = GmailPurchaseReconstruction(
        found: true,
        store: store.text.trim(),
        orderNumber: order.text.trim(),
        trackingNumbers: currentTrackingNumbers(),
        carrier: currentTrackingNumbers().isEmpty ? 'Auto / Otro' : inferCarrier(currentTrackingNumbers().first),
        status: emailStatusCtrl.text.trim(),
        estimatedDelivery: etaCtrl.text.trim(),
        shipToName: shipToCtrl.text.trim(),
        subtotal: number(subtotalCtrl.text),
        tax: number(taxCtrl.text),
        shipping: number(shippingCtrl.text),
        discount: number(discountCtrl.text),
        total: base,
        currency: currencyCtrl.text.trim(),
        items: items,
        emailPhotoUrls: emailPhotoUrls,
        emailPhotoPaths: emailPhotoPaths,
        subjects: const [],
        senders: const [],
        lastEmailDate: '',
        syncedAt: '${ocrMeta['gmailSyncedAt'] ?? ''}',
      );
      await syncPackagesFromGmail(rebuilt, purchaseIdOverride: '${item['id']}');
    }
    if (!mounted) return;"""
if old not in s:
    raise SystemExit('purchase save-list anchor missing')
s = s.replace(old, new, 1)
p.write_text(s)
print('purchase Gmail methods patched')
