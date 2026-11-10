# Fun 主控文档 (ROADMAP)

> 这是 Fun 的**唯一状态来源**。设计、证据和历史背景放在 `art/notes/` 与 `known-issues/`，
> 本文只维护当前基线、优先级、技术债和发版门槛。
> `art/notes/` 和 `known-issues/` 是维护者本地笔记，不在公开仓库；CI 只校验仓库内路径。
>
> 最近更新：2026-11-10
> 基线：Fun 9.5.5（tag `v9.5.5`）

## 0. 当前基线

- **版本**：9.5.5，`src/core/version.inc` 的 `funRelease = '9.5.5'`。
- **回归**：Linux `133/133`（`sh fun/test/run-linux-regression.sh`）。
- **可加载性**：`78/84`（`sh fun/test/lib-loadcheck.sh`，6 个 FAIL 均为 Windows 概念、
  raw socket 或 macOS-only 后端）。
- **标准库**：84 个候选模块（`fun/lib` 共 112 个 `.fun`，内部 `lib-base`/`lib-type`
  与 `-unx`/`-lnx` 后端单元不计），本机可加载 78 个。
- **平台**：Linux x86_64 / arm64、macOS x64 / arm64、Windows x64（FPC）；
  Delphi/Win32 继续人工验证。
- **CI**：GitHub Actions 的 `regression` 工作流覆盖 6 个构建作业（4 个 POSIX 平台 +
  linux-safe + windows-x64），`docs` 工作流检查本文件。
- **能力链**：ffi → 同步文件 IO → 进程 → 网络 → 数据库；另有 C/JIT/汇编、
  HTTP/WebSocket 单线程事件循环、safe 构建。

## 1. 正在进行 (NOW)

| ID | 事项 | 状态 | 优先级 | 验收 | 关联 |
|---|---|---|---|---|---|
| S-02 | jsbox 沙箱运行器 | DOING | P1 | 沙箱边界只由 `fun-jsbox` 承担，不以 fun `-safe` 代替。Linux seccomp-bpf、`process.run` 输出上限、Windows Job Object、macOS sandbox profile 已实现（后两者待 CI/真机验证）；剩余 bubblewrap/nsjail 网络与挂载隔离 | `src/prj/fun/jsbox/README.md` |

## 2. 下一步 (NEXT)

| ID | 事项 | 状态 | 优先级 | 验收 | 关联 |
|---|---|---|---|---|---|
| （空） | | | | | |

## 3. 以后 (LATER)

| ID | 事项 | 状态 | 优先级 | 验收 | 关联 |
|---|---|---|---|---|---|
| S-03 | `#!fun` 经 tcc 编译 | DEFERRED | P2 | 暂缓，不阻塞 9.5.5；先做数值/字符串/函数/控制流子集，再做模块导入 | `art/notes/todo.md` |
| S-05 | create-fun-app 脚手架 | OPEN | P3 | Fun 后端 + z-data 前端 + 一体发布 | `art/notes/todo.md` |
| S-06 | 用 fun-ui 重写 funide | OPEN | P3 | 新 IDE 替代旧 funide | `art/notes/todo.md` |
| S-07 | funcally AI agent | OPEN | P3 | 基于沙箱、CLI、HTTP 的 agent | `art/notes/todo.md` |
| S-09 | 流式/交互式子进程 stdio | OPEN | P2 | `io.pipe` 交接给子进程、边跑边读写、进程树终止、Windows Unicode 命令行（`io.pipe`、`process.run` 和 `output` 上限已完成）。与 S-02 保持独立：jsbox 走一次性 JSON，不需要流式 stdio | `README.zh.md` 的 io 一节 |

## 4. 技术债台账

| ID | 区域 | 优先级 | 状态 | 说明 | 证据 |
|---|---|---|---|---|---|
| K-01 | 内核 | P3 | OPEN | H-09 `_eval` 的 `$@@` 整体重扫 | 本地 hazards 清单 |
| K-02 | 内核 | P2 | OPEN | H-05 `div/mod 0` 仍抛 RTL `EDivByZero`，脚本可捕获，按兼容保留 | 本地 hazards 清单 |
| K-03 | 内核 | P2 | OPEN | H-06 Delphi/32 位与 Int64 极值边界未复测 | 本地 hazards 清单 |
| D-02 | 数据 | P2 | OPEN | FD fixed-length binary 类型跨端会退化成文本 | `art/notes/data-format-alignment.md` |
| D-03 | 数据 | P2 | OPEN | 日期/时间跨端约定未统一 | `art/notes/data-format-alignment.md` |
| D-04 | 数据 | P2 | OPEN | Fun `Int64` 超过 2^53 传给 JS 会静默丢精度 | `art/notes/data-format-alignment.md` |
| D-05 | 数据 | P3 | OPEN | FD/JSON 其余低风险一致性项（空键、定长前缀、kvd 空白分隔等） | `art/notes/data-format-alignment.md` |
| P-01 | 平台/并发 | P2 | OPEN | 真并发未做，同一函数并发调用仍不安全 | `art/notes/linux-threading.md` |
| P-02 | 平台 | P2 | OPEN | `lib-os` 全量 host 分派器未做 | `art/notes/library-port-plan.md` |
| P-03 | 平台 | P2 | OPEN | `lib-message`/`lib-async`/`lib-jsasync` 仍依赖消息泵或线程 | `art/notes/linux-capabilities.md` |
| P-04 | 平台 | P3 | OPEN | `lib-icmp` raw socket 未做，需 root/CAP_NET_RAW | `art/notes/linux-capabilities.md` |
| P-06 | 平台 | P3 | OPEN | `lib-os` B 档（GetIPs/inotify 等）未做 | `art/notes/linux-capabilities.md` |
| P-07 | 机器码 | P2 | OPEN | `asm-list` 的 x86-64 表覆盖不全 | `art/notes/arch-machine-code-plan.md` |
| P-15 | macOS 分发收尾 | P2 | OPEN | P-08 拆分后的未完成部分：正式 `codesign`/公证（需 Developer 证书）、Apple TCC 隐私授权（Desktop/Documents/Downloads，原 P-12）、物理机抽查 | `art/notes/macos-port.md` |
| P-16 | LoongArch 发布与真机 | P3 | OPEN | P-09 拆分后的未完成部分：`lib-asm` live 执行在 qemu/真机验收、CI 增加 loongarch 作业、`package.py`/capabilities 发布包、TCC 无后端策略（显式报错或 cc 回退）、真机验收 | `art/notes/loongarch-port-assessment.md`、`art/notes/arch-machine-code-plan.md` |
| P-13 | Windows/ARM | P3 | OPEN | win-arm64 无构建：FPC 3.2.2 没有 win64/aarch64 target，`regression.yml` 的 windows-arm64 job 仍禁用，需更新 FPC 或交叉工具链 | `.github/workflows/regression.yml` |

## 5. 接受 / 不做 / 已完成

> 终态归档：DONE 表示已交付；WONTFIX / DEFERRED 表示明确不做或暂不做。
> 开放中的事项只保留在第 1-4 节。

### 5.1 已完成 (DONE)

| ID | 事项 | 状态 | 说明 |
|---|---|---|---|
| S-04 | 站点 PHP 用 Fun 重写 | DONE | 站点页面与业务接口已全部迁到 Fun 服务；PHP-FPM 已停用，旧 URL 由 nginx 反代保持。验证时修复了 `match` 未命中判断导致的空 IP 500 与订单号校验问题。迁移与部署细节见独立部署仓库。 |
| K-04 | 循环集合深拷贝递归溢出 | DONE | `CEnv` clone 祖先栈 + `CSet.clone` 统一 set/object；循环副本保留在自己的克隆内，`@clone` 同样有栈上下文。`fun/test/clone-cycle-test.fun`、`fun/demos/benchmarks/clone-bench.md` 覆盖。 |
| P-05 | 第二数据库后端：unixODBC | DONE | MySQL/PostgreSQL 等经驱动管理器接入，unixODBC 与 P-11 同一交付。 |
| P-11 | unixODBC 后端 | DONE | `lib-ado-unx` 按 `odbc:`/`DRIVER=`/`DSN=` 自动分派，参数、事务、OpenSchema（SQLTables/Columns/PrimaryKeys/ForeignKeys）齐全；CI 装 `unixodbc`+`libsqliteodbc` 并跑 `run-ado-odbc.sh`。 |
| P-09 | LoongArch 交叉构建、解释器/标准库与汇编后端 | DONE | `src/prj/fun/bootstrap-linux-loongarch64.sh`、`src/prj/fun/make-linux-loongarch64.sh` + GNU binutils 产出 funcmd；musl sysroot 跑通 FFI、PCRE（无 JIT）、zlib、OpenSSL、curl、SQLite、XML，回归 115/115；`lib-asm-loongarch64` 编码器（binutils 生成表；164 curated + 361 全表 + 1083 随机差分与 GNU as 一致，QEMU 独立编码验证）；`install.sh` 与回归平台识别已接入。未进发布矩阵，收尾见 P-16。 |
| P-08 | macOS 运行时复验（x64/arm64） | DONE | 由 CI 原生 macOS runner 覆盖：`macos-x64`（`macos-15-intel`）与 `macos-arm64`（`macos-latest`，Apple Silicon）跑完整 macOS 套件，含 `MAP_JIT`、`sys_icache_invalidate`、FFI 回调；2026-11-10 六项回归全绿。分发签名/TCC 拆分到 P-15。 |
| P-14 | macOS 构建与运行时接入 | DONE | x64/arm64 引擎与 Fun 层可交叉构建；`lib-proc-darwin`、`MAP_JIT`、`libtcc.dylib` 接入与 arm64 ad-hoc 签名已完成，CI 有原生 macOS 回归。剩余签名/公证与 TCC 归入 P-15（原 P-08 拆分）。 |
| Q-01 | `lib-ado-schema.Filter` 丢外键 | DONE | ORM `@Parent`/`@Children` 直接走 OpenSchema，Windows/Unix 均恢复外键。 |
| Q-02 | `lib-fd`/`lib-bnf` 已知功能项 | DONE | 重名组问题已修，其余功能项已关闭。 |
| Q-03 | Windows `make-*.bat` 的 `-dRegexx` | DONE | 改为 `-dRegex -dPCRE_WinDLL`，有 pcre3.dll 时真正启用 regex。 |
| Q-05 | safe 模式只接 Linux 构建脚本 | DONE | `SAFE=...` 已覆盖 Linux aarch64、原生 macOS、darwin 交叉与 win64。 |

### 5.2 接受 / 不做 (WONTFIX / DEFERRED)

| ID | 事项 | 状态 | 说明 |
|---|---|---|---|
| X-01 | 短期不设 Delphi 编译器 CI | WONTFIX | GitHub 不适合引入非开源 Delphi；Delphi/Win32 人工验证 |
| X-02 | Windows UI/registry/trayicon/message 不移植 | WONTFIX | Windows 概念，Linux/macOS 无干净等价物 |
| X-03 | `move` / `toNum(ptr:-1)` 保持不安全 | WONTFIX | 裸内存原语，由 `-safe` 按 MEM 类拦截 |
| X-04 | H-07 递归求值栈 | WONTFIX | 16M 栈当前够用，不够再加 |
| X-05 | writer 15 位浮点输出 | WONTFIX | 可读性优先，接受细小往返差异 |
| X-06 | 重复键 last-wins、孤立 surrogate 不额外拒绝 | WONTFIX | 与 RFC 8259 / JSON.parse 行为一致 |
| X-07 | `compile(inline: true)` 是词法内联 | WONTFIX | 返回模块的 parent 是调用方，`m.x` 可读写调用方状态；需要隔离时用非 inline `compile()` 或传入状态容器。不要长期持有或返回 inline 模块。 |
| X-08 | `str.sha256()` 的 Pascal 内置实现（原 Q-04 并入） | DEFERRED | 正常构建走 libcrypto（Linux）/CryptoAPI（Windows）/CommonCrypto（macOS），不会回退；只有缺 libcrypto 或 safe 构建（getapi 被拦）才走纯 Fun。纯实现已用多块向量验证正确，只是约 12 ms/KB；需要时再仿 `funhash.pas` 补内置。 |
| P-10 | Linux aarch64 交叉产物补齐 `-dRegex`/`-dLinuxFFI` | WONTFIX | 交叉产物只是开发者在 x86_64 上验证核心解释器的工具；正式发布用 CI 原生 `linux-arm64` 构建，regex 与 FFI 都齐全，无需补齐。 |

## 6. 发版检查

- [ ] `sh fun/test/run-linux-regression.sh` 全绿，更新本文第 0 节的回归数字。
- [ ] `sh fun/test/lib-loadcheck.sh`，更新第 0 节的可加载数字。
- [ ] `src/core/version.inc` 与 `CHANGELOG.md` 的最新版本一致。
- [ ] NOW/NEXT 已复核，完成项移出，技术债状态已翻转。
- [ ] `sh src/prj/fun/check-roadmap.sh` 通过。
- [ ] 按 `RELEASING.md` 打 annotated tag，不用裸 tag。

## 7. 变更记录

- 2026-10-31：创建主控文档；把当前技术债、待办、接受项和发版检查集中到这里。
- 2026-10-31：修复 `SHA256()` 的 Unix 快路径，别名指向错误的 `-lnx` 包装，
  导致一直走纯 Fun；1 MB 从约 9.6 秒降到约 4 毫秒。
- 2026-10-31：`use ... as Alias` 现在会沿转发模块的 `use` 链暴露一级名字，
  `-lnx` 薄包装对限定访问也透明；新增 `alias-re-export.fun` 回归。
- 2026-10-31：确认 `compile(inline: true)` 是词法内联，`m.x` 可读写调用方状态；
  新增 `compile-inline-scope.fun` 回归，非 inline `compile()` 保持隔离。
- 2026-10-31：发布 9.5.2；包含 io stdio 适配器、SHA256 快路径、use 别名
  re-export、inline 语义锁定和 ROADMAP/检查脚本。
- 2026-11-02：Q-01/Q-02/Q-03/Q-05 关闭；Q-04 降级为 DEFERRED（X-08）。
- 2026-11-02：S-01 关闭（#44 `io.pipe` + #45 `process.run`）；流式/交互式子进程
  stdio 拆为 S-09。
- 2026-11-03：发布 9.5.4；`if`/条件循环新增 `{}` 块写法，`cli` 支持可选 stdin，
  修复裸 `var` 实参的命名绑定问题。
- 2026-11-05：发布脚本内置跨平台安装器：Unix 的 `install.sh` 增加
  `--bin-dir` / `--add-path`（带标记、可重复执行）；Windows 压缩包新增
  `install.cmd` / `install.ps1` / `uninstall.cmd` / `uninstall.ps1`，
  默认按用户安装到 `%LOCALAPPDATA%\Programs\Fun`，注册 PATH、`.fun`/`.foo`/
  `.fxx` 关联、Win+R `App Paths` 和“设置 > 应用”卸载项。技术债补记
  unixODBC、macOS TCC 与 win-arm64 FPC target。
- 2026-11-06：接入 unixODBC 第二数据库后端（P-05/P-11 关闭）。新增
  `lib-ado-odbc-unx.fun`，`lib-ado-unx` 在连接串含 `odbc:`/`DRIVER=`/`DSN=`
  时自动分派；SQLite 仍走内嵌路径，未装 unixODBC 的机器不受影响。参数按
  ORM DataType 绑定、结果按列类型读取，支持事务和 ODBC 目录函数
  （SQLTables/SQLColumns/SQLPrimaryKeys/SQLForeignKeys）。新增
  `run-ado-odbc.sh`（无驱动时 SKIP）与 `unixodbc`+`libsqliteodbc` CI 步骤，
  回归 `126/126 → 127/127`。验证时补了 `Begin`/`Commit`/`Rollback` 的隐式
  `Open()`（ORM 先开事务再执行，未显式 Open 时曾误走 SQLite 路径）、
  `?` 参数个数预检，以及 `Init()` 打开 ODBC 连接并安装驱动的标识符引号
  （ORM RPC 在生成 SQL 前依赖它）；ODBC 测试补了大文本/大 BLOB 分块、
  空串与 NULL、事务隐式打开和无驱动时的稳定 SKIP 输出。
- 2026-11-07：D-01 JSON Schema v0.x 完成。新增 `checkJson`/`checkFd` 与
  `validJson`/`validFd` 文本入口，补齐同文档 `$ref`/`$defs`、
  `allOf`/`anyOf`/`oneOf`/`not`、`uniqueItems`、元组 `items` +
  `additionalItems`、`patternProperties`、`propertyNames`、`format`。
  JSON schema 文本改为严格解析，非法数据返回 `parse` 错误；回归
  `127/127` 不变，schema 用例从 45 条扩到 115 条断言。
- 2026-11-08：S-02 明确以 `fun-jsbox` 为唯一沙箱边界，不以 fun `-safe`
  代替。Linux x86-64/arm64 的 worker 在求值前安装 seccomp-bpf 白名单，
  越权系统调用以 `SIGSYS` 终止；响应新增 `sandbox.seccomp`，
  `--selftest-seccomp` 验证 `openat` 被拒绝（退出 159），过滤安装失败
  时拒绝运行。`run-jsbox-test.sh` 增加该自检，`jsbox_test.fun` 增加沙箱
  模式断言（25/25）。`process.run` 增加 `output` 字节预算并在超限时终止
  子进程，jsbox 桥接用它限制失控 stdout。worker 增加 Windows MSVC 构建与
  Job Object 限制、macOS `sandbox_init`（网络/新进程拒绝），响应报告
  `sandbox.kind`，CI 在 POSIX 矩阵和 Windows x64 上跑 jsbox 测试。剩余：
  bubblewrap/nsjail 网络与挂载隔离，以及 Windows/macOS 真机复验。
- 2026-11-08：S-08 关闭。fun-ui 1.0.4 的 Windows WebView2 基线、Linux
  GTK3/WebKit2GTK 原生宿主与 macOS AppKit/WKWebView 原生宿主均已完成，
  README 状态表标记为已完成，`fun-ui` CI 的 linux-loopback、
  linux-webkitgtk、macos-wkwebview 全部通过。S-09 仍 OPEN：`io.pipe`、
  `process.run` 与输出上限已就绪，但把管道交给子进程并边跑边读写、进程树
  终止、Windows Unicode 命令行尚未实现。
- 2026-11-08：9.5.5 发版准备。S-04 站点 PHP -> Fun 迁移完成并归档；
  S-03 标记 DEFERRED；S-09 不并入 S-02（jsbox 是一次性 JSON，不依赖流式
  stdio），继续独立跟踪。技术债台账的 DONE 项统一移到第 5 节
  “接受 / 不做 / 已完成”，台账只留开放项；macOS 已完成的构建/运行时接入
  记为 P-14，剩余真机复验、签名/公证与 TCC 合并为 P-08（原 P-12 并入）；
  Q-04 并入 X-08。P-10 关闭：Linux aarch64 交叉产物只用于开发验证，正式
  发布用 CI 原生 linux-arm64 构建。回归刷新为 `131/131`，加载检查
  `77/83`。
- 2026-11-08：发布 9.5.5。新增 `fun-jsbox` 沙箱、JSON Schema v0.x 关键字、
  unixODBC 后端、HMAC-SHA1/URL 编码、`process.run` 输出上限与 macOS/win64
  运行时能力；修复循环集合深拷贝栈溢出；站点 PHP 已全部迁到 Fun，并在
  验证中修复正则未命中判断。
- 2026-11-10：LoongArch `lib-asm-loongarch64` 编码器落地（binutils 生成的
  指令表、与 GNU as 逐字节/随机差分、QEMU 独立交叉验证；live 执行待 qemu/真机）。
  macOS 的 P-08 拆分：x64/arm64 运行时复验由 CI 原生 macOS runner 覆盖并标记
  DONE，正式签名/公证与 TCC 独立为 P-15。LoongArch 同样拆分：已完成部分记为
  P-09 DONE，发布/CI/真机收尾独立为 P-16。CI 增加 fun-jsbox 二进制缓存
  （按 jsbox/main.c + build-jsbox.sh 哈希），并去掉 unixODBC 安装前无条件的
  `apt-get update`（失败时回退）。回归刷新为 `133/133`，加载检查 `78/84`。
