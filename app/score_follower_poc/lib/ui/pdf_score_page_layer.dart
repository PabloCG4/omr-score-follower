import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Immutable visual layer for one PDF page. Free of alignment state so it does
/// not rebuild when the cursor moves at 30–60 Hz.
class PdfScorePageLayer extends StatelessWidget {
  const PdfScorePageLayer({
    super.key,
    required this.pdfDocument,
    required this.pageIndex,
  });

  final PdfDocument pdfDocument;

  /// Zero-based page index (converted to 1-based for pdfrx).
  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    return PdfPageView(
      document: pdfDocument,
      pageNumber: pageIndex + 1,
      alignment: Alignment.center,
      backgroundColor: Colors.white,
      decoration: const BoxDecoration(color: Colors.white),
    );
  }
}
