import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FinanceAiSettingsPage extends StatefulWidget {
  const FinanceAiSettingsPage({super.key});

  @override
  State<FinanceAiSettingsPage> createState() => _FinanceAiSettingsPageState();
}

class _FinanceAiSettingsPageState extends State<FinanceAiSettingsPage> {
  String provider = 'gemini';
  bool loading = true;
  bool importing = false;

  final geminiKey = TextEditingController();
  final geminiModel = TextEditingController();
  final onlineUrl = TextEditingController();
  final onlineModel = TextEditingController();
  final onlineKey = TextEditingController();
  final localUrl = TextEditingController();
  final localModel = TextEditingController();
  final localKey = TextEditingController();

  String deviceModelPath = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    provider = p.getString('finance_ai_provider') ?? 'gemini';
    geminiKey.text = p.getString('finance_ai_gemini_key') ?? '';
    geminiModel.text =
        p.getString('finance_ai_gemini_model') ?? 'gemini-2.5-flash';
    onlineUrl.text =
        p.getString('finance_ai_openai_base_url') ?? 'https://api.openai.com/v1';
    onlineModel.text =
        p.getString('finance_ai_openai_model') ?? 'gpt-4.1-mini';
    onlineKey.text = p.getString('finance_ai_openai_key') ?? '';
    localUrl.text =
        p.getString('finance_ai_local_base_url') ?? 'http://127.0.0.1:11434/v1';
    localModel.text =
        p.getString('finance_ai_local_model') ?? 'llama3.2:3b';
    localKey.text = p.getString('finance_ai_local_key') ?? '';
    deviceModelPath = p.getString('finance_ai_device_model_path') ?? '';
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('finance_ai_provider', provider);
    await p.setString('finance_ai_gemini_key', geminiKey.text.trim());
    await p.setString('finance_ai_gemini_model', geminiModel.text.trim());
    await p.setString('finance_ai_openai_base_url', onlineUrl.text.trim());
    await p.setString('finance_ai_openai_model', onlineModel.text.trim());
    await p.setString('finance_ai_openai_key', onlineKey.text.trim());
    await p.setString('finance_ai_local_base_url', localUrl.text.trim());
    await p.setString('finance_ai_local_model', localModel.text.trim());
    await p.setString('finance_ai_local_key', localKey.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuración de IA guardada')),
    );
  }

  Future<void> _importGguf() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gguf'],
    );
    final sourcePath = picked?.files.single.path;
    if (sourcePath == null) return;
    setState(() => importing = true);
    try {
      final root = await getApplicationSupportDirectory();
      final dir = Directory('${root.path}/finance_ai_models');
      await dir.create(recursive: true);
      final name = picked!.files.single.name.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );
      final destination = '${dir.path}/$name';
      if (sourcePath != destination) {
        await File(sourcePath).copy(destination);
      }
      final old = deviceModelPath;
      final p = await SharedPreferences.getInstance();
      await p.setString('finance_ai_device_model_path', destination);
      if (old.isNotEmpty && old != destination && File(old).existsSync()) {
        try {
          await File(old).delete();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        deviceModelPath = destination;
        provider = 'device';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Modelo GGUF importado correctamente')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No pude importar el modelo: $e')));
      }
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Widget _choice(
    String value,
    IconData icon,
    String title,
    String subtitle,
  ) =>
      Card(
        child: RadioListTile<String>(
          value: value,
          groupValue: provider,
          onChanged: (v) => setState(() => provider = v ?? 'gemini'),
          secondary: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ajustes de IA')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Elige qué cerebro usará Finanzas',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'El Chat IA usa esta configuración. Puedes cambiar de modelo desde el propio chat.',
                  ),
                  const SizedBox(height: 10),
                  _choice(
                    'gemini',
                    Icons.cloud_outlined,
                    'Gemini online',
                    'Google Gemini con tu propia clave.',
                  ),
                  _choice(
                    'openai',
                    Icons.public,
                    'LLM online compatible',
                    'OpenAI o cualquier API compatible con /chat/completions.',
                  ),
                  _choice(
                    'local',
                    Icons.computer,
                    'LLM local / Ollama',
                    'Ollama, LM Studio u otro servidor compatible.',
                  ),
                  _choice(
                    'manager',
                    Icons.hub_outlined,
                    'Local AI Manager',
                    'Usa el modelo compartido del gestor sin cargar otro GGUF dentro de Finanzas.',
                  ),
                  _choice(
                    'device',
                    Icons.memory,
                    'GGUF en este teléfono',
                    'Usa un modelo local directamente dentro de Finanzas.',
                  ),
                  const SizedBox(height: 14),
                  if (provider == 'gemini') ...[
                    TextField(
                      controller: geminiModel,
                      decoration: const InputDecoration(
                        labelText: 'Modelo Gemini',
                        hintText: 'gemini-2.5-flash',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: geminiKey,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Clave de Gemini',
                        prefixIcon: Icon(Icons.key),
                      ),
                    ),
                  ],
                  if (provider == 'openai') ...[
                    TextField(
                      controller: onlineUrl,
                      decoration: const InputDecoration(
                        labelText: 'URL base',
                        hintText: 'https://api.openai.com/v1',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: onlineModel,
                      decoration: const InputDecoration(
                        labelText: 'Modelo',
                        hintText: 'gpt-4.1-mini',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: onlineKey,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'API key'),
                    ),
                  ],
                  if (provider == 'local') ...[
                    TextField(
                      controller: localUrl,
                      decoration: const InputDecoration(
                        labelText: 'URL del LLM local',
                        hintText: 'http://192.168.1.20:11434/v1',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: localModel,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del modelo',
                        hintText: 'llama3.2:3b',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: localKey,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Clave opcional',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Si Ollama o LM Studio corre en una PC, usa la IP local de esa PC. 127.0.0.1 solo sirve si el servidor está en el teléfono.',
                    ),
                  ],
                  if (provider == 'manager') ...[
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.memory_outlined),
                        title: const Text('Conexión automática'),
                        subtitle: const Text(
                          'Finanzas usará http://127.0.0.1:11435/v1 con el modelo shared. No necesitas configurar URL, modelo ni clave.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Abre Local AI Manager y carga allí el GGUF. Si el gestor no está activo, Finanzas mostrará un aviso claro y no intentará cargar el GGUF interno.',
                    ),
                  ],
                  if (provider == 'device') ...[
                    FilledButton.icon(
                      onPressed: importing ? null : _importGguf,
                      icon: const Icon(Icons.folder_open),
                      label: Text(
                        importing
                            ? 'Importando modelo…'
                            : deviceModelPath.isEmpty
                                ? 'Elegir modelo .gguf'
                                : 'Cambiar modelo .gguf',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      deviceModelPath.isEmpty
                          ? 'No hay un GGUF configurado.'
                          : 'Modelo: ${deviceModelPath.split('/').last}',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Recomendado: un modelo instruct pequeño o mediano cuantizado en Q4 para no consumir demasiada memoria del teléfono.',
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: const Text('Guardar y usar esta opción'),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Cuando uses Gemini u otro servicio online, la pregunta y el contexto financiero que elijas compartir se envían a ese proveedor. Con Ollama local o GGUF, pueden permanecer en tu red o dispositivo.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
      );
}
