import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../score/score_page.dart';

/// Immutable visual layer for one score page. Intentionally free of alignment
/// state so it does not rebuild when the cursor moves at 30–60 Hz.
class ScorePageLayer extends StatelessWidget {
  const ScorePageLayer({
    super.key,
    required this.page,
  });

  final ScorePage page;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      page.assetPath,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      placeholderBuilder: (context) {
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}
