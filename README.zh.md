# Fun 语言

**运行时很小，能力很深：从胶水代码到机器码。**

Fun 是一门约 0.3 MB、零外部依赖的脚本语言，自 2010 年起用于生产，覆盖
JSON/FD 数据、日常胶水代码、FFI、运行时 C、JIT 与原生机器码。

**约 0.3 MB** 运行时 · **0** 外部依赖 · **Windows 95 → LoongArch64** · **15 年以上**

[安装](#快速开始) · [教程](docs/tutorial.zh.md) · [中文手册](https://funlang.org/man-cn.htm) · [为什么是 Fun](#为什么是-fun)

[English](README.md) · **简体中文**（本文件）

- 版本：**9.5.7** · 官网：<https://funlang.org> · 许可证：MIT（[条款](#许可证)） · [路线图](ROADMAP.md)

```fun
use 'lib-set.fun';

var nums = [1, 2, 3, 4, 5];
var doubled = nums | map(a -> a * 2);
?. doubled.@toJson();   # [2,4,6,8,10]

class Number(me)
  this['#'] = you -> (me + you) * me * you;
end class;
var n = Number(2);
?. n .# 3;              # 30
```

---

## 亮点

**贴入 C 声明，直接调用。** 在 Windows 上，`CWin32API` 解析函数原型，生成 FFI
签名，并用命名参数调用：

```fun
use 'lib-cwinapi.fun';

var msgBox = CWin32API('user32.dll',
  'int MessageBoxA(HWND hWnd, LPCSTR lpText, LPCSTR lpCaption, UINT uType);');
msgBox.call([lpText: 'Hello from Fun', lpCaption: 'Fun', uType: 0]);
```

**贴入 C 结构体声明，直接拿到布局。** `CStruct` 计算字段偏移、数组与对齐，
返回可按指针传递的缓冲区：

```fun
use 'lib-cstruct.fun';
var point = CStruct('struct Point { int x; int y; };', [x: 3, y: 4]);
?. point.@totalSize;    # 8
?. point.@toPtr() != 0; # true
```

**需要时继续下沉。** 同一段脚本可以用内置 TCC 编译 C、JIT，或写内联汇编；
原生代码还能通过 `@toCallback` 回调回 Fun。见[能力阶梯](#能力阶梯)。

**打成一个文件，或锁进沙箱。** `fun pack` 把应用与依赖库打成单个可执行文件；
`fun-safe` 是独立构建，移除原生代码、任意内存访问与文件/编译加载，适合插件与
不可信脚本。

**电池自带，而不是外挂。** 同一套库包含 HTTP server/client（CORS、JWT、
session、multipart）、cron、日志、运行时 traceback、ORM、YAML/XML/TOML/CSV、
JSON Schema、桌面 UI 与 worker pool。

**三行代码嵌入。** `Run(PChar('script.fun')); Run(source); Run(-1);`
把整个运行时变成可嵌入的 `fun.dll`。

**老 Windows 仍然算数。** 大多数运行时都在追新，Fun 还照顾老系统与遗留系统。
32 位构建仍能在 Windows 95 OSR2（含完整 UI）与 NT 3.5 上运行，FFI 与机器码
保持可用。见 [Windows 95](https://funlang.org/art/fun-on-win95.htm) 与
[NT 3.5](https://funlang.org/art/fun-on-nt35.htm)。

---

## 为什么是 Fun

一句话定位：**Fun 是一门从 JSON 一路写到机器码的脚本语言。**

- 用同一个运行时，覆盖从高层数据处理（JSON/FD）到底层系统编程（FFI、运行时 C、JIT、机器码）的全谱系；
- 自带约 90 个用 Fun 自身编写的标准库模块，全栈能力打包进单个可嵌入的 `fun.dll`；
- 在信创与 AI Agent 场景中，作为连接国产 OS、数据库、芯片与业务逻辑的轻量级胶水。

Fun 的设计出发点很简单：**数据与代码都应该是头等公民，而且一段脚本应该能在不离开语言的情况下一路触达机器底层。**

多数脚本语言要么停留在高层（好用，但在 FFI 处撞墙），要么要求你在性能关键处去写 C。Fun 把这条能力阶梯收敛进同一个运行时：

- 用原生的 list / set / tree 集合处理 **JSON 与 FD** 数据；
- 通过 **紧凑的 FFI 签名**调用任意原生代码；
- 用内置的 Tiny C 编译器 **在运行时编译 C**；
- 需要最紧的循环时，直接 **内联汇编 / JIT**；

这一切都可以从纯脚本出发，并打包进单个可嵌入的二进制。

Fun 使用 Pascal（Delphi / Free Pascal）编写。核心是一个小巧的树遍历解释器，带有动态值模型、对象系统、闭包与模块——刻意保持精简，以便既可嵌入为 `fun.dll`，也可作为独立的 `fun.exe` 运行。

---

## 核心特性

- **动态、以数据为中心的值模型** —— 数字、字符串、时间、正则，以及头等集合：list（数组）、set 与 tree，构建于基于变体（variant）的运行时之上。
- **函数一等公民** —— 匿名函数、函数引用、柯里化、默认参数与可变参数，以及 `->` 管道。
- **对象系统** —— `class`、`this` / `base`、方法，以及属性的 get/set 分发（方法、getter、setter 统一通过 `.` 运算符分发）。
- **模块** —— `use 'file.fun'`（可 `as alias`）引入其它脚本；别名也会暴露转发模块导入的一级名字，运行时跟踪模块状态与依赖。
- **正则作为值类型** —— 内嵌 PCRE 引擎，支持行内正则字面量（`/.../`）与匹配运算符（`=~`、`!~`）。
- **内置数据格式** —— JSON 与 **FD**，一种兼容 JSON、对人类与 AI 都友好的类 Markdown 格式（见[下文](#fd-数据格式)）。
- **运行时 C 与机器码** —— 内置 Tiny C 编译器、JIT 与内联汇编（见[能力阶梯](#能力阶梯)）。
- **C 级 FFI** —— 贴入 C 声明，或用简短签名串调用 DLL/共享库函数（见 [FFI](#外部函数接口ffi)）。
- **关键字别名** —— 规范英文关键字 + 可插拔的别名包（中文、法文、自定义），运行时选择（见[下文](#关键字别名)）。
- **跨平台** —— Linux x64/arm64（LoongArch64/riscv64 为预发布）、macOS x64/arm64 与 Windows x64；32 位构建仍能在 Windows 95 OSR2 与 NT 3.5 上运行（见[老 Win32](docs/building.zh.md#老-win32)）。linux-x64 产物在 glibc 2.17 容器、linux-arm64 在 glibc 2.28 容器中构建，麒麟 V10 / 统信 UOS 20 等旧 glibc 系统可直接运行。
- **双形态分发** —— 命令行 `fun.exe` 与嵌入运行时 `fun.dll`（导出简单的 `Run` 接口）。
- **自托管的标准库** —— 约 90 个用 Fun 自身编写的公开模块，覆盖 JSON/YAML/XML 到 ORM、异步、UI 与原生绑定。

---

## 快速开始

从 [GitHub Releases](https://github.com/funlang/fun/releases) 下载预编译包，或使用
一行安装（macOS / Linux；校验 `SHA256SUMS`，安装到 `~/.fun`）：

```bash
curl -fsSL https://raw.githubusercontent.com/funlang/fun/main/install.sh | sh
```

Windows 上用 7-Zip 解压 `.7z`，双击 `install.cmd`。每个包都带 `fun`、
`fun-safe`、可用时的 `fun-mt`、标准 `lib/`、demo 与回归套件。发布包细节、
安装器选项与运行要求见 [docs/install.zh.md](docs/install.zh.md)。

运行脚本：

```text
fun <file.fun>                # 运行脚本（.fun / .foo / .fxx）
fun -v <file.fun>             # 显示编译与运行耗时
fun -log[:log.txt] -gui       # 输出日志 / GUI 模式运行
fun -key:key_cn.ini           # 加载关键字别名包
```

Hello world（规范关键字）：

```fun
fun foo()
  ?. 'Hello, fun!';
end fun;

foo();

fun max(a, b)
  if a > b then
    result = a;
  else
    result = b;
  end if;
end fun;

?. max(1, 9);
?. max(9, 1);
```

运行：

```text
> fun fun/demo/fun.fun
Hello, fun!
9
9
```

---

## 文档

建议从[教程](docs/tutorial.zh.md)开始；精确语言规则查官网
[中文手册](https://funlang.org/man-cn.htm)。

| 文档 | 内容 |
| ---- | ---- |
| [教程](docs/tutorial.zh.md) | 上手路径：第一个脚本、值、集合、类、文件、包、HTTP、worker、原生代码。 |
| [标准库指南](docs/standard-library.zh.md) | 模块地图，以及 worker、日志、运行时、cron、HTTP、CLI、IO、格式与 schema 的详细用法。 |
| [安装](docs/install.zh.md) | 发布包、一行安装、Windows 安装器、运行要求。 |
| [构建](docs/building.zh.md) | 原生与交叉构建、能力矩阵、第三方依赖、安全构建、CI。 |
| [工具链](docs/tooling.zh.md) | `package.fun`、`fun package`、`fun run`、`fun test`、`fun pack`。 |
| [中文手册](https://funlang.org/man-cn.htm) | 按章节组织的语言参考。 |

---

## 体验 Fun 语言

两个短小、自成一体的小片段，展示语言的两极（完整文件位于 `fun/demos/benchmarks/`）。

类的自定义运算符、一等函数、函数组合与管道：

```fun
# 带自定义运算符的类
class Number(me)
  this['#'] = you -> (me + you) * me * you;
end class;
var $ = Number(2);
?. $ .# 3;            # (2 + 3) * 2 * 3 = 30

# 一等函数、组合与管道
var f = a -> a * 2;
var g = a -> a + 3;
?. g(f(1 + 2) + 3);   # 12
?. 1 + 2 | f + 3 | g; # 12（同样结果，用管道写）
```

用正则与集合组合子把查询串解析成映射的数据管道：

```fun
use 'lib-regex.fun';
use 'lib-set.fun';
var q = 'a=1&b=2&c=';
var parseQuery = s -> (s | split(/&/) | map(sp_eq) | fromPairs);
?. parseQuery(q).@toJson(1);  # {"a":"1","b":"2","c":""}
```

完整版本见 [`test-high-level-language.fun`](fun/demos/benchmarks/test-high-level-language.fun)。

---

## 包管理与测试

一个项目就是带 `package.fun` 清单的目录：

```text
fun package init myapp          # package.fun + src/main.fun
fun package init mylib --lib    # package.fun + src/lib.fun
fun package tidy                # 把钉住的版本装进 ~/.fun
fun run [args...]               # 运行清单里的 bin
fun test                        # 运行所有 *_test.fun
fun pack                        # 把应用与依赖库打成单个可执行文件
```

测试使用 `test.fun` 与 `*_test.fun` 文件：

```fun
use 'test.fun';
test('adds', {
  assert.equal(add(1, 2), 3);
});
```

`fun test` 为每个文件启动子进程，任一失败时以非 0 退出。清单字段、依赖规则、
断言、`skip`/`todo` 与打包选项见 [docs/tooling.zh.md](docs/tooling.zh.md)。

---

## 能力阶梯

Fun 的特殊之处在于，一段脚本在无需独立工具链的情况下能走多远：

| 层次       | 能力                              | 支撑                                             |
| ---------- | --------------------------------- | ------------------------------------------------ |
| 高层       | JSON / FD 数据，list / set / tree | 原生集合与解析器                                 |
| 原生调用   | `dll.getapi(name, 'signature')`   | 紧凑签名约定的 FFI                               |
| 运行时 C   | `ccompile(code, ...)`             | 内置 Tiny C 编译器（`libtcc.dll`/`.so`/`.dylib`） |
| JIT        | `NewJit(...)`                     | 在 C（TCC）与汇编之间分发                        |
| 机器码     | `Assembly(code, ...).Load()`      | 内联汇编、可执行内存分配                         |

例如，`lib-tcc` 加载 `libtcc.dll`（Linux 为 `libtcc.so`，macOS x64 为 `libtcc.dylib`）并暴露 `tcc_new`、`tcc_compile_string`、`tcc_get_symbol` 等，从而你可以从字符串编译 C 源码并立即调用所得到的符号。`lib-asm` 分配可执行内存、写入机器码并调用之；`lib-jit` 则根据源码形态自动选择路径（`#!c` → TCC，否则走汇编）。

一段脚本可以同时混合两者：`NewJit` 在运行时编译 C **和**内联汇编，并且两者都能通过 `@toCallback` 直接回调回 Fun 函数。完整示例见 [`test-jit-cb.fun`](fun/demos/benchmarks/test-jit-cb.fun)。`#!C` 路径可跨平台，汇编片段与架构相关。

---

## FD 数据格式

FD 是一种 **对人类与 AI 都友好**、且与 JSON 互通的数据格式：

- 兼容 JSON 的结构（嵌套键、数组）；
- 基于缩进、类 Markdown 的语法；
- 可选的 SSE 压缩；
- 与 JSON 双向转换（`@toJson`、`getJson`）。

```text
# FD 格式（类 Markdown：缩进 + 空格分隔）
person
  name 张卫东
  age 46
  skills
    - pascal
    - c
    - fun

# 等价的 JSON
{"person": {"name": "张卫东", "age": 46, "skills": ["pascal", "c", "fun"]}}
```

它的定义性特点是**自描述**：`lib-fd.fun` 中的解析器是由一份用 FD 本身写成的 BNF 文法（`fd.bnf.fd`）生成的。文法文件 `src/parse/bnf/fun.ebnf` 以同样的精神记录了语言文法。

FD 取值规则（解释器、`fd.js`/`fd2.js` 与 BNF 读取器一致）的完整说明见[中文手册](https://funlang.org/man-cn.htm)与 `lib-fd.fun`；要点是 RFC 8259 数字、只有 `true`/`false`/`null` 字面量、字符串默认不转义、重复键后者覆盖前者。

---

## 外部函数接口（FFI）

有两个入口：贴入 C 原型获得可读绑定，或用紧凑签名获得完全控制。

### 贴入 C 原型

在 Windows 上，`CWin32API` 接受 C 头文件里原样的声明，并暴露命名参数：

```fun
use 'lib-cwinapi.fun';

var msgBox = CWin32API('user32.dll',
  'int MessageBoxA(HWND hWnd, LPCSTR lpText, LPCSTR lpCaption, UINT uType);');
msgBox.call([lpText: 'Hello from Fun', lpCaption: 'Fun', uType: 0]);
```

`CStruct` 把同样的思路用在数据上：贴入 `struct` 声明即可得到字段偏移、对齐与
布局兼容的缓冲区。支持的类型与限制见
[标准库指南](docs/standard-library.zh.md#c-声明与结构体)。

### 紧凑签名

其余场景用**紧凑的签名串**约定暴露原生函数。标准库中的例子：

```fun
'kernel32'.getapi('VirtualAlloc', 'iiii:i');  // 4 个 int 参数 -> int
'tcc'.getapi('tcc_new', 'v:i');               // void 参数 -> int
```

签名依次编码每个参数类型，然后是 `:`，最后是返回类型（`i`=int、`s`=string、`v`=void、`d`=double 等）。同一机制驱动 COM（`lib-winole`）、Windows API（`lib-winapi`）与 C 运行时。

`getapi` 本身按平台提供：32 位 Windows 用 `winapi.pas`，Linux / macOS / win64 用 `lffi.pas`（后端是 FPC 自带的 libffi；win64 上它对应 `ffi.dll`）。

对 `p` 参数传入裸 `var x` 时，两个后端都按 OUT/INOUT 指针处理：引擎传一个指针宽度的单元，并把结果拷回 `x`。需要显式控制（或调用方自备缓冲区）时，用 `buf.toNum(-1)` 自己传地址。

---

## 关键字别名

解释器的规范关键字是英文（`fun`、`if`、`then`、`loop`、`class`……）。由于关键字通过别名层（`ParseAlias`）解析，你可以在启动时提供**可插拔的别名包**：

```text
fun.exe -key:key_cn.ini   # 中文关键字（函数=fun、如果=if……）
fun.exe -key:key_fr.ini   # 法文关键字
```

已附带别名包：`key_cn.ini`（简体中文）、`key_fr.ini`（français）、`key_pua.ini`（自定义/私有区）。语言本身与关键字无关——别名是本地化/无障碍特性，而非另一种语言。

---

## 嵌入运行时 fun.dll

`fun.dll` 是嵌入运行时，用于把 Fun 脚本集成进第三方应用：

```pascal
Run(PChar('script.fun'));  // 编译脚本
Run(scriptContent);        // 执行
Run(-1);                   // 释放
```

- **免费使用（MIT）**：个人学习、内部工具，以及以开源许可证发布的产品。
- **商业使用**：将 `fun.dll` 嵌入闭源商业产品（exe/dmg/apk 或 SaaS 后端）需要商业授权，见 [`LICENSE.dll`](LICENSE.dll)。

---

## 目录结构

```text
fun/
├── src/
│   ├── core/          # 解释器核心（值模型、对象系统、流程控制、IO）
│   ├── parse/         # 词法/语法解析器
│   │   └── bnf/       #   文法定义：fun.ebnf、yacc.y、lex.l（生成 .inc/.cod）
│   ├── lib/           # 内建运行时库（winapi、winole、UI、host 等）
│   ├── regex/pcre/    # 内嵌 PCRE 正则引擎
│   ├── 3rd/           # 第三方组件（KOL）
│   ├── utils/         # 工具函数
│   └── prj/fun/       # 工程与构建脚本（funcmd.dpr，Delphi/FPC）
├── fun/
│   ├── lib/           # 标准库（纯 Fun 编写，约 90 个公开模块）
│   ├── demo/          # 语言语法演示
│   ├── demos/         # 完整应用与基准测试
│   └── key_*.ini      # 关键字别名包（CN / FR / PUA）
├── docs/              # 教程、标准库、安装、构建与工具链指南
└── LICENSE*           # 授权文件
```

---

## 构建

原生构建：

```sh
cd src/prj/fun && ./make-linux-x86_64.sh   # Linux x86_64
cd src/prj/fun && ./make-macos.sh          # macOS（Homebrew FPC）
```

```bat
cd src\prj\fun
make-win64.bat
```

平台能力矩阵（默认构建，另有 opt-in 的 `fun-safe` 与 `fun-mt`）：

| 平台          | regex | FFI | 运行时 C (tcc) | asm | safe 构建 | worker 构建 |
| ------------- | ----- | --- | -------------- | --- | --------- | ----------- |
| linux-arm64   | yes   | yes | yes            | yes | yes       | yes         |
| linux-loongarch64 | yes | yes | no           | yes | yes       | yes         |
| linux-riscv64 | yes   | yes | no             | yes | yes       | yes         |
| linux-x64     | yes   | yes | yes            | yes | yes       | yes         |
| macos-arm64   | yes   | yes | yes            | yes | yes       | yes         |
| macos-x64     | yes   | yes | yes            | yes | yes       | yes         |
| win-x64       | yes   | yes | yes            | yes | yes       | yes         |

老 Win32 不是事后补丁：32 位构建仍能在 Windows 95 OSR2（含 UI）与 NT 3.5 上
运行。这些是兼容性探针，不是发布门槛；见
[Windows 95](https://funlang.org/art/fun-on-win95.htm) 与
[NT 3.5](https://funlang.org/art/fun-on-nt35.htm)。

macOS、Linux aarch64、龙芯与 riscv64 这几行在 Linux x86_64 上用引导好的 FPC
交叉工具链构建。第三方源码（PCRE、TCC、zlib、libffi）不随仓库携带；缺失时
构建降级而不是失败。交叉构建命令、工具链要求、依赖布局、安全构建与 CI 细节见
[docs/building.zh.md](docs/building.zh.md)。

---

## 标准库

标准库位于 [`fun/lib`](fun/lib)，以纯 Fun 编写：约 90 个公开模块（含平台变体
与内部辅助模块共 135 个 `.fun` 文件）。完整模块地图与用法说明见
[标准库指南](docs/standard-library.zh.md)。

- **数据**：`lib-json`、`lib-fd`、`csv`、`toml`、`jsonschema`、`lib-yaml`、`lib-xml`、`lib-base64`、`lib-cstruct`、`lib-md5`、`lib-crypt`、`lib-hmac`、`lib-url`
- **工具**：`uuid`、`lib-utils`、`lib-param`
- **集合 / 算法**：`lib-set`、`lib-tree`、`lib-stack`、`lib-dyns`、`lib-math`、`lib-bnf`
- **文本**：`lib-string`、`lib-regex`、`lib-match`、`lib-unicode`
- **系统 / IO**：`lib-file`、`lib-os`、`lib-host`、`lib-path`、`lib-stream`、`lib-input`、`lib-zlib`、`lib-sse-compress`、`env`、`cli`、`fs`、`io`、`process`、`logging`、`runtime`、`cron`、`lib-time`、`lib-cmdline`、`lib-proc`
- **网络**：`lib-winsock`、`lib-netif`、`lib-icmp`、`lib-ajax`、`lib-jsonrpc`、`http-server`、`http-client`、`http-auth`、`http-bearer`、`http-cors`、`http-multipart`、`http-session`、`jwt`
- **数据库**：`lib-orm`、`lib-orm-pro`、`lib-orm-gen`、`lib-orm-rpc`、`lib-orm-cte`、`lib-ado`、`lib-ado-schema`
- **原生 / 底层**：`lib-winapi`、`lib-winole`、`lib-registry`、`lib-cwinapi`、`lib-cstruct`、`lib-tcc`（C 编译）、`lib-jit`、`lib-asm`、`lib-asm-pro`、`lib-eval`
- **UI**：`lib-ui`、`lib-ui-base`、`lib-dialog`、`lib-trayicon`
- **并发 / 异步**：`lib-async`、`lib-jsasync`、`lib-bind`、`lib-message`、`lib-worker`
- **沙箱**：`lib-jsbox`
- **测试**：`test`（`fun test` 的注册与断言库）

几个入口：

- **Worker** —— `lib-worker` 需要 opt-in 的 `fun-mt` 构建。worker 拥有独立 AST 与堆；结果以字符串跨线程，`Shared`/`Channel` 复制值。见 [Worker](docs/standard-library.zh.md#worker-与-fun-mt-构建) 与 [`worker-model.md`](fun/lib/worker-model.md)。
- **日志** —— 入口配置一次，之后用命名 logger（`logging.getLogger`）；见[日志](docs/standard-library.zh.md#日志)。
- **运行时诊断** —— `runtime.source`、`runtime.stack`、`runtime.lastError` 提供文件、行号、函数与调用栈；见[运行时诊断](docs/standard-library.zh.md#运行时诊断)。
- **Cron 与 HTTP** —— `CronScheduler`、`HttpMultipartWriter`、签名 cookie 与 JWT 共用同一套单线程模型；见 [Cron](docs/standard-library.zh.md#cron-调度) 与 [HTTP 辅助](docs/standard-library.zh.md#http-辅助)。
- **CLI、文件、流与进程** —— `cli`、`fs`、`io`、`process`、TOML、CSV、JSON Schema 的用法都在[指南](docs/standard-library.zh.md)里。

---

## 示例

- [`fun/demo`](fun/demo) —— 语法演示：函数、闭包、柯里化、类、对象、集合、正则与异常处理。
- [`fun/demos`](fun/demos) —— 完整应用与基准：`notepad--` 编辑器、`odbc-search`，以及性能/汇编/JIT 基准。
- [`fun/demos/package-demo`](fun/demos/package-demo) —— 带 path 依赖的小包：`tidy`、`run`（项目与平铺模式）、`pack`。
- [`fun/demos/test-demo`](fun/demos/test-demo) —— 带测试、共享 helper 与失败断言示例的纯库包。
- [`fun/demos/http-cors-demo`](fun/demos/http-cors-demo) —— CORS 预检、凭据、暴露头与浏览器页面。
- [`fun/demos/http-bearer-demo`](fun/demos/http-bearer-demo) —— Bearer 鉴权、401 挑战与同源页面。
- [`fun/demos/http-session-demo`](fun/demos/http-session-demo) —— cookie 登录/登出、SID 轮换与服务端状态。
- [`fun/demos/fs-demo`](fun/demos/fs-demo) —— 嵌套目录、列举、遍历、原子写与清理。
- [`fun/demos/cli-demo`](fun/demos/cli-demo) —— 命令、flag、别名、env、钩子、help/version 与可测试输出。

---

## 许可证

Fun 采用 **双授权** 模式：

1. **开源许可证（MIT）** —— 见 [`LICENSE`](LICENSE)。允许自由使用、修改、分发源码，只要保留版权声明。
2. **商业授权**（额外条款，仅适用于下列闭源分发场景）：
   - 对内核做实质性修改并以闭源形式商业化分发 —— 见 [`LICENSE.custom`](LICENSE.custom)；
   - 将 `fun.dll` 嵌入闭源商业产品或 SaaS 后端 —— 见 [`LICENSE.dll`](LICENSE.dll)。

**简单说明**：内部使用、学习研究，以及以开源方式（MIT/GPL 等）发布修改版均免费。只有把修改过的内核或 `fun.dll` 当作闭源商业产品对外售卖时才需要付费授权。商业授权为一次性授权，按项目/公司计费，请联系 &lt;zwd@funlang.org&gt;。

---

© 2010-2026 张卫东 &lt;zwd@funlang.org&gt;
