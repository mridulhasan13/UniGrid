import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../utils/constants.dart';

enum CropShape { circle, square, banner }

/// A modern, interactive in-app image cropper and editor dialog.
/// Supports zooming/scaling, 2D dragging/panning, 90° rotation, flipping,
/// and circular / rectangular display picture guides with dark vignette surroundings.
class ImageCropDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final CropShape initialShape;
  final String title;

  const ImageCropDialog({
    super.key,
    required this.imageBytes,
    this.initialShape = CropShape.circle,
    this.title = 'Adjust Profile Picture',
  });

  /// Static helper to show the crop dialog and return the edited Uint8List bytes.
  static Future<Uint8List?> show(
    BuildContext context, {
    required Uint8List imageBytes,
    CropShape initialShape = CropShape.circle,
    String title = 'Adjust Profile Picture',
  }) {
    return showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (context) => ImageCropDialog(
        imageBytes: imageBytes,
        initialShape: initialShape,
        title: title,
      ),
    );
  }

  @override
  State<ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<ImageCropDialog> {
  ui.Image? _decodedImage;
  bool _isLoading = true;
  String? _errorMessage;

  late CropShape _currentShape;
  double _scale = 1.0;
  double _baseScale = 1.0;
  Offset _offset = Offset.zero;
  int _rotationQuarterTurns = 0; // 0, 1, 2, 3
  bool _isFlippedHorizontally = false;
  bool _isProcessing = false;

  Size _canvasSize = Size.zero;
  Offset? _lastFocalPoint;

  @override
  void initState() {
    super.initState();
    _currentShape = widget.initialShape;
    _decodeImage();
  }

  Future<void> _decodeImage() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _decodedImage = frame.image;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load image: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _rotateClockwise() {
    setState(() {
      _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4;
    });
  }

  void _rotateCounterClockwise() {
    setState(() {
      _rotationQuarterTurns = (_rotationQuarterTurns - 1 + 4) % 4;
    });
  }

  void _flipHorizontal() {
    setState(() {
      _isFlippedHorizontally = !_isFlippedHorizontally;
    });
  }

  void _reset() {
    setState(() {
      _scale = 1.0;
      _offset = Offset.zero;
      _rotationQuarterTurns = 0;
      _isFlippedHorizontally = false;
    });
  }

  double get _totalAngle => _rotationQuarterTurns * (math.pi / 2);

  Rect _getCropRect(Size viewSize) {
    const double padding = 20.0;
    final double maxW = math.max(10, viewSize.width - (padding * 2));
    final double maxH = math.max(10, viewSize.height - (padding * 2));

    double targetW, targetH;
    if (_currentShape == CropShape.banner) {
      // 16:9 ratio
      targetW = maxW;
      targetH = targetW * (9 / 16);
      if (targetH > maxH) {
        targetH = maxH;
        targetW = targetH * (16 / 9);
      }
    } else {
      // 1:1 ratio (circle or square)
      final size = math.min(maxW, maxH);
      targetW = size;
      targetH = size;
    }

    final double left = (viewSize.width - targetW) / 2;
    final double top = (viewSize.height - targetH) / 2;
    return Rect.fromLTWH(left, top, targetW, targetH);
  }

  Future<void> _exportCroppedImage() async {
    if (_decodedImage == null || _isProcessing) return;
    if (_canvasSize == Size.zero) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final cropRect = _getCropRect(_canvasSize);
      final double outputSize = _currentShape == CropShape.banner ? 1024 : 600;
      final double outputWidth = outputSize;
      final double outputHeight = _currentShape == CropShape.banner
          ? (outputSize * (9 / 16))
          : outputSize;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, outputWidth, outputHeight),
      );

      // Scale factor between preview cropRect and high-res output
      final double scaleFactor = outputWidth / cropRect.width;

      // Fill black background for any empty border
      final bgPaint = Paint()..color = Colors.black;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, outputWidth, outputHeight),
        bgPaint,
      );

      // Clip canvas if circular
      if (_currentShape == CropShape.circle) {
        final path = Path()
          ..addOval(Rect.fromLTWH(0, 0, outputWidth, outputHeight));
        canvas.clipPath(path);
      }

      // Center of output canvas
      canvas.save();
      canvas.translate(outputWidth / 2, outputHeight / 2);

      // Apply User Offset
      canvas.translate(_offset.dx * scaleFactor, _offset.dy * scaleFactor);

      // Apply Rotation
      canvas.rotate(_totalAngle);

      // Apply Flip
      if (_isFlippedHorizontally) {
        canvas.scale(-1.0, 1.0);
      }

      // Apply Scale
      final double imgW = _decodedImage!.width.toDouble();
      final double imgH = _decodedImage!.height.toDouble();

      final double fitScale = math.max(
        cropRect.width / imgW,
        cropRect.height / imgH,
      );
      final double finalScale = _scale * fitScale * scaleFactor;

      canvas.scale(finalScale, finalScale);

      // Draw image centered
      canvas.drawImage(
        _decodedImage!,
        Offset(-imgW / 2, -imgH / 2),
        Paint()..filterQuality = FilterQuality.high,
      );

      canvas.restore();

      final picture = recorder.endRecording();
      final renderedImage = await picture.toImage(
        outputWidth.toInt(),
        outputHeight.toInt(),
      );

      final byteData =
          await renderedImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to generate PNG byte data');

      final croppedBytes = byteData.buffer.asUint8List();

      if (mounted) {
        Navigator.of(context).pop(croppedBytes);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cropping image: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxDialogH = math.min(680.0, media.size.height * 0.90);
    final maxDialogW = math.min(480.0, media.size.width * 0.94);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Container(
        width: maxDialogW,
        height: maxDialogH,
        decoration: BoxDecoration(
          color: const Color(0xFF0C1322),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 30,
              spreadRadius: 8,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            children: [
              // Top Header Bar
              _buildHeader(context),

              // Interactive Image Preview Canvas with Dark Surroundings
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      )
                    : (_errorMessage != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final viewSize = Size(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              );
                              _canvasSize = viewSize;
                              return _buildCanvas(viewSize);
                            },
                          )),
              ),

              // Bottom Editor Controls Toolbar
              _buildControlPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.glassCardColor.withValues(alpha: 0.6),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.crop_rotate_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                widget.title,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: _isProcessing
                ? null
                : () => Navigator.of(context).pop(null),
            icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
            splashRadius: 20,
            tooltip: 'Cancel',
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(Size viewSize) {
    final cropRect = _getCropRect(viewSize);

    return GestureDetector(
      onScaleStart: (details) {
        _baseScale = _scale;
        _lastFocalPoint = details.localFocalPoint;
      },
      onScaleUpdate: (details) {
        setState(() {
          // Zoom scale with clamp
          _scale = (_baseScale * details.scale).clamp(0.6, 5.0);

          // Panning delta
          if (_lastFocalPoint != null) {
            final delta = details.localFocalPoint - _lastFocalPoint!;
            _offset += delta;
            _lastFocalPoint = details.localFocalPoint;
          }
        });
      },
      onScaleEnd: (_) {
        _lastFocalPoint = null;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Deep dark canvas background
          Container(
            color: const Color(0xFF030710),
          ),

          // Custom Render of Transformed Image and Mask
          CustomPaint(
            size: viewSize,
            painter: _ImageCropPainter(
              image: _decodedImage!,
              cropRect: cropRect,
              shape: _currentShape,
              scale: _scale,
              offset: _offset,
              totalAngle: _totalAngle,
              isFlippedHorizontally: _isFlippedHorizontally,
            ),
          ),

          // Floating helper hint
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app_rounded,
                        color: AppColors.secondary, size: 13),
                    const SizedBox(width: 5),
                    const Text(
                      'Drag to position • Pinch to zoom',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.glassCardColor.withValues(alpha: 0.8),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Shape Selector (Scrollable to prevent any RenderFlex overflow) & Reset
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildShapeChip(
                          shape: CropShape.circle,
                          icon: Icons.account_circle_outlined,
                          label: 'Circle Avatar',
                        ),
                        const SizedBox(width: 4),
                        _buildShapeChip(
                          shape: CropShape.square,
                          icon: Icons.crop_square_rounded,
                          label: 'Square DP',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _reset,
                icon: Icon(Icons.refresh_rounded,
                    size: 15, color: AppColors.secondary),
                label: Text(
                  'Reset',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Row 2: Zoom Slider
          Row(
            children: [
              const Icon(Icons.zoom_out_rounded,
                  color: AppColors.textSecondary, size: 16),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.5,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: Colors.white12,
                    thumbColor: AppColors.primary,
                  ),
                  child: Slider(
                    value: _scale,
                    min: 0.8,
                    max: 4.0,
                    onChanged: (val) {
                      setState(() {
                        _scale = val;
                      });
                    },
                  ),
                ),
              ),
              const Icon(Icons.zoom_in_rounded,
                  color: AppColors.textSecondary, size: 16),
              const SizedBox(width: 4),
              SizedBox(
                width: 38,
                child: Text(
                  '${(_scale * 100).toInt()}%',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Row 3: Actions (Rotate Left, Rotate Right, Flip) & Apply Button
          Row(
            children: [
              _buildActionButton(
                icon: Icons.rotate_left_rounded,
                tooltip: 'Rotate 90° Left',
                onPressed: _rotateCounterClockwise,
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                icon: Icons.rotate_right_rounded,
                tooltip: 'Rotate 90° Right',
                onPressed: _rotateClockwise,
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                icon: Icons.flip_rounded,
                tooltip: 'Flip Horizontal',
                onPressed: _flipHorizontal,
                isActive: _isFlippedHorizontally,
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _isProcessing ? null : _exportCroppedImage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 3,
                ),
                icon: _isProcessing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 16),
                label: Text(
                  _isProcessing ? 'Applying...' : 'Apply Photo',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShapeChip({
    required CropShape shape,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _currentShape == shape;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentShape = shape;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool isActive = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primary.withValues(alpha: 0.25)
            : Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? AppColors.primary : Colors.white12,
        ),
      ),
      child: IconButton(
        icon: Icon(
          icon,
          size: 17,
          color: isActive ? AppColors.primary : AppColors.textPrimary,
        ),
        tooltip: tooltip,
        onPressed: onPressed,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: EdgeInsets.zero,
        splashRadius: 18,
      ),
    );
  }
}

/// Custom painter that draws the transformed image, darkened vignette mask,
/// circular or rectangular crop border, and rule of thirds guides.
class _ImageCropPainter extends CustomPainter {
  final ui.Image image;
  final Rect cropRect;
  final CropShape shape;
  final double scale;
  final Offset offset;
  final double totalAngle;
  final bool isFlippedHorizontally;

  _ImageCropPainter({
    required this.image,
    required this.cropRect,
    required this.shape,
    required this.scale,
    required this.offset,
    required this.totalAngle,
    required this.isFlippedHorizontally,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 0. Strictly clip everything to canvas boundary to prevent bleeding into header/outside
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final double imgW = image.width.toDouble();
    final double imgH = image.height.toDouble();

    // 1. Draw Transformed Image
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.translate(offset.dx, offset.dy);
    canvas.rotate(totalAngle);
    if (isFlippedHorizontally) {
      canvas.scale(-1.0, 1.0);
    }

    final double fitScale = math.max(
      cropRect.width / imgW,
      cropRect.height / imgH,
    );
    final double finalScale = scale * fitScale;
    canvas.scale(finalScale, finalScale);

    canvas.drawImage(
      image,
      Offset(-imgW / 2, -imgH / 2),
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();

    // 2. Draw Solid Deep-Dark Surroundings Mask using PathFillType.evenOdd (100% reliable across Web/Mobile)
    final maskPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    if (shape == CropShape.circle) {
      maskPath.addOval(cropRect);
    } else {
      maskPath.addRRect(
        RRect.fromRectAndRadius(cropRect, const Radius.circular(16)),
      );
    }

    final overlayPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.88)
      ..style = PaintingStyle.fill;
    canvas.drawPath(maskPath, overlayPaint);

    // 3. Draw Rule-of-Thirds Grid Lines inside Crop Rect
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Vertical third lines
    final double thirdW = cropRect.width / 3;
    canvas.drawLine(
      Offset(cropRect.left + thirdW, cropRect.top),
      Offset(cropRect.left + thirdW, cropRect.bottom),
      gridPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left + thirdW * 2, cropRect.top),
      Offset(cropRect.left + thirdW * 2, cropRect.bottom),
      gridPaint,
    );

    // Horizontal third lines
    final double thirdH = cropRect.height / 3;
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top + thirdH),
      Offset(cropRect.right, cropRect.top + thirdH),
      gridPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top + thirdH * 2),
      Offset(cropRect.right, cropRect.top + thirdH * 2),
      gridPaint,
    );

    // 4. Draw Glowing Crop Border
    final borderPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    if (shape == CropShape.circle) {
      canvas.drawOval(cropRect, borderPaint);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(cropRect, const Radius.circular(16)),
        borderPaint,
      );
    }

    // 5. Draw Corner Accent Anchors
    final cornerPaint = Paint()
      ..color = AppColors.secondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    const double cornerLen = 16.0;
    // Top-Left
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top + cornerLen),
      Offset(cropRect.left, cropRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top),
      Offset(cropRect.left + cornerLen, cropRect.top),
      cornerPaint,
    );

    // Top-Right
    canvas.drawLine(
      Offset(cropRect.right - cornerLen, cropRect.top),
      Offset(cropRect.right, cropRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(cropRect.right, cropRect.top),
      Offset(cropRect.right, cropRect.top + cornerLen),
      cornerPaint,
    );

    // Bottom-Left
    canvas.drawLine(
      Offset(cropRect.left, cropRect.bottom - cornerLen),
      Offset(cropRect.left, cropRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left, cropRect.bottom),
      Offset(cropRect.left + cornerLen, cropRect.bottom),
      cornerPaint,
    );

    // Bottom-Right
    canvas.drawLine(
      Offset(cropRect.right - cornerLen, cropRect.bottom),
      Offset(cropRect.right, cropRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(cropRect.right, cropRect.bottom),
      Offset(cropRect.right, cropRect.bottom - cornerLen),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ImageCropPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.cropRect != cropRect ||
        oldDelegate.shape != shape ||
        oldDelegate.scale != scale ||
        oldDelegate.offset != offset ||
        oldDelegate.totalAngle != totalAngle ||
        oldDelegate.isFlippedHorizontally != isFlippedHorizontally;
  }
}
