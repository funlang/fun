# Fun 主控文档 (ROADMAP)

> 这是 Fun 的**唯一状态来源**。设计、证据和历史背景放在 `art/notes/` 与 `known-issues/`，
> 本文只维护当前基线、优先级、技术债和发版门槛。
> `art/notes/` 和 `known-issues/` 是维护者本地笔记，不在公开仓库；CI 只校验仓库内路径。
>
> 最近更新：2026-10-31
> 基线：Fun 9.5.1（tag `v9.5.1`）

## 0. 当前基线

- **版本**：9.5.1，`src/core/version.inc` 的 `funRelease = '9.5.1'`。
- **回归**：Linux `121/121`（`sh fun/test/run-linux-regression.sh`）。
- **可加载性**：`72/78`（`sh fun/test/lib-loadcheck.sh`，6 个 FAIL 均为 Windows 概念、
  raw socket 或 macOS-only 后端）。
- **标准库**：76 个模块（`fun/lib` 有 78 个基础 `.fun`，内部 `lib-base`/`lib-type` 不计）。
- **平台**：Linux x86_64 / arm64、macOS x64 / arm64、Windows x64（FPC）；
  Delphi/Win32 继续人工验证。
- **CI**：GitHub Actions 的 `regression` 工作流覆盖 6 个构建作业（4 个 POSIX 平台 +
  linux-safe + windows-x64），`docs` 工作流检查本文件。
- **能力链**：ffi → 同步文件 IO → 进程 → 网络 → 数据库；另有 C/JIT/汇编、
  HTTP/WebSocket 单线程事件循环、safe 构建。

## 1. 正在进行 (NOW)

当前没有进行中的代码任务。下一项从 NEXT 选择，选定后在同一个提交里把它移到这里。

## 2. 下一步 (NEXT)

| ID | 事项 | 状态 | 优先级 | 验收 | 关联 |
|---|---|---|---|---|---|
| D-01 | JSON Schema v0.x | OPEN | P1 | `checkJson`/`checkFd`、`$ref/$defs`、`allOf`/`anyOf`/`oneOf`/`not`、`uniqueItems`、元组 `items`、`patternProperties`、`propertyNames`、`format` | `art/notes/jsonschema-plan.md` |
| S-01 | `io.pipe` + 子进程 stdio | OPEN | P1 | pipe、spawn/wait、退出码、超时、输出捕获 | `README.zh.md` 的 io 一节 |
| S-02 | 沙箱运行器 | OPEN | P1 | 用 `-safe` 子进程 + 超时/内存/输出上限跑 AI 生成脚本 | `art/notes/todo.md` |

## 3. 以后 (LATER)

| ID | 事项 | 状态 | 优先级 | 验收 | 关联 |
|---|---|---|---|---|---|
| S-03 | `#!fun` 经 tcc 编译 | OPEN | P2 | 先做数值/字符串/函数/控制流子集，再做模块导入 | `art/notes/todo.md` |
| S-04 | 站点 PHP 用 Fun 重写 | OPEN | P3 | 去掉 PHP 依赖，保持现有站点行为 | `art/notes/todo.md` |
| S-05 | create-fun-app 脚手架 | OPEN | P3 | Fun 后端 + z-data 前端 + 一体发布 | `art/notes/todo.md` |
| S-06 | 用 fun-ui 重写 funide | OPEN | P3 | 新 IDE 替代旧 funide | `art/notes/todo.md` |
| S-07 | funcally AI agent | OPEN | P3 | 基于沙箱、CLI、HTTP 的 agent | `art/notes/todo.md` |
| S-08 | fun-ui 跨平台 | OPEN | P2 | Windows/Linux 收尾 | `art/notes/todo.md` |

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
| P-05 | 平台 | P3 | OPEN | MySQL/ODBC 第二数据库后端未做 | `art/notes/linux-capabilities.md` |
| P-06 | 平台 | P3 | OPEN | `lib-os` B 档（GetIPs/inotify 等）未做 | `art/notes/linux-capabilities.md` |
| P-07 | 机器码 | P2 | OPEN | `asm-list` 的 x86-64 表覆盖不全 | `art/notes/arch-machine-code-plan.md` |
| P-08 | macOS | P2 | OPEN | arm64 真机验证、`libtcc.dylib`、签名/公证未做 | `art/notes/macos-port.md` |
| P-09 | 架构 | P3 | OPEN | LoongArch 工具链与编码器未做 | `art/notes/arch-machine-code-plan.md` |
| P-10 | 架构 | P3 | OPEN | Linux aarch64 交叉产物仍缺 `-dRegex` 与 `-dLinuxFFI` | `README.zh.md` |
| Q-01 | 质量 | P2 | OPEN | `lib-ado-schema.Filter` 丢外键 | `art/notes/linux-capabilities.md` |
| Q-02 | 质量 | P2 | OPEN | `lib-fd`/`lib-bnf` 仍有已知功能项（重名组已修） | `art/notes/port-decisions.md` |
| Q-03 | 质量 | P3 | OPEN | Windows `make-*.bat` 仍写 `-dRegexx` 拼写，实际不启用 regex | `src/prj/fun/make-win64.bat` |
| Q-04 | 质量 | P3 | OPEN | `str.sha256()` 没有 Linux 内置 Pascal 实现，纯回退正确但慢 | `art/notes/port-decisions.md` |
| Q-05 | 质量 | P2 | OPEN | safe 模式只接在 Linux 构建脚本，macOS/Windows 未接同一组宏 | `SAFETY.zh.md` |

## 5. 接受 / 不做

| ID | 事项 | 状态 | 说明 |
|---|---|---|---|
| X-01 | 短期不设 Delphi 编译器 CI | WONTFIX | GitHub 不适合引入非开源 Delphi；Delphi/Win32 人工验证 |
| X-02 | Windows UI/registry/trayicon/message 不移植 | WONTFIX | Windows 概念，Linux/macOS 无干净等价物 |
| X-03 | `move` / `toNum(ptr:-1)` 保持不安全 | WONTFIX | 裸内存原语，由 `-safe` 按 MEM 类拦截 |
| X-04 | H-07 递归求值栈 | WONTFIX | 16M 栈当前够用，不够再加 |
| X-05 | writer 15 位浮点输出 | WONTFIX | 可读性优先，接受细小往返差异 |
| X-06 | 重复键 last-wins、孤立 surrogate 不额外拒绝 | WONTFIX | 与 RFC 8259 / JSON.parse 行为一致 |

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
