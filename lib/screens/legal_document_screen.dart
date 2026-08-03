import 'package:flutter/material.dart';

import '../legal/legal_content.dart';

/// Generic renderer for the Privacy Policy and Terms & Conditions - both
/// are a list of (heading, body) sections plus a shared review disclaimer.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.sections,
  });

  final String title;
  final List<LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(kLegalEffectiveDate, style: textTheme.bodySmall),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(kLegalReviewDisclaimer, style: textTheme.bodySmall),
          ),
          const SizedBox(height: 20),
          for (final section in sections) ...[
            Text(section.heading, style: textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(section.body, style: textTheme.bodyMedium),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}
