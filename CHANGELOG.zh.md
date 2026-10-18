# 更新日志

本项目采用 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/) 风格记录主要变更，并遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

**English**: [CHANGELOG.md](CHANGELOG.md) · **简体中文**（本文件）

## [未发布]

- 正则匹配不再每次调用都重新编译同一个模式。编译后的 PCRE 代码按
  “模式文本 + 选项”放进一个小型 LRU 缓存，并用引用计数保证惰性匹配对象
  存活期间其编译代码不会被回收；每个正则字面量还各自持有引用，热路径无需
  再查缓存。同一模式第二次使用时还会升级到 PCRE 的 JIT 引擎；升级是延迟的，
  所以一次性的 `toRegex()` 不必承担 JIT 编译开销。
  全局 `match`/`replace` 改为写入一块可增长缓冲区，不再每匹配一次就改写并
  搬移主题字符串，原来的 O(n^2) 替换循环变成单遍扫描。在自带的 Linux
  x86_64 构建上，对约 100 KB 文本做 200 次全局替换从约 7.3 秒降到约
  0.24 秒，重复字面量匹配提升约 1.4-1.5 倍，全局匹配提升约 3 倍。替换串
  不含 `$` 或 `\` 引用时不再逐次扫描替换串，字面量全局替换再快约 25-40%。

- 全局正则替换现在按原始主题计算 `$_` 等主题引用。旧的原地循环会在两次
  匹配之间改写主题，因此 `'abcabc'.replace(/b/g, '[$_]')` 会得到
  `a[abcabc]ca[a[abcabc]cabc]c`；现在得到 `a[abcabc]ca[abcabc]c`。

## [9.4.1] - 2026-10-17

- 修复相距很远的整数比较。`varComp` 以及 `<`、`>`、`<=`、`>=`、`<>`、`=`
  的 CalcOpt 快路径原先先算 `a - b` 再判断符号，差值溢出 int32 后结果会反转
  （例如 `2147483647 > -1` 返回假）。现在直接比较两个操作数。

## [9.4] - 2026-10-17

- 标量值在热路径上绕开 Variant RTL：比较与逻辑运算直接写 `varBoolean`，
  标量赋值对 Boolean/Double 也走快路径（不再只优化 Integer），
  `CCtwo` 不再为左操作数构造临时 `CValue`。整数 `div`/`mod` 增加带保护的
  快路径，除数为零和 `Low(Integer) div -1` 仍回退到 RTL。在自带基准上，
  `1>2` 从约 193 降到约 130 ns/次，`if 1>2` 从约 166 降到约 130 ns，
  `not 1>2` 从约 343 降到约 196 ns，`7 div 3` 大约减半。

- 标准库新增 HTTP 服务端与客户端。`fun/lib/http-server.fun` 是单线程、平台
  无关的服务端（`HttpServer(port)` 或 `HttpServer('addr:port')`），路由支持
  字面量段、`:name` 参数与 `*` 通配尾巴（方法不匹配回 405 并带 `Allow`，无匹配
  回 404），支持路由组与全局 / 组内 / 单路由中间件、参数与查询串、静态文件、
  `json` / `text` / `html` 响应以及访问日志，可由自身的 poll 循环（`run`）
  驱动，也可一次推进一步（`runOnce`）。`fun/lib/http-client.fun` 是一次调用的
  阻塞客户端，`HttpClient(args) -> [rc, code, message, headers, body]`，落在
  宿主平台的 lib-ajax 后端上，同一份调用在各平台通用。服务端的 HTTP 分帧与
  keep-alive 位于 `lib-winsock-base.fun`；暂时只在 Linux/macOS 可用：Windows
  的 winsock 后端还没有 RunOnce/Run（消息泵驱动是后续工作）。

- Windows 的 `lib-ajax.fun` 现在也提供与 Unix 后端一致的 `Http(args)`，
  于是 `HttpClient` 不再需要退回 `Ajax`：它强制同步传输，把最终响应头以
  `Ajax.headers`（键名小写，与 `lib-ajax-unx` 相同）暴露出来，并返回同样的
  `[rc, code, message, headers, body]`。加上此前 `HttpServer` ->
  `HttpServerBase` 的更名（再别名为 `Server.HTTP` / `Server.HTP`，顺带修掉
  重复赋给 `HTP` 的笔误），服务端/客户端这轮工作暴露的 Windows 缺口就补齐了。

- `getapi` 新增 `variadic: <n>` 标记，告诉 FFI 前多少个参数是固定的，libffi
  据此按变参调用准备（`ffi_prep_cif_var`，若所载 libffi 拒绝则退回固定形式）。
  Darwin arm64 需要它，因为那里的变参尾巴走栈；libcurl 绑定的
  `curl_easy_setopt` 用上了它，lib-ajax 的测试因此能在 macOS 上跑。

- `funcmd` 会指出找不到的文件：指定的脚本不存在时打印 `not found: <file>`
  （仍为非零退出），而不是一言不发地失败。

- Delphi 构建恢复可用。`pcrd` 动态分支（`-dPCRE_LINKDLL`）的移植层把 FPC 的
  `dynlibs` 单元无条件写进了 `uses`，于是 `dcc32` 停在
  `pcrd.pas(542) Fatal: F1026 File not found: 'dynlibs.dcu'`——哪怕静态构建根本
  走不到那段代码（Delphi 没有 `dynlibs` 这个单元，FPC 才有）。现在该单元只在
  `{$IFDEF FPC}` 下引入，非 FPC 一侧改用 Win32 调用（`HINST` 句柄、
  `GetProcAddress`、`SafeLoadLibrary`、`FreeLibrary`）保持同样行为，两个编译器
  都能继续使用 `-dPCRE_LINKDLL`。

- CI 五个平台全部绿标（Windows arm64 暂时禁用：FPC 3.2.2 没有 win64/aarch64
  目标）。修掉三处只在 Windows 显形的差异，都放在 `{$IfDef FPC}` 分支里，
  Delphi 源码保持原样。其一，`ToFunTime` 在所有非 Unix 构建上走
  `VarToDateTime`，而 FPC 的 `VarToDateTime` 经 `TryStrToDateTime`、依赖宿主的
  `ShortDateFormat`/`DateSeparator`，于是美式区域下 Fun 的 ISO 时间字面量
  （`@'2010-04-09 15:35:15'`）抛 `EVariantError`（"Invalid variant type
  cast"），在 parse 期就把 `calc.fun`、`type.fun`、`lib-type-test.fun` 拖垮；
  现在 FPC 构建直接解析 ISO 形式（与既有 Unix 构建一致）。其二，日期回显又跟着
  宿主区域走（`7/18/2010` 而非 Unix 的 `18-7-10`），故 `funcmd` 把
  `DefaultFormatSettings` 钉到 FPC 在 Unix 上的内置值（Unix 下不引 clocale 读不到
  区域），日期与数字输出因此与宿主无关。其三，`Print` 走 RTL 的 `Output` 文本
  文件，而 FPC 会把它标成 `GetConsoleOutputCP()`，于是每次 `?.` 输出都从字符串
  代码页（CP1252）重编码到控制台代码页（runner 上是 CP65001），每个非 ASCII
  字节都变成两个；标准输出现在改走新增的 `WriteOut`，Windows 上直接向 stdout
  句柄写原始字节（与 `WriteErr` 对 stderr 的做法一致），`set-named.fun` 因此
  重新对齐。

- Windows 回归 runner 现在先探测正则引擎：PCRE 缺席时（没有 `-dRegex` 时正则
  字面量解析为 nil 节点）把依赖正则的用例报成 SKIP，而不是去比一份注定不同的
  输出；等 Windows 上有了 PCRE 构建它们会自动恢复。需要 `.getapi` 的用例即便
  构建已带上该能力也仍跳过（构建未开 `-dWinAPI`，`winapi.pas` 的 getapi 是
  32 位 x86 汇编，其余几个是 x86-64 System V 或要求 Unix 库名），需要 COM 的
  用例（`lib-orm-rows`，经 `lib-xml`）同样加入跳过名单；
  `lib-file-test`/`lib-dyns-test` 也是（`find()` 在 Windows 上给 `\`、
  别处给 `/`，而共享快照用的是 `/`）。工作流的 `expected-win` 复制改为逐字节
  （`ReadAllBytes`）：旧写法走文本模式，会把 `set-named.fun` 快照里的原始 GBK
  字节重编码，导致永远对不上。

- win64 的 FPC 构建现在有正则了，走**动态链接**。bcc32 那套 PCRE 对象属于 32 位
  构建，MinGW 编出来的对象又链不进 funcmd（FPC 两条链接路径都解不掉它们的 CRT
  符号），所以构建用 runner 的 MinGW-w64 gcc 把 PCRE 8.45 编成 `pcre3.dll` 放在
  funcmd.exe 旁，再用 `-dPCRE_WinDLL` 把 `{$LINK}` 对象与 CRT 声明换成
  `external 'pcre3.dll'` 导入（FPC 仅凭 DLL 名就能生成导入表）。随之而来两处
  Pascal 侧修复：`__llmul` 桩只对 32 位成立（win64 乘法是原生的，也没有
  `System.__llmul`）；PCRE 的内存必须交回它自己的 free —— DLL 用的是它自己的
  CRT 堆，静态路径的 `FreeMem` 在匹配成功后就把堆搞坏了（`pcre_free_substring`
  即 `(PUBL(free))(p)`，free 路径改走它）。32 位 Delphi 构建、Unix 静态构建与
  MinGW 搜索顺序都未受影响。Windows runner 的正则探测现在能探到引擎，那 8 个正则
  用例与 `portability-probe` 由 SKIP 变为实跑：51/51 通过、41 跳过。

- win64 同样有了 `getapi`。FPC 自带的 `ffi` 单元本就有 WIN64 目标
  （`FFI_DEFAULT_ABI = FFI_WIN64`），唯一缺的只是库：job 用 runner 的 MSYS2 装
  libffi 并复制到 funcmd.exe 旁作为 `ffi.dll`，而 `-dWinFFI`（映射到既有的
  `UnixFFI` 符号，即引擎 `getapi`/`@toCallback` 注册所依赖的开关）选择走 libffi
  的 `lffi` 单元。`lffi.pas` 在 Windows 上跳过 Unix 的 `{$LINKLIB ffi}`（FPC 仅凭
  单元 external 里的 `ffi` 名就能生成导入表），裸库名解析不到时再补 `.dll`，于是
  `'kernel32'.getapi(...)` 可用。若 libffi 或 DLL 缺失，job 退回核心解释器而不是
  失败；新增的探针步骤把正则与 getapi 的可用性以 annotation 报出（Fun 里
  `getapi()` 的结果对象是 falsy，所以探针会真的调用一次解析出来的函数）。
  随之而来两个构建细节：单元路径必须作为**单个**参数传入——PowerShell 的原生参数
  传递会把裸的 `-Fu..\..\lib` 拆成路径加一个多余的 `lib` 源文件；`libase.pas`
  现在与 `host.pas` 一样映射 `-dWinFFI`，两个文件不会因编译顺序而对 `UnixFFI`
  产生分歧。`make-win64.bat` 也加上了同样的 `-Fu..\..\lib`，这样把 `ffi.dll`
  放到 funcmd.exe 旁后可以手工启用 `-dWinFFI`。32 位（Delphi/bcc32）构建与 Unix
  各路径均未改动。

- FFI 用例套在 win64 上也跑起来了，并立刻又抓出一处只在 Windows 显形的差异。五个用例
  里的四个（`ffi-int64`、`ffi-float`、`ffi-float-cb`、`ffi-callbacks`）是纯粹的
  int/double/float/long long/回调 ABI，输出与宿主无关，因此直接共用共享快照；job 用
  MinGW gcc 编出 C 辅助库（`-Wl,--export-all-symbols`，因为 libffitest.c 没有
  `__declspec(dllexport)`），`lib-host.fun` 的 `DyLibWin()` 按宿主给出库名，runner 同时
  探测该 DLL 与可用的 `getapi`，任一缺失就把这几个用例放进跳过名单。`ffi-scalar` 仍限
  Unix（libc/libm，Windows 上也没有 `getpid`）。差异本身：这些用例会加载
  `lib-host.fun`，它的 Windows 分支调用 `'kernel32'.getapi('GetCommandLine', ':s')`，
  而 kernel32 导出的名字是 `GetCommandLineA`/`GetCommandLineW`——不带后缀的写法只是头
  文件宏；`io.GetProc`（Delphi 路径）本来就会在失败后补 A/W 后缀重试，libffi 路径却
  没有。于是 Fun 代码里所有不带后缀的 Windows API 名在 win64 上都取不到；现在
  `lffi.pas` 也会先补 `name + 'A'` 再报错（对窄字符串约定而言也正是该用的变体，
  显式写 `nameW` 仍直接生效）。windows-x64 从 51/51（跳 41）变成 55/55（跳 37）。

- 加密测试支持 OpenSSL 3，以及剩余的 CI 平台修复。`lib-crypt-unx` 之前探测
  `EVP_PKEY_size`，而 OpenSSL 3.0 把它变成了指向 `EVP_PKEY_get_size` 的头文件
  宏、符号已不存在，于是整个探测在 OpenSSL 3 的 CI 镜像上失败，连带拖垮
  `lib-crypt-lnx` 和 `lib-e2e-lnx`；现在会回退到 `EVP_PKEY_get_size`。macOS arm64
  改用 Homebrew 的 3.2.2 bottle 装 FPC，而不用官方 dmg——它的 PackageMaker `.mpkg`
  会被新系统以“与当前 macOS 版本不兼容”拒绝（`pkgutil --expand` 也打不开）；
  Intel 仍用 dmg。Windows 构建改为直接调用 `ppcrossx64`（与 `make-win64.bat` 一致），
  因为那里的通用 `fpc.exe` driver 其实是 i386 的，会把 `-Twin64` 转给 `ppc386.exe`。
  `lib-asm-a64` 在 Linux arm64 上跳过：它的实时 JIT 调用会让解释器在那里崩溃
  （`Load()` 报成 `Open "<repo>/" failed` 的 EFAULT），而且其快照本就是 x86_64 专用的。

- Windows 上 `funcmd` 带脚本运行且 stdout 被重定向（到文件、管道、CI runner）时
  完全没有输出：GUI/命令行模式的判断用了 `AttachConsole`，没有父控制台时它返回
  false，于是即使给了脚本也被当成 GUI 启动，`isLog` 一直是 false。现在只要指定了
  脚本就强制命令行模式。Windows 的 CI 任务改为用“补回末尾换行”的快照副本做比较：
  Fun 在所有平台都写 CRLF，而 POSIX runner 用 `$(...)` 捕获会吃掉末尾换行，因此
  Windows 原始重定向比每个快照都多一个字节。

- CI 在所有平台都缓存 Free Pascal 工具链（此前只有 Linux 有）。Linux 命中时本就跳过
  安装；Windows 现在缓存 `C:\FPC`，命中时同样跳过两个安装包。macOS 缓存的是安装包而
  非安装结果：Intel 缓存 274 MB 的 dmg，arm64 缓存 Homebrew 下载，因此这两者不再重复
  下载（但安装仍需执行——它写入 `/usr/local`、`/opt/homebrew` 等系统路径，无法直接缓存）。

- 修复全新 checkout 下 CI 首次构建失败。原始 PCRE 压缩包只有
  `config.h.generic` / `pcre.h.generic` / `pcre_chartables.c.dist`（上游
  `./configure` 的产物与它们逐字节相同），且没有 dftables 生成的
  `pcre_default_tables.c`，导致 `make-linux-x86_64.sh` 与 `make-macos.sh`
  在 runner 上立刻中止。现在两者会用随包提供的副本生成构建所需的文件，并
  跳过可选的生成副本。另外从 `lib-loadcheck.sh` 的 FAIL 行中去掉仓库绝对
  路径，使其快照与主机无关。

- 可移植的回归测试框架与 macOS CI。`fun/test/run-linux-regression.sh` 现在会
  自动识别主机（linux / macos），读取 `fun/test/regression-skip-<platform>.txt`
  跳过清单，并支持 `fun/test/expected/<platform>/` 覆盖快照，因此那些“按设计仅
  Linux”的测试（libc.so.6 / `/proc` / x86-64 汇编 / TCC / JIT）在 macOS 上会记为
  SKIP 而不是失败；`ffi-*.fun` 则改为与主机无关（`LibC()`/`DyLib()`，`libffitest`
  在 macOS 上构建为 `.dylib`），因此在 macOS 上同样验证 getapi。新增
  `fun/test/run-macos-regression.sh`、
  `regression-skip-macos.txt`、macOS 原生构建脚本 `src/prj/fun/make-macos.sh`、
  第三方源码下载脚本 `src/prj/fun/fetch-3rd-party.sh`、
  `fun/test/ffi/build.sh`（按需构建 FFI 辅助库，该产物不入库），以及
  `.github/workflows/regression.yml`（6 个 job：Linux / macOS / Windows 各 x64 与
  arm64）。当时 Windows 尚属首次接入；现在所有平台都作为通过门槛（见最新的
  条目）。依据 Issue #2 的 macOS 真机报告修复：`find()` 现在按固定字节序输出目录项
  （ext4、APFS、NTFS 的枚举顺序不同，`lib-dyns-test` / `lib-file-test` 快照此前
  依赖主机）；`run-benchmarks.sh` 不再依赖 GNU `timeout`（原生 macOS 没有）；
  `lib-loadcheck.sh` 的模块 glob 改为字节序；`builtin-dispatch` 与 `lib-host-test`
  快照改为与主机无关；`lib-bounds-test` 中依赖分配失败的“超大下标抛异常”断言已
  移除（Linux 上抛 `EOutOfMemory`，macOS 上可能惰性成功；见 `safety-bounds.md`）。
  Linux 回归仍为 92/92。

- 解释器的 Linux aarch64 (arm64) 交叉构建，与 x86_64 版一并保留。
  `bootstrap-linux-aarch64.sh` 在 x86_64 主机上建出 aarch64-linux 的 FPC
  RTL/rtl-objpas/hash 单元（复用 darwin 工具链的 `ppcrossa64`），
  `make-linux-aarch64.sh` 产出 `fun/funcmd-linux-aarch64`（静态、基于系统调用、
  已 strip）。汇编与链接经 `src/prj/fun/linux-aarch64/{as,ld}`（Zig 的 clang/lld），
  因此不需要 aarch64 binutils 或 glibc。尚未启用：`-dRegex`（需 libc）与
  `getapi`/`-dLinuxFFI`（需 aarch64 的 libffi）。
- 解释器命令行：不接脚本文件运行时，现在会打印用法并以 0 退出。
  之前它会尝试把可执行文件自己当脚本跑，只会报一句来自 ELF/PE/Mach-O 头的
  `syntax error[ELF]` 并以 1 退出。点名但不存在的脚本仍是非零错误；
  “可执行旁边同名 `<exe>.fun`”的兼容运行仍保留。用法行在非 Windows 上不再显示
  `fun.exe`（改为 `fun`）。
- macOS 交叉编译产物缩小约 67%。FPC 的 Darwin 目标会向 ld64 传 `-dead_strip` 与
  剥除（`-x`，来自 `-Xs`），但 `darwin/ld` shim 原先把两者都丢掉，而 Apple 单独的
  `strip` 步骤在 Linux 上也跑不了——于是链出的 Mach-O 带着完整符号表
  （__LINKEDIT 约 1.4 MB、3.8 万个符号）。现在 shim 把它们转给 lld
  （`-Wl,-dead_strip`，剥除请求用 `-Wl,-s`），结果 `funcmd-darwin-x86_64`
  2.62 MB -> 858 KB、`funcmd-darwin-aarch64` 2.69 MB -> 939 KB，arm64 的
  ad-hoc 签名依然有效。
- macOS 的 Fun 层库适配（引擎 FFI + `-unx` 后端）。Darwin 上现在可用 `getapi`：
  把 `-dLinuxFFI` 泛化为单一的 `UnixFFI` 符号（macOS 构建传 `-dDarwinFFI`），
  `bootstrap-darwin-cross.sh` 为两个 darwin CPU 编译 FPC 自带的 `ffi` 单元，并从
  `DARWIN_SDK` 拷入 `libffi.tbd` 链接桩，于是 `make-darwin.sh` 会链到
  `/usr/lib/libffi.dylib`（已在两个 Mach-O 产物中确认）。Fun 层把**只差库名**
  的后端改成 `lib-*-unx.fun`（Linux + macOS），`lib-*-lnx.fun` 保留为 `use` 薄包装：
  os、cmdline、unicode、ado、ado-schema、xml、crypt、ajax、winsock、jsonrpc、orm-rpc。
  `lib-host.fun` 新增 `IsMac()`/`IsUnix()` 与库名助手 `LibC()`（`libc.so.6` vs
  `libSystem.B.dylib`）、`DyLib()`、`DyLibList()`。Darwin 专门修正：`.dylib`
  库名、`GetProcName` 改用 `proc_pidpath`、256 字节的 `struct utsname` 布局、
  Darwin 的 `sockaddr_in`（8 位 `sin_len`/`sin_family`）与套接字选项值、
  `__error`（而非 glibc 的 `__errno_location`）、`addrinfo` 的 `ai_addr` 偏移。
  `lib-zlib`、`lib-tcc` 补上 macOS 库名。仍为 Linux 专有：`lib-proc`（需
  sysctl/libproc）与 `lib-asm`（JIT/可执行内存；Apple Silicon 需 `MAP_JIT`）。
  本机无 macOS，运行时正确性未经验证；Linux 回归仍 91/91。
- macOS (Darwin) 交叉编译。新增 `src/prj/fun/bootstrap-darwin-cross.sh`（在 Linux 上
  搭出 FPC 3.2.2 的 x86_64-darwin / aarch64-darwin 交叉工具链）与
  `src/prj/fun/make-darwin.sh`（产出 `fun/funcmd-darwin-<cpu>`）。Mach-O 的汇编与
  链接经 `src/prj/fun/darwin/{clang,ld}` 两个 shim 转交 Zig 0.13 自带的 clang/lld，
  因此不需要 macOS SDK。引擎侧把只表示"非 Windows"的 `{$IfDef Linux}` 统一改为 FPC
  内建的 `UNIX`（Linux 行为不变，Darwin 也走同一分支），`'host'.arg()` 上报
  `os macos`，并让随仓库的 PCRE 外部声明在 Darwin 下加 `cdecl` 以生成 Mach-O 的
  前导下划线。该步只是"能编能链"的里程碑；Fun 层后端与 `getapi` 的 FFI 已在上面
  那条完成（见 `art/notes/macos-port.md`）。
- 手写汇编新增 AArch64 (ARM64) 后端。新增 `lib-asm-a64.fun` 及其指令表
  `asm-list-a64.fd`（仍走 `fun/lib/tools/make-asm-list.fun` 同一条构建链），
  输出定长、位域编码的 aarch64 指令：add/sub（立即数与移位寄存器）、逻辑
  （寄存器与立即数，含位掩码立即数编码器）、move wide、`mov` 别名、`csel`、
  装载/存储（无偏移、前后变址、寄存器偏移，以及 `stp`/`ldp` 成对）、分支与
  `ret`。本地标签与 `B`/`BL`/`B.cond` 偏移两遍解析；`mov` 立即数按汇编器
  的习惯选 movz/movn/orr/movk。该后端为显式启用（`Assembly = AssemblyA64();`），
  在非 aarch64 上拒绝运行。
- aarch64 指令缓存一致性：`lib-asm.fun` 在把代码拷入可执行内存后调用可选的
  `_asm_flush(ptr, len)` 钩子，`lib-asm-a64.fun` 把 libc 的 `__clear_cache`
  （回退 `cacheflush`、再回退 libgcc）绑到该钩子——不做刷新时 cpu 可能执行旧
  字节，且只在 aarch64 上发作。
- `lib-asm.fun` 增加两个后端共用的钩子：可覆写的 `ret_hex` 收尾（x86 `C3`、
  aarch64 `C0035FD6`）、下沉到基类的 `_ptr2hex`/`int2hex64`/`<name>` 回调地址
  解析，以及由 `Load()` 校验的每后端 `arch`。后端不会再静默执行异构机器码
  （此前 aarch64 会跑进 x86 字节导致 SIGILL）。
- `'host'.arg()` 在 AArch64 上正确上报 `cpu arch64`（`CPUARCH64` 分支此前拼错，
  落到了 `cpu64`）；aarch64 汇编器的 cpu 门禁即以该值为准。
- 测试：`fun/test/lib-asm-a64.fun` 对编码器做快照（其编码已与 keystone/gas
  汇编器逐字节比对），`fun/test/tools/asm-a64-diff.sh` 在装有
  `gcc-aarch64-linux-gnu` 时重跑该逐字节对拍。Linux 回归清单已加入该用例。

- 运行版本探测：版本号改到生成式 include `src/core/version.inc`（`funVersion`，数值
  YYYYMMDD；`funRelease`，人工维护的语言版本串），由 `fun.pas` 用 `{$I}` 引入。
  用纯 Fun 脚本重新生成：`fun src/prj/fun/gen-version.fun [YYYYMMDD] ["release"]`，
  不依赖 shell/git，Windows 与 Linux 同一条命令。不传日期就盖当天日期（发版时传显式日期保证可复现）。
  脚本可用两条路径探测当前解释器，且读的是同一个常量：`N.time()`（N 在 2010..2099 时返回
  `funVersion`）与 `'host'.arg()` 新增的 `version` 字段。此前该数字是 `_time` 里的硬编码
  字面量，`'host'.arg()` 也只有可读串 `fun`。回归 `lib-host-test.fun` 断言两条路径相等。
- 首次以开源形式发布 Fun 核心与标准库源码。
- 命令行 `funcmd` 现在把诊断信息写入 stderr，并在解析或运行时出错时返回非零退出码 (1)，
  使 `a.fun && b.fun`、CI 任务与 cron 告警不再把失败脚本当成成功。运行时错误前缀为
  `文件:行:`。函数调用栈（每帧一行 `  in 名称() (文件:行)`，由内向外，最多 10 帧）仅在
  定义了 `-dFunTraceback` 的构建中追加；默认构建只报出错命令，因此每次调用零开销。
  脚本正常输出（`?.`）仍走 stdout。内嵌 `fun.dll` 的 `Run` 返回码约定不变，`-gui`/非控制台
  运行与原先一样保持静默。诊断信息直接写操作系统标准错误句柄（不再用 RTL 的
  `StdErr`/`ErrOutput` 文本文件，Delphi 7 未声明这两个标识符），因此驱动在 Delphi 7
  与 Free Pascal 上都能原样编译。
- 把输入结尾视为隐式语句终结符：文件最后一条语句即使漏写结尾的 `;`，现在也会被解析并执行，
  不再被静默丢弃。此前词法层在输入结尾不产生任何 token，待归约的语句永远无法归约，脚本会以
  0 退出且没有任何输出（例如末行为 `?. x` 的程序什么都不打印）。改动只作用于输入结尾，
  语句之间漏写 `;` 仍然是语法错误。该逻辑位于词法运行时（`src/parse/lib/lexlib.pas`），
  不涉及任何生成的解析/词法表文件。
- 新增 `README.md`、`CONTRIBUTING.md`、`.gitignore`、`.gitattributes`。
- 加固字符串/列表下标与字节访问，杜绝越界内存访问：越界**写**改为抛异常，越界**读**返回安全
  默认值（`s[i]`、`.toByte`、`.fromByte`、`.toNum(ptr:)`、`.movs`、`.x`、`.toStr`、列表
  `@count`）。字符串赋值保持引用语义。
- 语言版本：9.0。
- 限制 JSON/FD 解析的嵌套深度。扫描本身是迭代的，但生成的树在释放、克隆与序列化时
  是递归的，因此攻击者提交数千层 `[`/`{` 的文档会使栈溢出导致进程崩溃（DoS）。现在
  嵌套超过 512 层会抛异常，而不再构建出无法使用的结构。
- 修复多行 `DObject.Get`：内嵌的 `Read` 会遮蔽 `args` 成员，取多于一行的结果时抛
  `@Fields not found`。取行循环改为读 `this.args`。
- 在 `libase.pas` 中新增控制台输入内建：`'line'.input([prompt])`、
  `'char'.input([prompt])`（终端上为原始模式的单键读取）与 `'all'.input([prompt])`。
  可选的第二个参数用于接收 `ok` 标志，表示本次是否读到内容；由于 Fun 中空串与 nil
  相等，存在空行时该标志是让读循环可靠结束的唯一方式。Linux 逐字节读取标准输入，
  三种模式都支持；Windows 上只按行读取（用 RTL 的 `ReadLn`），得到的文本直接是
  本构建的字符串编码（ANSI；Delphi 2009 为 Unicode），不会把多字节字符拆成字节。
- 为基本类型新增严格比较与类型号：`a.eq(b)` 仅在类型与值都相同时为真（`nil`/`0`/`''`/`false`
  互不相等，`'1' <> 1`，`1 <> 1.0`，字符串区分大小写），`a.type()` 返回可移植的逻辑类型号。
  编号对标 COM `VARENUM`（`VT_*`，即 Delphi `VType` 与 ADO `DataTypeEnum` 的底层表），并把运行时
  依赖平台的标签归一化：所有整型宽度 -> 3，所有浮点宽度 -> 5，所有字符串形态 -> 8。两者都位于
  `libase`，只作用于基本（非对象）值，宽松的 `=` 保持不变；`100+` 预留给 Fun 专有的对象类型。
- 为容器新增键探测：`s.@has(key)` 在列表或集合确实含有该键时为真，即使其值是 nil。
  `m[key]` 无法区分键不存在与值为 nil（两者都读作 nil），而 `key in m` 扫描的是值而非键，
  因此这是判断键是否存在的唯一方式。数字键（或全数字字符串，与 `m[key]` 的解析保持一致）
  指向列表槽位，其他键则是集合成员。它与 `@count`、`@each`、`@add` 等原生集合方法同在
  `libset`。
- 补齐标准库中一直漏列的内建方法说明：`lib-file` 的 `x.input(prompt, ok)`、`lib-type` 的
  `a.eq(b)` / `a.type()`（从本地手工增补的副本同步），以及 `lib-host` 的 `n.arg()` /
  `'host'.arg()` / `'defaultCodePage'.set(cp)`。仅注释改动，不影响行为。
- 修复 Free Pascal 下布尔与数字比较不对称的问题：variant 比较按操作数顺序做隐式转换，
  于是 `true = 1` 为假而 `1 = true` 为真（`<`/`>`、`<=`/`>=`、`<>` 同理）。`varComp` 现在
  把布尔与数字统一按数值类型比较，`true` 取 -1（`VARIANT_BOOL`，与 Delphi/COM `VarCmp` 一致），
  两种顺序结果一致。该分支仅在 FPC 下生效（`{$IfDef FPC}`）；Delphi 的 `VarCmp` 本就对称。
  由 fun/test/bool-num-cmp.fun 覆盖（本地套件：89/89）。
- `str.getJson(json: 2)` 现在真正校验 RFC 8259 的分隔符文法，而不只是「未闭合 /
  括号失衡 / 顶层残留」。用一个分隔符状态机取代原先的「冒号之后」标志：尾逗号
  （`{"a":1,}`）、首逗号 / 重复逗号（`[,1]`、`[1,,2]`）、缺逗号（`[1 2]`、
  `{"a":1 "b":2}`）、缺冒号 / 重复冒号（`{"a" 1}`、`{"a"::1}`）、`;`/`=` 分隔符、
  单引号 / 反引号串、`@` 日期、十六进制数（`0xff`）、`nil`、非字符串键
  （`{a:1}`、`{1:2}`、`{[1]:2}`）全部拒绝。收尾括号与打开的容器类型匹配
  （`[1,2}`、`{"a":1]`），顶层值完成后不容许任何残留（`{"a":1} 2`、
  `[1,2] "x"`），空串或纯空白报 `no JSON value`。裸标量现在是合法根
  （`20`、`"hi"`、`true`、`null`），旧的 strict 反而误拒。strict 字符串拒绝
  未转义控制字符并校验转义（`\uXXXX` 需 4 位十六进制；不强制 surrogate 配对）。
  数字有意保持宽松（`.5`、`03`、`1.` 仍接受，真实 JSON 里会出现；完全不含数字的
  记号，如单独的 `.` 或 `-`，则拒绝）；宽松模式 `json:true` 与 FD 解析逐字节不变。

## [9.0] - 2026

- 以数据为中心的脚本能力：内置 JSON 与 FD 数据格式、原生 list / set / tree 集合、内嵌 PCRE 正则。
- 解释器核心（值模型 / 对象系统 / 流程控制）、内建运行时库与 58 个标准库模块。
- 双形态构建：命令行 `funcmd` 与嵌入运行时 `fun.dll`。
- Delphi 2006/2009 与 Free Pascal 跨平台构建（Windows / Linux / ARM / WinCE）。
- 附带 IDE（`funide`）及示例应用（`notepad--`、`odbc-search`、基准测试）。
- 通过标准库支持运行时 C 编译（TCC）、JIT 与内联汇编。

> 注：本仓库在开源发布前已有长期的历史版本（可追溯到 2010 年）。由于历史提交未随源码迁移，此处的更新日志从开源首版开始记录。
