import 'package:flutter_test/flutter_test.dart';
import 'package:venera/network/images.dart';

void main() {
  test('image_downloader_local_ref_never_calls_remote_getImageLoadingConfig', () {
    expect(ImageDownloader.shouldUseSourceImageConfig('local'), isFalse);
    expect(ImageDownloader.shouldUseSourceImageConfig(null), isFalse);
    expect(ImageDownloader.shouldUseSourceImageConfig('copymanga'), isTrue);
  });
}
