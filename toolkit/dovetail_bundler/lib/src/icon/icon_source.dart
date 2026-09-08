import 'dart:io';
import 'dart:typed_data';

import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:image/image.dart' as img;

final class IconSource {
  const IconSource._(this.path, this._image);

  factory IconSource.read(String path) {
    final File file = File(path);
    if (!file.existsSync()) {
      throw BundleFailure('there is no icon at $path.');
    }

    final Uint8List bytes = file.readAsBytesSync();
    final img.Image? decoded = img.decodePng(bytes);
    if (decoded == null) {
      throw BundleFailure(
        '$path is not a PNG this bundler can read.',
        remedy:
            'Every platform icon here is built from one square PNG. Give the '
            'largest one you have and the rest is derived.',
      );
    }
    if (decoded.width != decoded.height) {
      throw BundleFailure(
        'the icon is ${decoded.width}x${decoded.height}, which is not square.',
        remedy:
            'Windows and macOS both stretch a non-square icon rather than '
            'refusing it, so the artefact ships looking wrong.',
      );
    }
    if (decoded.width < 512) {
      throw BundleFailure(
        'the icon is ${decoded.width}px, below the 512 a macOS bundle needs.',
        remedy:
            'Upscaling produces a blurred icon that no reviewer rejects and '
            'every user sees.',
      );
    }

    return IconSource._(path, decoded);
  }

  final String path;
  final img.Image _image;

  int get size => _image.width;

  Uint8List pngAt(int edge) {
    if (edge > size) {
      throw BundleFailure(
        'asked for a ${edge}px icon from a ${size}px source.',
        remedy: 'This bundler shrinks and never upscales.',
      );
    }
    final img.Image resized = edge == size
        ? _image
        : img.copyResize(
            _image,
            width: edge,
            height: edge,
            interpolation: img.Interpolation.cubic,
          );
    return img.encodePng(resized, level: 9);
  }
}
