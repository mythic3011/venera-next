import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/sources/source_ref.dart';

abstract interface class ReadablePageProvider {
  Future<Res<List<String>>> loadPages(SourceRef ref);
}
