import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/sources/comic_source/source_management_controller.dart';
import 'package:venera/pages/comic_source_page.dart';
import 'package:venera/utils/translations.dart';

class _FakeSourceManagementController extends SourceManagementController {
  _FakeSourceManagementController({
    this.repositories = const <SourceRepositoryView>[],
    this.packages = const <SourcePackageView>[],
  });

  final List<SourceRepositoryView> repositories;
  final List<SourcePackageView> packages;
  int addRepositoryCalls = 0;
  int refreshRepositoryCalls = 0;

  @override
  Future<List<SourceRepositoryView>> listRepositories() async => repositories;

  @override
  Future<List<SourcePackageView>> listAvailablePackages({
    String? repositoryId,
  }) async {
    return packages;
  }

  @override
  Future<SourceRepositoryView> addRepository(
    String indexUrl, {
    String? name,
    bool userAdded = true,
    String trustLevel = 'user',
    bool enabled = true,
  }) async {
    addRepositoryCalls++;
    return SourceRepositoryView(
      id: 'new',
      name: name ?? 'New Repo',
      indexUrl: indexUrl,
      enabled: enabled,
      userAdded: userAdded,
      trustLevel: trustLevel,
    );
  }

  @override
  Future<int> refreshRepository(String repositoryId) async {
    refreshRepositoryCalls++;
    return 1;
  }
}

void main() {
  setUpAll(() {
    AppTranslation.translations = <String, Map<String, String>>{
      'en_US': <String, String>{},
      'zh_HK': <String, String>{},
    };
  });

  Future<void> pumpPage(
    WidgetTester tester,
    _FakeSourceManagementController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ComicSourcePage(controller: controller)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('settings comic sources page exposes repository section', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController();
    await pumpPage(tester, controller);
    expect(find.text('Repositories'), findsOneWidget);
  });

  testWidgets('settings comic sources page exposes installed sources section', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController();
    await pumpPage(tester, controller);
    expect(find.text('Installed Sources'), findsOneWidget);
  });

  testWidgets('settings comic sources page exposes available sources section', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController(
      packages: const <SourcePackageView>[
        SourcePackageView(
          sourceKey: 's1',
          repositoryId: 'repo-1',
          name: 'Source One',
          availableVersion: '1.0.0',
          lastSeenAtMs: 1,
        ),
      ],
    );
    await pumpPage(tester, controller);
    expect(find.text('Available Sources'), findsOneWidget);
  });

  testWidgets('settings add repository action uses source management controller', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController();
    await pumpPage(tester, controller);

    await tester.tap(find.text('Add Repository'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'https://repo.example.com/index.json',
    );
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();

    expect(controller.addRepositoryCalls, 1);
  });

  testWidgets(
    'settings refresh repository action uses source management controller',
    (tester) async {
      final controller = _FakeSourceManagementController(
        repositories: const <SourceRepositoryView>[
          SourceRepositoryView(
            id: 'repo-1',
            name: 'Repo 1',
            indexUrl: 'https://repo-1.example.com/index.json',
            enabled: true,
            userAdded: false,
            trustLevel: 'official',
          ),
        ],
      );
      await pumpPage(tester, controller);

      await tester.tap(find.byKey(const ValueKey('refresh-repo-repo-1')));
      await tester.pumpAndSettle();

      expect(controller.refreshRepositoryCalls, 1);
    },
  );
}
