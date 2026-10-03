from pathlib import Path
import os
import re

main = Path('app/lib/main.dart')
s = main.read_text()
if "part 'legacy_restore.dart';" not in s:
    s = s.replace("part 'gmail_reconstruction.dart';", "part 'gmail_reconstruction.dart';\npart 'legacy_restore.dart';")

anchor = "_quick(context, Icons.mail_outline, 'Gmail', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GmailConnectionPage()))),"
if anchor in s and "Restaurar datos" not in s:
    s = s.replace(
        anchor,
        anchor + "\n            _quick(context, Icons.restore, 'Restaurar datos', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LegacyRestorePage()))),",
        1,
    )
main.write_text(s)

# Stable Android identity and release signing. The signing material is loaded
# by GitHub Actions from an OIDC-protected vault on the private Railway volume.
gradle = Path('app/android/app/build.gradle.kts')
g = gradle.read_text()
g = re.sub(r'namespace\s*=\s*"[^"]+"', 'namespace = "com.angelapps.paqueteria"', g, count=1)
g = re.sub(r'applicationId\s*=\s*"[^"]+"', 'applicationId = "com.angelapps.paqueteria"', g, count=1)

key_alias = os.environ.get('PAQUETERIA_KEY_ALIAS', '').strip()
store_password = os.environ.get('PAQUETERIA_KEYSTORE_PASSWORD', '').strip()
key_password = os.environ.get('PAQUETERIA_KEY_PASSWORD', '').strip() or store_password
keystore = Path('app/android/app/paqueteria-release.p12')
if not (keystore.exists() and key_alias and store_password and key_password):
    raise SystemExit('Falta la firma permanente de Paquetería; se cancela el build para no generar una APK con firma temporal.')

def esc(v: str) -> str:
    return v.replace('\\', '\\\\').replace('"', '\\"')

signing = '''    signingConfigs {
        create("paqueteriaRelease") {
            keyAlias = "''' + esc(key_alias) + '''"
            keyPassword = "''' + esc(key_password) + '''"
            storeFile = file("paqueteria-release.p12")
            storePassword = "''' + esc(store_password) + '''"
        }
    }

'''
if 'create("paqueteriaRelease")' not in g:
    g = g.replace('    buildTypes {', signing + '    buildTypes {', 1)

g = re.sub(
    r'(getByName\("release"\)\s*\{)(.*?)(\n\s*\})',
    lambda m: m.group(1) + re.sub(r'\n\s*signingConfig\s*=.*', '', m.group(2)) +
        '\n            signingConfig = signingConfigs.getByName("paqueteriaRelease")' + m.group(3),
    g,
    count=1,
    flags=re.S,
)
gradle.write_text(g)
print('Stable Paqueteria signing and legacy restore patched')
