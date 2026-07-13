# ideaShell to Tana Sync

中文 | [English](README.en.md)

将闪念贝壳（ideaShell）的新笔记定时同步到 Tana 指定节点的 macOS 本地工具。

中文名称为“闪念同步”，英文系统及英文界面下显示为 **IdeaSync**。

提供原生 macOS 菜单栏 App：顾客可在图形界面中连接账号、选择 Tana 目标节点、配置 AI 润色、手动同步，以及开启或暂停自动同步，无需编辑 `.env` 或使用终端。

所有凭证、同步状态与日志都存放在你的 Mac 本机；项目不会上传笔记内容，也不提供中转服务器。

## 功能

- 通过闪念贝壳 MCP 读取最近新增的笔记。
- 仅将笔记详情文本写入 Tana，不使用闪念贝壳标题。
- 可选通过 OpenAI、DeepSeek、OpenRouter、其他 OpenAI 兼容接口、Anthropic Claude、Google Gemini 或 Ollama 润色正文。
- 去除正文结尾的 `#标签`。
- 本地记录已同步的笔记 ID，避免重复导入。
- 新笔记先等待转录完成；标题和正文连续两轮保持一致后才写入 Tana，避免同步 `(untitled)` 或半截转录。
- 菜单栏显示今天的新增、已同步、等待中和失败笔记数量。
- 提供本机同步历史窗口，显示累计同步、本月记录和最近 30 天趋势；每日计数保留 365 天，不保存笔记正文。
- 界面支持跟随 macOS 系统语言，也可在设置中手动切换简体中文或 English，无需重启。
- Tana 写入成功后，在原闪念贝壳标题前添加 `～～` 标记。
- 支持手动同步，或通过 macOS `launchd` 按 5、10、15、30、60 分钟间隔自动运行，也可设置每天固定时间同步一次。

## 要求

- macOS 14 或更新版本
- 闪念贝壳 API Key（MCP）
- Tana Write API Token 和目标节点 ID
- 可选：OpenAI 或兼容服务的 API Key

## 配置

### 推荐：菜单栏 App

构建并安装到当前用户的“应用程序”目录：

```bash
./build-mac-app.sh --install
open "$HOME/Applications/闪念同步.app"
```

构建结果同时支持 Apple Silicon 和 Intel Mac。安装到固定位置后，“开机自启”才能保持稳定。

点击菜单栏的同步图标，选择“设置”。填写闪念贝壳 API Key、Tana Write API Token 和 Tana 目标节点 ID；保存后可选择手动同步，或启用自动同步并选择 5、10、15、30、60 分钟间隔，也可以选择“每天一次”并指定执行时间。

App 会把配置保存到当前用户的本机专用目录，并将文件权限限制为仅当前用户可读。同步核心为原生 Swift 实现，不需要安装 Node.js、Shell 脚本或其他运行时；开机自启会注册 macOS 的登录项，关闭后会自动注销。

除“润色提示词”外，设置页采用自动保存：文本停止输入约 0.8 秒后保存，开关和选项修改后自动保存。润色提示词必须点击“保存提示词”才会写入本机。必要信息未填写完整时不会覆盖当前可用配置；同步操作统一从菜单栏执行。

启用 AI 润色后，可直接选择 OpenAI、DeepSeek、OpenRouter、Anthropic Claude、Google Gemini 或 Ollama；App 会自动填写对应的 API 地址和推荐模型。模型框可直接选择推荐项，也可手动填写任意模型 ID；点击“刷新模型”会从当前 API 地址读取该账户实际可用的模型。使用中转服务时选择“其他 OpenAI 兼容接口”，自行填写地址、模型和 API Key。API Key 旁提供对应服务商的获取说明；Ollama 不需要 API Key。设置页提供“测试 AI 连接”，测试过程不会读取闪念笔记或写入 Tana。

设置页同时提供完整提示词编辑器。初始内容是项目内的默认提示词，使用 `{{text}}` 表示闪念原文；用户可以修改并保存，也可以一键恢复默认。自定义提示词保存在本机，升级后台脚本时不会被覆盖。

配置、同步状态与日志仍只保存在本机：

- 配置与同步记录：`~/Library/Application Support/ideashell-tana-sync/`
- 日志：`~/Library/Logs/ideashell-tana-sync/`

## 首次测试

填写凭证后，先在菜单栏选择“立即同步”。第一次发现的笔记会等待两轮内容一致并至少稳定 4 分钟，避免写入未完成的语音转录；因此首次同步显示“等待中”属于正常情况。

同步引擎、状态文件和后台任务均由 App 原生处理；普通用户不需要安装 Node.js，也不需要打开终端。

## 定时同步

在菜单栏 App 的“设置”中开启自动同步，并选择间隔或每天执行时间。

任务会在登录后启动，并每 5 分钟运行一次。电脑需开机且已登录 macOS；不需要打开闪念贝壳、Tana 或终端。

为了确认闪念贝壳已经完成语音转录，新笔记通常会比首次发现晚 5～10 分钟写入 Tana。菜单栏会显示当前正在等待内容稳定的笔记数量。

## 发布新版本与更新提醒

App 的“关于”窗口提供“检查更新”。它读取仓库根目录的 `update.json`，以递增的构建号判断是否有新版本；发现更新后会显示发布说明，并打开对应的 GitHub Release 下载页。

构建测试版时，版本号末尾的数字会自动作为构建号：

```bash
./build-dmg.sh 0.1.0-beta.5
```

发布正式版或需要自定义构建号时，必须显式提供一个比历史版本更大的整数：

```bash
APP_BUILD=6 ./build-dmg.sh 0.1.0
```

发布时先创建 GitHub Release 并确认 DMG 可以下载，最后再更新并推送 `update.json`。不要提前更新清单，否则用户会收到一个尚无法下载的版本提示。

查看运行状态：

```bash
launchctl print gui/$(id -u)/com.ideashell-tana-sync
```

查看日志：

```bash
tail -f "$HOME/Library/Logs/ideashell-tana-sync/sync.log"
tail -f "$HOME/Library/Logs/ideashell-tana-sync/sync.err.log"
```

## 反馈与建议

可在 App 的“关于”窗口点击“反馈与建议”，或直接打开[反馈表](https://tally.so/r/2EyvKg)。提交前请移除 API Key、Token、笔记正文等隐私信息。

## 隐私与安全

- 不要提交 `.env`、`.ideashell-tana-state.json` 或 `logs/`。
- API Key 保存在当前用户的本地配置文件中，权限为 `600`；该文件位于项目目录之外且被 Git 忽略。
- 启用 AI 润色时，笔记正文会发送到你在 `OPENAI_BASE_URL` 配置的服务。

## License

[MIT](LICENSE)
