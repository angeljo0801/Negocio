import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FinanceDeviceLlmService {
  static LlamaController? _controller;
  static String? _loadedPath;
  static int _serial = 0;
  static int? _activeId;
  static final Set<int> _cancelled = <int>{};

  static int _maxTokens(String mode) {
    switch (mode) {
      case 'fast':
        return 160;
      case 'deep':
        return 520;
      default:
        return 280;
    }
  }

  static Future<void> _ensureLoaded() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('finance_ai_device_model_path') ?? '';
    if (path.isEmpty || !File(path).existsSync()) {
      throw Exception('No hay un modelo GGUF configurado. Ve a Ajustes de IA.');
    }
    if (_controller != null && _loadedPath == path) return;
    try {
      await _controller?.dispose();
    } catch (_) {}
    final controller = LlamaController();
    // Safe mode for Android: CPU-only avoids vendor Vulkan/native crashes that can
    // send the app to the launcher when inference starts.
    await controller.loadModel(
      modelPath: path,
      threads: Platform.numberOfProcessors.clamp(2, 4).toInt(),
      contextSize: 2048,
      gpuLayers: 0,
    );
    _controller = controller;
    _loadedPath = path;
  }

  static Future<String> ask(
    String prompt, {
    String responseMode = 'normal',
    void Function(String text)? onPartial,
  }) async {
    final id = ++_serial;
    _activeId = id;
    try {
      await _ensureLoaded();
      final controller = _controller;
      if (controller == null) throw Exception('No pude iniciar el modelo GGUF.');
      final buffer = StringBuffer();
      var lastUi = DateTime.fromMillisecondsSinceEpoch(0);
      final stream = controller.generateChat(
        messages: [
          ChatMessage(
            role: 'system',
            content:
                'Eres el asistente financiero local de Finanzas Definitiva. Sigue las instrucciones del contexto contable y no inventes datos.',
          ),
          ChatMessage(role: 'user', content: prompt),
        ],
        temperature: 0.2,
        maxTokens: _maxTokens(responseMode),
      );
      await for (final token in stream) {
        if (_cancelled.contains(id)) break;
        buffer.write(token);
        final now = DateTime.now();
        if (onPartial != null &&
            now.difference(lastUi) >= const Duration(milliseconds: 55)) {
          onPartial(buffer.toString());
          lastUi = now;
        }
      }
      final text = buffer.toString().trim();
      if (text.isNotEmpty) {
        onPartial?.call(text);
        return text;
      }
      if (_cancelled.contains(id)) return 'Generación cancelada.';
      throw Exception('El modelo local no generó una respuesta.');
    } finally {
      _cancelled.remove(id);
      if (_activeId == id) _activeId = null;
    }
  }

  static Future<void> stopCurrent() async {
    final id = _activeId;
    if (id != null) _cancelled.add(id);
    try {
      await _controller?.stop();
    } catch (_) {}
  }
}

class FinanceAiService {
  static http.Client? _activeClient;
  static int _serial = 0;
  static int? _activeOnlineId;
  static final Set<int> _cancelled = <int>{};

  static Future<void> cancelCurrent() async {
    final id = _activeOnlineId;
    if (id != null) _cancelled.add(id);
    final client = _activeClient;
    _activeClient = null;
    try {
      client?.close();
    } catch (_) {}
    await FinanceDeviceLlmService.stopCurrent();
  }

  static Future<T> _runOnline<T>(
    Future<T> Function(http.Client client, int id) action,
  ) async {
    final id = ++_serial;
    final client = http.Client();
    _activeOnlineId = id;
    _activeClient = client;
    try {
      final value = await action(client, id);
      if (_cancelled.contains(id)) throw Exception('Generación cancelada.');
      return value;
    } finally {
      try {
        client.close();
      } catch (_) {}
      _cancelled.remove(id);
      if (_activeOnlineId == id) _activeOnlineId = null;
      if (identical(_activeClient, client)) _activeClient = null;
    }
  }

  static int _maxTokens(String mode) {
    switch (mode) {
      case 'fast':
        return 350;
      case 'deep':
        return 1800;
      default:
        return 900;
    }
  }

  static Future<String> askConfigured({
    required String prompt,
    String? providerOverride,
    String responseMode = 'normal',
    void Function(String text)? onPartial,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final provider = providerOverride?.trim().isNotEmpty == true
        ? providerOverride!.trim()
        : (prefs.getString('finance_ai_provider') ?? 'gemini');

    if (provider == 'device') {
      return FinanceDeviceLlmService.ask(
        prompt,
        responseMode: responseMode,
        onPartial: onPartial,
      );
    }

    if (provider == 'gemini') {
      final key = (prefs.getString('finance_ai_gemini_key') ?? '').trim();
      final model =
          (prefs.getString('finance_ai_gemini_model') ?? 'gemini-2.5-flash')
              .trim();
      if (key.isEmpty) {
        throw Exception('Configura la clave de Gemini en Ajustes de IA.');
      }
      final result = await _runOnline((client, _) => _askGemini(
            client: client,
            apiKey: key,
            model: model,
            prompt: prompt,
            maxTokens: _maxTokens(responseMode),
          ));
      onPartial?.call(result);
      return result;
    }

    if (provider == 'openai') {
      final key = (prefs.getString('finance_ai_openai_key') ?? '').trim();
      final model =
          (prefs.getString('finance_ai_openai_model') ?? 'gpt-4.1-mini').trim();
      final baseUrl =
          (prefs.getString('finance_ai_openai_base_url') ??
                  'https://api.openai.com/v1')
              .trim();
      if (key.isEmpty || model.isEmpty) {
        throw Exception('Configura la clave y el modelo online en Ajustes de IA.');
      }
      final result = await _runOnline((client, _) => _askOpenAiCompatible(
            client: client,
            baseUrl: baseUrl,
            apiKey: key,
            model: model,
            prompt: prompt,
            maxTokens: _maxTokens(responseMode),
          ));
      onPartial?.call(result);
      return result;
    }

    if (provider == 'local') {
      final baseUrl =
          (prefs.getString('finance_ai_local_base_url') ??
                  'http://127.0.0.1:11434/v1')
              .trim();
      final model =
          (prefs.getString('finance_ai_local_model') ?? 'llama3.2:3b').trim();
      final key = (prefs.getString('finance_ai_local_key') ?? '').trim();
      if (model.isEmpty) {
        throw Exception('Indica el nombre del modelo local en Ajustes de IA.');
      }
      final result = await _runOnline((client, _) => _askOpenAiCompatible(
            client: client,
            baseUrl: baseUrl,
            apiKey: key,
            model: model,
            prompt: prompt,
            maxTokens: _maxTokens(responseMode),
          ));
      onPartial?.call(result);
      return result;
    }

    throw Exception('Fuente de IA no reconocida: $provider');
  }

  static Future<String> _askGemini({
    required http.Client client,
    required String apiKey,
    required String model,
    required String prompt,
    required int maxTokens,
  }) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
    );
    final response = await client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt}
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.2,
              'maxOutputTokens': maxTokens,
            },
          }),
        )
        .timeout(const Duration(minutes: 4));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Gemini respondió ${response.statusCode}: ${_errorMessage(response.body)}',
      );
    }
    final data = jsonDecode(response.body);
    return data['candidates']?[0]?['content']?['parts']?[0]?['text']?.toString() ??
        'No pude generar una respuesta.';
  }

  static Future<String> _askOpenAiCompatible({
    required http.Client client,
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
    required int maxTokens,
  }) async {
    final cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey.isNotEmpty) headers['Authorization'] = 'Bearer $apiKey';
    final response = await client
        .post(
          Uri.parse('$cleanBase/chat/completions'),
          headers: headers,
          body: jsonEncode({
            'model': model,
            'messages': [
              {
                'role': 'system',
                'content':
                    'Eres la inteligencia de Finanzas Definitiva. Sigue cuidadosamente el contexto financiero suministrado.',
              },
              {'role': 'user', 'content': prompt},
            ],
            'temperature': 0.2,
            'max_tokens': maxTokens,
          }),
        )
        .timeout(const Duration(minutes: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'El modelo respondió ${response.statusCode}: ${_errorMessage(response.body)}',
      );
    }
    final data = jsonDecode(response.body);
    return data['choices']?[0]?['message']?['content']?.toString() ??
        'No pude generar una respuesta.';
  }

  static String userFacingError(Object error) {
    var text = error.toString().trim();
    if (text.startsWith('Exception: ')) {
      text = text.substring('Exception: '.length).trim();
    }
    if (text.length > 360) text = '${text.substring(0, 360).trim()}…';
    return text.isEmpty ? 'La IA no pudo completar la solicitud.' : text;
  }

  static String _errorMessage(String body) {
    try {
      final data = jsonDecode(body);
      return data['error']?['message']?.toString() ?? body;
    } catch (_) {
      return body.length > 280 ? body.substring(0, 280) : body;
    }
  }
}
