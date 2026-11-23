# Fun 主控文档 (ROADMAP)

> 这是 Fun 的**唯一状态来源**。设计、证据和历史背景放在 `art/notes/` 与 `known-issues/`，
> 本文只维护当前基线、优先级、技术债和发版门槛。
> `art/notes/` 和 `known-issues/` 是维护者本地笔记，不在公开仓库；CI 只校验仓库内路径。
>
> 最近更新：2026-11-22
> 基线：Fun 9.5.7（tag `v9.5.7`）

## 0. 当前基线

- **版本**：9.5.7，`src/core/version.inc` 的 `funRelease = '9.5.7'`。
- **回归**：Linux `141/141`（`sh fun/test/run-linux-regression.sh`）。
- **标准库**：`fun/lib` 共 119 个 `.fun`，90 个候选模块，本机可加载 84 个
  （`sh fun/test/lib-loadcheck.sh`；6 个 FAIL 为 Windows 概念、raw socket 或 macOS 后端）。
- **平台**：Linux x86_64 / arm64、macOS x64 / arm64、Windows x64（FPC）；
  Delphi/Win32 人工验证。LoongArch64 / riscv64 为预发布目标。
- **CI**：`regression` 覆盖 6 个构建作业（4 个 POSIX 平台 + linux-safe + windows-x64），
  其中 5 个发布平台额外构建 `funcmd-mt` 并跑 worker 测试；`loongarch`/`riscv64`
  预发布作业同样构建 `funcmd-mt` 并在 qemu 下跑 `lib-worker-test`；`docs` 检查本文件。
- **能力链**：ffi → 同步文件 IO → 进程 → 网络 → 数据库；另有 C/JIT/汇编、
  HTTP/WebSocket 单线程事件循环、safe 构建。

## 1. 正在进行 (NOW)

| ID | 事项 | 状态 | 优先级 | 验收 | 关联 |
|---|---|---|---|---|---|
| （空） | | | | | |

## 2. 下一步 (NEXT)

| ID | 事项 | 状态 | 优先级 | 验收 | 关联 |
|---|---|---|---|---|---|
| （空） | | | | | |

## 3. 以后 (LATER)

| ID | 事项 | 状态 | 优先级 | 验收 | 关联 |
|---|---|---|---|---|---|
| S-03 | `#!fun` 经 tcc 编译 | DEFERRED | P2 | 先做数值/字符串/函数/控制流子集，再做模块导入 | `art/notes/todo.md` |
| S-05 | create-fun-app 脚手架 | OPEN | P3 | Fun 后端 + z-data 前端 + 一体发布 | `art/notes/todo.md` |
| S-06 | 用 fun-ui 重写 funide | OPEN | P3 | 新 IDE 替代旧 funide | `art/notes/todo.md` |
| S-07 | funcally AI agent | OPEN | P3 | 基于沙箱、CLI、HTTP 的 agent | `art/notes/todo.md` |
| S-09 | 流式/交互式子进程 stdio | OPEN | P2 | 管道交给子进程并边跑边读写；进程树终止见 S-12，Windows Unicode 见 S-13 | `docs/standard-library.zh.md` 的子进程一节 |
| S-10 | jsbox 网络与挂载隔离 | OPEN | P2 | Linux bubblewrap/nsjail 网络与挂载隔离（S-02 剩余） | `src/prj/fun/jsbox/README.md` |
| S-11 | jsbox Windows/macOS 沙箱验证 | OPEN | P2 | Job Object / sandbox profile 的 CI 与真机验证（S-02 剩余） | `src/prj/fun/jsbox/README.md` |
| S-12 | 子进程树终止 | OPEN | P2 | Unix 进程组 / Windows Job Object 终止整棵进程树（S-09 剩余） | `docs/standard-library.zh.md` 的子进程一节 |
| S-13 | Windows Unicode 子进程命令行 | OPEN | P3 | 命令行走宽字符并正确转义（S-09 剩余） | `docs/standard-library.zh.md` 的子进程一节 |

## 4. 技术债台账

| ID | 区域 | 优先级 | 状态 | 说明 | 证据 |
|---|---|---|---|---|---|
| K-01 | 内核 | P3 | OPEN | H-09 `_eval` 的 `$@@` 整体重扫 | 本地 hazards 清单 |
| K-02 | 内核 | P2 | OPEN | H-05 `div/mod 0` 抛 RTL `EDivByZero`，按兼容保留 | 本地 hazards 清单 |
| K-03 | 内核 | P2 | OPEN | H-06 Delphi/32 位与 Int64 极值边界未复测 | 本地 hazards 清单 |
| K-05 | 内核 | P3 | OPEN | `result` 由脚本手动初始化；重复调用会复用旧栈槽，新库入口需写 `result = nil` / `0` | `src/core/core.pas:1058`、`src/core/base.pas:980` |
| D-02 | 数据 | P2 | OPEN | FD fixed-length binary 跨端退化为文本 | `art/notes/data-format-alignment.md` |
| D-03 | 数据 | P2 | OPEN | 日期/时间跨端约定未统一 | `art/notes/data-format-alignment.md` |
| D-04 | 数据 | P2 | OPEN | Fun `Int64` 超过 2^53 传给 JS 静默丢精度 | `art/notes/data-format-alignment.md` |
| D-05 | 数据 | P3 | OPEN | FD/JSON 其余低风险一致性项 | `art/notes/data-format-alignment.md` |
| P-02 | 平台 | P2 | OPEN | `lib-os` 全量 host 分派器未做 | `art/notes/library-port-plan.md` |
| P-03 | 平台 | P2 | OPEN | `lib-message`/`lib-async`/`lib-jsasync` 仍依赖消息泵或线程 | `art/notes/linux-capabilities.md` |
| P-04 | 平台 | P3 | OPEN | `lib-icmp` raw socket 未做，需 root/CAP_NET_RAW | `art/notes/linux-capabilities.md` |
| P-06 | 平台 | P3 | OPEN | `lib-os` B 档（GetIPs/inotify 等）未做 | `art/notes/linux-capabilities.md` |
| P-07 | 机器码 | P2 | OPEN | `asm-list` 的 x86-64 表覆盖不全 | `art/notes/arch-machine-code-plan.md` |
| P-13 | Windows/ARM | P3 | OPEN | win-arm64 因 FPC 生成物在真机 `0xC0000005` 崩溃（#42048/#42091）；已备交叉脚本与 bring-up，待 FPC 修复接回 nightly | `src/prj/fun/make-win-arm64.sh`、`.github/workflows/winarm64.yml` |
| P-15 | macOS 分发收尾 | P2 | OPEN | 正式 `codesign`/公证、Apple TCC 授权、物理机抽查 | `art/notes/macos-port.md` |
| P-16 | LoongArch 发布与真机 | P3 | OPEN | 已有独立 loongarch CI、打包与 nightly 资产、asm live 验收；剩余 TCC 龙芯后端策略与整包真机验收 | `art/notes/loongarch-port-assessment.md` |

## 5. 接受 / 不做 / 已完成

> 终态归档：DONE 表示已交付；WONTFIX / DEFERRED 表示明确不做或暂不做。
> 开放中的事项只保留在第 1-4 节。

### 5.1 已完成 (DONE)

| ID | 事项 | 状态 | 说明 |
|---|---|---|---|
| S-02 | jsbox 沙箱运行器 | DONE | `fun-jsbox` 为唯一沙箱边界；Linux seccomp-bpf、Windows Job Object、macOS sandbox profile、桥接与测试已交付。剩余拆 S-10/S-11。 |
| P-01 | 平台/并发：worker 模型 | DONE | worker 独立解析 AST/CEnv，跨线程只走字符串/FD；`Shared`/`Channel`/`onDone`/`workerMapLimit`、常驻池与协作式取消已落地；5 个发布平台 CI 跑 `lib-worker-test`，发布包附带 fun-mt。 |
| P-17 | LoongArch64/riscv64 `fun-mt` | DONE | 交叉脚本支持 `FUN_THREADS=1`，两架构 qemu 下 `lib-worker-test` 72/72；CI 构建、测试并打包为 `fun-mt`。 |
| S-04 | 站点 PHP 用 Fun 重写 | DONE | 页面与接口全部迁到 Fun，PHP-FPM 停用，nginx 反代旧 URL。 |
| K-04 | 循环集合深拷贝递归溢出 | DONE | `CEnv` clone 栈 + `CSet.clone`；`fun/test/clone-cycle-test.fun` 覆盖。 |
| P-05 | 第二数据库后端：unixODBC | DONE | MySQL/PostgreSQL 等经 unixODBC 接入（与 P-11 同一交付）。 |
| P-11 | unixODBC 后端 | DONE | `lib-ado-unx` 自动分派 `odbc:`/`DRIVER=`/`DSN=`；参数、事务、OpenSchema 齐全，CI 跑 `run-ado-odbc.sh`。 |
| P-09 | LoongArch 解释器/标准库/汇编后端 | DONE | 交叉构建与 musl 全栈跑通；`lib-asm-loongarch64` 编码器经 GNU as 差分与 QEMU 验证。收尾见 P-16。 |
| P-08 | macOS 运行时复验 | DONE | CI 原生 macOS x64/arm64 跑完整套件，含 `MAP_JIT` 与 FFI 回调。签名/TCC 见 P-15。 |
| P-14 | macOS 构建与运行时接入 | DONE | x64/arm64 引擎、`lib-proc-darwin`、`libtcc.dylib` 与 ad-hoc 签名完成。剩余归 P-15。 |
| Q-01 | `lib-ado-schema.Filter` 丢外键 | DONE | ORM `@Parent`/`@Children` 走 OpenSchema，Windows/Unix 均恢复外键。 |
| Q-02 | `lib-fd`/`lib-bnf` 已知功能项 | DONE | 重名组已修，其余功能项关闭。 |
| Q-03 | Windows `make-*.bat` 的 `-dRegexx` | DONE | 改为 `-dRegex -dPCRE_WinDLL`。 |
| Q-05 | safe 模式只接 Linux 构建脚本 | DONE | `SAFE=...` 覆盖 Linux aarch64、macOS 原生/交叉与 win64。 |

### 5.2 接受 / 不做 (WONTFIX / DEFERRED)

| ID | 事项 | 状态 | 说明 |
|---|---|---|---|
| X-01 | 短期不设 Delphi 编译器 CI | WONTFIX | GitHub 不适合引入非开源 Delphi；人工验证。 |
| X-02 | Windows UI/registry/trayicon/message 不移植 | WONTFIX | Windows 概念，Linux/macOS 无干净等价物。 |
| X-03 | `move` / `toNum(ptr:-1)` 保持不安全 | WONTFIX | 裸内存原语，由 `-safe` 按 MEM 类拦截。 |
| X-04 | H-07 递归求值栈 | WONTFIX | 16M 栈当前够用。 |
| X-05 | writer 15 位浮点输出 | WONTFIX | 可读性优先，接受细小往返差异。 |
| X-06 | 重复键 last-wins、孤立 surrogate 不额外拒绝 | WONTFIX | 与 RFC 8259 / JSON.parse 一致。 |
| X-07 | `compile(inline: true)` 是词法内联 | WONTFIX | 可读写调用方状态；需要隔离时用非 inline 或传状态容器。 |
| X-08 | `str.sha256()` 的 Pascal 内置实现 | DEFERRED | 正常构建走 libcrypto/CryptoAPI/CommonCrypto；纯 Fun 版正确但约 12 ms/KB。 |
| P-10 | Linux aarch64 交叉产物补齐 regex/FFI | WONTFIX | 交叉产物只用于开发验证；正式发布用 CI 原生 linux-arm64。 |

## 6. 发版检查

- [ ] `sh fun/test/run-linux-regression.sh` 全绿，更新第 0 节回归数字。
- [ ] `sh fun/test/lib-loadcheck.sh`，更新第 0 节可加载数字。
- [ ] `src/core/version.inc` 与 `CHANGELOG.md` 版本一致。
- [ ] NOW/NEXT 已复核，完成项移出，技术债状态已翻转。
- [ ] `sh src/prj/fun/check-roadmap.sh` 通过。
- [ ] 按 `RELEASING.md` 打 annotated tag，不用裸 tag。

## 7. 变更记录

> 详细历史见 `CHANGELOG.md` 与 git；这里只留影响当前基线的里程碑。

- 2026-11-23：linux-x64 发布产物的 glibc 地板从 2.34 降到 2.17（manylinux2014
  容器构建，PCRE/libffi 静态链入），覆盖麒麟 V10 / 统信 UOS；`getapi` 支持
  musl 库名解析与 Unix 宽字符串 `'w'`。回归 `141/141`。
- 2026-11-22：发布 9.5.7。P-01/P-17 完成（常驻池、协作式取消、LoongArch64/riscv64 `fun-mt`）。回归 `139/139`，加载 `84/90`。
- 2026-11-15：发布 9.5.6。traceback、`lib-cron`、LoongArch nightly、`fun package tidy`。回归 `137/137`。
- 2026-11-10：P-09/P-08 完成：LoongArch asm 后端与 macOS 原生 runner 复验。
- 2026-11-08：发布 9.5.5。jsbox、JSON Schema v0.x、unixODBC、站点 PHP→Fun。
- 2026-11-02：S-01 关闭；流式/交互式子进程 stdio 拆为 S-09。
