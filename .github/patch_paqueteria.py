from pathlib import Path

trip = Path('app/lib/trips.dart')
ts = trip.read_text().replace("Tarifa $/lb", "Tarifa \\$/lb")
ts = ts.replace(
    "appBar:AppBar(title:const Text('Viajes'))",
    "appBar:AppBar(title:const Text('Viajes'),actions:[IconButton(tooltip:'Envíos por agencia',icon:const Icon(Icons.local_shipping),onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const AgencyShipmentsPage())))])"
)
trip.write_text(ts)

packages = Path('app/lib/packages.dart')
ps = packages.read_text()
ps = ps.replace(
    "clients = active(r[0]); purchases = active(r[1]); recipients = active(r[2]);",
    "clients = active(r[0] as List<Map<String, dynamic>>); purchases = active(r[1] as List<Map<String, dynamic>>); recipients = active(r[2] as List<Map<String, dynamic>>);"
)
ps = ps.replace("return showDialog<String>(", "return await showDialog<String>(")
ps = ps.replace(
    "'Asignado a viaje', 'En tránsito a Cuba'",
    "'Asignado a viaje', 'Asignado a agencia', 'Enviado por agencia', 'En tránsito a Cuba'"
)
packages.write_text(ps)

purchases = Path('app/lib/purchases.dart')
pus = purchases.read_text().replace("Wrap(mainAxisSize: MainAxisSize.min, children:", "Wrap(children:")
purchases.write_text(pus)

flights = Path('app/lib/flights.dart')
fs = flights.read_text().replace("Wrap(mainAxisSize: MainAxisSize.min, children:", "Wrap(children:")
flights.write_text(fs)

main = Path('app/lib/main.dart')
ms = main.read_text()
ms = ms.replace(
    "import 'package:flutter/material.dart';",
    "import 'package:flutter/material.dart';\nimport 'package:flutter_local_notifications/flutter_local_notifications.dart';\nimport 'package:cross_file/cross_file.dart';\nimport 'package:pdf/pdf.dart';\nimport 'package:pdf/widgets.dart' as pw;\nimport 'package:share_plus/share_plus.dart';"
)
ms = ms.replace(
    "import 'package:url_launcher/url_launcher.dart';",
    "import 'package:url_launcher/url_launcher.dart';\nimport 'package:workmanager/workmanager.dart';"
)
ms = ms.replace(
    "part 'tracking_service.dart';",
    "part 'tracking_service.dart';\npart 'bulletins.dart';\npart 'search.dart';\npart 'flight_service.dart';\npart 'background_sync.dart';\npart 'agencies.dart';"
)
old_main = """void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PaqueteriaApp());
}"""
new_main = """Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await NotificationService.initialize(requestPermission: true);
    await BackgroundCourierSync.initializeAndSchedule();
  } catch (_) {}
  runApp(const PaqueteriaApp());
}"""
if old_main not in ms:
    raise SystemExit('No se encontró main() para aplicar la integración de background')
ms = ms.replace(old_main, new_main)
ms = ms.replace(
    "appBar: AppBar(title: const Text('Paquetería'), actions: [",
    "appBar: AppBar(title: const Text('Paquetería'), actions: [\n        IconButton(tooltip: 'Buscar tracking o cliente', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BusinessSearchPage())), icon: const Icon(Icons.search)),"
)
ms = ms.replace(
    "final owed = purchases.where((e) => '${e['clientId']}' == clientId).fold<double>(0, (a, e) => a + number(e['clientTotal']));",
    "final owed = purchases.fold<double>(0, (a, e) => a + purchaseAmountForClient(e, clientId));"
)
main.write_text(ms)

clients = Path('app/lib/clients.dart')
cs = clients.read_text()
cs = cs.replace(
    "purchases = active(r[2]).where((e) => '${e['clientId']}' == widget.clientId).toList();",
    "purchases = active(r[2]).where((e) => purchaseHasClient(e, widget.clientId)).toList();"
)
cs = cs.replace(
    "final due = purchases.fold<double>(0, (a,e)=>a+number(e['clientTotal'])) - payments.fold<double>(0,(a,e)=>a+number(e['amount']));",
    "final due = purchases.fold<double>(0, (a,e)=>a+purchaseAmountForClient(e, widget.clientId)) - payments.fold<double>(0,(a,e)=>a+number(e['amount']));"
)
cs = cs.replace(
    "title: Text('${p['store']} · ${money(number(p['clientTotal']))}'), subtitle: Text('${p['description']}\\n${p['status']}'))",
    "title: Text('${p['store']} · ${money(purchaseAmountForClient(p, widget.clientId))}'), subtitle: Text('${p['description']}\\n${p['status']}'), trailing: IconButton(icon: const Icon(Icons.receipt_long), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BulletinPage(purchase: p, initialClientId: widget.clientId)))))"
)
clients.write_text(cs)

extras = Path('app/lib/extras.dart')
ex = extras.read_text()
ex = ex.replace(
    "List<Map<String,dynamic>>purchases=[],payments=[],expenses=[],trips=[],packages=[];",
    "List<Map<String,dynamic>>purchases=[],payments=[],expenses=[],trips=[],packages=[],agencyShipments=[];"
)
ex = ex.replace(
    "Store.list('expenses'),Store.list('trips'),Store.list('packages')]);",
    "Store.list('expenses'),Store.list('trips'),Store.list('packages'),Store.list('agencyShipments')]);"
)
ex = ex.replace(
    "packages=active(r[4]);});}",
    "packages=active(r[4]);agencyShipments=active(r[5]);});}"
)
ex = ex.replace(
    "tripProfit+=w*number(t['ratePerLb'])-tripExpenses(t);}return Scaffold",
    "tripProfit+=w*number(t['ratePerLb'])-tripExpenses(t);}double agencyProfit=0;for(final a in agencyShipments){final ids=dynList(a['packageIds']).map((e)=>'$e').toSet();final w=packages.where((p)=>ids.contains('${p['id']}')).fold<double>(0,(s,p)=>s+number(p['billWeight']));agencyProfit+=w*number(a['sellRatePerLb'])-w*number(a['agencyCostPerLb'])-number(a['fuelCost'])-agencyOtherExpenses(a);}return Scaffold"
)
ex = ex.replace(
    "Text('Resultado estimado de viajes: ${money(tripProfit)}'),Text('Gastos generales: ${money(general)}')",
    "Text('Resultado estimado de viajes: ${money(tripProfit)}'),Text('Resultado estimado por agencia: ${money(agencyProfit)}'),Text('Gastos generales: ${money(general)}')"
)
ex = ex.replace(
    "money(tripProfit+purchaseRevenue-general)",
    "money(tripProfit+agencyProfit+purchaseRevenue-general)"
)
ex = ex.replace(
    "'flightWatches':'Alertas de vuelos'};",
    "'flightWatches':'Alertas de vuelos','agencyShipments':'Envíos por agencia','agents':'Agentes','agentReports':'Informes de agentes'};"
)
ex = ex.replace(
    "_more(context,Icons.flight_takeoff,'Vuelos y alertas'",
    "_more(context,Icons.local_shipping,'Envíos por agencia','Javier u otras agencias, costos y rentabilidad',const AgencyShipmentsPage()),\n_more(context,Icons.badge_outlined,'Agentes','Crear agentes e importar sus informes',const AgentsPage()),\n_more(context,Icons.flight_takeoff,'Vuelos y alertas'"
)
extras.write_text(ex)

tracking = Path('app/lib/tracking_service.dart')
tr = tracking.read_text()
tr = tr.replace(
    "Text('• EasyPost cobra los trackers independientes por uso.'),",
    "Text('• EasyPost cobra los trackers independientes por uso.'),\n          Text('• Android revisará los trackings periódicamente en segundo plano y mostrará una notificación cuando detecte un cambio.'),"
)
tracking.write_text(tr)

manifest = Path('app/android/app/src/main/AndroidManifest.xml')
m = manifest.read_text()
permissions = '''<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.CAMERA" />\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />\n    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />\n    <uses-permission android:name="android.permission.VIBRATE" />'''
if 'android.permission.INTERNET' not in m:
    m = m.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">', permissions)
else:
    for perm in ['POST_NOTIFICATIONS', 'RECEIVE_BOOT_COMPLETED', 'VIBRATE']:
        if f'android.permission.{perm}' not in m:
            m = m.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">', f'<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n    <uses-permission android:name="android.permission.{perm}" />')
m = m.replace('android:label="paqueteria"', 'android:label="Paquetería"')
sync_permission = 'com.angelapps.paqueteria.permission.FINANCE_SYNC'
if sync_permission not in m:
    m = m.replace('<application', f'<permission android:name="{sync_permission}" android:protectionLevel="normal" />\n    <application', 1)
if 'FinanceSyncProvider' not in m:
    provider = '''        <provider
  android:name=".FinanceSyncProvider"
  android:authorities="com.angelapps.paqueteria.finance_sync"
  android:exported="true"
  android:readPermission="com.angelapps.paqueteria.permission.FINANCE_SYNC"
  android:grantUriPermissions="true" />
'''
    m = m.replace('    </application>', provider + '    </application>')
manifest.write_text(m)

import base64
kotlin_dir = Path('app/android/app/src/main/kotlin/com/angelapps/paqueteria')
kotlin_dir.mkdir(parents=True, exist_ok=True)
(kotlin_dir / 'FinanceSyncProvider.kt').write_bytes(base64.b64decode('cGFja2FnZSBjb20uYW5nZWxhcHBzLnBhcXVldGVyaWEKCmltcG9ydCBhbmRyb2lkLmNvbnRlbnQuQ29udGVudFByb3ZpZGVyCmltcG9ydCBhbmRyb2lkLmNvbnRlbnQuQ29udGVudFZhbHVlcwppbXBvcnQgYW5kcm9pZC5jb250ZW50LkNvbnRleHQKaW1wb3J0IGFuZHJvaWQuZGF0YWJhc2UuQ3Vyc29yCmltcG9ydCBhbmRyb2lkLm5ldC5VcmkKaW1wb3J0IGFuZHJvaWQub3MuUGFyY2VsRmlsZURlc2NyaXB0b3IKaW1wb3J0IGphdmEuaW8uRmlsZU91dHB1dFN0cmVhbQoKY2xhc3MgRmluYW5jZVN5bmNQcm92aWRlciA6IENvbnRlbnRQcm92aWRlcigpIHsKICAgIG92ZXJyaWRlIGZ1biBvbkNyZWF0ZSgpOiBCb29sZWFuID0gdHJ1ZQoKICAgIG92ZXJyaWRlIGZ1biBnZXRUeXBlKHVyaTogVXJpKTogU3RyaW5nID0gImFwcGxpY2F0aW9uL2pzb24iCgogICAgb3ZlcnJpZGUgZnVuIG9wZW5GaWxlKHVyaTogVXJpLCBtb2RlOiBTdHJpbmcpOiBQYXJjZWxGaWxlRGVzY3JpcHRvciB7CiAgICAgICAgdmFsIHBpcGUgPSBQYXJjZWxGaWxlRGVzY3JpcHRvci5jcmVhdGVQaXBlKCkKICAgICAgICB2YWwgcHJlZnMgPSBjb250ZXh0ISEuZ2V0U2hhcmVkUHJlZmVyZW5jZXMoIkZsdXR0ZXJTaGFyZWRQcmVmZXJlbmNlcyIsIENvbnRleHQuTU9ERV9QUklWQVRFKQogICAgICAgIHZhbCBzbmFwc2hvdCA9IHByZWZzLmdldFN0cmluZygiZmx1dHRlci5maW5hbmNlX3N5bmNfc25hcHNob3QiLCAie30iKSA/OiAie30iCiAgICAgICAgVGhyZWFkIHsKICAgICAgICAgICAgdHJ5IHsKICAgICAgICAgICAgICAgIEZpbGVPdXRwdXRTdHJlYW0ocGlwZVsxXS5maWxlRGVzY3JpcHRvcikudXNlIHsgb3V0IC0+CiAgICAgICAgICAgICAgICAgICAgb3V0LndyaXRlKHNuYXBzaG90LnRvQnl0ZUFycmF5KENoYXJzZXRzLlVURl84KSkKICAgICAgICAgICAgICAgICAgICBvdXQuZmx1c2goKQogICAgICAgICAgICAgICAgfQogICAgICAgICAgICB9IGZpbmFsbHkgewogICAgICAgICAgICAgICAgdHJ5IHsgcGlwZVsxXS5jbG9zZSgpIH0gY2F0Y2ggKF86IEV4Y2VwdGlvbikge30KICAgICAgICAgICAgfQogICAgICAgIH0uc3RhcnQoKQogICAgICAgIHJldHVybiBwaXBlWzBdCiAgICB9CgogICAgb3ZlcnJpZGUgZnVuIHF1ZXJ5KHVyaTogVXJpLCBwcm9qZWN0aW9uOiBBcnJheTxvdXQgU3RyaW5nPj8sIHNlbGVjdGlvbjogU3RyaW5nPywgc2VsZWN0aW9uQXJnczogQXJyYXk8b3V0IFN0cmluZz4/LCBzb3J0T3JkZXI6IFN0cmluZz8pOiBDdXJzb3I/ID0gbnVsbAogICAgb3ZlcnJpZGUgZnVuIGluc2VydCh1cmk6IFVyaSwgdmFsdWVzOiBDb250ZW50VmFsdWVzPyk6IFVyaT8gPSBudWxsCiAgICBvdmVycmlkZSBmdW4gZGVsZXRlKHVyaTogVXJpLCBzZWxlY3Rpb246IFN0cmluZz8sIHNlbGVjdGlvbkFyZ3M6IEFycmF5PG91dCBTdHJpbmc+Pyk6IEludCA9IDAKICAgIG92ZXJyaWRlIGZ1biB1cGRhdGUodXJpOiBVcmksIHZhbHVlczogQ29udGVudFZhbHVlcz8sIHNlbGVjdGlvbjogU3RyaW5nPywgc2VsZWN0aW9uQXJnczogQXJyYXk8b3V0IFN0cmluZz4/KTogSW50ID0gMAp9Cg=='))

gradle = Path('app/android/app/build.gradle.kts')
g = gradle.read_text()
if 'isCoreLibraryDesugaringEnabled' not in g:
    g = g.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true')
deps = '''\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")\n    implementation("com.google.mlkit:text-recognition-devanagari:16.0.1")\n    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")\n    implementation("com.google.mlkit:text-recognition-korean:16.0.1")\n}\n'''
if 'com.google.mlkit:text-recognition-chinese' not in g:
    g += deps
elif 'coreLibraryDesugaring(' not in g:
    g += '\ndependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }\n'
gradle.write_text(g)
