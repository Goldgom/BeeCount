import 'package:flutter/material.dart';
import '../../ai/providers/tokennest_auth_service.dart';
import '../../ai/providers/ai_provider_config.dart';
import '../../ai/providers/ai_provider_manager.dart';

class TokenNestSettingsPage extends StatefulWidget {
  const TokenNestSettingsPage({super.key});
  @override
  State<TokenNestSettingsPage> createState() => _TokenNestSettingsPageState();
}

class _TokenNestSettingsPageState extends State<TokenNestSettingsPage> {
  final auth = TokenNestAuthService.instance;
  bool busy = false;
  bool signedIn = false;
  bool loggingIn = false;
  String? error;
  List<String> models = [];
  final selected = <AICapabilityType, String?>{};

  @override
  void initState() {
    super.initState();
    _run(_load);
  }

  Future<void> _load() async {
    signedIn = await auth.isSignedIn;
    final provider =
        await AIProviderManager.getProvider(TokenNestAuthService.providerId);
    selected[AICapabilityType.text] = provider?.textModel;
    selected[AICapabilityType.vision] = provider?.visionModel;
    selected[AICapabilityType.speech] = provider?.audioModel;
    if (signedIn) models = await auth.models();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) error = e is TokenNestAuthException ? e.message : '操作失败，请重试';
    } finally {
      signedIn = await auth.isSignedIn;
      if (mounted) {
        setState(() {
          busy = false;
          loggingIn = false;
        });
      }
    }
  }

  @override
  void dispose() {
    if (loggingIn) auth.cancelSignIn();
    super.dispose();
  }

  Future<void> _save() async {
    if (!signedIn) throw const TokenNestAuthException('请先登录 TokenNest');
    if (!selected.values.any((value) => value != null && value.isNotEmpty)) {
      throw const TokenNestAuthException('请选择至少一种能力的模型');
    }
    if (selected.values.any((value) =>
        value != null && value.isNotEmpty && !models.contains(value))) {
      throw const TokenNestAuthException('模型列表已改变，请重新选择');
    }
    final existing =
        await AIProviderManager.getProvider(TokenNestAuthService.providerId);
    final config = AIServiceProviderConfig(
      id: TokenNestAuthService.providerId,
      name: 'TokenNest',
      baseUrl: TokenNestAuthService.apiBase,
      textModel: selected[AICapabilityType.text] ?? '',
      visionModel: selected[AICapabilityType.vision] ?? '',
      audioModel: selected[AICapabilityType.speech] ?? '',
      createdAt: existing?.createdAt ?? DateTime.now(),
    );
    if (existing == null) {
      await AIProviderManager.addProviderWithConfig(config);
    } else {
      await AIProviderManager.updateProvider(config);
    }
    final binding = await AIProviderManager.getCapabilityBinding();
    final bindings = {
      AICapabilityType.text: binding.textProviderId,
      AICapabilityType.vision: binding.visionProviderId,
      AICapabilityType.speech: binding.speechProviderId
    };
    for (final capability in AICapabilityType.values) {
      if ((selected[capability] ?? '').isNotEmpty) {
        await AIProviderManager.setCapabilityProvider(capability, config.id);
      } else if (bindings[capability] == config.id) {
        await AIProviderManager.setCapabilityProvider(capability, 'zhipu_glm');
      }
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('TokenNest AI 记账')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(signedIn ? '已连接 TokenNest' : '使用 TokenNest 账号授权，无需填写 API Key'),
          const SizedBox(height: 12),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          if (!signedIn)
            FilledButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('登录 TokenNest'),
              onPressed: busy
                  ? null
                  : () => _run(() async {
                        loggingIn = true;
                        await auth.signIn();
                        loggingIn = false;
                        await _load();
                      }),
            ),
          if (loggingIn)
            TextButton(onPressed: auth.cancelSignIn, child: const Text('取消登录')),
          if (signedIn) ...[
            Row(children: [
              TextButton(
                  onPressed: busy ? null : () => _run(_load),
                  child: const Text('刷新模型')),
              TextButton(
                  onPressed: busy
                      ? null
                      : () => _run(() async {
                            try {
                              await auth.signOut();
                            } finally {
                              models = [];
                            }
                          }),
                  child: const Text('退出并撤销授权')),
            ]),
            const Text('选择后将用于现有 AI 记账。图片/语音模型须支持相应能力；模型调用可能产生 TokenNest 费用。'),
            if (models.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('暂无可用模型，请刷新或检查账号权限')),
            for (final capability in AICapabilityType.values)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration:
                        InputDecoration(labelText: capability.displayName),
                    // value supports the project's Flutter 3.27 baseline.
                    // ignore: deprecated_member_use
                    value: models.contains(selected[capability])
                        ? selected[capability]
                        : '',
                    items: [
                      const DropdownMenuItem(value: '', child: Text('不使用此能力')),
                      ...models.map((model) => DropdownMenuItem(
                          value: model,
                          child: Text(model, overflow: TextOverflow.ellipsis)))
                    ],
                    onChanged: busy
                        ? null
                        : (value) =>
                            setState(() => selected[capability] = value),
                  )),
            FilledButton(
                onPressed: busy || models.isEmpty ? null : () => _run(_save),
                child: const Text('保存并用于 AI 记账')),
          ],
          const SizedBox(height: 16),
          const Text('登录通过系统浏览器完成。授权凭据仅保存在本机系统安全存储，不随配置同步或备份导出。'),
        ]),
      );
}
