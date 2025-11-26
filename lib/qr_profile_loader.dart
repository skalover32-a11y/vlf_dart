import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as im;
import 'package:zxing2/qrcode.dart';

/// Попытатьcя прочитать QR-код из изображения-файла.
/// Возвращает распознанный текст или null.
Future<String?> decodeQrFromImage(File file) async {
  try {
    final bytes = await file.readAsBytes();
    final image = im.decodeImage(bytes);
    if (image == null) return null;

    // Получить RGBA байты (image.getBytes() возвращает байты пикселей)
    final rgba = image.getBytes();
    final width = image.width;
    final height = image.height;

    // ZXing RGBLuminanceSource expects a list of 32-bit packed ARGB ints
    final pixels = Int32List(width * height);
    int src = 0;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final r = rgba[src++];
        final g = rgba[src++];
        final b = rgba[src++];
        final a = rgba[src++];
        final argb =
            ((a & 0xFF) << 24) |
            ((r & 0xFF) << 16) |
            ((g & 0xFF) << 8) |
            (b & 0xFF);
        pixels[y * width + x] = argb;
      }
    }

    final source = RGBLuminanceSource(width, height, pixels);
    final binarizer = HybridBinarizer(source);
    final bitmap = BinaryBitmap(binarizer);
    final reader = QRCodeReader();
    final result = reader.decode(bitmap);
    return result.text;
  } catch (e) {
    // any error -> null
    return null;
  }
}
