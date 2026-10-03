from pathlib import Path

# Flutter does not expose Icons.mail_search_outlined.
for name in ['packages.dart', 'purchases.dart']:
    path = Path('app/lib') / name
    text = path.read_text().replace('Icons.mail_search_outlined', 'Icons.manage_search')
    path.write_text(text)

p = Path('app/lib/purchases.dart')
s = p.read_text()

# An earlier broad replacement can land the post-save package sync in assignClient.
bad_start = "    await Store.saveList('purchases', rows);\n    if (currentTrackingNumbers().isNotEmpty) {"
if bad_start in s:
    start = s.index(bad_start)
    end_marker = "    if (!mounted) return;"
    end = s.index(end_marker, start) + len(end_marker)
    s = s[:start] + "    await Store.saveList('purchases', rows);\n    if (!mounted) return;" + s[end:]

# Insert the package-linking pass only inside PurchaseEditPage.save().
save_start = s.index('  Future<void> save() async {', s.index('class _PurchaseEditPageState'))
save_store = s.index("    await Store.saveList('purchases', rows);", save_start)
return_pos = s.index('    if (!mounted) return;', save_store)
insert = """    if (currentTrackingNumbers().isNotEmpty) {
      final rebuilt = GmailPurchaseReconstruction(
        found: true,
        store: store.text.trim(),
        orderNumber: order.text.trim(),
        trackingNumbers: currentTrackingNumbers(),
        carrier: inferCarrier(currentTrackingNumbers().first),
        status: emailStatusCtrl.text.trim(),
        estimatedDelivery: etaCtrl.text.trim(),
        shipToName: shipToCtrl.text.trim(),
        subtotal: number(subtotalCtrl.text),
        tax: number(taxCtrl.text),
        shipping: number(shippingCtrl.text),
        discount: number(discountCtrl.text),
        total: base,
        currency: currencyCtrl.text.trim().isEmpty ? 'USD' : currencyCtrl.text.trim(),
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
"""
if 'final rebuilt = GmailPurchaseReconstruction(' not in s[save_store:return_pos]:
    s = s[:return_pos] + insert + s[return_pos:]

p.write_text(s)
print('final Gmail build fixes applied')
