abstract class LlmService {
  Stream<String> streamAnalysis({
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userMessage,
  });
}

class LlmApiException implements Exception {
  const LlmApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

enum LlmProvider { claude, groq, gemini }

class LlmModelOption {
  const LlmModelOption({
    required this.id,
    required this.label,
    required this.note,
  });

  final String id;
  final String label;
  final String note;
}

const claudeModels = [
  LlmModelOption(
    id: 'claude-opus-4-7',
    label: 'Opus 4.7',
    note: 'Most capable · \$5 / \$25 per 1M tokens',
  ),
  LlmModelOption(
    id: 'claude-sonnet-4-6',
    label: 'Sonnet 4.6',
    note: 'Balanced · \$3 / \$15 per 1M tokens',
  ),
  LlmModelOption(
    id: 'claude-haiku-4-5',
    label: 'Haiku 4.5',
    note: 'Fastest & cheapest · \$1 / \$5 per 1M tokens',
  ),
];

const groqModels = [
  LlmModelOption(
    id: 'llama-3.3-70b-versatile',
    label: 'Llama 3.3 70B',
    note: 'Best quality · Free',
  ),
  LlmModelOption(
    id: 'llama-3.1-8b-instant',
    label: 'Llama 3.1 8B',
    note: 'Fastest · Free',
  ),
  LlmModelOption(
    id: 'mixtral-8x7b-32768',
    label: 'Mixtral 8x7B',
    note: 'Good quality · Free',
  ),
];

const geminiModels = [
  LlmModelOption(
    id: 'gemini-2.0-flash',
    label: 'Gemini 2.0 Flash',
    note: 'Best free option',
  ),
  LlmModelOption(
    id: 'gemini-1.5-flash',
    label: 'Gemini 1.5 Flash',
    note: 'Fast & free',
  ),
  LlmModelOption(
    id: 'gemini-1.5-pro',
    label: 'Gemini 1.5 Pro',
    note: 'Higher quality · Limited free quota',
  ),
];

const defaultClaudeModel = 'claude-opus-4-7';
const defaultGroqModel = 'llama-3.3-70b-versatile';
const defaultGeminiModel = 'gemini-2.0-flash';

List<LlmModelOption> modelsFor(LlmProvider provider) => switch (provider) {
      LlmProvider.claude => claudeModels,
      LlmProvider.groq => groqModels,
      LlmProvider.gemini => geminiModels,
    };

String defaultModelFor(LlmProvider provider) => switch (provider) {
      LlmProvider.claude => defaultClaudeModel,
      LlmProvider.groq => defaultGroqModel,
      LlmProvider.gemini => defaultGeminiModel,
    };
