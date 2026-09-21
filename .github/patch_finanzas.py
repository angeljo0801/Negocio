from pathlib import Path
import re

root=Path('finanzas_definitiva')

# Paqueteria sync needs sqflite's ConflictAlgorithm.
sync=root/'lib/paqueteria_sync.dart'
ss=sync.read_text()
if "import 'package:sqflite/sqflite.dart';" not in ss:
    ss=ss.replace(
        "import 'package:flutter/services.dart';",
        "import 'package:flutter/services.dart';\nimport 'package:sqflite/sqflite.dart';",
    )
sync.write_text(ss)

# Main app: import AI surfaces, sync at startup, and expose the same AI workflow
# used in Memora: Chat IA + Ajustes de IA, plus the deterministic quick assistant.
main=root/'lib/main.dart'
s=main.read_text()
marker="import 'manager_pages.dart';"
if marker not in s:
    raise SystemExit('No se encontro manager_pages.dart en main.dart')
for imp in [
    "import 'paqueteria_sync.dart';",
    "import 'finance_bot.dart';",
    "import 'finance_ai_settings.dart';",
    "import 'finance_ai_chat.dart';",
    "import 'personal_finance.dart';",
    "import 'finance_learning.dart';",
]:
    if imp not in s:
        s=s.replace(marker, marker+"\n"+imp, 1)

old="class _HomePageState extends State<HomePage> {\n  int index = 0, revision = 0;"
if old in s:
    new="""class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final result = await PaqueteriaSyncService.sync(silent: true);
      if (result != null && mounted) refresh();
    });
  }
  int index = 0, revision = 0;"""
    s=s.replace(old,new,1)

settings_marker="      ListTile(leading:const Icon(Icons.receipt_long_outlined),title:const Text('Libro diario profesional')"
if settings_marker not in s:
    raise SystemExit('No se encontro Libro diario profesional')

tiles=""
if "title:const Text('Chat IA')" not in s:
    tiles += "      ListTile(leading:const Icon(Icons.chat_bubble_outline),title:const Text('Chat IA'),subtitle:const Text('Habla con la IA que elijas usando tus finanzas como contexto'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>FinanceAiChatPage(onChanged:widget.onChanged)))),\n"
if "title:const Text('Ajustes de IA')" not in s:
    tiles += "      ListTile(leading:const Icon(Icons.tune),title:const Text('Ajustes de IA'),subtitle:const Text('Gemini, LLM online, Ollama/local o GGUF en el teléfono'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const FinanceAiSettingsPage()))),\n"
if "title:const Text('Asistente financiero')" not in s:
    tiles += "      ListTile(leading:const Icon(Icons.smart_toy_outlined),title:const Text('Asistente financiero'),subtitle:const Text('Interpreta operaciones personales y del negocio con la IA'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>FinanceAssistantPage(onChanged:widget.onChanged)))),\n"
if "title:const Text('Finanzas personales')" not in s:
    tiles += "      ListTile(leading:const Icon(Icons.account_balance_wallet_outlined),title:const Text('Finanzas personales'),subtitle:const Text('Saldos y movimientos separados del negocio'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const PersonalFinancePage()))),\n"
if "title:const Text('Base de conocimiento')" not in s:
    tiles += "      ListTile(leading:const Icon(Icons.auto_stories_outlined),title:const Text('Base de conocimiento'),subtitle:const Text('Reglas aprendidas y conocimiento agregado manualmente'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const LearnedFinanceRulesPage()))),\n"
if "Sincronizar con Paquetería" not in s:
    tiles += "      ListTile(leading:const Icon(Icons.sync_alt),title:const Text('Sincronizar con Paquetería'),subtitle:const Text('Compras, paquetes, pendientes, agentes y gastos'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>PaqueteriaSyncPage(onChanged:widget.onChanged)))),\n"
if tiles:
    s=s.replace(settings_marker, tiles+settings_marker,1)

dash_marker="      const SizedBox(height:14),FilledButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const DailyPositionPage())),icon:const Icon(Icons.today),label:const Text('Ver posición diaria')),"
if dash_marker in s:
    replacement="""      const SizedBox(height:14),FilledButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>FinanceAiChatPage(onChanged:(){}))),icon:const Icon(Icons.chat_bubble_outline),label:const Text('Abrir Chat IA')),
      const SizedBox(height:8),OutlinedButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>FinanceAssistantPage(onChanged:(){}))),icon:const Icon(Icons.smart_toy_outlined),label:const Text('Asistente financiero con IA')),
      const SizedBox(height:8),OutlinedButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const PersonalFinancePage())),icon:const Icon(Icons.account_balance_wallet_outlined),label:const Text('Finanzas personales')),
      const SizedBox(height:8),FilledButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const DailyPositionPage())),icon:const Icon(Icons.today),label:const Text('Ver posición diaria')),"""
    s=s.replace(dash_marker,replacement,1)

main.write_text(s)

# Dependencies for the Memora-style AI selector/chat and phone GGUF.
pub=root/'pubspec.yaml'
ps=pub.read_text()
ps=re.sub(r'^version:.*$', 'version: 2.5.2+18', ps, flags=re.M)
anchor='  file_picker: ^10.3.3'
if anchor not in ps:
    raise SystemExit('No se encontro file_picker en pubspec')
for dep in [
    '  http: ^1.5.0',
    '  shared_preferences: ^2.5.3',
    '  llama_flutter_android: ^0.2.6',
]:
    if dep.strip() not in ps:
        ps=ps.replace(anchor,anchor+'\n'+dep,1)
pub.write_text(ps)

# Android: internet/cloud/local-server access + Paqueteria local sync.
manifest=root/'android/app/src/main/AndroidManifest.xml'
m=manifest.read_text()
manifest_open='<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
if 'android.permission.INTERNET' not in m:
    m=m.replace(manifest_open,manifest_open+'\n    <uses-permission android:name="android.permission.INTERNET" />',1)
perm='com.angelapps.paqueteria.permission.FINANCE_SYNC'
if perm not in m:
    m=m.replace(manifest_open,manifest_open+'\n    <uses-permission android:name="'+perm+'" />',1)
manager_perm='com.angelapps.local_ai_manager.permission.USE_AI'
if manager_perm not in m:
    m=m.replace(manifest_open,manifest_open+'\n    <uses-permission android:name="'+manager_perm+'" />',1)
if 'android:usesCleartextTraffic' not in m:
    m=m.replace('<application','<application android:usesCleartextTraffic="true"',1)
if 'com.angelapps.paqueteria.finance_sync' not in m:
    q='    <queries>\n        <provider android:authorities="com.angelapps.paqueteria.finance_sync" />\n        <package android:name="com.angelapps.local_ai_manager" />\n    </queries>\n'
    m=m.replace('    <application',q+'    <application',1)
elif 'com.angelapps.local_ai_manager' not in m:
    m=m.replace('</queries>','        <package android:name="com.angelapps.local_ai_manager" />\n    </queries>',1)
manifest.write_text(m)


# GGUF runtime requires Android API 26+.
gradle=root/'android/app/build.gradle.kts'
g=gradle.read_text()
g=g.replace('minSdk = flutter.minSdkVersion','minSdk = 26')
g=g.replace('minSdk = 24','minSdk = 26')
gradle.write_text(g)
