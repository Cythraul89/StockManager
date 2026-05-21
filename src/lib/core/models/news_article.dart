import 'package:equatable/equatable.dart';

class NewsArticle extends Equatable {
  const NewsArticle({
    required this.headline,
    required this.url,
    required this.source,
    required this.publishedAt,
    this.summary,
  });

  final String headline;
  final String url;
  final String source;
  final DateTime publishedAt;
  final String? summary;

  @override
  List<Object?> get props => [headline, url, source, publishedAt, summary];
}
