# 变更日志

记录本仓库（部署工具链）的变更。
上游项目自身的变更日志见 <https://github.com/Christ9038/Ydisks-Xianyu-Helper>。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

## [1.0.0] - 2026-10-24

首次发布。把上游 `Ydisks-Xianyu-Helper v1.0.14`（commit `39e7660`）
在 Windows 上完整部署并验证通过。

### 新增

- **一键部署** `deploy/bootstrap.ps1`（九阶段）
  - 自动下载便携 Go 工具链（1.26.10）并校验官方 SHA256，装在 `runtime\go`
  - 克隆上游源码到 `app\`（已存在则增量更新）
  - 构建前端（Vite，产物写入 `internal/webui/static` 供 `//go:embed` 使用）
  - 编译三个 Go 可执行文件（server / tray / browser-install）
  - 安装 Playwright driver 与 Chromium（约 700 MB）
  - 初始化 SQLite 数据库与管理员账号
  - 启动服务并做健康检查
- **构建脚本** `deploy/build.ps1`
  - 版本号/提交号/BuildTime 注入（`xianyu-go/internal/version` 包）
  - 版本号优先取 git tag
  - 检测运行中的服务并自动停/起（Windows 不允许覆盖运行中的 exe）
  - 清理历史遗留的 `.exe~` 临时产物
- **服务管理**：`start.ps1` / `stop.ps1` / `status.ps1` / `reset-admin.ps1`
  - 停止采用三级退让：停止标记 → 关闭窗口 → 强杀
  - 状态包含进程、端口、健康检查、版本、数据库、Chromium 就绪情况
- **Windows 服务安装** `deploy/install-service.ps1`
  - 注册 `YdisksXianyuHelper` 服务，开机自启
  - 配置崩溃自动重启（10s → 30s → 60s，24 小时后重置计数）
  - 卸载不删业务数据
- **部署完整验证** `deploy/verify.ps1`（30 项，八层）
  - 产物层 / 进程层 / HTTP 层 / 鉴权层 / 业务层 / 数据层 / 浏览器层 / 收尾
  - 静态资源校验「返回的不是 index.html」（防 SPA 回退造成的假通过）
  - 浏览器层用真实 Chromium 无头渲染，断言 React 实际挂载
  - 支持 `-SkipBrowser` / `-SkipRestart` / `-Json`
- **公共层** `deploy/common.ps1`
  - 外部命令封装，带超时与进程树终止
  - Windows 参数引号处理（`ConvertTo-ArgumentString`）
  - `npm.ps1` → `npm.cmd` 路径解析（`Resolve-ExternalPath` / `Get-ToolPath`）
  - 系统代理探测、端口探测、HTTP 健康轮询、前置条件检查
- **快捷入口**：`一键部署.bat` / `启动.bat` / `停止.bat` / `状态.bat` /
  `打开后台.bat` / `验证部署.bat`
- **文档**：项目分析、部署手册、使用说明、验证报告
- **CI** `.github/workflows/ci.yml`：PowerShell 语法检查 + 脚本静态检查 + 公共层自测

### 修复（相对直接用上游脚本会踩到的坑）

| 问题 | 表现 | 处理 |
|---|---|---|
| `npm` 在 Windows 上是 `.ps1` | `Start-Process` 报「不是有效的 Win32 应用程序」 | 解析到同名 `.cmd` |
| 参数不加引号 | `-ldflags "-s -w"` 被拆开，`go build` 报 `flag provided but not defined: -w` | 按 Windows 命令行规则转义引号与末尾反斜杠 |
| 覆盖运行中的 exe | 构建「成功」但产物是旧的 + 留下 `.exe~` | 构建前停服务、清理临时产物、构建后自动重启 |
| 版本变量包路径写错 | `-X main.commit` 静默无效，版本永远 `dev` | 用 `xianyu-go/internal/version.Version/Commit/BuildTime` |
| `Start-Process -Wait` 等整棵进程树 | Chromium 留后台子进程 → 卡住 10 分钟不返回 | 加 `-TimeoutSeconds`，超时用 `taskkill /T /F` 杀进程树 |
| `Write-Log ''` 报错 | `[Parameter(Mandatory)]` 拒绝空字符串 | 加 `[AllowEmptyString()]` |
| 字符串拼接被当字面量 | `Write-Host '  ' + ('─' * 60)` 把 `+` 一起打出来 | 用括号包住整个表达式 |
| 上游冒烟工具找不到 Chromium | 服务退出 → 冒烟 90 秒超时 | 设 `PLAYWRIGHT_DRIVER_PATH` / `PLAYWRIGHT_BROWSERS_PATH` 环境变量（上游 `isolatedEnv` 会保留它们） |
| `chrome.exe --dump-dom` 不退出 | headless 下 26 秒仍未结束 | 改用 `chrome-headless-shell.exe`（0.3 秒返回） |
| Chromium 目录 junction | Chrome 报「并行配置不正确」（SxS 清单解析被破坏） | 不用 junction；需要 ASCII 路径就整个复制 |

### 己方验证脚本的修正记录

第一版 `verify.ps1` 报出的「失败」中有 5 项实际是**检查写错了**，
一并记录，因为它们也是使用这套系统时容易误判的地方：

1. 静态资源路径漏 `/static` 前缀 → 落进 SPA 回退返回 index.html，状态码仍是 200 被误判通过
2. 用 `$null -ne $obj` 判断空数组 → PowerShell 比较语义下误判为空
3. 端点名靠猜（`/api/v1/rules`、`/api/v1/dashboard` 实际不存在）→ 改从 `api/openapi.yaml` 取真实契约
4. `/api/v1/chat/sessions` 只有 DELETE 方法，被当 GET 用
5. `/api/v1/session` 响应是扁平的，被当成 `{data:{...}}` 解析

[1.0.0]: https://github.com/Yunique-hub/-/releases/tag/v1.0.0