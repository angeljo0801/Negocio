from pathlib import Path

p = Path('app/lib/main.dart')
s = p.read_text()

old = "part 'packages.dart';"
new = "part 'packages.dart';\npart 'gmail_reconstruction.dart';"
if old not in s:
    raise SystemExit('packages.dart part anchor not found')
s = s.replace(old, new)

old = "_quick(context, Icons.cloud_sync, 'Couriers', openCourier),"
new = "_quick(context, Icons.cloud_sync, 'Couriers', openCourier),\n            _quick(context, Icons.mail_outline, 'Gmail', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GmailConnectionPage()))),"
if old not in s:
    raise SystemExit('courier quick action anchor not found')
s = s.replace(old, new)

s = s.replace(
    "PackageEditPage(initialTracking: code)",
    "PackageEditPage(initialTracking: code, autoReconstruct: true)",
)

p.write_text(s)
print('Gmail main patch applied')
