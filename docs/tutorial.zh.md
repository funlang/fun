# 任务式教程

这份教程是“上手路径”：从第一个脚本走到文件、包、HTTP、worker 与原生代码。
它不替代参考文档，而是与它们互补：

- [`man.htm`](https://funlang.org/man.htm) / [`man-cn.htm`](https://funlang.org/man-cn.htm) — 按章节组织的语言手册（语法、类型、类、正则、标准库）。
- [`docs/standard-library.zh.md`](standard-library.zh.md) — 模块地图与较大库的用法说明。
- [`README.zh.md`](../README.zh.md) — 项目概览、平台矩阵与安装说明。

每章末尾都有“继续深入”的指针，需要精确规则时直接跳到手册对应章节。

---

## 1. 运行第一个脚本

安装发布包（见 README），或使用源码构建，然后：

```text
fun hello.fun
```

`hello.fun`：

```fun
?. 'Hello, Fun!';
```

`?.` 打印一个值并换行。脚本自上而下执行，语句以 `;` 结束，`#` 开始注释。
文件后缀可以是 `.fun`、`.foo` 或 `.fxx`。

带计时或关键字包运行：

```text
fun -v hello.fun
fun -key:key_cn.ini hello.fun
```

## 2. 函数、值与返回值

函数写作 `fun ... end fun;`。最后赋给 `result` 的值就是返回值；`return`
立即返回。

```fun
fun max(a, b)
  if a > b then
    result = a;
  else
    result = b;
  end if;
end fun;

?. max(1, 9);
```

类型是动态的：数字、字符串、list、set、函数和对象可以放在同一个变量里。
缺省参数为 `nil`，调用时可以用命名参数：

```fun
fun greet(name, punct)
  if punct = nil then punct = '!'; end if;
  result = 'Hello, ' & name & punct;
end fun;

?. greet('Fun');
?. greet(punct: '?', name: 'world');
```

继续深入：手册第 2 章（变量）与第 3 章（函数）。

## 3. 控制流与错误

`if`/`else`、`case`、`for`、`while`、`loop`、`try` 都保持 Ada 风格的结构：

```fun
for i = 1 to 3 do
  ?. i;
end do;

try
  raise 'boom';
except
  ?. 'caught';
end try;
```

可恢复的失败用 `try`/`except`。`raise` 可以抛字符串或对象；失败后
`runtime.lastError()`（见标准库文档）给出消息、文件、行号和调用栈。

继续深入：手册第 1 章（控制流）。

## 4. 集合、JSON 与 FD

list 和 set 是原生类型。JSON 是交换格式；FD 是 Fun 的缩进式数据表示。

```fun
use 'lib-set.fun';

var nums = [1, 2, 3, 4, 5];
var doubled = nums | map(a -> a * 2);
?. doubled.@toJson();          # [2,4,6,8,10]

var total = 0;
for i = 0 to nums.@count() - 1 do
  total = total + nums[i];
end do;
?. total;                      # 15

var user = [name: 'Ada', tags: ['math', 'code']];
?. user.@toJson();
```

`@toJson()` 输出 JSON，`@toJson(fd: true)` 输出 FD；解析用
`text.getJson()` / `text.getJson(fd: true)`（或 `lib-json` / `lib-fd` 的辅助函数）。
`user['tags'][0]` 与 `user.name` 都可以访问；值可能合法地为 `nil` 时用
`@has(key)` 判断键是否存在。

继续深入：手册第 6 章（集合）与 README 的 FD 小节。

## 5. 闭包、管道与高阶代码

函数是值。`|` 把值送入函数，数据管道从左到右阅读：

```fun
var f = a -> a * 2;
var g = a -> a + 3;
?. g(f(1 + 2) + 3);            # 12
?. 1 + 2 | f + 3 | g;          # 12
```

`map`、`filter`、`find`、`compose` 等在 `lib-set.fun` 中。闭包捕获外层作用域：

```fun
fun counter()
  var i = 0;
  return fun(){
    i += 1;
    result = i;
  };
end fun;

var c = counter();
?. c();
?. c();
```

继续深入：手册第 5 章（函数式编程）。

## 6. 类

`class` 定义类型，类体在构造时执行；类里的 `fun` 是方法。

```fun
class Person(name)
  var name = name;

  fun hello()
    result = 'I am ' & name;
  end fun;
end class;

var p = Person('Ada');
?. p.hello();
```

继承、`this`/`base` 与运算符重载见手册第 4 章。自定义运算符就是字段，例如
`this['#'] = you -> ...`。

## 7. 文件、流与进程

整文件读写是内置能力：

```fun
save('out.txt', 'hello');
var text = 'out.txt'.load();
```

目录、遍历与原子写用 `fs.fun`；按字节读写用 `fs.open` 和 `io.fun` 的
reader/writer 契约：

```fun
use 'fs.fun';
use 'io.fun';

fs.mkdirAll('build/out');
fs.atomicWrite('build/out/config.json', data);

var f = fs.open('data.bin', 'r');
var head = f.read(16);
f.close();

var out = io.buffer();
io.writeString(out, 'done');
```

`process.run('git', ['status', '--short'], [timeout: 5000])` 不经过 shell
启动子进程，返回 `ok`、`exitCode`、`stdout`、`stderr`。管道与进程标准流遵循
同一套 Reader/Writer 契约；阻塞与字节规则见标准库文档。

继续深入：手册第 8 章（库）与 [`docs/standard-library.zh.md`](standard-library.zh.md)。

## 8. 模块、包与测试

`use 'name.fun'` 导入模块。项目用 `package.fun` 清单：

```text
fun package init myapp          # package.fun + src/main.fun
fun package init mylib --lib    # package.fun + src/lib.fun
```

声明依赖后，把钉住的版本装进共享缓存：

```text
fun package add hello github.com/acme/hello --version v1.0.0
fun package tidy
fun run
```

`fun pack` 把应用和依赖库打成单个可执行文件。测试是使用 `test.fun` 的
`*_test.fun` 文件：

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

继续深入：[`docs/tooling.zh.md`](tooling.zh.md)。

## 9. 一个小的 HTTP JSON 服务

`HttpServer` 是阻塞式单线程服务器；handler 收到 request 和 response 对象。

```fun
use 'http-server.fun';

fun hello(req, res)
  res.json([ok: true, path: req.path]);
end fun;

fun echo(req, res)
  res.json([got: req.json()]);
end fun;

var s = HttpServer(8080);
s.get('/api/hello', hello);
s.post('/api/echo', echo);
s.run();
```

运行后用 `curl http://127.0.0.1:8080/api/hello` 验证。中间件用 `s.Use(...)`
挂载；仓库里的 demo 覆盖 CORS、Bearer 鉴权、session 与 multipart 上传。要同时
跑定时任务，在服务器循环里驱动 `cron.tick()`，不要调用 `run()`。

继续深入：[`fun/demos`](../fun/demos) 以及
[`docs/standard-library.zh.md`](standard-library.zh.md) 的 HTTP/cron 小节。

## 10. Worker、cron 与后台任务

`cron` 在当前线程调度回调。worker 隔离是 opt-in 的：使用 `fun-mt`
二进制（默认 `fun` 会给出明确错误）。

```fun
use 'lib-worker.fun';

var w = WorkerFile('job.fun', 'sum', '[1,2,3]');
var total = w.join(-1);
if w.error() <> nil then raise w.error(); end if;
?. total;
```

worker 解析自己的模块，拥有独立 AST 与堆，因此不共享任何 Fun 对象。结果以
字符串跨线程；`Shared` 与 `Channel` 在进出时复制值。批量任务用
`WorkerPool(file, size)` 配合 `poolMap` / `poolRun`；`cancel()` 是协作式的。

继续深入：[`fun/lib/worker-model.md`](../fun/lib/worker-model.md)。

## 11. 原生能力：从 FFI 到机器码

Fun 不局限于自己的运行时。能力阶梯是：

| 层级 | 设施 |
| ---- | ---- |
| FFI | `dll.getapi(name, 'signature')` |
| 运行时 C | 通过内置 TCC 的 `ccompile(...)` |
| JIT | `NewJit(...)` 在 C 与汇编之间选择 |
| 机器码 | `Assembly(...).Load()` |

这些能力很强，也与宿主平台相关。先读 `lib-tcc` / `lib-jit` 的模块头再使用；
不要把原生调用放进不可信脚本：独立的 `fun-safe` 构建会移除整个层级。

继续深入：手册附录与 [`docs/building.zh.md`](building.zh.md)（能力矩阵与安全构建）。

## 12. 下一步

- 精确语法与语义：[中文手册](https://funlang.org/man-cn.htm) / [English manual](https://funlang.org/man.htm)。
- 逐模块 API 说明：[`docs/standard-library.zh.md`](standard-library.zh.md)。
- 构建、交叉构建与 CI：[`docs/building.zh.md`](building.zh.md)。
- 包、测试与 `fun pack`：[`docs/tooling.zh.md`](tooling.zh.md)。
- 运行真实程序：[`fun/demo`](../fun/demo)（语法）与
  [`fun/demos`](../fun/demos)（应用、HTTP demo、基准）。
