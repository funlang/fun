# 标准库指南

标准库位于 [`fun/lib`](../fun/lib)，以纯 Fun 编写：约 90 个公开模块。
目录内共 135 个 `.fun` 文件（含平台变体与内部辅助模块）；其中 6 个需要
Windows、raw socket 或仅 macOS 的后端。

本文件是 README 中标准库概要的详细版，包含模块地图、较大的运行时库，以及
容易踩坑的边界行为。语法与语言语义见[手册](https://funlang.org/man-cn.htm)，
上手路径见[教程](tutorial.zh.md)。

## 目录

- [模块地图](#模块地图)
- [Worker 与 `fun-mt` 构建](#worker-与-fun-mt-构建)
- [日志](#日志)
- [运行时诊断](#运行时诊断)
- [Cron 调度](#cron-调度)
- [HTTP 辅助](#http-辅助)
- [环境变量](#环境变量)
- [命令行程序](#命令行程序)
- [文件系统](#文件系统)
- [字节流与进程标准流](#字节流与进程标准流)
- [管道](#管道)
- [子进程](#子进程)
- [TOML](#toml)
- [CSV](#csv)
- [JSON Schema](#json-schema)
- [平台拆分惯例](#平台拆分惯例)

---

## 模块地图

- **数据**：`lib-json`、`lib-fd`、`csv`、`toml`、`jsonschema`、`lib-yaml`、`lib-xml`、`lib-base64`、`lib-cstruct`、`lib-md5`、`lib-crypt`、`lib-hmac`、`lib-url`
- **工具**：`uuid`、`lib-utils`、`lib-param`
- **集合 / 算法**：`lib-set`、`lib-tree`、`lib-stack`、`lib-dyns`、`lib-math`、`lib-bnf`
- **文本**：`lib-string`、`lib-regex`、`lib-match`、`lib-unicode`
- **系统 / IO**：`lib-file`、`lib-os`、`lib-host`、`lib-path`、`lib-stream`、`lib-input`、`lib-zlib`、`lib-sse-compress`、`env`、`cli`、`fs`、`io`、`process`、`logging`、`runtime`、`cron`、`lib-time`、`lib-cmdline`、`lib-proc`
- **网络**：`lib-winsock`、`lib-netif`、`lib-icmp`、`lib-ajax`、`lib-jsonrpc`、`http-server`、`http-client`、`http-auth`、`http-bearer`、`http-cors`、`http-multipart`、`http-session`、`jwt`
- **数据库**：`lib-orm`、`lib-orm-pro`、`lib-orm-gen`、`lib-orm-rpc`、`lib-orm-cte`、`lib-ado`、`lib-ado-schema`
- **原生 / 底层**：`lib-winapi`、`lib-winole`、`lib-registry`、`lib-tcc`（C 编译）、`lib-jit`、`lib-asm`、`lib-asm-pro`、`lib-eval`
- **UI**：`lib-ui`、`lib-ui-base`、`lib-dialog`、`lib-trayicon`
- **并发 / 异步**：`lib-async`、`lib-jsasync`、`lib-bind`、`lib-message`、`lib-worker`
- **沙箱**：`lib-jsbox`
- **测试**：`test`（`fun test` 的注册与断言库）

## Worker 与 `fun-mt` 构建

`lib-worker` 需要 opt-in 的 `funcmd-mt` 构建。5 个稳定平台发布包把它作为
`fun/fun-mt` 附带；LoongArch64/riscv64 的 nightly 预发布 stage 也包含它。
从源码构建使用 `src/prj/fun/make-linux-x86_64-mt.sh`、
`FUN_THREADS=1 make-macos.sh` 或 `make-win64-mt.bat`；预发布 Linux 目标传
`FUN_THREADS=1 FULL=1` 给对应的 `make-linux-*.sh`。默认 `funcmd` 保持
单线程堆与性能，首次使用 worker 时会给出明确错误。

worker 解析自己的模块并拥有独立的 AST 与堆，因此线程之间不共享任何 Fun
对象。结果以字符串返回；`Shared` 与 `Channel` 在进出时复制值：

```fun
use 'lib-worker.fun';
var w = WorkerFile('job.fun', 'sum', (new [1000]).@toJson(fd: true));
var total = w.join(-1);
if w.error() <> nil then raise w.error(); end if;

Shared('counter').add('done', 1);          // 进程范围、按名字共享的存储
Channel('log').send('job finished');       // 按名字共享的 FIFO
```

主线程完成回调用 `onDone` + `workerTick()`；另有常驻池
`WorkerPool(file, size)` 与协作式 `cancel()`。隔离模型、惯用法与限制见
[`worker-model.md`](../fun/lib/worker-model.md)。

## 日志

日志在入口配置一次，之后通过命名 logger 使用：

```fun
use 'logging.fun';

logging.config([level: 'debug']);   // 按名字： [levels: ['http': 'debug']]
var logger = logging.getLogger('http');
logger.info('request', [path: '/users']);
```

默认是 stderr + info + 文本格式，文本行包含调用点 source；`logging.config`
可替换 handler/formatter，`newLogger` 用于测试或独立 sink，formatter 的
`sourcePath` 选择 short/full/base 路径。

## 运行时诊断

运行时错误会带上失败语句位置和调用点 traceback。脚本也可以直接读取这些信息：

```fun
use 'runtime.fun';

var s = runtime.source();   // [file, path, line, function, className]
var st = runtime.stack();   // 由内到外的调用帧
runtime.root('/app');       // short path 的根，默认是启动时 cwd

try
  risky();
except
  var e = runtime.lastError(); // message、file、path、line、function、stack
end try;
```

## Cron 调度

`cron` 在同一套单线程阻塞模型上提供 cron 表达式与固定间隔：

```fun
use 'cron.fun';
var s = CronScheduler([onError: (job, err) {
  logger.error('cron job failed', [job: job['id'], error: err]);
}]);
var daily = s.addJob('0 3 * * *', cleanup);          // 5 字段 Vixie/POSIX
var every30s = s.addJob('0-30 * * * * *', cleanup, [withSeconds: true]);
s.every('1s', refresh);
s.removeJob(daily);
s.run();                                             // 或在循环里调用 s.tick()
```

- 每个 daemon 一个调度器；id 从 1 开始且不复用。`addJob` 支持范围、列表、
  步长与 `@hourly`/`@daily`；Quartz/AWS 的 `?`、`L`、`W`、`#` 和年字段
  直接拒绝。
- `run()` 睡到最近任务（单次上限 1s），错过的周期只补一次。到期用本地墙钟，
  间隔用单调时钟；暂不提供时区/DST 控制。
- 要和 `HttpServer` 或其它 poll 循环共用线程，用 `tick()` 和
  `nextWaitMs(maxMs)` 驱动单次 pass。回调同步执行，慢 handler 会拖住循环；
  `run()` 活跃时拒绝 `tick()`。
- 回调失败默认静默，除非传入 `onError`。

## HTTP 辅助

上传表单直接从请求读取；客户端上传用 `HttpMultipartWriter` 生成同样的 body：

```fun
var m = req.multipart();
var name = m.fields['name'][0];
var file = m.files['avatar'][0];
```

cookie 可以签名，JWT 复用同一套鉴权工具：

```fun
res.signedCookie('uid', 'u1', secret, [path: '/', httpOnly: true]);
var r = req.signedCookie('uid', secret);

use 'jwt.fun';
var token = jwt.sign([sub: 'u1', exp: jwt.now() + 3600], secret);
var v = jwt.verify(token, secret, [issuer: 'app']);
```

## 环境变量

环境变量也可以直接读取，不需要自己写平台 FFI：

```fun
use 'env.fun';
var home = env.get('HOME');
var port = env.get('PORT', '8080');
```

## 命令行程序

`cli` 是一个小型命令框架。根命令持有全局 flag 与子命令，子命令同样用
`cli.command` 创建；help、version、别名、env 回退、required、钩子和退出码都已内置。

```fun
use 'cli.fun';

fun hello(ctx)
  var times = ctx.int('times');
  for i = 1 to times do
    ?. 'hello ' & ctx.string('name');
  end do;
end fun;

fun serve(ctx)
  ?. 'serving on port ' & ctx.int('port');
end fun;

var root = cli.command('demo', [
  usage: 'demo command-line tool',
  version: '1.0.0'
]);
root.flag(cli.string('name', [aliases: ['n'], value: 'world', usage: 'who to greet']));
root.flag(cli.int('times', [aliases: ['t'], value: 1, usage: 'repeat count']));
root.action(hello);
root.command(cli.command('serve', [
  usage: 'start the server',
  flags: [cli.int('port', [aliases: ['p'], value: 8080, usage: 'listen port'])],
  action: serve
]));

var code = root.run();          // nil：读取进程参数
if code <> 0 then cli.quit(code); end if;
```

```text
$ demo --name bob -t 2
hello bob
hello bob
$ demo serve -p 9000
serving on port 9000
$ demo --help
$ demo --version
```

`cli.command(name, opts)` 支持 `usage`（父命令列表中的一句话说明；自身没有
`description` 时也显示在自身 help 中）、`usageText`（替换自动生成的 usage 行）、
`argsUsage`、`version`、`description`、`aliases`、`flags`、`commands`、`action`、
`before`、`after`、`hidden`、`out`、`err`、`input`。

flag 由 `cli.string`、`cli.bool`、`cli.int`、`cli.float`、`cli.strings` 创建；
选项有 `aliases`、`value`（默认值）、`usage`、`env`（单个名字或名字列表）、
`required`、`hidden`、`placeholder`。`strings` 可以重复出现；默认列表只在
flag 未出现时使用，第一次显式赋值会替换默认值。help 会显示默认值和 env 名称。
`required` 只接受命令行或 env，默认值不算满足；空的 `--flag=` 也算已提供（非空
校验请放在 action 里）。flag 与命令名区分大小写，`-V` 和 `-v` 是两个不同的 flag。
`hidden` 的 flag/命令仍可解析，但不显示在 help 中。重复的 flag/命令名或别名在
构造时直接报错。

长短选项可混用：`--name=value`、`--name value`、`-n value`、`-n=value`、
`-ab` 这类两个 bool 的组合，以及用 `--` 终止选项解析。bool 接受
`true/false`、`1/0`、`yes/no`、`on/off`；bool flag 不吞下一个 token，请用
`--flag=false`。int 为十进制整数；float 支持小数和指数。非 bool 选项的下一个
token 作为值；如果值以 `-` 开头，请用紧贴形式
`--name=-x`/`-n=-x`（`--times -1` 这类负 int/float 仍可直接写）。全局 flag 要放在
子命令前，子命令后的 token 由子命令解析。命令有子命令时，第一个位置参数会被当作
命令名；根 action 需要位置参数时请用 `--`。

action 收到 context：`ctx.string/bool/int/float/strings(name)`、`ctx.has(name)`
（只有命令行或 env 显式设置才为 true）、`ctx.args()`、`ctx.arg(n)`、`ctx.narg()`、
`ctx.command()`，以及配置好的流 `ctx.out()`/`ctx.err()`/`ctx.stdin()`。带类型的
访问器会校验声明的 flag：未知名字或类型不匹配会报错，而不是静默返回零值；子命令仍可
访问父命令继承下来的 flag。访问器使用 flag 的规范名而不是别名。env 值按 flag
类型转换，`strings` 按逗号分隔；`env` 列表中先存在的名字生效。

help/version 自动提供：`--help`/`-h`、`help [command...]`；命令设置 `version` 后
还有 `-v`/`--version`。根命令和有子命令的命令提供 `help` 命令，叶子命令仍可把
`help` 当普通位置参数。`help`/`h` 是保留 flag 名；有版本的命令上 `version`/`v`
也是保留名，注册冲突 flag 会直接报错。子命令 help 只列自己的选项；全局选项在
父/根命令的 help 中。

钩子无需进程级初始化：`before(ctx)` 返回 nil/true/0 继续，返回 false 以退出码 1
停止，返回非零整数则以该码停止。父命令的 `before` 在子命令 action 前执行，
`after` 在子命令 action 后执行（action 抛异常也执行）；help/version/解析错误不会
触发父命令钩子。`after(ctx)` 在自己的 action 返回或抛异常后执行，前提是 `before`
已成功；`after` 的返回值会被忽略。

`run(args)` 不退出进程，只返回退出码；要精确控制参数时传列表，调用 `run()`
则读取进程参数（会丢掉开头的 `.fun`/`.foo`/`.fxx` 脚本路径；进程参数中遇到空
参数就停止扫描）。命令结束后需要退出时调用 `cli.quit(code)`。混用 `?.` 和重定向的
`out`/`err` 可能导致顺序错乱：`?.` 始终写进程控制台，`ctx.out()`/`ctx.err()`
才使用指定 writer。

退出码：解析错误、未知 flag/命令、非法值和缺失 required 返回 2；hook 返回 false
或抛出异常返回 1；action 返回的整数作为退出码。action 只能返回 nil、bool 或 int，
其他类型会报错并返回 1；`before` 同样只接受 nil、bool 或 int。

help 默认写 stdout，错误默认写 stderr。默认 console writer 直接写进程句柄；需要
捕获、重定向或非 ASCII 输出时请传 `out`/`err`。任意带 `write(s)` 的对象都可以；
action 通过 `ctx.out()`/`ctx.err()` 访问它们；子命令自己的 writer 优先，否则继承
根命令。框架不关闭也不 flush writer。

可选的 `input` 是任意带 `read(n)` 的对象，reader 契约与 `io.fun` 相同；默认惰性
使用 `io.stdin()`，因此读取 `ctx.stdin()` 的命令天然支持管道输入。子命令自己的
`input` 优先，否则继承根命令；父 hook 与子 action 共享同一个输入流，hook 的读取
会先消费输入。框架不主动读取、缓冲或关闭 reader，help/version 也不会消费输入。
测试用 `io.buffer` 同时注入输出和输入：

```fun
use 'io.fun';
var out = io.buffer();
var app = cli.command('demo', [out: out, err: out]);
app.flag(cli.string('name', [value: 'world']));
app.flag(cli.int('times', [value: 1]));
app.action(hello);

?. app.run(['--help']) = 0;
?. out.text().subpos('usage: demo') >= 0;
```

输入也是同样的方式：

```fun
var source = io.buffer('hello');
var copied = io.buffer();
fun copy(ctx)
  ctx.out().write(io.readAll(ctx.stdin()));
end fun;
var cat = cli.command('cat', [input: source, out: copied]);
cat.action(copy);
?. cat.run([]) = 0;
?. copied.text() = 'hello';
```

## 文件系统

文件系统辅助覆盖目录、遍历和临时文件/目录：

```fun
use 'fs.fun';
fs.mkdirAll('build/out');
fs.walk('src', (p, isDir) { ... });
fs.atomicWrite('build/out/config.json', data);
```

`walk` 与 `removeAll` 不跟随符号链接（`removeAll` 只删除链接本身，含断链）；
`exists/isDir/isFile` 跟随目标。整文件的创建/读取/追加仍用 built-in：
`save(data)`、`save(data, append: true)`、`load()`。

分段/二进制读写用 `fs.open`，返回按字节操作的文件对象：

```fun
var f = fs.open('data.bin', 'r+');
f.seek(16, 0);
var head = f.read(4);
f.write(bytes);
f.close();
```

模式为 `r`、`w`、`a`、`r+`、`w+`、`a+`（可带 `b` 后缀）；默认 `r`，
`a`/`a+` 的写入追加到末尾。方法为 `read(n)`、`write(data)`、
`seek(offset, whence)`、`tell()`、`eof()`、`flush()`、`close()`；
`whence` 可省略（默认 0 起），也可为 1 当前/2 末尾。`read` 返回字节串（字符值 0..255），
`write` 写每个字符的低字节。打开/I/O 失败抛异常，EOF 时 `read` 返回 `''`；
使用完必须显式 `close()`。读写切换遵循 C stdio：读→写先 `seek`；写→读可
`seek` 或 `flush`。64 位宿主上偏移为 64 位；大值需用算术构造
（如 `0xFFFFFFFF + 1`）。Windows 上 `fs.open` 需要 64 位构建；64 位窄字符构建
的路径使用当前 ANSI 代码页。

## 字节流与进程标准流

通用流辅助接受任何 reader/writer，不关闭句柄，并把 `''` 视为 EOF：

```fun
use 'io.fun';
var b = io.buffer('hello');
var text = io.readAll(b);        // 仅适合小数据
var out = io.buffer();
var f = fs.open('copy.bin', 'r');
var n = io.copy(out, f);         // 按 8192 字符分块
f.close();
io.writeString(out, 'done');
```

`io.buffer` 是内存 reader/writer（`read/write/text/length/reset`）；
`io.readAll` 是便捷入口，`io.copy` 才是流式复制。格式库和辅助函数接受
`io.buffer` 作为流，`fs.open` 句柄也可直接使用；格式 reader/writer 不关闭、
不 flush 底层 IO。

`io.scanner` 按 token 遍历任意 Reader，默认按行（`\n` 或 `\r\n`，最后一行可无
换行）。`scan()` 在 EOF 或出错时返回 false，`text()` 是当前 token，`err()`
报告 `token too long` 或 Reader 错误。`maxToken` 默认 64 KB，`delimiter`
可替换换行符：

```fun
use 'io.fun';
var sc = io.scanner(io.stdin());
while sc.scan() do ?. sc.text(); end do;
if sc.err() <> nil then raise sc.err(); end if;
```

自定义分隔符用 `io.scanner(r, [delimiter: ','])`；扫描器不关闭 Reader，并且
可能预读，不要和直接 `read()` 混用。

进程标准流沿用同一契约：

```fun
use 'io.fun';
var input = io.stdin();
var output = io.stdout();
var errors = io.stderr();

var chunk = input.read(4096);     // 可能短读；'' 表示 EOF
output.write('received ' & chunk.length() & 10.toChar());
errors.write('warning' & 10.toChar());
```

`io.stdin` 是 Reader，`io.stdout`/`io.stderr` 是 Writer；三者都不关闭、不 flush、
不转换换行，也不创建管道；`io.pipe` 单独创建管道，CLI stdin 仍是后续独立层。
进程 stdio 按字节处理字符串：UTF-16 Windows 构建中每个字符写成一个字节，
因此 ASCII 和二进制数据可原样往返；非 ASCII 文本需调用方先编码。Windows
console 的代码页/UTF-16 不做转换。进程 stdio 依赖 `getapi`，需要启用 FFI 的
构建；安全构建或无 FFI 构建中 `io.buffer` 仍可用，但读写进程 stdio 会报错。
Unix 上管道关闭时进程可能按惯例收到 SIGPIPE 并退出。不要在同一个 stdin 上
混用 `io.stdin()` 与内置 `line`/`char`/`all` 输入；输出顺序重要时也不要混用
`io.stdout()` 和 `?.`，它们使用独立的缓冲/FFI 路径。

## 管道

进程管道沿用同一套 reader/writer 契约：

```fun
use 'io.fun';
var p = io.pipe();
p.writer.write('hello');
p.writer.close();                  // reader 读完缓冲后看到 EOF
var text = io.readAll(p.reader);   // 'hello'
p.close();
```

`io.pipe()` 创建阻塞式 OS 管道；`p.reader`/`p.writer` 是 Reader/Writer，另有显式
`close()`，`p.close()` 关闭两端并丢弃未读数据。关闭 writer 后 reader 先读完缓冲数据
再返回 `''`；关闭 reader 后再读会报错，之后的写可能直接触发 SIGPIPE 终止进程
（不可捕获）。管道拥有自己的句柄，必须显式关闭；`io.readAll`/`io.copy` 不会替
调用方关闭。管道缓冲有限：单线程脚本先写入超过系统缓冲容量再读会死锁；v1 只适合
小数据，当前没有受支持的线程/进程句柄交接，大数据需要后续的流式/进程交接层。
管道为空且 writer 未关闭时，read（含 readAll/copy）会阻塞；没有超时/取消；
关闭 writer 才能让空读以 EOF 结束。`p.reader`/`p.writer` 不是线程安全的：
不要并发 read/write/close。`io.pipe` 需要启用 FFI 的构建，字节语义与进程 stdio 相同。

## 子进程

用 `process.run` 启动子进程：

```fun
use 'process.fun';

var r = process.run('git', ['status', '--short'], [timeout: 5000]);
if r.ok then
  ?. r.stdout;
else
  ?. r.stderr;
  ?. r.exitCode;
end if;
```

`process.run(name[, args[, opts]])` 直接执行命令，不经过 shell；尾随参数可省略，
没有参数时也可传 `nil` 或空列表。选项为 `stdin`（字符串，默认 `''`）、
`cwd`（空表示继承当前目录）、`timeout`（毫秒；`nil`/`0` 表示不超时）、
`output`（字节；`nil`/`0` 表示不限）。
返回对象包含 `ok`、`exitCode`、`signal`、`timedOut`、`outputExceeded`、
`stdout`、`stderr`。
非 0 退出码是正常结果；无法启动才 raise。Unix 上被信号终止时
`exitCode` 为负信号值（例如 `-15`），同时给出信号编号；Windows 返回进程退出码，
`signal` 为 `nil`。stdout/stderr 分开捕获为原始字节，不做编码或换行转换。

调用会阻塞到子进程退出或超时。超时后终止直接子进程并等待，结果中
`timedOut = true`、`ok = false`。实现使用单线程 stdio 泵，避免 stdout/stderr
互相堵死；不创建语言级线程，也不杀整个进程树。设置 `output` 后 stdout 与
stderr 共用同一字节预算，超限会终止直接子进程并置 `outputExceeded = true`、
`ok = false`；流式/交互式 stdio 仍未支持。需要 shell 语法时显式调用
`sh -c` / `cmd /c`。`process.run` 需要启用 FFI
的构建。Windows v1 的 stdin 用临时文件承载（Unix 用管道），且 `CreateProcessA`
的 ANSI 路径不能可靠处理非 ASCII 命令行/路径；32 位 Unicode/Delphi 仍需人工验证。
如果直接子进程退出后孙进程仍持有 stdout/stderr，v1 可能在短暂宽限期后停止读取，
迟到输出可能丢失。

## TOML

TOML 文档沿用同一套 reader/writer 契约：

```fun
use 'toml.fun';
var f = fs.open('config.toml', 'r');
var doc = toml.reader(f).read();   // 第一次读取后返回 nil
f.close();

var out = io.buffer();
toml.writer(out).write(doc);
```

表是 set，数组是 list；日期时间、`inf` 和 `nan` 用 `TomlLiteral` 保留
`.kind` / `.text`，writer 可以还原 TOML 语法。reader 一次返回一份文档，
之后返回 `nil`；writer 写一份文档；二者都不关闭句柄。

## CSV

CSV 文件按行流式读写；reader/writer 只包装文件句柄，不负责关闭：

```fun
use 'csv.fun';
var f = fs.open('users.csv', 'r');
var r = csv.reader(f);
var row = r.read();          // EOF 时返回 nil
while row <> nil do
  ...
  row = r.read();
end do;
f.close();

var g = fs.open('out.csv', 'w');
var w = csv.writer(g);
w.write(['name', 'age']);
g.close();
```

字段都是字符串，列数默认严格。空行按“一个空字段的记录”处理，在多列文件中会因
列数不一致报错；传 `[skipEmptyLines: true]` 可跳过完全空行。writer 按需加引号，
行尾默认 `\n`，传 `[crlf: true]` 写 CRLF。reader 接受任何有 `read(n)` 的对象，
writer 接受任何有 `write(s)` 的对象。

## JSON Schema

数据可以按 JSON Schema 校验。schema 默认用 FD 写，也接受 JSON 文本或已解析的对象：

```fun
use 'jsonschema.fun';

var schema = 'user.schema.fd'.load();
var r = JsonSchema.check(data, schema);
if not r.ok then
  ?. r.first.path & ': ' & r.first.message;
end if;
```

错误路径是 JSON Pointer（`/user/name`、`/tags/0`）。文本数据可以直接先解析再校验：
`JsonSchema.checkJson(text, schema)` / `JsonSchema.checkFd(text, schema)`，
布尔快捷方式是 `validJson` / `validFd`；解析失败会作为普通结果返回，关键字为
`parse`。

v0.x 支持 `type`（含类型列表）、`properties` / `required` /
`additionalProperties`、`items`（单 schema 或元组）/ `additionalItems` /
`minItems` / `maxItems` / `uniqueItems`、数值上下界、`minLength` / `maxLength`
（按 Unicode 码点计数）、`pattern` / `patternProperties` / `propertyNames`、
`enum`、`const`、`allOf` / `anyOf` / `oneOf` / `not`、同文档 `$ref` 与
`$defs` / `definitions`，以及 `format` 的 `email`、`date`、`time`、
`date-time`、`uri`、`uri-reference`、`uuid`、`ipv4`、`hostname`、`regex`。
外部 `$ref`、`dependencies`、`if` / `then` / `else` 和 `contains` 暂未支持。

## 平台拆分惯例

> Windows 实现保留原名，Unix 后端为 `<name>-unx.fun`（Linux + macOS），
> 旧的 `<name>-lnx.fun` 名字保留为它之上的薄包装；两者共用的逻辑放在
> `<name>-base.fun`（不计入上面的模块数）。只在 Linux 成立的后端（如读 `/proc` 的
> `lib-proc`）继续用 `<name>-lnx`。例如 `lib-os` / `lib-os-unx`（+ `lib-os-lnx`），
> 以及 `lib-unicode-base` + `lib-unicode` / `lib-unicode-unx`。
> 用 `use` 时也可以直接写中性名：会按平台探测变体（macOS `-darwin`→`-unx`，Linux `-lnx`→`-unx`，变体存在才替换）。
