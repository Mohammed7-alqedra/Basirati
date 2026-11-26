import 'dart:typed_data';

import 'package:baseerte_ai/camera_frame_encoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('YUV420 frame is converted to upright JPEG', () {
    const width = 4;
    const height = 2;
    final snapshot = CameraFrameSnapshot(
      width: width,
      height: height,
      rotationDegrees: 90,
      pixelFormat: FramePixelFormat.yuv420,
      planes: [
        FramePlaneSnapshot(Uint8List.fromList(List.filled(8, 170)), 4, 1),
        FramePlaneSnapshot(Uint8List.fromList([128, 128]), 2, 1),
        FramePlaneSnapshot(Uint8List.fromList([128, 128]), 2, 1),
      ],
    );

    final jpeg = encodeCameraFrame(snapshot);
    final decoded = img.decodeJpg(jpeg.jpeg);
    expect(jpeg.width, height);
    expect(jpeg.height, width);
    expect(decoded, isNotNull);
    expect(decoded!.width, height);
    expect(decoded.height, width);
  });

  test('NV21 packed camera buffer can be encoded', () {
    final snapshot = CameraFrameSnapshot(
      width: 4,
      height: 2,
      rotationDegrees: 0,
      pixelFormat: FramePixelFormat.nv21,
      planes: [
        FramePlaneSnapshot(
          Uint8List.fromList([
            128, 128, 128, 128,
            128, 128, 128, 128,
            128, 128, 128, 128,
          ]),
          4,
          1,
        ),
      ],
    );
    final jpeg = encodeCameraFrame(snapshot);
    expect(jpeg.width, 4);
    expect(jpeg.height, 2);
    expect(jpeg.jpeg, isNotEmpty);
  });
}
