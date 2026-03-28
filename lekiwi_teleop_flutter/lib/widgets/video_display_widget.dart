import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class VideoDisplayWidget extends StatelessWidget {
  final Map<String, dynamic>? observationData;
  final String cameraKey; // Should be 'front' or 'wrist'
  final bool isThumbnail; // New parameter for thumbnail mode
  final bool flipped; // 180° rotation
  final VoidCallback? onTitleTap; // New parameter for click handling
  final VoidCallback? onFlipTap; // Flip toggle callback

  const VideoDisplayWidget({
    super.key,
    required this.observationData,
    required this.cameraKey,
    this.isThumbnail = false,
    this.flipped = false,
    this.onTitleTap,
    this.onFlipTap,
  });

  @override
  Widget build(BuildContext context) {
    // Extract observation data from the message
    final data = observationData?['data'] as Map<String, dynamic>?;
    final imageKey = 'observation.images.$cameraKey';
    final imageData = data?[imageKey] as Map<String, dynamic>?;
    
    if (imageData == null || imageData['type'] != 'image') {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.videocam_off, 
                size: isThumbnail ? 24 : 48, 
                color: Colors.grey
              ),
              SizedBox(height: isThumbnail ? 4 : 8),
              Text(
                '${cameraKey.toUpperCase()} Camera', 
                style: TextStyle(
                  color: Colors.grey, 
                  fontSize: isThumbnail ? 8 : 12
                )
              ),
              Text(
                'No Signal', 
                style: TextStyle(
                  color: Colors.grey, 
                  fontSize: isThumbnail ? 6 : 10
                )
              ),
            ],
          ),
        ),
      );
    }

    // Decode base64 image data
    try {
      final String base64String = imageData['data'] as String;
      final Uint8List imageBytes = base64Decode(base64String);
      
      Widget image = Image.memory(
        imageBytes,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true, // Prevents blinking on image update
        errorBuilder: (context, error, stackTrace) {
          return Center(
            child: Text(
              '${cameraKey.toUpperCase()} Error', 
              style: TextStyle(
                color: Colors.red,
                fontSize: isThumbnail ? 8 : 12,
              )
            )
          );
        },
      );

      if (flipped) {
        image = Transform.rotate(angle: 3.14159265, child: image);
      }

      // Extract detections for this camera
      final detectionsData = data?['detections'] as Map<String, dynamic>?;
      List<dynamic>? camDetections;
      List<num>? imageSize;
      if (detectionsData != null && detectionsData['type'] == 'detections') {
        final detData = detectionsData['data'] as Map<String, dynamic>?;
        if (detData != null) {
          camDetections = detData[cameraKey] as List<dynamic>?;
        }
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              image,
              // Detection bounding box overlay
              if (camDetections != null && camDetections.isNotEmpty && !isThumbnail)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DetectionOverlayPainter(
                      detections: camDetections,
                      widgetSize: Size(constraints.maxWidth, constraints.maxHeight),
                      flipped: flipped,
                    ),
                  ),
                ),
              // Camera label overlay with click handling
              Positioned(
            top: isThumbnail ? 4 : 8,
            left: isThumbnail ? 4 : 8,
            child: GestureDetector(
              onTap: onTitleTap,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isThumbnail ? 4 : 8, 
                  vertical: isThumbnail ? 2 : 4
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  cameraKey.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isThumbnail ? 8 : 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          // Flip button (top-right of video)
          if (!isThumbnail && onFlipTap != null)
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: onFlipTap,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: flipped ? Colors.blue.withOpacity(0.7) : Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.flip_camera_android, color: Colors.white, size: 18),
                ),
              ),
            ),
        ],
      );
        },
      );
    } catch (e) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error, 
                size: isThumbnail ? 24 : 48, 
                color: Colors.red
              ),
              SizedBox(height: isThumbnail ? 4 : 8),
              Text(
                '${cameraKey.toUpperCase()} Camera', 
                style: TextStyle(
                  color: Colors.red, 
                  fontSize: isThumbnail ? 8 : 12
                )
              ),
              Text(
                'Decode Error', 
                style: TextStyle(
                  color: Colors.red, 
                  fontSize: isThumbnail ? 6 : 10
                )
              ),
            ],
          ),
        ),
      );
    }
  }
}

class _DetectionOverlayPainter extends CustomPainter {
  final List<dynamic> detections;
  final Size widgetSize;
  final bool flipped;

  _DetectionOverlayPainter({
    required this.detections,
    required this.widgetSize,
    required this.flipped,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final boxPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final bgPaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;

    for (final det in detections) {
      final bbox = det['bbox'] as List<dynamic>?;
      final className = det['class'] as String? ?? '?';
      final conf = det['confidence'] as num? ?? 0;
      if (bbox == null || bbox.length < 4) continue;

      // bbox is [x1, y1, x2, y2] in original image pixel coordinates
      // We need to scale to widget size. Assume image fills widget (BoxFit.cover)
      // The image aspect ratio vs widget ratio determines the actual mapping.
      // For simplicity, use the widget size directly — the image uses BoxFit.cover
      // so the mapping isn't exact, but close enough for UX.
      // TODO: pass actual image dimensions for exact mapping
      final imgW = 640.0; // typical camera resolution
      final imgH = 480.0;

      double scaleX = size.width / imgW;
      double scaleY = size.height / imgH;

      double x1 = bbox[0].toDouble() * scaleX;
      double y1 = bbox[1].toDouble() * scaleY;
      double x2 = bbox[2].toDouble() * scaleX;
      double y2 = bbox[3].toDouble() * scaleY;

      if (flipped) {
        final tmpX1 = size.width - x2;
        final tmpX2 = size.width - x1;
        final tmpY1 = size.height - y2;
        final tmpY2 = size.height - y1;
        x1 = tmpX1; y1 = tmpY1; x2 = tmpX2; y2 = tmpY2;
      }

      final rect = Rect.fromLTRB(x1, y1, x2, y2);
      canvas.drawRect(rect, boxPaint);

      // Label background + text
      final label = '${className} ${(conf * 100).toInt()}%';
      final textSpan = TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final labelRect = Rect.fromLTWH(
        x1, y1 - textPainter.height - 2,
        textPainter.width + 6, textPainter.height + 2,
      );
      canvas.drawRect(labelRect, bgPaint);
      textPainter.paint(canvas, Offset(x1 + 3, y1 - textPainter.height - 1));
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionOverlayPainter oldDelegate) {
    return detections != oldDelegate.detections;
  }
}