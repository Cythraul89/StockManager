import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'llm_service.dart';

final groqServiceProvider = Provider<LlmService>((ref) => GroqService());

class GroqService implements LlmService {
  static const _endpoint =
      'https://api.groq.com/openai/v1/chat/completions';

  @override
  Stream<String> streamAnalysis({
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userMessage,
  }) async* {
    final dio = Dio();

    final body = {
      'model': model,
      'max_tokens': 4096,
      'stream': true,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userMessage},
      ],
    };

    late Response<ResponseBody> response;
    try {
      response = await dio.post<ResponseBody>(
        _endpoint,
        data: jsonEncode(body),
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'content-type': 'application/json',
          },
        ),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401) {
        throw const LlmApiException(
          'Invalid Groq API key. Check your key in Settings → AI Analysis.',
          statusCode: 401,
        );
      }
      if (status == 429) {
        throw const LlmApiException(
          'Groq rate limit reached. Please wait a moment and try again.',
          statusCode: 429,
        );
      }
      if (status != null && status >= 500) {
        throw LlmApiException(
          'Groq server error ($status). Please try again later.',
          statusCode: status,
        );
      }
      throw LlmApiException('Network error: ${e.message}');
    }

    final buffer = StringBuffer();
    await for (final chunk in response.data!.stream) {
      buffer.write(utf8.decode(chunk));
      final raw = buffer.toString();
      final lines = raw.split('\n');
      buffer
        ..clear()
        ..write(lines.last);

      for (final line in lines.sublist(0, lines.length - 1)) {
        if (!line.startsWith('data: ')) continue;
        final payload = line.substring(6).trim();
        if (payload == '[DONE]') return;

        Map<String, dynamic> event;
        try {
          event = jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }

        final choices = event['choices'] as List<dynamic>?;
        final delta =
            choices?.firstOrNull?['delta'] as Map<String, dynamic>?;
        final text = delta?['content'] as String?;
        if (text != null && text.isNotEmpty) yield text;
      }
    }
  }
}
