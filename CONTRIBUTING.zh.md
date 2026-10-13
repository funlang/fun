# 贡献指南

感谢你有兴趣为 **Fun** 贡献代码！请遵循以下约定，以保证协作顺畅。

**English**: [CONTRIBUTING.md](CONTRIBUTING.md) · **简体中文**（本文件）

## 分支与提交

- 本项目遵循「单一主干 `main`」的简单模型。修复与功能直接基于 `main` 提交。
- 提交信息使用简洁的祈使句，例如：
  - `Fix: parser handles empty array literal`
  - `Add: lib-yaml round-trip test`
  - `Docs: update build matrix`
- 尽量让每个提交只包含一个逻辑变更，便于回溯。

## 编码与换行

- 语言核心为 Pascal（Delphi / Free Pascal），源码文件使用 **CRLF** 换行（Windows 工具链）。
- 部分历史文件为 GBK 编码。**新增/修改的文件请尽量使用 UTF-8**，并保持既有文件的编码与换行方式，避免造成无意义的整文件 diff。
- 请勿提交构建产物（`.exe/.dll/.obj/.dcu/.ppu/.res/.dof/.cfg` 等），它们已被 `.gitignore` 忽略。

## 目录约定

| 路径          | 内容                                |
| ------------- | ----------------------------------- |
| `src/core/`   | 解释器核心（值模型、对象系统、流程控制） |
| `src/parse/`  | 词法/语法解析器（`bnf/fun.ebnf`）   |
| `src/lib/`    | 内建运行时库                        |
| `fun/lib/`    | 纯 Fun 编写的标准库                 |
| `fun/demo/`   | 语言语法演示                        |
| `fun/demos/`  | 完整应用与基准测试                  |

## 标准库规范

`fun/lib` 下的标准库模块：

- 文件头保留版权声明与 `SPDX-License-Identifier: MIT`。
- 以 `# lib-xxx` 标题块说明内建函数、参数与行为。
- 请在 `fun/demo/` 中添加对应的测试脚本验证改动。

## 构建

构建脚本位于 `src/prj/fun/`（Delphi 2006/2009 与 Free Pascal 2.4.0，支持 Windows/Linux/ARM/WinCE 交叉编译）；本机 x86_64 Linux 用 `src/prj/fun/make-linux-x86_64.sh`，macOS / Linux aarch64 交叉构建（同样在 x86_64 Linux 构建机上）见[构建 → 交叉构建](README.zh.md#交叉构建在-linux-x86_64-上构建-macos-与-linux-aarch64)。改动解析器后，请确保语法定义 `src/parse/bnf/fun.ebnf`、`yacc.y`、`lex.l` 同步更新。

> 仓库**不携带**第三方源码/二进制（PCRE、Tiny C Compiler、Windows 运行期 DLL）。构建前请按 README 的[构建 → 第三方依赖](README.zh.md#第三方依赖仓库未携带)一节下载并放到指定目录；缺失只会**降级**，不会中断构建。

## 提交 Pull Request

1. `git pull` 同步最新 `main`。
2. 创建功能分支，完成改动并补充测试。
3. 运行相关演示脚本确认行为符合预期。
4. 发起 Pull Request，描述改动内容与验证方式。

---

有问题或商业授权咨询，请联系 &lt;zwd@funlang.org&gt;。
