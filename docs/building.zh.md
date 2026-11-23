# 构建 Fun

Fun 核心为 Pascal，源码入口为 `src/prj/fun/funcmd.dpr`。本指南覆盖原生构建、
交叉构建、可选依赖、安全构建与回归/CI；简要版见 README。

## 目录

- [工具链与构建脚本](#工具链与构建脚本)
- [原生构建](#原生构建)
- [平台能力矩阵](#平台能力矩阵)
- [交叉构建](#交叉构建)
- [第三方依赖](#第三方依赖)
- [安全构建](#安全构建)
- [回归测试与 CI](#回归测试与-ci)

---

## 工具链与构建脚本

Windows 端 `.bat` 脚本的工具链路径集中在一个文件里：
[`src/prj/fun/setenv.bat`](../src/prj/fun/setenv.bat)。只需修改一次，指向你
安装的 Delphi / Free Pascal；或在构建前预先设置 `FPC`、`DELPHI2006`、
`DELPHI2009` 环境变量——每个 `make-*.bat` 脚本都会调用它并读取这些路径。

每个脚本名为 `<工具链>-<目标>`；**构建机**指脚本运行所在的机器，交叉编译各行
与目标并不相同：

| 目标                   | 构建机       | 脚本                                     | 工具链             |
| ---------------------- | ------------ | ---------------------------------------- | ------------------ |
| Windows 32 位          | Windows      | `src/prj/fun/make-2006.bat` / `-2009.bat` | Delphi 2006 / 2009 |
| Windows 64 位          | Windows      | `make-win64.bat`                         | FPC 交叉           |
| Windows arm64（bring-up） | Linux x86_64 | `src/prj/fun/make-win-arm64.sh`         | FPC 3.3.1 交叉 + Zig |
| Windows CE / ARM       | Windows      | `make-wince.bat`                         | FPC 交叉           |
| Linux（i386）          | Windows      | `make-linux.bat`                         | FPC 2.4.0 交叉     |
| Linux / ARM            | Windows      | `make-arm-linux.bat`                     | FPC 交叉           |
| Linux x86_64（原生）   | Linux x86_64 | `src/prj/fun/make-linux-x86_64.sh`      | FPC（本机）+ gcc   |
| Linux aarch64（arm64） | Linux x86_64 | `src/prj/fun/make-linux-aarch64.sh`     | FPC 交叉 + Zig     |
| Linux LoongArch64（龙芯） | Linux x86_64 | `src/prj/fun/make-linux-loongarch64.sh` | FPC 主线交叉     |
| Linux riscv64          | Linux x86_64 | `src/prj/fun/make-linux-riscv64.sh`     | FPC 主线交叉     |
| macOS x86_64 / aarch64 | Linux x86_64 | `src/prj/fun/make-darwin.sh`            | FPC 交叉 + Zig     |
| macOS（原生）          | macOS        | `src/prj/fun/make-macos.sh`             | FPC（Homebrew）    |

以 `-DFunDll` 编译可生成嵌入运行时 `fun.dll`，导出 `Run` 接口。构建产物已由
`.gitignore` 覆盖，不纳入版本控制。

完整文法定义见 [`src/parse/bnf/fun.ebnf`](../src/parse/bnf/fun.ebnf)。

## 原生构建

常用原生构建命令：

```sh
# Linux x86_64（存在 PCRE/TCC 时一并编译）
cd src/prj/fun
./make-linux-x86_64.sh

# macOS（Homebrew FPC）
cd src/prj/fun
./make-macos.sh
```

```bat
REM Windows x64
cd src\prj\fun
make-win64.bat
```

Linux 脚本会同时在 `lib/` 与 `lib64/` 下探测 FPC 的 `libffi` 单元，因此在
Fedora/RHEL 风格的布局上 `getapi`/FFI 也会自动启用。

### Linux 兼容性地板

正式发布的 linux-x64 产物在 **manylinux2014**（CentOS 7，glibc 2.17）里构建，
linux-arm64 则在 **manylinux_2_28**（glibc 2.28）里构建，不再直接用 Ubuntu
24.04 runner。这样它们才能跑在麒麟 V10 / 统信 UOS 20 等国产系统上——这些系统
的 glibc 通常只有 2.28~2.31，低于 Ubuntu 24.04 构建继承的 2.34 地板（arm64
runner 是 2.39）。构建方式本身不变：

```sh
src/prj/fun/build-linux-legacy.sh   # 在旧容器内执行

# 或在普通主机上从仓库根目录执行：
docker run --rm -v "$PWD:/work" -w /work \
  quay.io/pypa/manylinux2014_x86_64 \
  ./src/prj/fun/build-linux-legacy.sh

# arm64 发布 stage：
docker run --rm -v "$PWD:/work" -w /work \
  -e FLOOR_MAX=2.28 quay.io/pypa/manylinux_2_28_aarch64 \
  ./src/prj/fun/build-linux-legacy.sh
```

脚本按 `FPC_ARCH`（默认 `uname -m`）安装容器原生 FPC，并补上
`utils-fpcmkcfg` 包与 `ppc*` 编译器链接，干净容器才能生成 `fpc.cfg`。

配套两点让产物自包含：

- 当 `src/3rd/pcre-8` 与 `src/3rd/libffi` 存在时（CI 会拉取），
  `make-linux-x86_64.sh` 会把 PCRE 与 libffi **静态链入**。产物不再把
  `libpcre.so.1` / `libffi.so.N` 记为 `DT_NEEDED`，目标机只需提供 C 运行库。
- `src/prj/fun/check-linux-floor.sh --max 2.17 funcmd libtcc.so` 会报告二进制
  需要的最高 `GLIBC_*` 符号版本，并在超过目标版本或出现意外共享库时失败。
  CI 每次构建 Linux 都会跑它（arm64 用 `--max 2.28`）；`--json` 会把实测
  地板与 `needed` 清单写入 `capabilities.json`，并展示在发布页。

CI 的 `linux-legacy` 与 `linux-arm64-legacy` 作业用容器构建的二进制跑同一套
回归，然后分别产出 `linux-x64`、`linux-arm64` 发布 stage；Ubuntu 构建保留为
`linux-x64-modern`、`linux-arm64-modern`。调试时可以给
`make-linux-x86_64.sh` 传 `FFI_SYSTEM=1` 回到旧的动态 libffi 行为。

## 平台能力矩阵

三个能力层（regex、FFI、运行时 C）加机器码层、面向不可信脚本的第二构建模式，
以及 opt-in 的 worker 构建：

| 平台          | regex | FFI | 运行时 C (tcc) | asm | safe 构建 | worker 构建 |
| ------------- | ----- | --- | -------------- | --- | --------- | ----------- |
| linux-arm64   | yes   | yes | yes            | yes | yes       | yes         |
| linux-loongarch64 | yes | yes | no           | yes | yes       | yes         |
| linux-riscv64 | yes   | yes | no             | yes | yes       | yes         |
| linux-x64     | yes   | yes | yes            | yes | yes       | yes         |
| macos-arm64   | yes   | yes | yes            | yes | yes       | yes         |
| macos-x64     | yes   | yes | yes            | yes | yes       | yes         |
| win-x64       | yes   | yes | yes            | yes | yes       | yes         |

`safe 构建` 指独立的 `fun-safe` 二进制（`-dFunSafe`，strict 档），与默认解释器
一起发布，默认构建的行为不受影响；`worker 构建` 是
[`worker-model.md`](../fun/lib/worker-model.md) 描述的 opt-in `fun-mt`
二进制。其余列均描述默认二进制。`运行时 C` 已在 macOS x64 与 arm64 上通过
`libtcc.dylib` 补齐；Apple Silicon 使用一个小补丁处理 Darwin ucontext 字段与
`MAP_JIT`。release notes 与每个包里的 `capabilities.json` 都由实测探针生成，
降级构建无法虚报能力。

Windows arm64 仍处于 bring-up（FPC 代码生成崩溃，无法发布）；Win32/Windows CE
构建属于遗留路径，均不在发布门槛内。当前状态见 [`ROADMAP.md`](../ROADMAP.md)。

### 老 Win32

32 位构建的实际兼容底线远低于官方支持列表：

- **Windows 95 OSR2（4.00.1111）**：语言核心、FFI（`MessageBoxA`）、
  `lib-asm` 手写机器码，以及完整 UI（`lib-ui` + IE3 WebBrowser 控件、
  HTML/CSS、`fun:data` 绑定、`fun:click`/`fun:key` 事件、COM 回调进 Fun）。
- **Windows NT 3.5（Build 807）**：加 `-DNoDialog` 后，核心、FFI、机器码与
  窗口创建可用；系统没有 IE 控件，内嵌 WebBrowser 无内容。
- **Windows NT 3.1**：系统没有 OLE 2.0（`oleaut32.dll`），无法启动。

这些是兼容性探针，不是发布门槛。实测文章与截图：
[Windows 95](https://funlang.org/art/fun-on-win95.htm)、
[Windows 95 UI](https://funlang.org/art/fun-win95-ui-bind.htm)、
[NT 3.5](https://funlang.org/art/fun-on-nt35.htm)。

## 交叉构建

macOS、Linux aarch64、龙芯与 riscv64 这几行需要先搭交叉工具链。它们都在
**Linux x86_64 构建机**上运行，产物是目标平台的原生二进制；Mach-O 与
aarch64 的汇编器/链接器来自 Zig 0.13 自带的 clang/lld，龙芯与 riscv64
则使用 GNU binutils（`binutils-loongarch64-linux-gnu`、
`binutils-riscv64-linux-gnu`）：

```sh
cd src/prj/fun
./bootstrap-darwin-cross.sh     # 一次性：FPC darwin 交叉工具链 + Zig（~/.fun/darwin-cross，约 2 GB）
CPU=all ./make-darwin.sh        # -> fun/funcmd-darwin-{x86_64,aarch64}
CPU=all FUN_THREADS=1 ./make-darwin.sh  # -> fun/funcmd-darwin-{x86_64,aarch64}-mt

./bootstrap-linux-aarch64.sh    # 一次性：aarch64-linux RTL，复用 darwin 工具链里的 ppcrossa64 + Zig
./make-linux-aarch64.sh         # -> fun/funcmd-linux-aarch64

# 龙芯目前只有预发布：FPC 尚无稳定的 loongarch64 目标。
./bootstrap-linux-loongarch64.sh  # 一次性：FPC 主线交叉编译器 + loongarch64 binutils
./prepare-linux-loongarch64-sysroot.sh  # 一次性：Alpine musl/FFI/PCRE sysroot
FULL=1 ./make-linux-loongarch64.sh      # -> fun/funcmd-linux-loongarch64-musl
FUN_THREADS=1 FULL=1 ./make-linux-loongarch64.sh  # -> ...-musl-mt

# riscv64 同样只有预发布：FPC 的后端仍在主线。
./bootstrap-linux-riscv64.sh  # 一次性：FPC 主线交叉编译器 + riscv64 binutils
./prepare-linux-riscv64-sysroot.sh  # 一次性：Alpine musl/FFI/PCRE sysroot
FULL=1 ./make-linux-riscv64.sh      # -> fun/funcmd-linux-riscv64-musl
FUN_THREADS=1 FULL=1 ./make-linux-riscv64.sh  # -> ...-musl-mt
```

- **构建机要求**：Linux x86_64、宿主 FPC 3.2.x、`make`、`curl` 或 `wget`、`tar`，约 2 GB 空闲磁盘。Zig 由 bootstrap 下载（钉在 0.13；0.14 在较旧的 glibc 上会 panic）。**不需要** macOS 真机、Apple SDK 或 `osxcross`——Zig 自带 libSystem stub。
- `bootstrap-linux-aarch64.sh` 复用 darwin 工具链的 `ppcrossa64` 与 Zig：FPC 编译器二进制与 CPU 绑定，但只要目标 OS 的单元齐备，就能编译该 OS。
- 龙芯路径需要 `binutils-loongarch64-linux-gnu` 2.42 或更新版本与 FPC 主线快照；它针对 Alpine musl sysroot 交叉构建，因此正则、FFI、`-lnx` 后端与 `lib-asm-loongarch64` 都可用（sysroot 随带 `libgcc_s`，提供 `__clear_cache`），仅 TinyCC 不可用。`.github/workflows/loongarch.yml` 在 main 推送时执行该构建，同时构建 `-mt` worker 二进制、在 qemu 下跑 `lib-worker-test`，并上传供 nightly 预发布使用的 stage。
- riscv64 路径需要 `binutils-riscv64-linux-gnu` 与 FPC 主线快照，同样针对 Alpine musl sysroot 交叉构建，因此正则、FFI、`-lnx` 后端与 `lib-asm-riscv64` 都可用（sysroot 随带 `libgcc_s`，提供 `__clear_cache`），仅 TinyCC 不可用。`.github/workflows/riscv64.yml` 在 main 推送时执行该构建，同时构建 `-mt` worker 二进制、在 qemu 下跑 `lib-worker-test`，并上传供 nightly 预发布使用的 stage；`fun/test/run-riscv64-qemu.sh` 在 `qemu-riscv64` 下运行同一套 Linux 测试。
- 可选特性照例降级：缺 PCRE → 无正则；缺 libffi 单元/stub → 无 `getapi`（win64 的 CI 两者都会备好：`pcre3.dll` 与 `ffi.dll`）。Linux aarch64 交叉产物是核心解释器（其 `-dRegex` 与 `-dLinuxFFI` 需要 libc / libffi，尚未交叉构建）；而原生 Linux arm64 构建（CI 即如此）两者都有。
- 移植细节见维护者本地的 `art/notes/macos-port.md`（`art/` 不随公开仓库发布）。

## 第三方依赖

为控制体积与许可，仓库**不携带**下列第三方源码/二进制。缺失时构建脚本会**降级并打印提示**，不会中断：

| 组件 | 放到哪里 | 从哪里获取 | 由谁构建 |
| ---- | -------- | ---------- | -------- |
| PCRE 8（8-bit） | `src/3rd/pcre-8/` | <https://www.pcre.org/>（8.x 源码，如 8.45） | Linux：`make-linux-x86_64.sh` 用 gcc 静态编译（`-dRegex`）；Windows(i386)：`src/regex/pcre/make.bat`（Borland bcc32 + make，可 `-Dpcresrc=<路径>`，产物即 `pcrd.pas` 里 `{$LINK}` 的对象）；win64：CI 用 MinGW-w64 gcc 编出 `pcre3.dll` 并动态链接（`-dRegex -dPCRE_WinDLL`） |
| Tiny C Compiler 0.9.27 | `src/3rd/tcc/` | savannah/nongnu 的 tinycc 发行包，或 repo.or.cz 的 `release_0_9_27` tag | `make-linux-x86_64.sh` 产出 `libtcc.so`；`build-win64-deps.sh` 产出 x86-64 的 `libtcc.dll`（win64）；`build-tcc-darwin.sh` 产出 `libtcc.dylib`（macOS x86_64 与 arm64，arm64 使用 `patches/tcc-darwin-arm64.patch`） |
| libffi（win64） | 放在 `funcmd.exe` 旁的 `ffi.dll` | MSYS2 的 `mingw-w64-x86_64-libffi`，或任意 x86_64 libffi 构建 | win64 CI 会装好它，从而让 `getapi` 可用（`-dWinFFI`）；Linux / macOS 用 FPC 自带的 libffi |
| zlib 1.2.11（win64） | `src/3rd/zlib-1.2.11/` | <https://zlib.net/fossils/> | `build-win64-deps.sh` 产出 x86-64 的 `zlib.dll`；Linux / macOS 用系统 zlib |

- 放好目录后，`cd src/prj/fun && ./make-linux-x86_64.sh` 会自动编译 PCRE 与 TCC。
- 也可以显式指定路径：`PCRE_SRC=/path/to/pcre TCC_SRC=/path/to/tcc ./make-linux-x86_64.sh`。
- 缺 PCRE → 构建不带正则（`-dRegex` 关闭）；缺 TCC → 无 `libtcc.so`，`lib-tcc` 不可用。两者都不影响核心解释器。
- 便捷下载脚本：`src/prj/fun/fetch-3rd-party.sh` 会把钉住的 PCRE 8.45 与 TCC 0.9.27 发行包下载并解包到 `src/3rd/`（CI 使用）。

## 安全构建

需要运行不受信任的脚本时，可以单独编译安全构建：

```sh
cd src/prj/fun && SAFE=strict ./make-linux-x86_64.sh   # 产出 funcmd-safe
fun/test/run-safe-regression.sh strict                  # 只跑安全能力测试

# Windows
cd src\prj\fun && set SAFE=strict && make-win64.bat      # 产出 funcmd-safe.exe
fun\test\run-safe-regression.bat strict
```

`funcmd-safe`（`-dFunSafe`）在编译期去掉本机代码（`getapi` / `@toCallback` /
COM）、任意地址读写、文件访问、以及从文件或 `inline` 加载代码这些路径。
档位在构建脚本选择：`SAFE=strict` 全禁，`SAFE=readonly` 放开文件读，
`SAFE=readwrite` 再放开文件写，`SAFE=custom SAFE_ALLOW=read,write,compile`
按需组合。默认的 `funcmd` 与完整回归不受影响。每个 release 都同时提供 strict
构建；CI 的 `linux-safe` job 分别验证 strict 与 readonly，Windows job 也会
构建并运行同一套 strict 能力测试。`linux-safe` job 只在手动触发
（`safe_only`）时运行，普通 push/PR 不会跑 safe 部分。

## 回归测试与 CI

构建完成后，在仓库根目录运行快照测试：

```sh
fun/test/run-linux-regression.sh     # Linux（或任意 POSIX 主机：自动识别）
fun/test/run-macos-regression.sh     # macOS 包装脚本；跳过仅 Linux 的用例
fun/test/run-windows-regression.bat  # Windows 对应脚本
```

runner 会识别宿主：`fun/test/regression-skip-<platform>.txt` 列出无法在该宿主上
运行的用例（`/proc` 或 `libc.so.6` 后端、尚未移植的 JIT……），
`fun/test/expected/<platform>/` 可存放覆盖共享 `fun/test/expected/` 的宿主专属快照。
`--update` 写入宿主自己的快照目录；macOS 细节与当前的跳过原因保存在维护者
本地的 `art/notes/macos-port.md`。

[`.github/workflows/regression.yml`](../.github/workflows/regression.yml) 在五个平台上
运行本套件——Linux / macOS / Windows 的 x64，加上 Linux 与 macOS 的 arm64。五个
都基于 Free Pascal 构建并作为门槛。win64 构建的正则来自 `pcre3.dll`：CI 用 runner 的
MinGW-w64 gcc 编出该 DLL（bcc32 的目标文件属于 32 位构建，MinGW 目标文件也无法链进
funcmd，因此 `pcrd.pas` 以 `-dPCRE_WinDLL` 方式导入 DLL）；`run-windows-regression.bat`
启动时仍会探测引擎，构建没有正则时把依赖正则的用例报成 SKIP，于是缺 PCRE 的工具链
只会降级而不是失败。

`linux-x64`、`linux-arm64`、`macos-x64`、`macos-arm64` 任务还会用
`FUN_THREADS=1` 构建 `funcmd-mt` 并运行聚焦的 `lib-worker-test`；Windows 任务
构建 `funcmd-mt.exe` 并运行同一测试。它们留在现有任务里而不是单独开
workflow：编译器和第三方缓存已经就绪，另起 runner 只会为约一秒的编译再付一次
checkout 与工具链安装时间。只有 MT 二进制使用独立缓存，没有 worker 的平台继续
复用原有的 `funcmd` 缓存。

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

Windows job 还会运行 `build-win64-deps.sh`（x86-64 `libtcc.dll` 与 `zlib.dll`），
用真实的 C 编译 / deflate 调用实测两者，以同一特性集构建 `funcmd-safe.exe`，
并运行 focused safe 测试；stage 步骤只复制探针通过的文件。

`windows-arm64` **还不是发布目标**。FPC 3.2.2 没有 win64/aarch64 目标，
而支持该目标的 FPC 3.3.1（主线）目前生成的二进制在真机 Windows ARM64 上会以
`0xC0000005` 崩溃（连它自己的编译器也一样）。用 `-O-`、`-O1`、`-O2` 编译一个
裸 `writeln('hello')` 都能复现，因此问题在 FPC 的 aarch64-win64 后端/RTL
（上游 #42048、#42091），不在 Fun。`.github/workflows/winarm64.yml` 只是手动
bring-up 工装：在 Linux 上经 Zig 的 clang 交叉构建，在 `windows-11-arm` 上跑
便携回归；它不发布任何产物，nightly 也不会包含 win-arm64。等 FPC 修好目标后，
`make-win-arm64.sh` 可以直接升级为正式构建。
