from pathlib import Path

p = Path('app/lib/packages.dart')
s = p.read_text()

def rep(old: str, new: str):
    global s
    if old not in s:
        raise SystemExit('packages anchor missing: ' + old[:80])
    s = s.replace(old, new)

rep(
    "  if (t.startsWith('TBA')) return 'Amazon';",
    "  if (t.startsWith('TBA')) return 'Amazon';\n  if (t.startsWith('SPX')) return 'SpeedX';\n  if (t.startsWith('GFUS') || RegExp(r'^GF[A-Z0-9]{8,24}$').hasMatch(t)) return 'GOFO';",
)
rep(
    "    RegExp(r'\\bTBA[A-Z0-9]{8,24}\\b'),",
    "    RegExp(r'\\bTBA[A-Z0-9]{8,24}\\b'),\n    RegExp(r'\\bSPX[A-Z0-9]{8,24}\\b'),\n    RegExp(r'\\bGFUS\\d{14}\\b'),",
)
rep(
    "class PackageEditPage extends StatefulWidget {\n  final Map<String, dynamic>? existing;\n  final String? initialTracking;\n  const PackageEditPage({super.key, this.existing, this.initialTracking});",
    "class PackageEditPage extends StatefulWidget {\n  final Map<String, dynamic>? existing;\n  final String? initialTracking;\n  final bool autoReconstruct;\n  const PackageEditPage({super.key, this.existing, this.initialTracking, this.autoReconstruct = false});",
)
rep(
    "  final tracking = TextEditingController(), weightUs = TextEditingController(), weightCu = TextEditingController(), billWeight = TextEditingController(), notes = TextEditingController();\n  List<Map<String, dynamic>> clients = [], purchases = [], recipients = [];\n  String? clientId, purchaseId, recipientId;\n  String carrier = 'Auto / Otro', status = 'Tracking creado';\n  bool loaded = false, syncing = false;",
    "  final tracking = TextEditingController(), weightUs = TextEditingController(), weightCu = TextEditingController(), billWeight = TextEditingController(), notes = TextEditingController();\n  final storeCtrl = TextEditingController(), orderCtrl = TextEditingController(), emailStatusCtrl = TextEditingController(), etaCtrl = TextEditingController();\n  List<Map<String, dynamic>> clients = [], purchases = [], recipients = [];\n  List<String> carriers = ['Auto / Otro', 'UPS', 'FedEx', 'USPS', 'DHL', 'Amazon', 'SpeedX', 'GOFO'];\n  List<String> emailPhotoPaths = [], emailPhotoUrls = [];\n  String? clientId, purchaseId, recipientId;\n  String carrier = 'Auto / Otro', status = 'Tracking creado';\n  bool loaded = false, syncing = false, reconstructing = false;",
)
rep(
    "    clients = active(r[0] as List<Map<String, dynamic>>); purchases = active(r[1] as List<Map<String, dynamic>>); recipients = active(r[2] as List<Map<String, dynamic>>);",
    "    clients = active(r[0] as List<Map<String, dynamic>>); purchases = active(r[1] as List<Map<String, dynamic>>); recipients = active(r[2] as List<Map<String, dynamic>>);\n    final settings = r[3] as Map<String, dynamic>;\n    final savedCarriers = settings['courierNames'];\n    if (savedCarriers is List) {\n      for (final value in savedCarriers) {\n        final name = '$value'.trim();\n        if (name.isNotEmpty && !carriers.contains(name)) carriers.add(name);\n      }\n    }",
)
rep(
    "    notes.text = '${widget.existing?['notes'] ?? ''}';\n    if (mounted) setState(() => loaded = true);",
    "    notes.text = '${widget.existing?['notes'] ?? ''}';\n    storeCtrl.text = '${widget.existing?['store'] ?? ''}';\n    orderCtrl.text = '${widget.existing?['orderNumber'] ?? ''}';\n    emailStatusCtrl.text = '${widget.existing?['emailStatus'] ?? ''}';\n    etaCtrl.text = '${widget.existing?['estimatedDelivery'] ?? ''}';\n    emailPhotoPaths = dynList(widget.existing?['emailPhotoPaths']).map((e) => '$e').where((e) => e.isNotEmpty).toSet().toList();\n    emailPhotoUrls = dynList(widget.existing?['emailPhotoUrls']).map((e) => '$e').where((e) => e.isNotEmpty).toSet().toList();\n    if (!carriers.contains(carrier)) carriers.add(carrier);\n    if (mounted) setState(() => loaded = true);\n    if (widget.autoReconstruct && tracking.text.trim().isNotEmpty && mounted) {\n      WidgetsBinding.instance.addPostFrameCallback((_) => reconstructFromGmail(auto: true));\n    }",
)
rep(
    "    final duplicate = rows.where((e) => e['deleted'] != true && '${e['tracking']}' == code && '${e['id']}' != '${widget.existing?['id'] ?? ''}').firstOrNull;",
    "    final duplicate = rows.where((e) => e['deleted'] != true && normalizeTracking('${e['tracking']}') == normalizeTracking(code) && '${e['id']}' != '${widget.existing?['id'] ?? ''}').firstOrNull;",
)
rep(
    "      'notes': notes.text.trim(),",
    "      'notes': notes.text.trim(),\n      'store': storeCtrl.text.trim(),\n      'orderNumber': orderCtrl.text.trim(),\n      'emailStatus': emailStatusCtrl.text.trim(),\n      'estimatedDelivery': etaCtrl.text.trim(),\n      'emailPhotoPaths': emailPhotoPaths,\n      'emailPhotoUrls': emailPhotoUrls,",
)
rep(
    "      case 'Amazon': u = Uri.parse('https://www.amazon.com/progress-tracker/package/ref=ppx_yo_dt_b_track_package'); break;",
    "      case 'Amazon': u = Uri.parse('https://www.amazon.com/progress-tracker/package/ref=ppx_yo_dt_b_track_package'); break;\n      case 'SpeedX': u = Uri.parse('https://tracking.speedx.io/${Uri.encodeComponent(tracking.text.trim())}'); break;\n      case 'GOFO': u = Uri.parse('https://www.gofoexpress.com/tracking.html?searchID=$t'); break;",
)
s = s.replace("PackageEditPage(initialTracking: code)", "PackageEditPage(initialTracking: code, autoReconstruct: true)")
p.write_text(s)
print('package Gmail core patched')
