import 'package:flutter/material.dart';

import '../session/cursor_display_model.dart';
import '../session/following_session_controller.dart';
import 'cursor_overlay.dart';
import 'score_page_layer.dart';

/// Score pages plus the selectively-rebuilt cursor overlay. Listens to
/// [FollowingSessionController] only for page-index / document changes; the
/// cursor itself listens solely to [CursorDisplayModel].
class ScoreViewport extends StatefulWidget {
  const ScoreViewport({
    super.key,
    required this.sessionController,
    required this.cursorDisplayModel,
  });

  final FollowingSessionController sessionController;
  final CursorDisplayModel cursorDisplayModel;

  @override
  State<ScoreViewport> createState() => ScoreViewportState();
}

class ScoreViewportState extends State<ScoreViewport> {
  late final PageController pageController;
  int lastSyncedPageIndex = 0;

  @override
  void initState() {
    super.initState();
    pageController = PageController(
      initialPage: widget.sessionController.currentPageIndex,
    );
    lastSyncedPageIndex = widget.sessionController.currentPageIndex;
    widget.sessionController.addListener(onSessionChanged);
  }

  @override
  void dispose() {
    widget.sessionController.removeListener(onSessionChanged);
    pageController.dispose();
    super.dispose();
  }

  void onSessionChanged() {
    final targetPage = widget.sessionController.currentPageIndex;
    if (targetPage == lastSyncedPageIndex) {
      return;
    }
    lastSyncedPageIndex = targetPage;
    if (!pageController.hasClients) {
      return;
    }
    widget.sessionController.onPageTransitionChanged(true);
    pageController
        .animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOut,
        )
        .whenComplete(() {
      widget.sessionController.onPageTransitionChanged(false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.sessionController.scoreDocument;
    if (document == null) {
      return const Center(child: Text('No score loaded.'));
    }

    final canNavigate = widget.sessionController.canNavigateManually;

    return LayoutBuilder(
      builder: (context, constraints) {
        return PageView.builder(
          controller: pageController,
          physics: canNavigate
              ? const PageScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          onPageChanged: (pageIndex) {
            lastSyncedPageIndex = pageIndex;
            widget.sessionController.adoptPageIndexFromViewport(pageIndex);
          },
          itemCount: document.pages.length,
          itemBuilder: (context, pageIndex) {
            final page = document.pages[pageIndex];
            final pageSize = computeLetterboxedSize(
              constraints.biggest,
              page.aspectRatio,
            );
            return Center(
              child: SizedBox(
                width: pageSize.width,
                height: pageSize.height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: canNavigate
                      ? (details) {
                          widget.sessionController.onScorePageTapped(
                            pageIndex: pageIndex,
                            localPosition: details.localPosition,
                            pageSize: pageSize,
                          );
                        }
                      : null,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ScorePageLayer(page: page),
                      ListenableBuilder(
                        listenable: widget.cursorDisplayModel,
                        builder: (context, child) {
                          final model = widget.cursorDisplayModel;
                          final pose = model.displayedPose;
                          final hideCursor = model.isPageTransitionInProgress ||
                              pose.pageIndex != pageIndex;
                          return CursorOverlay(
                            pose: pose,
                            isHidden: hideCursor,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Fits a page of the given aspect ratio inside [viewport] without cropping.
  Size computeLetterboxedSize(Size viewport, double aspectRatio) {
    if (viewport.width <= 0 || viewport.height <= 0 || aspectRatio <= 0) {
      return Size.zero;
    }
    final viewportAspect = viewport.width / viewport.height;
    if (viewportAspect > aspectRatio) {
      final height = viewport.height;
      return Size(height * aspectRatio, height);
    }
    final width = viewport.width;
    return Size(width, width / aspectRatio);
  }
}
