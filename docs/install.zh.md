# 安装 Fun

预编译解释器发布在 [GitHub Releases](https://github.com/funlang/fun/releases)。
从源码构建见 [building.zh.md](building.zh.md)。

## 目录

- [发布包](#发布包)
- [macOS 与 Linux](#macos-与-linux)
- [Windows](#windows)
- [压缩包里有什么](#压缩包里有什么)
- [运行要求](#运行要求)

---

## 发布包

- Linux x64 / arm64：`.tar.gz`，含 `libtcc.so`、`fun-mt` 与标准 `lib/`；
- Linux LoongArch64：`.tar.gz`，**只在 nightly 预发布**中提供，因为 FPC 的
  loongarch64 后端仍在主线。完整构建带正则、`getapi`/FFI 与原生 asm 后端
  （`lib-asm-loongarch64`），但没有 `libtcc`（运行时 C），同时附带 `fun-mt`。
  稳定版不包含它；
- Linux riscv64：`.tar.gz`，**只在 nightly 预发布**中提供，因为 FPC 的
  riscv64 后端仍在主线。完整构建带正则、`getapi`/FFI、`-lnx` 后端与
  `lib-asm-riscv64`，但没有 `libtcc`（运行时 C），同时附带 `fun-mt`。
  稳定版不包含它；
- macOS x64 / arm64：`.zip`。两个包都含 `libtcc.dylib` 与 `fun-mt`。
  这些构建**未签名、未公证**；用包内 `install.sh --local`（curl 不会设置
  quarantine 属性），或解压后执行
  `xattr -dr com.apple.quarantine <目录>`；
- Windows x64：`.7z`。构建未签名，SmartScreen 可能提示；用 7-Zip 解压后
  双击 `install.cmd`（或运行
  `powershell -ExecutionPolicy Bypass -File install.ps1`）。包内包含
  `fun.exe`、`fun-safe.exe`、`fun-mt.exe`、安装脚本，以及 CI 构建的 x86-64
  运行库（`pcre3.dll`、`ffi.dll`、`libtcc.dll`、`zlib.dll`）；
  `capabilities.json` 记录该构建缺失的能力。

## macOS 与 Linux

一行安装（校验 `SHA256SUMS`，安装到 `~/.fun`）：

```bash
curl -fsSL https://raw.githubusercontent.com/funlang/fun/main/install.sh | sh
```

如果最新稳定版还没有二进制，安装器会说明并回退到最新 nightly；传 `--tag`
或 `--nightly` 可显式选择。默认把 `fun` 链接到 `~/.local/bin`；该目录不在
`PATH` 时，加 `--add-path` 向 `~/.profile`（zsh 为 `~/.zshrc`）追加带标记的
配置块，或用 `--bin-dir DIR` 放到已有 `PATH` 目录。

要离线安装已解压的包，在包根目录运行 `./install.sh --local`。`install.sh`
存在于每个 Unix 包（不只 macOS），并会创建 `funcmd` 与 `funcmd-safe`
兼容符号链接。

## Windows

Windows 安装（当前用户，无需管理员权限）：

1. 用 7-Zip 解压 `.7z`。
2. 双击解压目录里的 `install.cmd`。

`install.cmd` 会把目录复制到 `%LOCALAPPDATA%\Programs\Fun`，把
`%LOCALAPPDATA%\Programs\Fun\fun` 加入用户 `PATH`，为 `.fun`、`.foo`、`.fxx`
注册 `Fun Script` ProgID（双击即可运行），添加 Win+R 的 `fun` 入口，并在
**设置 > 应用**中提供卸载项。

常用选项：

- `-AllUsers`（提权，安装到 `Program Files`）
- `-Dir DIR`
- `-NoPath`
- `-NoAssoc`
- `-Portable`

在安装目录运行 `uninstall.cmd`，或用**设置 > 应用**卸载。Windows 可能保留
已有的按用户扩展名选择；用一次**打开方式 > 选择其他应用**选中 Fun。

## 压缩包里有什么

每个包都有一个 `fun/` 运行时树：`fun/fun`（Windows 为 `fun/fun.exe`）、
`fun/fun-safe`（能力受限构建），以及可用时的 `fun/fun-mt`，外加 `lib/`、
`demo/`、`demos/` 与 `test/` 里的回归套件。

运行 `./fun/fun --help`，或在 Linux/macOS 上运行
`./fun/test/run-linux-regression.sh`，Windows 上运行
`fun\test\run-windows-regression.bat --portable`。

两个安装器都打包在运行时树旁，是获得全局 `fun` 命令的受支持方式。

## 运行要求

- Linux 产物在 Ubuntu 24.04 上构建，需要 glibc 2.34 或更新版本。
- 启用 `getapi`/FFI 时，Linux 运行时还需要 `libffi.so.8`。
- nightly 是预发布，`releases/latest` 仍指向稳定版。
- `fun.dll` 是单独授权的产品，不包含在这些包里。

每个发布还带有 `capabilities.json` 与 `SHA256SUMS`；缺失的可选能力会列在
其中。
