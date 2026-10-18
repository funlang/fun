# 发布流程

维护者发版检查清单。

[English](RELEASING.md) · **简体中文**（本文件）

## 1. 准备

- 确认 `main` 上的回归工作流全部通过。
- 把 `CHANGELOG.md` 和 `CHANGELOG.zh.md` 里 `Unreleased` 的条目移到新版本号下，写上日期。
- 重新生成版本号：`fun src/prj/fun/gen-version.fun [YYYYMMDD] ["release"]`。
- 将这三个文件提交为 `release: Fun X.Y.Z`。

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
