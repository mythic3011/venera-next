part of 'settings_page.dart';

class AboutSettings extends StatefulWidget {
  const AboutSettings({super.key});

  @override
  State<AboutSettings> createState() => _AboutSettingsState();
}

class _AboutSettingsState extends State<AboutSettings> {
  bool isCheckingUpdate = false;

  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text(AboutSettingsStrings.title)),
        SizedBox(
          height: 112,
          width: double.infinity,
          child: Center(
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(136),
              ),
              clipBehavior: Clip.antiAlias,
              child: const Image(
                image: AssetImage("assets/app_icon.png"),
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ).paddingTop(16).toSliver(),
        Column(
          children: [
            const SizedBox(height: 8),
            Text("V${App.version}", style: const TextStyle(fontSize: 16)),
            Text(AboutSettingsStrings.description),
            const SizedBox(height: 8),
          ],
        ).toSliver(),
        ListTile(
          title: Text(AboutSettingsStrings.checkForUpdates),
          trailing: Button.filled(
            isLoading: isCheckingUpdate,
            child: Text(AboutSettingsStrings.check),
            onPressed: () async {
              setState(() {
                isCheckingUpdate = true;
              });
              await checkUpdateUi(context: context);
              if (!mounted) {
                return;
              }
              setState(() {
                isCheckingUpdate = false;
              });
            },
          ).fixHeight(32),
        ).toSliver(),
        _SwitchSetting(
          title: AboutSettingsStrings.checkOnStartup,
          settingKey: CommonSettingKeys.checkUpdateOnStart.name,
        ).toSliver(),
        ListTile(
          title: Text(AboutSettingsStrings.github),
          trailing: const Icon(Icons.open_in_new),
          onTap: () {
            launchUrlString(AppUrls.githubRepo);
          },
        ).toSliver(),
        ListTile(
          title: Text(AboutSettingsStrings.telegram),
          trailing: const Icon(Icons.open_in_new),
          onTap: () {
            launchUrlString(AppUrls.telegramChannel);
          },
        ).toSliver(),
      ],
    );
  }
}

Future<bool> checkUpdate() async {
  var res = await AppDio().get(AppUrls.pubspecRaw);
  if (res.statusCode == 200) {
    var data = loadYaml(res.data);
    if (data["version"] != null) {
      return _compareVersion(data["version"].split("+")[0], App.version);
    }
  }
  return false;
}

Future<void> checkUpdateUi({
  required BuildContext context,
  bool showMessageIfNoUpdate = true,
  bool delay = false,
}) async {
  try {
    var value = await checkUpdate();
    if (value) {
      if (delay) {
        await Future.delayed(const Duration(seconds: 2));
      }
      if (!context.mounted) {
        return;
      }
      showDialog(
        context: context,
        builder: (context) {
          return ContentDialog(
            title: AboutSettingsStrings.newVersionAvailable,
            content: Text(
              AboutSettingsStrings.updatePrompt,
            ).paddingHorizontal(16),
            actions: [
              Button.text(
                onPressed: () {
                  Navigator.pop(context);
                  launchUrlString(AppUrls.githubReleases);
                },
                child: Text(AboutSettingsStrings.update),
              ),
            ],
          );
        },
      );
    } else if (showMessageIfNoUpdate) {
      if (!context.mounted) {
        return;
      }
      context.showMessage(
        message: AboutSettingsStrings.noNewVersionAvailable,
      );
    }
  } catch (e, s) {
    diag.AppDiagnostics.error(
      AboutSettingsStrings.checkUpdateChannel,
      e,
      message: AboutSettingsStrings.checkUpdateFailedMessage,
      stackTrace: s,
      data: {'source': 'settings.about', 'action': 'checkUpdateUi'},
    );
  }
}

/// return true if version1 > version2
bool _compareVersion(String version1, String version2) {
  return isVersionGreater(version1, version2);
}

/// return true if [left] > [right]
bool isVersionGreater(String left, String right) {
  final leftParts = left.split(".");
  final rightParts = right.split(".");
  final length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var i = 0; i < length; i++) {
    final leftValue = i < leftParts.length ? int.parse(leftParts[i]) : 0;
    final rightValue = i < rightParts.length ? int.parse(rightParts[i]) : 0;
    if (leftValue > rightValue) {
      return true;
    }
    if (leftValue < rightValue) {
      return false;
    }
  }
  return false;
}
