
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// A processor that implements Apple Music-like fluid background generation.
/// 
/// The pipeline involves:
/// 1. Downscaling & Blurring
/// 2. Mesh Warping (Distortion)
/// 3. Upscaling
/// 4. Mesh Warping again
/// 5. Blurring again
/// 6. Color Corrections (Saturation/Brightness)
class DynamicBgProcessor {
  
  // The mesh configuration from the provided reference (Apple Music parameters)
  static const List<double> _meshFloats = [
    -0.2351, -0.0967, 0.2135, -0.1414, 0.9221, -0.0908, 0.9221, -0.0685, 1.3027, 0.0253, 1.2351, 0.1786, 
    -0.3768, 0.1851, 0.2, 0.2, 0.6615, 0.3146, 0.9543, 0.0, 0.6969, 0.1911, 1.0, 0.2, 
    0.0, 0.4, 0.2, 0.4, 0.0776, 0.2318, 0.6, 0.4, 0.6615, 0.3851, 1.0, 0.4, 
    0.0, 0.6, 0.1291, 0.6, 0.4, 0.6, 0.4, 0.4304, 0.4264, 0.5792, 1.2029, 0.8188, 
    -0.1192, 1.0, 0.6, 0.8, 0.4264, 0.8104, 0.6, 0.8, 0.8, 0.8, 1.0, 0.8, 
    0.0, 1.0, 0.0776, 1.0283, 0.4, 1.0, 0.6, 1.0, 0.8, 1.0, 1.1868, 1.0283
  ];

  /// Processes the input image to generate a fluid background image.
  /// 
  /// Returns a [ui.Image] that can be drawn on a Canvas.
  static Future<ui.Image> processImage(ui.Image inputImage) async {
    // 1. Initial Scale (Small) & Blur
    // Kotlin: zoom(150f, ...) -> blur(25F)
    const double initialWidth = 150.0;
    final double initialHeight = (inputImage.height * initialWidth / inputImage.width);
    
    // Step 1: Scale Down + Blur
    var tempImage = await _drawToImage(
      (canvas) {
        final paint = Paint()
          ..filterQuality = FilterQuality.medium
          ..imageFilter = ui.ImageFilter.blur(sigmaX: 90.0, sigmaY: 90.0); // radius 90
        
        canvas.drawImageRect(
          inputImage,
          Rect.fromLTWH(0, 0, inputImage.width.toDouble(), inputImage.height.toDouble()),
          Rect.fromLTWH(0, 0, initialWidth, initialHeight),
          paint,
        );
      },
      Size(initialWidth, initialHeight),
    );

    // Step 2: Mesh Warp
    tempImage = await _applyMesh(tempImage, _meshFloats);

    // Step 3: Scale Up (Zoom 1000F)
    // Kotlin: zoom(1000F, 1000F) - Making it square or just large? 
    // The kotlin code says: zoom(1000F, 1000F). It forces 1000x1000.
    const double largeSize = 1000.0;
    
    tempImage = await _drawToImage(
      (canvas) {
        // Just scaling up
        canvas.drawImageRect(
          tempImage,
          Rect.fromLTWH(0, 0, tempImage.width.toDouble(), tempImage.height.toDouble()),
          Rect.fromLTWH(0, 0, largeSize, largeSize),
          Paint()..filterQuality = FilterQuality.low, // Point sampling for speed, we blur later
        );
      },
      Size(largeSize, largeSize),
    );

    // Step 4: Mesh Warp again
    tempImage = await _applyMesh(tempImage, _meshFloats);

    // Step 5: Final Blur & Saturation & Brightness Check
    // Kotlin: blur(12F) -> handleImageEffect(1.8f) (Saturation)
    // Also checks brightness processing and overlay
    
    // We can do blur and saturation in one pass
    final finalImage = await _drawToImage(
      (canvas) {
        final paint = Paint();
        
        // Blur
        paint.imageFilter = ui.ImageFilter.blur(sigmaX: 60.0, sigmaY: 60.0);
        
        // Saturation 1.8
        // ColorMatrix for saturation
        // 1.8 saturation matrix roughly:
        // R = 0.213+0.787*s  0.715-0.715*s  0.072-0.072*s
        // ...
        final matrix = _saturationMatrix(1.8);
        paint.colorFilter = ColorFilter.matrix(matrix);

        canvas.drawImageRect(
          tempImage,
          Rect.fromLTWH(0, 0, tempImage.width.toDouble(), tempImage.height.toDouble()),
          Rect.fromLTWH(0, 0, largeSize, largeSize),
          paint,
        );
      },
      Size(largeSize, largeSize),
    );

    // Step 6: Brightness Check & Overlay
    // We need to read pixels to check brightness.
    // Kotlin: zoom(3,3) -> getPixel(1,1)
    
    // Let's create a tiny 3x3 version of the final image to check brightness
    final tinyImage = await _drawToImage(
      (canvas) {
        canvas.drawImageRect(
          finalImage,
          Rect.fromLTWH(0, 0, finalImage.width.toDouble(), finalImage.height.toDouble()),
          const Rect.fromLTWH(0, 0, 3, 3),
          Paint(),
        );
      },
      const Size(3, 3),
    );

    final brightness = await _calculateBrightness(tinyImage);
    
    // Apply overlay if needed
    if (brightness > 0.8) {
      // Light image -> Dark overlay
      return await _applyOverlay(finalImage, Colors.black.withValues(alpha: 0.31)); // #50000000
    } else if (brightness < 0.2) {
      // Dark image -> Light overlay
      return await _applyOverlay(finalImage, Colors.white.withValues(alpha: 0.31)); // #50FFFFFF
    }

    return finalImage;
  }

  /// Processes the input image for Desktop (Closer to original Kotlin implementation values)
  static Future<ui.Image> processImageDesktop(ui.Image inputImage) async {
    // 1. Initial Scale (Small) & Blur
    // Kotlin: zoom(150f) -> blur(25F) -> Sigma ~12
    const double initialWidth = 150.0;
    final double initialHeight = (inputImage.height * initialWidth / inputImage.width);
    
    var tempImage = await _drawToImage(
      (canvas) {
        final paint = Paint()
          ..filterQuality = FilterQuality.medium
          ..imageFilter = ui.ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0); // radius 25 ~= sigma 12
        
        canvas.drawImageRect(
          inputImage,
          Rect.fromLTWH(0, 0, inputImage.width.toDouble(), inputImage.height.toDouble()),
          Rect.fromLTWH(0, 0, initialWidth, initialHeight),
          paint,
        );
      },
      Size(initialWidth, initialHeight),
    );

    // Step 2: Mesh Warp
    tempImage = await _applyMesh(tempImage, _meshFloats);

    // Step 3: Scale Up (Zoom to Landscape 16:9 for Desktop)
    // Changing from square 1000x1000 to 1280x720 to prevent vertical cropping on wide screens
    const double targetWidth = 1280.0;
    const double targetHeight = 720.0;
    
    tempImage = await _drawToImage(
      (canvas) {
        canvas.drawImageRect(
          tempImage,
          Rect.fromLTWH(0, 0, tempImage.width.toDouble(), tempImage.height.toDouble()),
          Rect.fromLTWH(0, 0, targetWidth, targetHeight),
          Paint()..filterQuality = FilterQuality.low, 
        );
      },
      Size(targetWidth, targetHeight),
    );

    // Step 4: Mesh Warp again
    tempImage = await _applyMesh(tempImage, _meshFloats);

    // Step 5: Final Blur & Saturation & Brightness Check
    // Kotlin: blur(12F) -> Sigma ~6
    final finalImage = await _drawToImage(
      (canvas) {
        final paint = Paint();
        
        // Blur
        paint.imageFilter = ui.ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0);
        
        // Saturation 1.8
        final matrix = _saturationMatrix(1.8);
        paint.colorFilter = ColorFilter.matrix(matrix);

        canvas.drawImageRect(
          tempImage,
          Rect.fromLTWH(0, 0, tempImage.width.toDouble(), tempImage.height.toDouble()),
          Rect.fromLTWH(0, 0, targetWidth, targetHeight),
          paint,
        );
      },
      Size(targetWidth, targetHeight),
    );

    // Step 6: Brightness Check & Overlay
    final tinyImage = await _drawToImage(
      (canvas) {
        canvas.drawImageRect(
          finalImage,
          Rect.fromLTWH(0, 0, finalImage.width.toDouble(), finalImage.height.toDouble()),
          const Rect.fromLTWH(0, 0, 3, 3),
          Paint(),
        );
      },
      const Size(3, 3),
    );

    final brightness = await _calculateBrightness(tinyImage);
    
    // Kotlin: > 0.8 -> #50000000 (Black 31%)
    //         < 0.2 -> #50FFFFFF (White 31%)
    if (brightness > 0.8) {
      return await _applyOverlay(finalImage, Colors.black.withValues(alpha: 0.31));
    } else if (brightness < 0.2) {
      return await _applyOverlay(finalImage, Colors.white.withValues(alpha: 0.31));
    }

    return finalImage;
  }

  static Future<ui.Image> _applyMesh(ui.Image image, List<double> floats) async {
    final width = image.width.toDouble();
    final height = image.height.toDouble();
    
    // Convert floats to absolute coordinates and create vertices
    // The floats provided are for a 5x5 Grid (6 points across, 6 points down = 36 points)
    // 36 points * 2 coords = 72 floats. Correct.
    
    // Texture Coordinates (Regular Grid)
    final int rows = 5;
    final int cols = 5;
    
    final List<Offset> textureCoords = [];
    final List<Offset> positions = [];
    final List<int> indices = [];

    // Generate Vertices
    for (int y = 0; y <= rows; y++) {
      for (int x = 0; x <= cols; x++) {
        // Texture Coord (Regular)
        final tx = (x / cols) * width;
        final ty = (y / rows) * height;
        textureCoords.add(Offset(tx, ty));

        // Position (Distorted from floats) with Amplification
        final index = (y * (cols + 1) + x) * 2;
        
        // Original normalized pos
        final ox = x / cols;
        final oy = y / rows;
        
        // Target normalized pos from floats
        final fx = floats[index];
        final fy = floats[index + 1];
        
        // Amplify the distortion
        const double intensity = 1.5; 
        final nx = ox + (fx - ox) * intensity;
        final ny = oy + (fy - oy) * intensity;

        positions.add(Offset(nx * width, ny * height));
      }
    }

    // Generate Indices (Triangles for grid)
    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        final topLeft = y * (cols + 1) + x;
        final topRight = topLeft + 1;
        final bottomLeft = (y + 1) * (cols + 1) + x;
        final bottomRight = bottomLeft + 1;

        // Triangle 1
        indices.add(topLeft);
        indices.add(topRight);
        indices.add(bottomLeft);

        // Triangle 2
        indices.add(topRight);
        indices.add(bottomRight);
        indices.add(bottomLeft);
      }
    }

    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: textureCoords,
      indices: Uint16List.fromList(indices),
    );

    // Draw mesh
    return await _drawToImage(
      (canvas) {
        final paint = Paint()
          ..shader = ImageShader(
            image, 
            TileMode.clamp, 
            TileMode.clamp, 
            Float64List.fromList(Matrix4.identity().storage),
          );
        canvas.drawVertices(vertices, BlendMode.src, paint);
      },
      Size(width, height), // Maintain size during mesh (or should we?) logic says input image is source.
    );
  }

  static Future<ui.Image> _drawToImage(
    void Function(Canvas) drawCallback,
    Size size,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    drawCallback(canvas);
    final picture = recorder.endRecording();
    return picture.toImage(size.width.toInt(), size.height.toInt());
  }

  static Future<ui.Image> _applyOverlay(ui.Image image, Color color) async {
    return await _drawToImage(
      (canvas) {
        canvas.drawImage(image, Offset.zero, Paint());
        canvas.drawColor(color, BlendMode.srcOver);
      },
      Size(image.width.toDouble(), image.height.toDouble()),
    );
  }

  static Future<double> _calculateBrightness(ui.Image tinyImage) async {
    final byteData = await tinyImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return 0.5;

    // Get center pixel (1, 1). Width is 3. 
    // Index = (y * width + x) * 4
    // (1 * 3 + 1) * 4 = 16
    final offset = 16;
    if (offset + 3 >= byteData.lengthInBytes) return 0.5;

    final r = byteData.getUint8(offset);
    final g = byteData.getUint8(offset + 1);
    final b = byteData.getUint8(offset + 2);
    
    // Y = 0.299R + 0.587G + 0.114B (Standard Rec. 601)
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
  }

  static List<double> _saturationMatrix(double saturation) {
    final double r = 0.213 * (1 - saturation);
    final double g = 0.715 * (1 - saturation);
    final double b = 0.072 * (1 - saturation);
    
    return [
      r + saturation, g, b, 0, 0,
      r, g + saturation, b, 0, 0,
      r, g, b + saturation, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }
}
