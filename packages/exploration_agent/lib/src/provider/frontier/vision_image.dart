import 'dart:convert';
import 'dart:typed_data';

/// Encodes a PNG screenshot for both Anthropic image content blocks and
/// OpenAI `image_url` parts. Pure Dart; no `dart:io`.
///
/// Consumed by `AnthropicModelProvider` (.36) and `OpenAiModelProvider` (.37).
class VisionImage {
  const VisionImage._(this.base64Png);

  /// Base64-encoded PNG payload.
  final String base64Png;

  /// Build a [VisionImage] from raw PNG bytes.
  factory VisionImage.fromPngBytes(Uint8List bytes) =>
      VisionImage._(base64Encode(bytes));

  /// Build a [VisionImage] from an already-encoded base64 PNG string.
  /// Used by providers when forwarding `Observation.screenshot` (cx6.7).
  factory VisionImage.fromBase64(String b64) => VisionImage._(b64);

  /// Anthropic-shaped image content block.
  Map<String, dynamic> toAnthropicBlock() => <String, dynamic>{
        'type': 'image',
        'source': <String, dynamic>{
          'type': 'base64',
          'media_type': 'image/png',
          'data': base64Png,
        },
      };

  /// OpenAI-shaped `image_url` content part.
  Map<String, dynamic> toOpenAiPart() => <String, dynamic>{
        'type': 'image_url',
        'image_url': <String, dynamic>{
          'url': 'data:image/png;base64,$base64Png',
        },
      };
}
