from pathlib import Path

p = Path('app/lib/purchases.dart')
s = p.read_text()

def rep(old: str, new: str):
    global s
    if old not in s:
        raise SystemExit('purchase anchor missing: ' + old[:90])
    s = s.replace(old, new)

rep(
    "  final store = TextEditingController(), desc = TextEditingController(), total = TextEditingController(), order = TextEditingController(), date = TextEditingController();",
    "  final store = TextEditingController(), desc = TextEditingController(), total = TextEditingController(), order = TextEditingController(), date = TextEditingController();\n  final subtotalCtrl = TextEditingController(), taxCtrl = TextEditingController(), shippingCtrl = TextEditingController(), discountCtrl = TextEditingController(), currencyCtrl = TextEditingController(text: 'USD');\n  final emailStatusCtrl = TextEditingController(), etaCtrl = TextEditingController(), shipToCtrl = TextEditingController(), trackingCtrl = TextEditingController();",
)
rep(
    "  List<String> photoPaths = [];\n  bool loaded = false;",
    "  List<String> photoPaths = [];\n  List<String> emailPhotoPaths = [], emailPhotoUrls = [];\n  bool loaded = false, gmailLoading = false;",
)
rep(
    "      items = purchaseItems(widget.existing!);",
    "      items = purchaseItems(widget.existing!);\n      subtotalCtrl.text = '${widget.existing!['subtotal'] ?? ''}';\n      taxCtrl.text = '${widget.existing!['tax'] ?? ''}';\n      shippingCtrl.text = '${widget.existing!['shipping'] ?? ''}';\n      discountCtrl.text = '${widget.existing!['discount'] ?? ''}';\n      currencyCtrl.text = '${widget.existing!['currency'] ?? 'USD'}';\n      emailStatusCtrl.text = '${widget.existing!['emailStatus'] ?? ''}';\n      etaCtrl.text = '${widget.existing!['estimatedDelivery'] ?? ''}';\n      shipToCtrl.text = '${widget.existing!['shipToName'] ?? ''}';\n      trackingCtrl.text = dynList(widget.existing!['trackingNumbers']).map((e) => '$e').join(', ');\n      emailPhotoPaths = dynList(widget.existing!['emailPhotoPaths']).map((e) => '$e').where((e) => e.isNotEmpty).toSet().toList();\n      emailPhotoUrls = dynList(widget.existing!['emailPhotoUrls']).map((e) => '$e').where((e) => e.isNotEmpty).toSet().toList();",
)
rep(
    "    if (widget.startWithReceipt && widget.existing == null && mounted) {\n      WidgetsBinding.instance.addPostFrameCallback((_) => importReceipt());\n    }",
    "    if (widget.startWithReceipt && widget.existing == null && mounted) {\n      WidgetsBinding.instance.addPostFrameCallback((_) => importReceipt());\n    } else if (widget.existing != null && order.text.trim().isNotEmpty && mounted) {\n      final last = DateTime.tryParse('${widget.existing!['gmailSyncedAt'] ?? ''}');\n      if (last == null || DateTime.now().difference(last).inMinutes >= 30) {\n        WidgetsBinding.instance.addPostFrameCallback((_) => reconstructFromGmail(silent: true));\n      }\n    }",
)
rep(
    "      'clientId': assigned ?? '',\n    };",
    "      'clientId': assigned ?? '',\n      'received': item?['received'] == true,\n    };",
)
rep(
    "    final rows = await Store.list('purchases');\n    final item = {",
    "    final rows = await Store.list('purchases');\n    final normalizedOrder = normalizeOrderNumber(order.text);\n    if (normalizedOrder.isNotEmpty) {\n      final duplicate = rows.where((e) => e['deleted'] != true && normalizeOrderNumber('${e['orderNumber'] ?? ''}') == normalizedOrder && '${e['id']}' != '${widget.existing?['id'] ?? ''}').firstOrNull;\n      if (duplicate != null) {\n        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ya existe una compra con ese número de orden. Abre la existente para evitar duplicados.')));\n        return;\n      }\n    }\n    final item = {",
)
rep(
    "      'orderNumber': order.text.trim(),\n      'date': date.text.trim().isEmpty ? today() : date.text.trim(),",
    "      'orderNumber': order.text.trim(),\n      'trackingNumbers': currentTrackingNumbers(),\n      'subtotal': number(subtotalCtrl.text),\n      'tax': number(taxCtrl.text),\n      'shipping': number(shippingCtrl.text),\n      'discount': number(discountCtrl.text),\n      'currency': currencyCtrl.text.trim().isEmpty ? 'USD' : currencyCtrl.text.trim(),\n      'emailStatus': emailStatusCtrl.text.trim(),\n      'estimatedDelivery': etaCtrl.text.trim(),\n      'shipToName': shipToCtrl.text.trim(),\n      'emailPhotoPaths': emailPhotoPaths,\n      'emailPhotoUrls': emailPhotoUrls,\n      'gmailSyncedAt': ocrMeta['gmailSyncedAt'] ?? widget.existing?['gmailSyncedAt'],\n      'date': date.text.trim().isEmpty ? today() : date.text.trim(),",
)
p.write_text(s)
print('purchase Gmail core patched')
