import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'llm_service.dart';

final geminiServiceProvider = Provider<LlmService>((ref) => GeminiService());

class GeminiService implements LlmService {
  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  @override
  Stream<String> streamAnalysis({
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userMessage,
  }) async* {
    final url = '$_baseUrl/$model:streamGenerateContent?alt=sse&key=$apiKey';
    final dio = Dio();

    final body = {
      'system_instruction': {
        'parts': [
          {'text': systemPrompt}
        ]
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': userMessage}
          ]
        }
      ],
      'generationConfig': {'maxOutputTokens': 4096},
    };

    late Response<ResponseBody> response;
    try {
      response = await dio.post<ResponseBody>(
        url,
        data: jsonEncode(body),
        options: Options(
          responseType: ResponseType.stream,
          headers: {'content-type': 'application/json'},
        ),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 400) {
        throw const LlmApiException(
          'Invalid Gemini request. Check your API key and model selection.',
          statusCode: 400,
        );
      }
      if (status == 403) {
        throw const LlmApiException(
          'Gemini API key invalid or quota exceeded. Check your key in Settings → AI Analysis.',
          statusCode: 403,
        );
      }
      if (status == 429) {
        throw const LlmApiException(
          'Gemini rate limit reached. Please wait a moment and try again.',
          statusCode: 429,
        );
      }
      if (status != null && status >= 500) {
        throw LlmApiException(
          'Gemini server error ($status). Please try again later.',
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

        Map<String, dynamic> event;
        try {
          event = jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }

        final candidates = event['candidates'] as List<dynamic>?;
        final content =
            candidates?.firstOrNull?['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List<dynamic>?;
        final text = parts?.firstOrNull?['text'] as String?;
        if (text != null && text.isNotEmpty) yield text;
      }
    }
  }
}
