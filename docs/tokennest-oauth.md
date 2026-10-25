# TokenNest OAuth AI 记账

## 登录渠道

在应用 AI 服务商管理中打开 TokenNest，点击登录。应用会启动系统浏览器到 https://openai.goldgom.top 的 OAuth 授权页，经用户确认后回到应用。不要手工复制带 code/state 的授权链接，不要在聊天中提供密码或 token。

- 独立 public client：`tnc_beecount`。
- 精确回调：`beecount.oauth://oauth/callback`。
- scope：`api offline_access`。
- 使用 PKCE S256、随机 state、五分钟授权有效期；不内置 client secret。
- 登录后刷新模型列表，选择文本/视觉/语音模型，再由现有 AI 记账使用。
- OAuth access/refresh token 独立放入设备安全存储；配置 JSON、导入、同步、备份均不携带 OAuth token。
- 退出登录清除本机授权并尝试服务端撤销；撤销网络失败不恢复本机凭据。

## 服务端依赖

TokenNest 服务端须部署本轮独立 BeeCount public client 注册，或由管理员合法登记同一 client ID、精确回调与最小 scope。仅安装 APK 不会修改线上 OAuth 客户端数据库。不要借用 TokenBird/Copilot 客户端身份。

如果部署方选择其他 client ID，使用构建参数 `--dart-define=TOKENNEST_CLIENT_ID=...`，并在服务端登记相同 ID；不能仅改手机端绕过服务端注册。

## 验证范围

已验证 provider 单元测试、定向静态分析和 Android dev debug 构建。用户真实系统浏览器授权、回调及计费模型调用仍须在服务端注册部署后通过真机确认。iOS 构建需要 macOS。TokenNest 注册变更已测 SQLite；MySQL/PostgreSQL 实例验证须由部署环境补齐，不能以 SQLite 测试推定三库均验证。
