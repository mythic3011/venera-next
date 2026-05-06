import 'adapter.dart';
import 'models.dart';

class SourceRegistry {
  final Map<String, ExternalSourceAdapter> _adapters = <String, ExternalSourceAdapter>{};

  void register(ExternalSourceAdapter adapter) {
    if (adapter.sourceKey.isEmpty) {
      throw ReaderRuntimeException('SOURCE_KEY_INVALID', 'Adapter sourceKey must not be empty');
    }
    _adapters[adapter.sourceKey] = adapter;
  }

  ExternalSourceAdapter requireAdapter(String sourceKey) {
    final adapter = _adapters[sourceKey];
    if (adapter == null) {
      throw ReaderRuntimeException(
        'ADAPTER_NOT_FOUND',
        'No adapter registered for sourceKey=$sourceKey',
      );
    }
    return adapter;
  }
}
