part of 'settings_page.dart';

class NetworkSettings extends StatefulWidget {
  const NetworkSettings({super.key});

  @override
  State<NetworkSettings> createState() => _NetworkSettingsState();
}

class _NetworkSettingsState extends State<NetworkSettings> {
  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Network".tl)),
        _PopupWindowSetting(
          title: "Proxy".tl,
          builder: () => const _ProxySettingView(),
        ).toSliver(),
        _PopupWindowSetting(
          title: "DNS Overrides".tl,
          builder: () => const _DNSOverrides(),
        ).toSliver(),
        _SliderSetting(
          title: "Download Threads".tl,
          settingsIndex: CommonSettingKeys.downloadThreads.name,
          interval: 1,
          min: 1,
          max: 16,
        ).toSliver(),
      ],
    );
  }
}

class _ProxySettingView extends StatefulWidget {
  const _ProxySettingView();

  @override
  State<_ProxySettingView> createState() => _ProxySettingViewState();
}

class _ProxySettingViewState extends State<_ProxySettingView> {
  _ProxyMode type = _ProxyMode.direct;
  String host = '';
  String port = '';
  String username = '';
  String password = '';

  // USERNAME:PASSWORD@HOST:PORT
  String toProxyStr() {
    if (type == _ProxyMode.direct) {
      return _ProxyMode.direct.value;
    } else if (type == _ProxyMode.system) {
      return _ProxyMode.system.value;
    }
    var res = '';
    if (username.isNotEmpty) {
      res += username;
      if (password.isNotEmpty) {
        res += ':$password';
      }
      res += '@';
    }
    res += host;
    if (port.isNotEmpty) {
      res += ':$port';
    }
    return res;
  }

  void parseProxyString(String proxy) {
    if (proxy == _ProxyMode.direct.value) {
      type = _ProxyMode.direct;
      return;
    } else if (proxy == _ProxyMode.system.value) {
      type = _ProxyMode.system;
      return;
    }
    type = _ProxyMode.manual;
    var parts = proxy.split('@');
    if (parts.length == 2) {
      var auth = parts[0].split(':');
      if (auth.length == 2) {
        username = auth[0];
        password = auth[1];
      }
      parts = parts[1].split(':');
      if (parts.length == 2) {
        host = parts[0];
        port = parts[1];
      }
    } else {
      parts = proxy.split(':');
      if (parts.length == 2) {
        host = parts[0];
        port = parts[1];
      }
    }
  }

  @override
  void initState() {
    var proxy = appdata.settings[CommonSettingKeys.proxy.name];
    parseProxyString(proxy);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return PopUpWidgetScaffold(
      title: "Proxy".tl,
      body: SingleChildScrollView(
        child: RadioGroup<String>(
          groupValue: type.value,
          onChanged: (v) {
            setState(() {
              type = _ProxyMode.fromValue(v) ?? type;
            });
            if (type != _ProxyMode.manual) {
              appdata.settings[CommonSettingKeys.proxy.name] = toProxyStr();
              appdata.saveData();
            }
          },
          child: Column(
            children: [
              RadioListTile<String>(
                title: Text("Direct".tl),
                value: _ProxyMode.direct.value,
              ),
              RadioListTile<String>(
                title: Text("System".tl),
                value: _ProxyMode.system.value,
              ),
              RadioListTile<String>(
                title: Text("Manual".tl),
                value: _ProxyMode.manual.value,
              ),
              if (type == _ProxyMode.manual) buildManualProxy(),
            ],
          ),
        ),
      ),
    );
  }

  var formKey = GlobalKey<FormState>();

  Widget buildManualProxy() {
    return Form(
      key: formKey,
      child: Column(
        children: [
          TextFormField(
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: "Host".tl,
            ),
            controller: TextEditingController(text: host),
            onChanged: (v) {
              host = v;
            },
            validator: (v) {
              if (v?.isEmpty ?? false) {
                return "Host cannot be empty".tl;
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: "Port".tl,
            ),
            controller: TextEditingController(text: port),
            onChanged: (v) {
              port = v;
            },
            validator: (v) {
              if (v?.isEmpty ?? true) {
                return null;
              }
              if (int.tryParse(v!) == null) {
                return "Port must be a number".tl;
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: "Username".tl,
            ),
            controller: TextEditingController(text: username),
            onChanged: (v) {
              username = v;
            },
            validator: (v) {
              if ((v?.isEmpty ?? false) && password.isNotEmpty) {
                return "Username cannot be empty".tl;
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: "Password".tl,
            ),
            controller: TextEditingController(text: password),
            onChanged: (v) {
              password = v;
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                appdata.settings[CommonSettingKeys.proxy.name] = toProxyStr();
                appdata.saveData();
                context.pop();
              }
            },
            child: Text("Save".tl),
          ),
        ],
      ),
    ).paddingHorizontal(16).paddingTop(16);
  }
}

class _DNSOverrides extends StatefulWidget {
  const _DNSOverrides();

  @override
  State<_DNSOverrides> createState() => __DNSOverridesState();
}

enum _ProxyMode {
  direct('direct'),
  system('system'),
  manual('manual');

  final String value;
  const _ProxyMode(this.value);

  static _ProxyMode? fromValue(String? value) {
    if (value == null) return null;
    for (final mode in _ProxyMode.values) {
      if (mode.value == value) return mode;
    }
    return null;
  }
}

class __DNSOverridesState extends State<_DNSOverrides> {
  var overrides = <(TextEditingController, TextEditingController)>[];

  @override
  void initState() {
    for (var entry in (appdata.settings['dnsOverrides'] as Map).entries) {
      if (entry.key is String && entry.value is String) {
        overrides.add((
          TextEditingController(text: entry.key),
          TextEditingController(text: entry.value),
        ));
      }
    }
    super.initState();
  }

  @override
  void dispose() {
    var map = <String, String>{};
    for (var entry in overrides) {
      map[entry.$1.text] = entry.$2.text;
    }
    appdata.settings['dnsOverrides'] = map;
    appdata.saveData();
    JsEngine().resetDio();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopUpWidgetScaffold(
      title: "DNS Overrides".tl,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _SwitchSetting(
              title: "Enable DNS Overrides".tl,
              settingKey: CommonSettingKeys.enableDnsOverrides.name,
            ),
            _SwitchSetting(
              title: "Server Name Indication",
              settingKey: CommonSettingKeys.sni.name,
            ),
            const SizedBox(height: 8),
            Container(
              height: 1,
              margin: EdgeInsets.symmetric(horizontal: 8),
              color: context.colorScheme.outlineVariant,
            ),
            for (var i = 0; i < overrides.length; i++) buildOverride(i),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  overrides.add((
                    TextEditingController(),
                    TextEditingController(),
                  ));
                });
              },
              icon: const Icon(Icons.add),
              label: Text("Add".tl),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildOverride(int index) {
    var entry = overrides[index];
    return Container(
      key: ValueKey(index),
      height: 48,
      margin: EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.colorScheme.outlineVariant),
          left: BorderSide(color: context.colorScheme.outlineVariant),
          right: BorderSide(color: context.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: "Domain".tl,
              ),
              controller: entry.$1,
            ).paddingHorizontal(8),
          ),
          Container(width: 1, color: context.colorScheme.outlineVariant),
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: "IP".tl,
              ),
              controller: entry.$2,
            ).paddingHorizontal(8),
          ),
          Container(width: 1, color: context.colorScheme.outlineVariant),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              setState(() {
                overrides.removeAt(index);
              });
            },
          ),
        ],
      ),
    );
  }
}
