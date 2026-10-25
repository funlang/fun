# Fun 语言

> 一门轻量、可嵌入、**以数据为中心**的脚本语言，能力覆盖从 JSON/FD 数据处理一直到运行时编译 C 与直接编写机器码。

**English**: [README.md](README.md) · **简体中文**（本文件）

- 版本：**9.4**
- 官网：<https://funlang.org>
- 作者：张卫东 &lt;zwd@funlang.org>
- 授权：MIT（另有商业授权条款，见下文「许可证」）

> **版本 9.4**：这不是玩具或原型——一门经历了超过 15 年（2010 至今）持续演化与生产级验证的成熟语言，其前身可追溯至 Nuva（2006）与 TemplateScript（2005）。

---

## 目录

- [为什么是 Fun](#为什么是-fun)
- [核心特性](#核心特性)
- [快速开始](#快速开始)
- [包管理](#包管理)
- [测试](#测试)
- [体验 Fun 语言](#体验-fun-语言)
- [能力阶梯](#能力阶梯)
- [FD 数据格式](#fd-数据格式)
- [外部函数接口（FFI）](#外部函数接口ffi)
- [关键字别名](#关键字别名)
- [嵌入运行时 fun.dll](#嵌入运行时-fundll)
- [目录结构](#目录结构)
- [构建](#构建)
- [标准库](#标准库)
- [示例](#示例)
- [许可证](#许可证)

---

## 为什么是 Fun

一句话定位：**Fun 是一门从 JSON 一路写到机器码的脚本语言。**

- 用同一个运行时，覆盖从高层数据处理（JSON/FD）到底层系统编程（FFI、运行时 C、JIT、机器码）的全谱系；
- 自带 68 个用 Fun 自身编写的标准库模块，全栈能力打包进单个可嵌入的 `fun.dll`；
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
- **模块** —— `use 'file.fun'`（可 `as alias`）引入其它脚本；运行时跟踪模块状态与依赖。
- **正则作为值类型** —— 内嵌 PCRE 引擎，支持行内正则字面量（`/.../`）与匹配运算符（`=~`、`!~`）。
- **内置数据格式** —— JSON 与 **FD**，一种兼容 JSON、对人类与 AI 都友好的类 Markdown 格式（见[下文](#fd-数据格式)）。
- **运行时 C 与机器码** —— 内置 Tiny C 编译器、JIT 与内联汇编（见[能力阶梯](#能力阶梯)）。
- **紧凑的 FFI** —— 用简短的签名串调用 DLL/共享库函数（见 [FFI](#外部函数接口ffi)）。
- **关键字别名** —— 规范英文关键字 + 可插拔的别名包（中文、法文、自定义），运行时选择（见[下文](#关键字别名)）。
- **跨平台** —— Windows（32/64 位）、Linux、ARM 与 Windows CE。
- **双形态分发** —— 命令行 `fun.exe` 与嵌入运行时 `fun.dll`（导出简单的 `Run` 接口）。
- **自托管的标准库** —— 68 个用 Fun 自身编写的模块，覆盖 JSON/YAML/XML 到 ORM、异步、UI 与原生绑定。

---

## 快速开始

运行脚本：

```text
fun.exe <file.fun>            # 运行脚本（.fun / .foo / .fxx）
fun.exe -v <file.fun>         # 显示编译与运行耗时
fun.exe -log[:log.txt] -gui   # 输出到日志 / 以 GUI 模式运行
fun.exe -key:key_cn.ini       # 加载关键字别名包
```

Hello world（规范英文关键字）：

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
> fun.exe fun/demo/fun.fun
Hello, fun!
9
9
```

---

## 包管理

下文 `fun` 指命令行程序（Windows 上是 `fun.exe`）。一个项目就是一个带
`package.fun` 清单的目录，`fun package init` 生成清单和最小模板：

```text
fun package init myapp          # package.fun + src/main.fun
fun package init mylib --lib    # package.fun + src/lib.fun
```

```fun
fun package()
  result = [
    name: 'myapp',
    version: '0.1.0',
    bin: 'src/main.fun',
    lib: '',
    'fun': '9.4',
    dependencies: [
      'hello': [source: 'github.com/acme/hello', version: 'v1.0.0'],
      'local': [source: '../libs/local']
    ],
    // >>> generated - do not edit; run 'fun package tidy' to refresh
    resolved: []
    // <<< generated
  ];
end fun;
```

- `fun package add <name> <source> [--version <v>]` / `remove <name>` 只改
  `dependencies` 段；版本只接受精确的 tag、分支或 commit。
- `fun package tidy` 把声明的版本装进共享的 `~/.fun` 缓存（`FUN_HOME` 可
  覆盖），校验 git tree 哈希，并写回 `resolved` 段；path 依赖就地使用，
  只有 git 依赖需要 `git`。
- `fun run [args...]` 以清单目录为根运行 `bin`；在项目里 `fun <script>` 是
  同一个启动器的平铺模式，带依赖运行指定脚本。
- `fun pack` 把应用和依赖库打成单个可执行文件，产物运行时不依赖 `~/.fun`。

运行期只读校验：缺失或陈旧的依赖会提示 `run 'fun package tidy'`，不会联网
或改清单。`FUN_PACKAGE_READY=1` 可跳过项目模式（清单损坏时的逃生口）。可运行
示例见 [`fun/demos/package-demo`](fun/demos/package-demo)。

---

## 测试

测试文件名以 `_test.fun` 结尾，位置不限（推荐放在 `tests/`）。其他 `.fun`
是普通模块，测试之间可以复用 helper。测试文件导入 `test.fun` 并注册用例：

```fun
use 'test.fun';
use '../src/lib.fun';

test('adds', {
  assert.equal(add(1, 2), 3);
});
```

```text
fun test
```

`fun test` 会在项目根下查找并运行所有 `*_test.fun`，每个文件一个子进程，
逐文件打印 `PASS`/`FAIL`，任一测试失败时以非 0 退出。项目只需要
`package.fun`（不要求 `bin`）；清单里的依赖通过和 `fun run` 相同的项目
启动器生效。

- 断言：`assert.equal`、`not_equal`、`is_true`、`is_false`、`match`、`contains`、
  `greater`、`less`、`is_nil`、`not_nil`、`raises`、`fail`，每个都可带最后一个
  自定义消息参数。
- `test.fun`、全局名 `test`/`assert`/`runTests`、别名 `as test`/`as assert`、
  依赖键 `test`/`assert` 为保留名；三方测试库请换别名导入。
- `dist/`、`.` 开头目录和 path 依赖目录不会参与发现。

可运行示例见 [`fun/demos/test-demo`](fun/demos/test-demo)。

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

## 能力阶梯

Fun 的特殊之处在于，一段脚本在无需独立工具链的情况下能走多远：

| 层次       | 能力                              | 支撑                                             |
| ---------- | --------------------------------- | ------------------------------------------------ |
| 高层       | JSON / FD 数据，list / set / tree | 原生集合与解析器                                 |
| 原生调用   | `dll.getapi(name, 'signature')`   | 紧凑签名约定的 FFI                               |
| 运行时 C   | `ccompile(code, ...)`             | 内置 Tiny C 编译器（`libtcc.dll`/`.so`）          |
| JIT        | `NewJit(...)`                     | 在 C（TCC）与汇编之间分发                        |
| 机器码     | `Assembly(code, ...).Load()`      | 内联汇编、可执行内存分配                         |

例如，`lib-tcc` 加载 `libtcc.dll`（Linux 上为 `libtcc.so`）并暴露 `tcc_new`、`tcc_compile_string`、`tcc_get_symbol` 等，从而你可以从字符串编译 C 源码并立即调用所得到的符号。`lib-asm` 分配可执行内存、写入机器码并调用之；`lib-jit` 则根据源码形态自动选择路径（`#!c` → TCC，否则走汇编）。

一段脚本可以同时混合两者：`NewJit` 在运行时编译 C **和**内联汇编，并且两者都能通过 `@toCallback` 直接回调回 Fun 函数。下面的片段对 `1..n` 求和——一次走汇编、一次走编译出的 C，两次都把结果交给 Fun 回调（完整版本见 [`test-jit-cb.fun`](fun/demos/benchmarks/test-jit-cb.fun)）：

```fun
use 'lib-jit.fun';
fun cb(a, b)          # 由 JIT 编译出的代码回调的 Fun 函数
  result = a * 2^32 + b;
end fun;

# 汇编路径
var asm = `#!asm i:i
    mov ecx, dword ptr [esp+04]
    @sum1ton
    push eax
    push edx
    mov  eax, <test>
    call eax
`;
var jit = NewJit(asm, names: [test: cb.@toCallback(nil, 'ii:i', true)]);
?. jit.Run(100000);

# C 路径（用内置 TCC 在运行时编译）
var c = `#!C ii:i
  int sum(int n, int (*test)(int, int)) {
    long long s = 0;
    for (int i = 1; i <= n; i++) s += i;
    test((int)(s >> 32), (int)(s & 0xFFFFFFFF));
    return 1;
  }
`;
jit = NewJit(c);
?. jit.call(100000, cb.@toCallback(nil, 'ii:C', true));
```

> **平台说明**：上面的 `#!asm` 块是 32 位 x86（Windows）汇编（基于 `esp` 相对寻址、`ecx`）。`#!C` 路径可跨平台，但汇编片段与架构相关——在 Linux/ARM 上请改用 C 形式，或按目标 ABI 重写汇编。

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

---

## 外部函数接口（FFI）

Fun 通过**紧凑的签名串**约定暴露原生函数。标准库中的例子：

```fun
'kernel32'.getapi('VirtualAlloc', 'iiii:i');  // 4 个 int 参数 -> int
'tcc'.getapi('tcc_new', 'v:i');               // void 参数 -> int
```

签名依次编码每个参数类型，然后是 `:`，最后是返回类型（`i`=int、`s`=string、`v`=void、`d`=double 等）。同一机制驱动 COM（`lib-winole`）、Windows API（`lib-winapi`）与 C 运行时。

`getapi` 本身按平台提供：32 位 Windows 用 `winapi.pas`，Linux / macOS / win64 用 `lffi.pas`（后端是 FPC 自带的 libffi；win64 上它对应 `ffi.dll`）。

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
│   ├── lib/           # 标准库（纯 Fun 编写，68 个模块）
│   ├── demo/          # 语言语法演示
│   ├── demos/         # 完整应用与基准测试
│   └── key_*.ini      # 关键字别名包（CN / FR / PUA）
└── LICENSE*           # 授权文件
```

---

## 构建

Fun 核心为 Pascal，源码入口为 `src/prj/fun/funcmd.dpr`。

Windows 端 `.bat` 脚本的工具链路径集中在一个文件里：[`src/prj/fun/setenv.bat`](src/prj/fun/setenv.bat)。只需修改一次，指向你安装的 Delphi / Free Pascal；或在构建前预先设置 `FPC`、`DELPHI2006`、`DELPHI2009` 环境变量——每个 `make-*.bat` 脚本都会调用它并读取这些路径。

每个脚本名为 `<工具链>-<目标>`；**构建机**指脚本运行所在的机器，交叉编译各行与目标并不相同：

| 目标                   | 构建机       | 脚本                                     | 工具链             |
| ---------------------- | ------------ | ---------------------------------------- | ------------------ |
| Windows 32 位          | Windows      | `src/prj/fun/make-2006.bat` / `-2009.bat` | Delphi 2006 / 2009 |
| Windows 64 位          | Windows      | `make-win64.bat`                         | FPC 交叉           |
| Windows CE / ARM       | Windows      | `make-wince.bat`                         | FPC 交叉           |
| Linux（i386）          | Windows      | `make-linux.bat`                         | FPC 2.4.0 交叉     |
| Linux / ARM            | Windows      | `make-arm-linux.bat`                     | FPC 交叉           |
| Linux x86_64（原生）   | Linux x86_64 | `src/prj/fun/make-linux-x86_64.sh`      | FPC（本机）+ gcc   |
| Linux aarch64（arm64） | Linux x86_64 | `src/prj/fun/make-linux-aarch64.sh`     | FPC 交叉 + Zig     |
| macOS x86_64 / aarch64 | Linux x86_64 | `src/prj/fun/make-darwin.sh`            | FPC 交叉 + Zig     |
| macOS（原生）          | macOS        | `src/prj/fun/make-macos.sh`             | FPC（Homebrew）    |

以 `-DFunDll` 编译可生成嵌入运行时 `fun.dll`，导出 `Run` 接口。构建产物已由 `.gitignore` 覆盖，不纳入版本控制。

完整文法定义见 [`src/parse/bnf/fun.ebnf`](src/parse/bnf/fun.ebnf)。

### 交叉构建（在 Linux x86_64 上构建 macOS 与 Linux aarch64）

最后两行是仅有的、需要先搭交叉工具链的构建。二者都在 **Linux x86_64 构建机**
上运行，产物是目标平台的原生二进制，无需目标 SDK、也无需目标平台 binutils——
Mach-O 与 aarch64 的汇编器/链接器来自 Zig 0.13 自带的 clang/lld：

```sh
cd src/prj/fun
./bootstrap-darwin-cross.sh     # 一次性：FPC darwin 交叉工具链 + Zig（~/.fun/darwin-cross，约 2 GB）
CPU=all ./make-darwin.sh        # -> fun/funcmd-darwin-{x86_64,aarch64}

./bootstrap-linux-aarch64.sh    # 一次性：aarch64-linux RTL，复用 darwin 工具链里的 ppcrossa64 + Zig
./make-linux-aarch64.sh         # -> fun/funcmd-linux-aarch64
```

- **构建机要求**：Linux x86_64、宿主 FPC 3.2.x、`make`、`curl` 或 `wget`、`tar`，约 2 GB 空闲磁盘。Zig 由 bootstrap 下载（钉在 0.13；0.14 在较旧的 glibc 上会 panic）。**不需要** macOS 真机、Apple SDK 或 `osxcross`——Zig 自带 libSystem stub。
- `bootstrap-linux-aarch64.sh` 复用 darwin 工具链的 `ppcrossa64` 与 Zig：FPC 编译器二进制与 CPU 绑定，但只要目标 OS 的单元齐备，就能编译该 OS。
- 可选特性照例降级：缺 PCRE → 无正则；缺 libffi 单元/stub → 无 `getapi`（win64 的 CI 两者都会备好：`pcre3.dll` 与 `ffi.dll`）。Linux aarch64 产物是核心解释器（其 `-dRegex` 与 `-dLinuxFFI` 需要 libc / libffi，尚未交叉构建）。
- 移植细节见 [`art/notes/macos-port.md`](art/notes/macos-port.md)。

### 第三方依赖（仓库未携带）

为控制体积与许可，仓库**不携带**下列第三方源码/二进制。缺失时构建脚本会**降级并打印提示**，不会中断：

| 组件 | 放到哪里 | 从哪里获取 | 由谁构建 |
| ---- | -------- | ---------- | -------- |
| PCRE 8（8-bit） | `src/3rd/pcre-8/` | <https://www.pcre.org/>（8.x 源码，如 8.45） | Linux：`make-linux-x86_64.sh` 用 gcc 静态编译（`-dRegex`）；Windows(i386)：`src/regex/pcre/make.bat`（Borland bcc32 + make，可 `-Dpcresrc=<路径>`，产物即 `pcrd.pas` 里 `{$LINK}` 的对象）；win64：CI 用 MinGW-w64 gcc 编出 `pcre3.dll` 并动态链接（`-dRegex -dPCRE_WinDLL`） |
| Tiny C Compiler 0.9.27 | `src/3rd/tcc/` | savannah/nongnu 的 tinycc 发行包，或 repo.or.cz 的 `release_0_9_27` tag | `make-linux-x86_64.sh`，产出 `libtcc.so`（放在 `funcmd` 旁） |
| libffi（win64） | 放在 `funcmd.exe` 旁的 `ffi.dll` | MSYS2 的 `mingw-w64-x86_64-libffi`，或任意 x86_64 libffi 构建 | win64 CI 会装好它，从而让 `getapi` 可用（`-dWinFFI`）；Linux / macOS 用 FPC 自带的 libffi |
| Windows 运行期 DLL | `fun/libtcc.dll`、`fun/zlib.dll` | 官方发行包或自行构建 | 无需构建；运行时与 `fun.exe` 同目录，供 `ccompile` / `NewJit` 使用 |

- 放好目录后，`cd src/prj/fun && ./make-linux-x86_64.sh` 会自动编译 PCRE 与 TCC。
- 也可以显式指定路径：`PCRE_SRC=/path/to/pcre TCC_SRC=/path/to/tcc ./make-linux-x86_64.sh`。
- 缺 PCRE → 构建不带正则（`-dRegex` 关闭）；缺 TCC → 无 `libtcc.so`，`lib-tcc` 不可用。两者都不影响核心解释器。
- 便捷下载脚本：`src/prj/fun/fetch-3rd-party.sh` 会把钉住的 PCRE 8.45 与 TCC 0.9.27 发行包下载并解包到 `src/3rd/`（CI 使用）。

### 回归测试与 CI

构建完成后，在仓库根目录运行快照测试：

```sh
fun/test/run-linux-regression.sh     # Linux（或任意 POSIX 主机：自动识别）
fun/test/run-macos-regression.sh     # macOS 包装脚本；跳过仅 Linux 的用例
fun/test/run-windows-regression.bat  # Windows 对应脚本
```

runner 会识别宿主：`fun/test/regression-skip-<platform>.txt` 列出无法在该宿主上
运行的用例（`/proc` 或 `libc.so.6` 后端、尚未移植的 JIT……），
`fun/test/expected/<platform>/` 可存放覆盖共享 `fun/test/expected/` 的宿主专属快照。
`--update` 写入宿主自己的快照目录；macOS 细节与当前的跳过原因见
[`art/notes/macos-port.md`](art/notes/macos-port.md)。

[`.github/workflows/regression.yml`](.github/workflows/regression.yml) 在五个平台上
运行本套件——Linux / macOS / Windows 的 x64，加上 Linux 与 macOS 的 arm64。五个
都基于 Free Pascal 构建并作为门槛。win64 构建的正则来自 `pcre3.dll`：CI 用 runner 的
MinGW-w64 gcc 编出该 DLL（bcc32 的目标文件属于 32 位构建，MinGW 目标文件也无法链进
funcmd，因此 `pcrd.pas` 以 `-dPCRE_WinDLL` 方式导入 DLL）；`run-windows-regression.bat`
启动时仍会探测引擎，构建没有正则时把依赖正则的用例报成 SKIP，于是缺 PCRE 的工具链
只会降级而不是失败。

同一个 job 还会从 runner 的 MSYS2 装 libffi，当 `ffi.dll` 落在 `funcmd.exe` 旁时就以
`-dWinFFI` 构建 win64，这正是打开 `getapi` 的开关：FPC 自带的 `ffi` 单元本就有 WIN64
目标，Windows 上只差这个库。两个可选特性遵循同一条规则——DLL 或单元缺失时 job 退回
核心解释器而不是失败，另有一个探针步骤报告最终构建带上了哪些特性。

有了 `getapi`，Windows 的 job 还会用同一个 MinGW gcc 把 FFI 测试辅助库
（`fun/test/ffi/libffitest.c`）编成 `libffitest.dll`，并让四个与宿主无关的 FFI 用例
（`ffi-int64`、`ffi-float`、`ffi-float-cb`、`ffi-callbacks`）跑共享快照——于是 64 位整数、
float/混合参数与 `@toCallback` 闭包在 win64 上也有覆盖；`ffi-scalar` 仍限 Unix
（它直接调 `getpid`/libm）。`lib-host.fun` 的 `DyLibWin()` 按宿主取辅助库名，runner
会同时探测该 DLL 与可用的 `getapi`，任一缺失就把这几个用例放进跳过名单。

`windows-arm64` 已暂时禁用：所钉住的工具链 FPC 3.2.2 没有 win64/aarch64 目标，
没有可用的构建方式。

需要运行不受信任的脚本时，可以单独编译安全构建：

```sh
cd src/prj/fun && SAFE=strict ./make-linux-x86_64.sh   # 产出 funcmd-safe
fun/test/run-safe-regression.sh strict                  # 只跑安全能力测试
```

`funcmd-safe`（`-dFunSafe`）在编译期去掉本机代码（`getapi` / `@toCallback` /
COM）、任意地址读写、文件访问、以及从文件或 `inline` 加载代码这些路径。
档位在构建脚本选择：`SAFE=strict` 全禁，`SAFE=readonly` 放开文件读，
`SAFE=readwrite` 再放开文件写，`SAFE=custom SAFE_ALLOW=read,write,compile`
按需组合。默认的 `funcmd` 与完整回归不受影响，CI 里的 `linux-safe` job
分别验证 strict 与 readonly，且只在手动触发（`safe_only`）时运行，
普通 push/PR 不会跑 safe 部分。

---

## 标准库

标准库位于 [`fun/lib`](fun/lib)，以纯 Fun 编写（68 个模块）：

> 总代码量约 6,000 行逻辑代码（不含注释），平均每个模块约 100 行——68 个模块全部用 Fun 自身写成。

- **数据**：`lib-json`、`lib-yaml`、`lib-xml`、`lib-base64`、`lib-cstruct`、`lib-md5`、`lib-crypt`
- **工具**：`uuid`
- **集合 / 算法**：`lib-set`、`lib-tree`、`lib-stack`、`lib-dyns`、`lib-math`
- **文本**：`lib-string`、`lib-regex`、`lib-match`、`lib-unicode`
- **系统 / IO**：`lib-file`、`lib-os`、`lib-host`、`lib-path`、`lib-time`、`lib-cmdline`、`lib-proc`
- **网络**：`lib-winsock`、`lib-ajax`、`lib-jsonrpc`、`http-server`、`http-client`、`http-auth`、`http-bearer`、`http-cors`、`http-session`
- **数据库**：`lib-orm`、`lib-orm-pro`、`lib-orm-gen`、`lib-orm-rpc`、`lib-orm-cte`、`lib-ado`、`lib-ado-schema`
- **原生 / 底层**：`lib-winapi`、`lib-winole`、`lib-tcc`（C 编译）、`lib-jit`、`lib-asm`、`lib-asm-pro`
- **UI**：`lib-ui`、`lib-ui-base`、`lib-dialog`、`lib-trayicon`
- **并发 / 异步**：`lib-async`、`lib-jsasync`、`lib-bind`、`lib-message`
- **测试**：`test`（`fun test` 的注册与断言库）

> **平台拆分惯例**：Windows 实现保留原名，Unix 后端为 `<name>-unx.fun`（Linux + macOS），
> 旧的 `<name>-lnx.fun` 名字保留为它之上的薄包装；两者共用的逻辑放在
> `<name>-base.fun`（不计入上面的模块数）。只在 Linux 成立的后端（如读 `/proc` 的
> `lib-proc`）继续用 `<name>-lnx`。例如 `lib-os` / `lib-os-unx`（+ `lib-os-lnx`），
> 以及 `lib-unicode-base` + `lib-unicode` / `lib-unicode-unx`。
> 用 `use` 时也可以直接写中性名：会按平台探测变体（macOS `-darwin`→`-unx`，Linux `-lnx`→`-unx`，变体存在才替换）。

---

## 示例

- [`fun/demo`](fun/demo) —— 语法演示：函数、闭包、柯里化、类、对象、集合、正则与异常处理。
- [`fun/demos`](fun/demos) —— 完整应用与基准测试：记事本 `notepad--`、`odbc-search`，以及性能 / 汇编 / JIT 基准。
- [`fun/demos/package-demo`](fun/demos/package-demo) —— 带路径依赖的小项目：`tidy`、`run`（项目/平铺）与 `pack`。
- [`fun/demos/test-demo`](fun/demos/test-demo) —— 只有库的包及测试：共享 helper、通过用例与失败断言示例。
- [`fun/demos/http-cors-demo`](fun/demos/http-cors-demo) —— CORS 预检、credentials、暴露响应头与浏览器页面示例。
- [`fun/demos/http-bearer-demo`](fun/demos/http-bearer-demo) —— Bearer token 认证、401 挑战与同源页面示例。
- [`fun/demos/http-session-demo`](fun/demos/http-session-demo) —— cookie session 登录/登出、SID 轮换与服务端状态示例。

---

## 许可证

Fun 采用 **双授权** 模式：

1. **开源许可证（MIT）** —— 见 [`LICENSE`](LICENSE)。允许自由使用、修改、分发源码，只要保留版权声明。
2. **商业授权**（额外条款，仅适用于下列闭源分发场景）：
   - 对内核做实质性修改并以闭源形式商业化分发 —— 见 [`LICENSE.custom`](LICENSE.custom)；
   - 将 `fun.dll` 嵌入闭源商业产品或 SaaS 后端 —— 见 [`LICENSE.dll`](LICENSE.dll)。

**简单说明**：内部使用、学习研究，以及以开源方式（MIT/GPL 等）发布修改版均免费。只有把修改过的内核或 `fun.dll` 当作闭源商业产品对外售卖时才需要付费授权。商业授权为一次性授权，按项目/公司计费，请联系 &lt;zwd@funlang.org&gt;。

---

© 2010-2026 张卫东 &lt;zwd@funlang.org>
