import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/constants.dart';

/// A widget that detects URLs inside a text string and turns them into
/// interactive, styled, clickable links that open in the device browser or external app.
class LinkifiedText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;
  final TextAlign textAlign;
  final TextOverflow overflow;
  final int? maxLines;
  final bool selectable;

  const LinkifiedText(
    this.text, {
    super.key,
    this.style,
    this.linkStyle,
    this.textAlign = TextAlign.start,
    this.overflow = TextOverflow.clip,
    this.maxLines,
    this.selectable = false,
  });

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  static final RegExp _urlRegex = RegExp(
    r'((?:https?://|ftp://|mailto:|www\.)[^\s<]+|(?:[a-zA-Z0-9-]+\.)+(?:com|org|net|edu|gov|io|co|me|dev|app|bd|info|site|online|tv|cc|xyz|tech|link|store|page|live)(?:/[^\s<]*)?)',
    caseSensitive: false,
  );

  Future<void> _launchUrl(String urlString) async {
    String formatted = urlString.trim();
    if (!formatted.toLowerCase().startsWith('http://') &&
        !formatted.toLowerCase().startsWith('https://') &&
        !formatted.toLowerCase().startsWith('ftp://') &&
        !formatted.toLowerCase().startsWith('mailto:')) {
      formatted = 'https://$formatted';
    }
    final uri = Uri.tryParse(formatted);
    if (uri != null) {
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          await launchUrl(uri);
        }
      } catch (e) {
        debugPrint('Error launching URL ($formatted): $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();

    final text = widget.text;
    if (text.isEmpty) {
      return widget.selectable
          ? SelectableText(
              '',
              style: widget.style,
              textAlign: widget.textAlign,
              maxLines: widget.maxLines,
            )
          : Text(
              '',
              style: widget.style,
              textAlign: widget.textAlign,
              overflow: widget.overflow,
              maxLines: widget.maxLines,
            );
    }

    final baseStyle = widget.style ?? const TextStyle();
    final defaultLinkStyle = baseStyle.copyWith(
      color: AppColors.primary,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.primary,
    );
    final effectiveLinkStyle = widget.linkStyle ?? defaultLinkStyle;

    final matches = _urlRegex.allMatches(text).toList();

    if (matches.isEmpty) {
      return widget.selectable
          ? SelectableText(
              text,
              style: widget.style,
              textAlign: widget.textAlign,
              maxLines: widget.maxLines,
            )
          : Text(
              text,
              style: widget.style,
              textAlign: widget.textAlign,
              overflow: widget.overflow,
              maxLines: widget.maxLines,
            );
    }

    final List<InlineSpan> spans = [];
    int lastEnd = 0;

    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: widget.style,
        ));
      }

      String rawUrl = text.substring(match.start, match.end);
      String trailingPunctuation = '';

      while (rawUrl.isNotEmpty) {
        final lastChar = rawUrl[rawUrl.length - 1];
        if ('.!?:;,`"'.contains(lastChar) ||
            (lastChar == ')' && rawUrl.split('(').length < rawUrl.split(')').length) ||
            (lastChar == ']' && rawUrl.split('[').length < rawUrl.split(']').length)) {
          trailingPunctuation = lastChar + trailingPunctuation;
          rawUrl = rawUrl.substring(0, rawUrl.length - 1);
        } else {
          break;
        }
      }

      if (rawUrl.isNotEmpty) {
        final targetUrl = rawUrl;
        final recognizer = TapGestureRecognizer()
          ..onTap = () => _launchUrl(targetUrl);
        _recognizers.add(recognizer);

        spans.add(TextSpan(
          text: rawUrl,
          style: effectiveLinkStyle,
          recognizer: recognizer,
        ));
      }

      if (trailingPunctuation.isNotEmpty) {
        spans.add(TextSpan(
          text: trailingPunctuation,
          style: widget.style,
        ));
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: widget.style,
      ));
    }

    if (widget.selectable) {
      return SelectableText.rich(
        TextSpan(children: spans),
        style: widget.style,
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
      );
    }

    return Text.rich(
      TextSpan(children: spans),
      style: widget.style,
      textAlign: widget.textAlign,
      overflow: widget.overflow,
      maxLines: widget.maxLines,
    );
  }
}
