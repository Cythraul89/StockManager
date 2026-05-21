import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final claudeServiceProvider = Provider<ClaudeService>((ref) {
  return ClaudeService();
});

class ClaudeApiException implements Exception {
  const ClaudeApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Available Claude models ordered from most to least capable.
const claudeModels = [
  (id: 'claude-opus-4-7',   label: 'Opus 4.7',   note: 'Most capable · \$5 / \$25 per 1M tokens'),
  (id: 'claude-sonnet-4-6', label: 'Sonnet 4.6', note: 'Balanced · \$3 / \$15 per 1M tokens'),
  (id: 'claude-haiku-4-5',  label: 'Haiku 4.5',  note: 'Fastest & cheapest · \$1 / \$5 per 1M tokens'),
];

const defaultClaudeModel = 'claude-opus-4-7';

class ClaudeService {
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _apiVersion = '2023-06-01';

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
        throw const ClaudeApiException(
          'Invalid API key. Check your Claude API key in Settings → AI Analysis.',
          statusCode: 401,
        );
      }
      if (status == 429) {
        throw const ClaudeApiException(
          'Rate limit reached. Please wait a moment and try again.',
          statusCode: 429,
        );
      }
      if (status != null && status >= 500) {
        throw ClaudeApiException(
          'Anthropic server error ($status). Please try again later.',
          statusCode: status,
        );
      }
      throw ClaudeApiException('Network error: ${e.message}');
    }

    final stream = response.data!.stream;
    final buffer = StringBuffer();

    await for (final chunk in stream) {
      buffer.write(utf8.decode(chunk));
      final raw = buffer.toString();
      final lines = raw.split('\n');

      // Keep the last (potentially incomplete) line in the buffer.
      buffer.clear();
      buffer.write(lines.last);

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
          throw ClaudeApiException(
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
