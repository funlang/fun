# 发布流程

维护者发版检查清单。

[English](RELEASING.md) · **简体中文**（本文件）

## 1. 准备

- 确认 `main` 上的回归工作流全部通过。
- 把 `CHANGELOG.md` 和 `CHANGELOG.zh.md` 里 `Unreleased` 的条目移到新版本号下，写上日期。
- 更新 `ROADMAP.md`：基线版本、回归/可加载数字，以及已完成条目的状态。把完成项移出
  NOW/NEXT，并翻转技术债台账里对应的行。
- 重新生成版本号：`fun src/prj/fun/gen-version.fun [YYYYMMDD] ["release"]`。
- 运行 `sh src/prj/fun/check-roadmap.sh`，有报错先修再打 tag。
- 将两个 changelog、版本戳和 `ROADMAP.md` 提交为 `release: Fun X.Y.Z`。

## 2. 打带摘要的注解 tag，不要打空 tag

发布页没有描述时，GitHub 会把 tag 的注解当作 release 正文显示。只写标题的 tag 或轻量 tag 会让发布页一片空白。

每个 release tag 都必须是**注解 tag**，格式如下：

```text
Fun X.Y.Z

<一句话概括本版主题>

Highlights since v<上一版>:

- <2-6 条面向用户的改动摘要，按主题合并>

Full list: CHANGELOG.md / CHANGELOG.zh.md.
```

把说明写到文件里再打 tag，保留空行和换行：

```bash
git tag -a -F /tmp/vX.Y.Z.txt vX.Y.Z
git push origin main
git push origin vX.Y.Z
```

- tag 必须打在 release 提交上，不要打在其后的提交。
- 单独推送 tag；`git push --tags` 会把无关或过期的 tag 一起推上去。
- 发布前检查：`git tag -n99 -l vX.Y.Z`。
- 修订版说明可以短，但要写清修了什么问题、用户能看到什么变化。

## 3. 发布

- 为已推送的 tag 创建 GitHub release。
- 描述留空（或粘贴同样的摘要），让页面显示 tag 注解。
- 打开发布页确认说明正常显示。

推送 tag 也会启动 `.github/workflows/release.yml`：校验 tag 与
`src/core/version.inc` 中的 `funRelease` 一致，找到该 commit 在 `main` 上
成功的 regression 运行，下载那次运行上传的各平台产物，并附加压缩包、
`SHA256SUMS`、`capabilities.json` 与 `SBOM.cdx.json`。tag 注解会作为发布说明
的开头。如果该 commit 还没有成功的 main 分支回归，任务会失败，而不是发布
未经测试的二进制。

## 4. 夜间预发布（自动）

`.github/workflows/release.yml` 每晚北京时间 04:37 运行。它是交付通道，不是
发版事件：

- 只有自上一个 nightly 以来 `src/`、`fun/lib`、`fun/test`、`fun/demos`、
  `fun/demo` 发生代码变更时才发布。纯文档/CI 改动不发；当天没有任何提交也
  不发。
- 日期取自 HEAD commit 时间戳的北京时间，不取 runner 墙钟，延迟跨午夜也不会
  错一天。
- 版本是当前最新稳定版的下一个 patch，例如
  `v9.5.5-nightly.20261104`。按 SemVer 它低于 `v9.5.5`。nightly 不修改
  `version.inc`、README、ROADMAP、CHANGELOG，也不产生任何提交。
- tag 用 `gh release create --target` 打在现有 HEAD 上。同一 commit 重跑会复用
  该 tag；同一天又有新提交则依次使用 `.2`、`.3`。
- nightly 一律是 GitHub **prerelease**，`releases/latest` 继续指向稳定版。
  仅保留最近 14 个 nightly。

手动运行：Actions -> **release** -> Run workflow。选择 `nightly` 并勾选
`force` 可以在没有新代码变更时发布当前 commit，也用于验证流水线。选择
`stable` 并填写 tag 可为已有稳定版补传资产。

每个产物都带 `capabilities.json`，记录 regex、getapi/FFI、运行时 C 编译与
safe 构建能力。缺失的可选依赖会明确写进清单和发布说明，不会把降级构建
标成完整版。

产物使用 `SHA256SUMS` 校验，并附 `SBOM.cdx.json`。目前尚未启用
Sigstore/cosign 签名，不要对外声称存在签名。

每个 Unix 压缩包内含 `install.sh`；Windows 压缩包内含 `install.cmd`、
`install.ps1`、`uninstall.cmd`、`uninstall.ps1`。打包 job 会在发布前
校验这些文件。`install.sh` 同时作为顶层 release 资产上传。Windows 的
PATH 与文件关联行为见 README。

### 监控

schedule 可能延迟数小时，甚至被平台直接丢弃且不产生失败事件。设置仓库
secret `HEARTBEAT_URL`（例如 healthchecks.io 的 ping URL）：成功运行（包括
正确地跳过发布）会 ping 它，失败运行会 ping `<url>/fail`。外部监控应在约
一个周期没有信号时报警。未配置该 secret 时，调度停止不会留下带外信号。

## 修补已发布的 tag

如果某个 tag 已经推上去但没有摘要：

```bash
git update-ref refs/tags-backup/vX.Y.Z vX.Y.Z
git tag -f -a -F /tmp/vX.Y.Z.txt vX.Y.Z vX.Y.Z^{commit}
git push origin vX.Y.Z --force
```

- 保持提交不变，只更新注解。
- 本地 `refs/tags-backup/*` 保留旧 tag 对象。
- 已经拉取过旧 tag 的人下次 fetch 时可能看到 "tag changed" 提示，代码不会变动。
