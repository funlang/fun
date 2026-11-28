# 包管理、测试与打包

本指南覆盖项目工具链：`package.fun`、`fun package`、`fun run`、`fun test`
与 `fun pack`。解释器构建见 [building.zh.md](building.zh.md)。

## 目录

- [包管理](#包管理)
- [测试](#测试)
- [打包](#打包)

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
    'fun': '9.5.7',
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
示例见 [`fun/demos/package-demo`](../fun/demos/package-demo)，带测试的纯库
示例见 [`fun/demos/test-demo`](../fun/demos/test-demo)。

最小项目：

```text
myapp/
├── package.fun
├── src/
│   ├── main.fun          # bin: 'src/main.fun'
│   └── lib.fun           # 共享库代码
└── tests/
    └── lib_test.fun
```

只有 `fun package tidy` 会写缓存；`fun run` 与 `fun test` 不会联网。版本可以
写分支或 commit，但为了可复现构建，建议钉住 tag。

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
- 在测试块内调用 `test.skip('reason')` 可跳过当前测试；reason 可省略，
  跳过数单独统计，不影响套件通过。不要用宽泛的 `try/except` 捕获它：
  测试仍记为跳过，但测试块剩余语句会继续执行。
- `test.todo('name', 'reason')` 登记一个不执行的占位测试；
  `test.todo('name', { ... }, 'reason')` 执行测试体，失败视为预期。
  预期失败的测试体通过时会打印 `todo passed: ... (remove todo)`。
  todo 单独计数，不影响套件通过。
- `bench('name', { ... })` 登记基准；`fun test -bench` 会在测试之后运行它们：
  每条先预热一次，再以倍增 N 校准（直到单轮累计 ≥1s），输出
  `bench: name  N  ns/op`。基准体抛错与测试失败同样按文件失败计；
  不带 `-bench` 时基准不会运行。
- `test.fun`、全局名 `test`/`assert`/`runTests`、别名 `as test`/`as assert`、
  依赖键 `test`/`assert` 为保留名；三方测试库请换别名导入。
- `dist/`、`.` 开头目录和 path 依赖目录不会参与发现。

## 打包

`fun pack` 从清单入口和依赖库生成单个可执行文件：

```text
fun pack -o dist/myapp        # 使用清单里的 bin 与默认输出名
fun pack src/main.fun -o app  # 指定入口与输出名
fun pack src/main.fun -a assets -o app  # 额外包含文件或目录
```

打包产物是自包含的：不需要 `~/.fun`、源码树或依赖目录。适合把工具交给没有
包缓存的机器。默认输出名来自清单。
