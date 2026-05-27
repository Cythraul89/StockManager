import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'llm_service.dart';

final claudeServiceProvider = Provider<LlmService>((ref) => ClaudeService());

class ClaudeService implements LlmService {
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _apiVersion = '2023-06-01';

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
      'system': [
        {
          'type': 'text',
          'text': systemPrompt,
          'cache_control': {'type': 'ephemeral'},
        }
      ],
      'messages': [
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
            'x-api-key': apiKey,
            'anthropic-version': _apiVersion,
            'content-type': 'application/json',
          },
        ),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401) {
        throw const LlmApiException(
          'Invalid Claude API key. Check your key in Settings → AI Analysis.',
          statusCode: 401,
        );
      }
      if (status == 429) {
        throw const LlmApiException(
          'Claude rate limit reached. Please wait a moment and try again.',
          statusCode: 429,
        );
      }
      if (status != null && status >= 500) {
        throw LlmApiException(
          'Anthropic server error ($status). Please try again later.',
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

        if (event['type'] == 'error') {
          final err = event['error'] as Map<String, dynamic>?;
          throw LlmApiException(
            err?['message']?.toString() ?? 'Unknown streaming error',
          );
        }

        if (event['type'] != 'content_block_delta') continue;
        final delta = event['delta'] as Map<String, dynamic>?;
        if (delta?['type'] != 'text_delta') continue;
        final text = delta?['text'] as String?;
        if (text != null && text.isNotEmpty) yield text;
      }
    }
  }
}
