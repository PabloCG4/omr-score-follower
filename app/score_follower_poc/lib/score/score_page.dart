/// A single page of a score document, referencing a visual asset and its
/// authored aspect ratio so the viewport can letterbox without distorting
/// the timeline map's normalized coordinates.
final class ScorePage {
  const ScorePage({
    required this.pageIndex,
    required this.assetPath,
    required this.aspectRatio,
  });

  /// Zero-based page index within the owning [ScoreDocument].
  final int pageIndex;

  /// Flutter asset path of the page's SVG (or raster) artwork.
  final String assetPath;

  /// Authored width / height of the page. Used to size the viewport so that
  /// normalized timeline coordinates map 1:1 onto the laid-out pixel space.
  final double aspectRatio;
}
