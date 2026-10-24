# Ydisks闲鱼助手 · Windows 本地部署工具链

把开源项目 [**Christ9038/Ydisks-Xianyu-Helper**](https://github.com/Christ9038/Ydisks-Xianyu-Helper)
（Go + React 的闲鱼多账号自动发货与消息回复系统）在 Windows 上**从零部署到可用**，
并配上一整套构建、运维与验证脚本。

不需要 Docker。不需要预装 Go。不需要 MySQL/PostgreSQL —— 默认走 SQLite，零外部依赖。

```
┌─────────────────────────────────────────────────────────────────────┐
│  一键部署.bat          ← 从零开始（下 Go → 拉源码 → 构建 → 装浏览器 → 起服务）│
│  启动.bat / 停止.bat    ← 日常开关                                    │
│  状态.bat / 打开后台.bat ← 看状态、打开管理后台                          │
│  deploy\               ← 全部运维脚本（PowerShell）                     │
│  docs\                 ← 项目分析 / 部署手册 / 使用说明 / 验证报告        │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 快速开始

### 前置条件

| 项 | 要求 |
|---|---|
| 操作系统 | Windows 10/11 x64 |
| **Node.js** | **24 或更高**（[下载](https://nodejs.org/)） |
| Git | 任意近期版本（[下载](https://git-scm.com/download/win)） |
| 磁盘 | ≥ 3 GB 空闲 |
| Go | **不需要** —— 脚本会自动下载便携版到 `runtime\go` |

### 部署

```powershell
git clone https://github.com/Yunique-hub/-.git
cd -
.\一键部署.bat
```

首次约需 10–20 分钟（下载 Go 72 MB + Chromium 700 MB + npm 依赖）。
部署完成会打印管理后台地址与管理员密码。

### 部署后

浏览器打开 **<http://127.0.0.1:59188>**，用户 `admin`，密码见部署输出
（也写在 `data\初始管理员凭据.txt`，**改完密码就删掉它**）。

---

## 这个仓库解决什么问题

上游项目本身很完整（300k 行代码、测试代码是生产代码的 1.5 倍、
有架构门禁和 API 契约），但它的部署文档假设你熟悉 Go / Docker / Linux。
在 Windows 单机上真正跑起来会撞上一串坑：

| 坑 | 表现 |
|---|---|
| `npm` 在 PATH 里是 `npm.ps1` | `Start-Process` 报「不是有效的 Win32 应用程序」 |
| `Start-Process -ArgumentList` 不给参数加引号 | `-ldflags "-s -w"` 被拆开，`go build` 报 `flag provided but not defined: -w` |
| 运行中的 exe 无法被覆盖 | 重建「成功」但产物是旧的，还多一个 `.exe~` 垃圾文件 |
| 版本变量不在 `main` 包 | 写成 `-X main.commit` 静默无效，版本永远显示 `dev` |
| `Start-Process -Wait` 等整个进程树 | Chromium 留后台子进程 → 卡住不返回 |
| 上游冒烟工具不传 Playwright 路径 | 服务找不到 Chromium 直接退出 → 冒烟 90 秒超时 |
| 上游冒烟工具用 `syscall.SIGTERM` | Windows 不支持 → `make smoke` 必然失败 |

本仓库把这些**全部处理掉**，并留下可复现的证据（见 [docs/04-验证报告.md](docs/04-验证报告.md)）。

---

## 目录结构

```
.
├── README.md                     本文件
├── LICENSE                       Apache-2.0（沿用上游）
├── NOTICE                        上游归属声明
├── CHANGELOG.md                  变更日志
├── .editorconfig / .gitattributes / .gitignore
├── .github/workflows/ci.yml      CI：脚本静态检查 + PowerShell 语法
│
├── deploy/                       ★ 部署与运维脚本
│   ├── common.ps1                公共层：路径、日志、外部命令封装、参数引号处理
│   ├── bootstrap.ps1             从零部署（9 阶段）
│   ├── build.ps1                 构建：前端 → Go 二进制（自动停/起服务）
│   ├── start.ps1                 启动 + 健康检查
│   ├── stop.ps1                  优雅停止（停止标记 → 关闭窗口 → 强杀）
│   ├── status.ps1                状态总览
│   ├── verify.ps1                部署完整验证（30 项 / 8 层）
│   ├── reset-admin.ps1           重置管理员密码
│   └── install-service.ps1       注册为 Windows 服务
│
├── tests/
│   ├── test_scripts.ps1          脚本静态检查（语法/危险写法/文档一致性）
│   └── test_common_selftest.ps1  公共层单元自测（参数引号、路径解析）
│
├── docs/
│   ├── 01-项目分析.md            上游项目的代码级分析（含真实统计数据）
│   ├── 02-部署手册.md            部署、配置、构建、排错完整手册
│   ├── 03-使用说明.md            ★ 面向使用者的日常操作指南
│   └── 04-验证报告.md            全部验证的真实执行输出
│
├── 一键部署.bat / 启动.bat / 停止.bat / 状态.bat / 打开后台.bat / 验证部署.bat
│
├── app/                          上游源码（由 bootstrap 克隆，不入库）
├── runtime/                      工具链与产物（由 bootstrap 生成，不入库）
├── data/                         业务数据 + 加密密钥（★ 必须备份，不入库）
└── logs/                         日志（不入库）
```

---

## 命令速查

```powershell
cd D:\ydisks

# 部署与构建
.\deploy\bootstrap.ps1                     # 从零部署
.\deploy\bootstrap.ps1 -SkipBrowser        # 不装 Chromium（省 700 MB）
.\deploy\build.ps1                         # 重新构建（自动停/起服务）
.\deploy\build.ps1 -SkipFrontend           # 只重建 Go（前端没改时更快）

# 日常
.\deploy\start.ps1                         # 启动
.\deploy\start.ps1 -Foreground             # 前台启动，直接看报错
.\deploy\stop.ps1                          # 停止
.\deploy\status.ps1                        # 状态
.\deploy\status.ps1 -Json                  # 状态（JSON）

# 验证
.\deploy\verify.ps1 -Password '<密码>'      # 30 项完整验证
.\deploy\verify.ps1 -Password '<密码>' -SkipRestart   # 不中断服务

# 运维
.\deploy\reset-admin.ps1                   # 重置管理员密码
.\deploy\install-service.ps1 -Mode install # 装成 Windows 服务（需管理员）
.\deploy\install-service.ps1 -Mode status
.\deploy\install-service.ps1 -Mode uninstall
```

---

## 验证结果

`deploy\verify.ps1` 分八层共 30 项，全部通过：

| 层 | 内容 | 结果 |
|---|---|---|
| A 产物层 | 3 个 exe、版本已注入、Chromium 运行时、driver | 6/6 |
| B 进程层 | 进程、端口、PID 文件一致性 | 3/3 |
| C HTTP 层 | `/health`、SPA 首页、**10 个静态资源逐个真实命中**、深链回退 | 5/5 |
| D 鉴权层 | 未登录 401、已初始化、错误密码 401 | 3/3 |
| E 业务层 | 管理员登录、**20 个核心只读接口全部 200 JSON**、登出 | 3/3 |
| F 数据层 | 数据库与文件头、加密密钥、上传目录 | 4/4 |
| G 浏览器层 | **服务内 Playwright 就绪**、**真实 Chromium 渲染 SPA** | 3/3 |
| H 收尾 | 优雅停止、端口释放、重新启动 | 3/3 |

```
结论：全部通过    通过 30 / 跳过 0 / 失败 0 / 共 30    20.7 秒
```

**两个刻意的严格判据**（普通检查会漏掉）：

1. 静态资源挂在 `/static/assets/` 下。按 `/assets/xxx` 请求会落进 SPA 回退，
   服务返回 **index.html 且状态码 200** —— 只看状态码会误判成功。
   所以额外断言「返回的不是 index.html」。
2. 浏览器层不只看 HTTP 200，而是用真实 Chromium **无头渲染**，
   断言 React 挂载点非空 + 出现界面文案 + 引用了静态资源。

完整输出见 [docs/04-验证报告.md](docs/04-验证报告.md)。

---

## 已知限制

- **上游 `make smoke` 在 Windows 上必然失败**：`tools/smoke/process.go:86` 用
  `syscall.SIGTERM` 终止子进程，Windows 不支持 POSIX 信号，也没有 Windows 专用实现。
  **功能检查其实全过**（服务日志可证：`数据库已就绪` → `playwright chromium 就绪` →
  `HTTP 服务启动`），失败只在最后的优雅终止步骤。用 `deploy\verify.ps1` 代替。
- **改了前端必须重新构建 + 重启服务**：前端用 `//go:embed` 编进 Go 二进制，
  浏览器硬刷新不会替换运行中进程已加载的资源。
- **不要对 Chromium 目录建目录 junction**：会让 Chrome 报
  「应用程序无法启动，因为应用程序的并行配置不正确」（SxS 清单解析被破坏）。
  确实需要 ASCII 路径就整个复制。
- **`chrome.exe --dump-dom` 在 headless 下不会自己退出**（实测 26 秒仍未结束）。
  要做无头渲染请用 `chrome-headless-shell.exe`，它在同一份运行时里且 0.3 秒返回。
- 本部署固定监听 `127.0.0.1`。**管理后台能完全控制闲鱼账号，不要暴露到公网。**

---

## 安全要点

| 项 | 说明 |
|---|---|
| `data\data.key` | 敏感字段（账号凭证）的 AES-256-GCM 加密密钥。**丢了就无法恢复已加密数据**，必须和数据库一起备份 |
| `data\xianyu_data.db` | 含账号凭证。不要外发 |
| 首次初始化 | 上游默认走「网页首次初始化」，**能访问端口的首个客户端即可创建管理员**。本部署改用 `-init-admin` 预初始化，规避这个窗口 |
| MTOP 节流 | 上游内置同账号请求 ≥2 秒间隔（后台任务 ≥5 秒）。**不要为提高速度去放宽** —— 那是防封号的 |
| 脱敏 | 服务日志已做脱敏（`"dialect":"<redacted>"`），但请求路径仍会记录。分享日志前自行检查 |

---

## 文档

| 文档 | 内容 |
|---|---|
| [01-项目分析.md](docs/01-项目分析.md) | 上游项目的代码级分析：规模统计、架构、功能矩阵、工程化水平、风险 |
| [02-部署手册.md](docs/02-部署手册.md) | 前置条件、一键部署、目录说明、配置参数、构建细节、排错表 |
| [03-使用说明.md](docs/03-使用说明.md) | **面向使用者**：首次使用七步、日常运维、常见问题、安全红线 |
| [04-验证报告.md](docs/04-验证报告.md) | 全部验证的真实执行输出 + 验证过程中修正的 8 个自身缺陷 |

---

## 许可与归属

- 本仓库的部署工具链（`deploy/`、`tests/`、`docs/`、`*.bat`、元数据文件）
  以 **Apache-2.0** 发布。
- 上游项目 [Christ9038/Ydisks-Xianyu-Helper](https://github.com/Christ9038/Ydisks-Xianyu-Helper)
  同样以 Apache-2.0 发布，归属其作者。见 [NOTICE](NOTICE)。
- 本仓库**不包含**上游源码 —— `app/` 由部署脚本从上游克隆，不入库。
- 使用前请自行确认符合闲鱼平台规则与当地法律法规。
  自动化工具的使用后果由使用者承担。