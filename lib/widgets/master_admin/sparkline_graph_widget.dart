import 'package:flutter/material.dart';
import '../../utils/constants.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// MiniSparkline
///
/// Smooth cubic Bézier micro-chart that renders clean velocity curves inside
/// metric cards with glowing stroke and soft gradient baseline fill.
/// ─────────────────────────────────────────────────────────────────────────────
class MiniSparkline extends StatelessWidget {
  final List<double> data;
  final Color color;
  final double height;
  final double strokeWidth;
  final bool showFill;

  const MiniSparkline({
    super.key,
    required this.data,
    required this.color,
    this.height = 22,
    this.strokeWidth = 1.8,
    this.showFill = true,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return SizedBox(height: height);

    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(
          data: data,
          lineColor: color,
          strokeWidth: strokeWidth,
          showFill: showFill,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color lineColor;
  final double strokeWidth;
  final bool showFill;

  _SparklinePainter({
    required this.data,
    required this.lineColor,
    required this.strokeWidth,
    required this.showFill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    double minVal = data.reduce((a, b) => a < b ? a : b);
    double maxVal = data.reduce((a, b) => a > b ? a : b);
    if ((maxVal - minVal).abs() < 0.0001) {
      maxVal += 1.0;
      minVal -= 1.0;
    }

    final double stepX = size.width / (data.length - 1);
    final points = <Offset>[];

    for (int i = 0; i < data.length; i++) {
      final double normalizedY = (data[i] - minVal) / (maxVal - minVal);
      // Invert Y because canvas (0,0) is top-left
      final double y = size.height - (normalizedY * (size.height - 4)) - 2;
      final double x = i * stepX;
      points.add(Offset(x, y));
    }

    final strokePath = Path();
    strokePath.moveTo(points.first.dx, points.first.dy);

    for (int i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      final controlPoint1 = Offset(current.dx + (next.dx - current.dx) / 2, current.dy);
      final controlPoint2 = Offset(current.dx + (next.dx - current.dx) / 2, next.dy);
      strokePath.cubicTo(
        controlPoint1.dx, controlPoint1.dy,
        controlPoint2.dx, controlPoint2.dy,
        next.dx, next.dy,
      );
    }

    // Optional gradient fill below line
    if (showFill) {
      final fillPath = Path.from(strokePath);
      fillPath.lineTo(size.width, size.height);
      fillPath.lineTo(0, size.height);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.35),
            lineColor.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.fill;

      canvas.drawPath(fillPath, fillPaint);
    }

    // Line stroke
    final strokePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(strokePath, strokePaint);

    // End point highlight dot
    final lastPoint = points.last;
    final dotGlow = Paint()
      ..color = lineColor.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(lastPoint, 3.5, dotGlow);
    canvas.drawCircle(lastPoint, 1.8, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.lineColor != lineColor;
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// TrendDeltaBadge
///
/// Clean visual delta pill displaying percentage change (e.g. +12.4% vs last week)
/// ─────────────────────────────────────────────────────────────────────────────
class TrendDeltaBadge extends StatelessWidget {
  final double deltaPercent;
  final String? comparisonLabel;
  final bool compact;

  const TrendDeltaBadge({
    super.key,
    required this.deltaPercent,
    this.comparisonLabel,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = deltaPercent > 0.05;
    final isNegative = deltaPercent < -0.05;

    final Color badgeColor = isPositive
        ? const Color(0xFF10B981) // Green
        : isNegative
            ? const Color(0xFFF43F5E) // Rose/Red
            : AppColors.textSecondary; // Neutral

    final IconData icon = isPositive
        ? Icons.trending_up_rounded
        : isNegative
            ? Icons.trending_down_rounded
            : Icons.trending_flat_rounded;

    final String sign = isPositive ? '+' : '';
    final String text = '$sign${deltaPercent.toStringAsFixed(1)}%';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4.5 : 6.0,
        vertical: compact ? 1.5 : 2.5,
      ),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.28),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 10.5 : 12, color: badgeColor),
          const SizedBox(width: 2.5),
          Text(
            text,
            style: TextStyle(
              color: badgeColor,
              fontSize: compact ? 9.0 : 10.0,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.2,
            ),
          ),
          if (comparisonLabel != null && !compact) ...[
            const SizedBox(width: 3),
            Text(
              comparisonLabel!,
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.7),
                fontSize: 8.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// InteractiveTrafficGraph
///
/// Comprehensive traffic timeline chart displaying daily active user trends
/// with interactive touch tooltips, peak badges, and grid lines.
/// ─────────────────────────────────────────────────────────────────────────────
class InteractiveTrafficGraph extends StatefulWidget {
  final List<double> dailyValues;
  final List<String> labels;
  final Color primaryColor;
  final String title;
  final String subtitle;

  const InteractiveTrafficGraph({
    super.key,
    required this.dailyValues,
    required this.labels,
    this.primaryColor = const Color(0xFF38BDF8),
    this.title = 'Traffic Velocity Trend',
    this.subtitle = 'Daily active workspace members over time',
  });

  @override
  State<InteractiveTrafficGraph> createState() => _InteractiveTrafficGraphState();
}

class _InteractiveTrafficGraphState extends State<InteractiveTrafficGraph> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.dailyValues.isEmpty) return const SizedBox.shrink();

    final maxVal = widget.dailyValues.reduce((a, b) => a > b ? a : b);
    final minVal = widget.dailyValues.reduce((a, b) => a < b ? a : b);
    final avgVal = widget.dailyValues.reduce((a, b) => a + b) / widget.dailyValues.length;
    final peakIndex = widget.dailyValues.indexOf(maxVal);

    final selectedIdx = _selectedIndex ?? (widget.dailyValues.length - 1);
    final selectedVal = widget.dailyValues[selectedIdx];
    final selectedLabel = selectedIdx < widget.labels.length ? widget.labels[selectedIdx] : '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.primaryColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.primaryColor.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Selected Value
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.primaryColor,
                          boxShadow: [
                            BoxShadow(
                              color: widget.primaryColor.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.title,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    widget.subtitle,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: widget.primaryColor.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${selectedVal.toInt()} active',
                      style: TextStyle(
                        color: widget.primaryColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      selectedLabel,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 8.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Interactive Canvas
          SizedBox(
            height: 95,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTapDown: (details) {
                    final boxWidth = constraints.maxWidth;
                    final stepX = boxWidth / (widget.dailyValues.length - 1);
                    final touchIndex = (details.localPosition.dx / stepX).round().clamp(0, widget.dailyValues.length - 1);
                    setState(() => _selectedIndex = touchIndex);
                  },
                  onHorizontalDragUpdate: (details) {
                    final boxWidth = constraints.maxWidth;
                    final stepX = boxWidth / (widget.dailyValues.length - 1);
                    final touchIndex = (details.localPosition.dx / stepX).round().clamp(0, widget.dailyValues.length - 1);
                    setState(() => _selectedIndex = touchIndex);
                  },
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 95),
                    painter: _FullGraphPainter(
                      data: widget.dailyValues,
                      color: widget.primaryColor,
                      selectedIndex: _selectedIndex,
                      peakIndex: peakIndex,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),

          // X-Axis Date Labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(widget.labels.length, (i) {
              final isSelected = i == selectedIdx;
              return Text(
                widget.labels[i],
                style: TextStyle(
                  color: isSelected ? widget.primaryColor : AppColors.textSecondary.withValues(alpha: 0.6),
                  fontSize: 8.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              );
            }),
          ),
          const SizedBox(height: 10),

          // Summary Stats Footnote
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatChip('Avg / Day', '${avgVal.toStringAsFixed(1)} users'),
              _buildStatChip('Peak Traffic', '${maxVal.toInt()} (${widget.labels[peakIndex]})'),
              _buildStatChip('Lowest', '${minVal.toInt()} users'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 9,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _FullGraphPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final int? selectedIndex;
  final int peakIndex;

  _FullGraphPainter({
    required this.data,
    required this.color,
    this.selectedIndex,
    required this.peakIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    double minVal = data.reduce((a, b) => a < b ? a : b);
    double maxVal = data.reduce((a, b) => a > b ? a : b);
    if ((maxVal - minVal).abs() < 0.0001) {
      maxVal += 1.0;
      minVal -= 1.0;
    }

    final double stepX = size.width / (data.length - 1);
    final points = <Offset>[];

    // Grid lines (3 horizontal guides)
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;
    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), gridPaint);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), gridPaint);
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), gridPaint);

    for (int i = 0; i < data.length; i++) {
      final double normalizedY = (data[i] - minVal) / (maxVal - minVal);
      final double y = size.height - (normalizedY * (size.height - 18)) - 10;
      final double x = i * stepX;
      points.add(Offset(x, y));
    }

    // Spline curve
    final strokePath = Path();
    strokePath.moveTo(points.first.dx, points.first.dy);

    for (int i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      final cp1 = Offset(current.dx + (next.dx - current.dx) / 2, current.dy);
      final cp2 = Offset(current.dx + (next.dx - current.dx) / 2, next.dy);
      strokePath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, next.dx, next.dy);
    }

    // Area Fill
    final fillPath = Path.from(strokePath);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.28),
          color.withValues(alpha: 0.01),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    // Stroke
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(strokePath, strokePaint);

    // Draw Dots
    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      final isSelected = selectedIndex == i;
      final isPeak = peakIndex == i;

      if (isSelected) {
        // Vertical indicator line
        final vLinePaint = Paint()
          ..color = color.withValues(alpha: 0.4)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        canvas.drawLine(Offset(pt.dx, 0), Offset(pt.dx, size.height), vLinePaint);

        // Highlight ring
        canvas.drawCircle(pt, 6.0, Paint()..color = color.withValues(alpha: 0.3));
        canvas.drawCircle(pt, 4.0, Paint()..color = Colors.white);
        canvas.drawCircle(pt, 2.5, Paint()..color = color);
      } else if (isPeak) {
        canvas.drawCircle(pt, 4.5, Paint()..color = Colors.amberAccent.withValues(alpha: 0.4));
        canvas.drawCircle(pt, 2.8, Paint()..color = Colors.amberAccent);
      } else {
        canvas.drawCircle(pt, 2.5, Paint()..color = color.withValues(alpha: 0.8));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FullGraphPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex || oldDelegate.data != data;
  }
}
