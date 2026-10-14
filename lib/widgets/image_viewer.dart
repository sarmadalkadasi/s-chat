import 'dart:io';
import 'package:flutter/material.dart';

enum ImageType { assets, network, file }

class ImageViewer extends StatefulWidget {
  final String imageUrl;
  final ImageType imageType;

  const ImageViewer({
    super.key,
    required this.imageUrl,
    required this.imageType,
  });

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  final TransformationController _transformationController =
      TransformationController();

  static const double _minScale = 1.0;
  static const double _maxScale = 5.0;
  static const double _zoomFactor = 1.25;

  double get _currentScale =>
      _transformationController.value.getMaxScaleOnAxis();

  void _zoom(double factor, Size viewportSize) {
    final currentScale = _currentScale;
    final targetScale = (currentScale * factor).clamp(_minScale, _maxScale);
    final actualFactor = targetScale / currentScale;

    if (actualFactor == 1.0) return;

    // Zoom around the center of the viewport.
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);

    final matrix = Matrix4.identity()
      ..translate(center.dx, center.dy)
      ..scale(actualFactor)
      ..translate(-center.dx, -center.dy)
      ..multiply(_transformationController.value);

    _transformationController.value = matrix;
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  Widget _buildImage(Size size) {
    final width = size.width;
    final height = size.height;

    switch (widget.imageType) {
      case ImageType.network:
        return Image.network(
          widget.imageUrl,
          width: width,
          height: height,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;

            return Center(
              child: CircularProgressIndicator(
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Icon(
                Icons.broken_image_outlined,
                size: 64,
                color: Colors.grey,
              ),
            );
          },
        );

      case ImageType.assets:
        return Image.asset(
          widget.imageUrl,
          width: width,
          height: height,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Icon(
                Icons.broken_image_outlined,
                size: 64,
                color: Colors.grey,
              ),
            );
          },
        );

      case ImageType.file:
        return Image.file(
          File(widget.imageUrl),
          width: width,
          height: height,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Icon(
                Icons.broken_image_outlined,
                size: 64,
                color: Colors.grey,
              ),
            );
          },
        );
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Viewer'),
        actions: [
          IconButton(
            tooltip: 'Reset zoom',
            onPressed: _resetZoom,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);

          return Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: _minScale,
                  maxScale: _maxScale,
                  panEnabled: true,
                  scaleEnabled: true,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: Hero(tag: widget.imageUrl, child: _buildImage(size)),
                  ),
                ),
              ),

              // Zoom controls
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Material(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHigh.withAlpha(230),
                    borderRadius: BorderRadius.circular(32),
                    elevation: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Zoom out',
                          onPressed: _currentScale > _minScale
                              ? () => _zoom(1 / _zoomFactor, size)
                              : null,
                          icon: const Icon(Icons.remove_rounded),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '${(_currentScale * 100).round()}%',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Zoom in',
                          onPressed: _currentScale < _maxScale
                              ? () => _zoom(_zoomFactor, size)
                              : null,
                          icon: const Icon(Icons.add_rounded),
                        ),
                        IconButton(
                          tooltip: 'Reset zoom',
                          onPressed: _resetZoom,
                          icon: const Icon(Icons.fit_screen_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
