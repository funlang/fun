# Fun language card

Fun 9.5.7, ontology v0.1.0.

## Syntax

- `?. 'Hello, Fun!';` (syntax.hello): A Fun script is a sequence of statements; `?.` prints a value and a newline.

```fun
?. 'Hello, Fun!';
```
- `stmt; block ... end block` (syntax.statement): Statements end with `;`. The `;` after a block closer (`end if`, `end fun`, `end class`, `end do`, `end loop`, `end try`) is optional. Newlines are not statement boundaries.

```fun
var a = 1;
var b = a
  + 2;
?. b;
```
- `# line / // line / #* block #` (syntax.comment): Both `#` and `//` start a line comment. `#* ... #` is a block comment; the next `#` closes it.

```fun
# a hash comment
// a slash comment
#* a block
   comment #
?. 1;
```
- `var x = expr;` (syntax.var): Declare with `var name = expr;` or `var name;` (nil). There is no `let` or `const`; identifiers are case-insensitive.

```fun
var x = 1;
var y;
?. x;
?. y = nil;
```
- `x = value; if a = b then ...` (syntax.assignment): A statement `x = expr;` assigns; the same `=` inside an expression compares. `<>` and `!=` both mean not-equal. Compound assignment uses `+= -= *= &=`.

```fun
var x = 1;
x = x + 2;
?. x;
?. x = 3;
?. x <> 4;
```
- `?. value;` (syntax.print): The `?.` operator prints with a newline, `?,` prints with a space, and `?:` prints with a tab. All three accept any value.

```fun
?, 'a';
?: 'b';
?. 'c';
```
- `fun f(a, b) result = a + b; end fun;` (syntax.function): A `fun name(params) ... end fun;` returns the value assigned to `result`; `return expr;` exits early. `result` is not reset on entry, so initialize it explicitly.

```fun
fun add(a, b)
  result = a + b;
end fun;
?. add(2, 3);
```
- `f = a -> a * 2;` (syntax.lambda): A lambda `a -> expr` takes one argument; `(a, b) -> expr` takes several. A braced body is a block that must assign `result`.

```fun
use 'lib-set.fun';
var f = a -> a * 2;
?. f(3);
var nums = [1, 2, 3];
?. (nums | map(a -> a + 1)).@toJson();
```
- `if c then ... elsif c2 then ... else ... end if;` (syntax.if): The form `if c then ... elsif c2 then ... else ... end if;` uses Fun truthiness; use explicit comparisons for clarity.

```fun
var n = 2;
if n = 1 then
  ?. 'one';
elsif n = 2 then
  ?. 'two';
else
  ?. 'other';
end if;
```
- `case x is when 1 do ... else ... end case;` (syntax.case): The form `case expr is when v do ... else ... end case;` matches values.

```fun
var x = 2;
case x is
  when 1 do ?. 'one';
  when 2 do ?. 'two';
  else ?. 'other';
end case;
```
- `for i = 1 to 3 do ... end do;` (syntax.loop): Forms: `for i = a to b do ... end do;`, `for k: v in set do ... end do;`, `while c do ... end do;`, and `loop ... exit when c; ... end loop;`. `next when c;` skips.

```fun
var total = 0;
for i = 1 to 3 do
  total += i;
end do;
?. total;
var m = 0;
loop
  m += 1;
  exit when m >= 2;
end loop;
?. m;
```
- `try ... except ... end try;` (syntax.try): The form `try ... except ... finally ... end try;` catches `raise` and runtime errors. `runtime.lastError()` exposes message, file, line and stack.

```fun
try
  raise 'boom';
except
  ?. 'caught';
end try;
```
- `class C(x) var x = x; fun get() result = x; end fun; end class;` (syntax.class): A `class Name(params) ... end class;` body runs as the constructor; `var` fields become members, `fun` declarations become methods, `this` is the instance and `base` the parent. Inherit with `class Child = Parent()`.

```fun
class Point(x, y)
  var x = x;
  var y = y;
  fun sum() result = x + y; end fun;
end class;
var p = Point(2, 3);
?. p.sum();
?. p.x;
```
- `use 'lib-set.fun';` (syntax.use): The statement `use 'lib-set.fun';` links a module by file name; `use 'x.fun' as ns;` namespaces it. Paths resolve relative to the script and the runtime `lib/` directory.

```fun
use 'lib-set.fun';
var xs = [1, 2, 3];
?. (xs | map(a -> a * 2)).@toJson();
```
- `var xs = [1,2]; var m = new [a: 1];` (syntax.collection): A list literal `[1, 2, 3]` is a list. `new [k: v]` is a string-keyed map (called a set in Fun). Both support `@count`, `@has`, `@add`, and JSON conversion.

```fun
var xs = [1, 2, 3];
var m = new [name: 'Ada'];
?. xs.@count();
?. m.name;
?. m['name'];
xs.@add(4);
?. xs.@toJson();
```
- `obj.key / obj['key'] / a?.k?` (syntax.member): Forms `obj.key`, `obj['key']` and `obj.['1']` read members; a missing member compares equal to nil. Postfix `?` makes a member or its base optional: `x?.k?`.

```fun
var m = new [name: 'Ada'];
?. m.name;
?. m['name'];
?. m.missing = nil;
var none = nil;
?. none?.name? = nil;
```
- `value.@builtin(); obj.userMethod();` (syntax.method): Engine-provided methods use `@`: `x.@toJson()`, `s.@count()`, `m.@('group')`. Methods you write in a class are called without `@`.

```fun
var xs = [1, 2, 3];
?. xs.@count();
?. xs.@toJson();
```
- `xs | map(f) | filter(p)` (syntax.pipe): The pipe `value | f` passes the value as the last argument of `f`. `map(f)` takes the list last, so it composes; `filter(list, f)` takes the list first, so call it directly.

```fun
use 'lib-set.fun';
var xs = [1, 2, 3, 4];
var ys = xs | map(a -> a * 10);
?. ys.@toJson();
```
- `'a\nb'.escape() / backtick multiline` (syntax.string): Single, double and backtick quotes all delimit strings. Literals do not decode backslash escapes; call `.escape()` to decode `\n`, `\t`, etc., use `10.toChar()`, or use a multiline backtick string. `$name` interpolation is done by `.eval()`.

```fun
var a = 'x\ny'.escape();
?. a.length();
var b = 'hello';
?. 'say $b'.eval();
var c = 'one' & 10.toChar() & 'two';
?. c;
```
- `s.match(/\d+/g); s.replace(/\d+/g, fn); s =~ /^a/` (syntax.regex): Regex literals are `/pattern/flags`, `%pattern%flags` or `$'pattern'flags`. Use `=~` / `!~` to test, `.match()` to extract, `.replace()` to rewrite.

```fun
var s = 'a1b22';
?. s.match(/\d+/g).@toJson();
?. s.replace(/\d+/g, (m) -> '[' & m.@(0) & ']');
?. (s =~ /^a/) <> nil;
```
- `s.getJson(json: true); v.@toJson(json: true);` (syntax.json): The built-in `value.@toJson()` emits JSON; `value.@toJson(json: true)` quotes keys. Parse with `text.getJson(json: true)`. `text.getJson(fd: true)` parses FD.

```fun
var m = '{"a": 1, "b": [2, 3]}'.getJson(json: true);
?. m.a;
?. m.b[1];
?. m.@toJson(json: true);
```
- `s.getJson(fd: true); v.@toJson(fd: true);` (syntax.fd): FD is Fun's indentation data notation: `key value` lines, `- item` lists, no braces. `text.getJson(fd: true)` parses it and `value.@toJson(fd: true)` emits it.

```fun
var s = 'name Ada' & 10.toChar() & 'tags' & 10.toChar() & '  - math' & 10.toChar() & '  - code';
var m = s.getJson(fd: true);
?. m.name;
?. m.tags.@count();
```
- `this['#'] = you -> (me + you) * me * you;` (syntax.operator): An operator is a field keyed by its symbol. In `this['#'] = you -> ...`, `me` is the receiver and `you` the right operand.

```fun
class Num(me)
  this['#'] = you -> (me + you) * me * you;
end class;
var n = Num(2);
?. n .# 3;
```

## Semantics

- `missing = nil -> True` (sem.missing-is-nil): Reading a missing member, key or index yields a value that compares equal to nil. This makes `if x = nil then x = init; end if` safe.

```fun
var m = new [];
?. m.nope = nil;
?. m['nope'] = nil;
?. m[0] = nil;
```
- `nil + 1 -> 1; x += 1 works on a fresh key` (sem.nil-arithmetic): A nil operand in `+ - * / div mod` is treated as 0, and as '' for strings. `x += 1` therefore works on a fresh key. The flip side is that a missing value also compares equal to 0.

```fun
var m = new [];
m.k += 1;
?. m.k;
var z;
?. z + 1;
?. m.@has('k');
?. m.@has('no');
```
- `x = x or default;` (sem.or-value): Operators `or` and `and` return one of their operands, Lua style: `nil or 5` is 5, `7 or 5` is 7. This powers default values.

```fun
?. (nil or 5);
?. (7 or 5);
?. (nil and 5) = nil;
```
- `fun f() result = 0; ... end fun;` (sem.result): Each function has one `result` slot. It is not cleared on entry, so a call at the same stack depth can see the previous value. Always initialize `result`.

```fun
fun f(n)
  if n > 0 then result = n; end if;
end fun;
?. f(1);
?. f(0);
fun g(n)
  result = 0;
  if n > 0 then result = n; end if;
end fun;
?. g(1);
?. g(0);
```
- `Foo = foo; o.NAME = o.name;` (sem.case-insensitive): Variables, functions, members and built-in method names all fold case. Avoid local names that differ from another symbol only by case.

```fun
var Foo = 1;
?. foo;
var m = new [name: 'Ada'];
?. m.NAME;
?. 'Hi'.UPPER();
```
- `f(b: 2, a: 1)` (sem.named-args): Call sites may name arguments: `f(b: 2, a: 1)`. Missing arguments are nil, so defaults are written as `if p = nil then p = default; end if`.

```fun
fun greet(name, punct)
  if punct = nil then punct = '!'; end if;
  result = 'Hi ' & name & punct;
end fun;
?. greet('Ada');
?. greet(punct: '?', name: 'Bob');
```
- `x.type() -> 0/3/5/6/7/8/11/-1` (sem.type): The method `.type()` returns 0 nil, 3 int, 5 real, 6 currency, 7 time, 8 string, 11 bool, -1 other. Integers are 32-bit unless explicitly 64-bit.

```fun
var n = 1;
var s = 'x';
var z;
var b = true;
?. n.type();
?. s.type();
?. z.type();
?. b.type();
```
- `var b = a; b.k = 1; # a.k is 1; use a.@clone()` (sem.reference): Assigning a map or list copies the reference. Mutating one alias is visible through the other; use `@clone()` for an independent copy.

```fun
use 'lib-set.fun';
var a = [x: 1];
var b = a;
b.x = 2;
?. a.x;
var c = a.@clone();
c.x = 3;
?. a.x;
?. c.x;
```
- `obj.get() / obj.@toJson()` (sem.user-vs-builtin): Methods declared with `fun` inside a class are called as `obj.method()`. Engine methods are called as `obj.@method()`. The `@` is the dispatch marker, not part of the name.

```fun
class Box(v)
  var v = v;
  fun get() result = v; end fun;
end class;
var b = Box(7);
?. b.get();
```

## Built-ins

- `value.@toJson(json: true);` (builtin.tojson): The built-in serializer. Default output is JSON-like with bare keys; `json: true` quotes keys, and `fd: true` emits FD.

```fun
var m = new [a: 1, b: [2]];
?. m.@toJson(json: true);
```
- `'a\nb'.escape()` (builtin.escape): Decodes backslash escapes in a string: `'\n'.escape()` is a newline, `'\t'.escape()` a tab. Literals keep the backslash until `.escape()` is called.

```fun
?. 'a\nb'.length();
?. 'a\nb'.escape().length();
?. 'x\ty'.escape().length();
```

## Modules

- `use 'lib-set.fun';` (module.lib-set): Collection helpers in pure Fun: `map`, `filter`, `find`, `sort`, `compose`, `range`, `@clone`, and more.

```fun
use 'lib-set.fun';
?. ([1, 2, 3] | map(a -> a * 2)).@toJson();
```
- `use 'lib-json.fun';` (module.lib-json): JSON and FD parse/stringify helpers. The underlying built-ins are `.getJson()` and `.@toJson()`, documented in `lib-json.fun`.

```fun
var m = '{"a": 1}'.getJson(json: true);
?. m.@toJson(json: true);
```
- `use 'runtime.fun'; runtime.lastError();` (module.runtime): The calls `runtime.source()`, `runtime.stack()`, `runtime.lastError()` expose source locations, call stacks and the last caught error.

```fun
use 'runtime.fun';
try
  raise 'boom';
except
  var e = runtime.lastError();
  ?. e.message = 'boom';
end try;
```
- `use 'fs.fun'; fs.mkdirAll('out');` (module.fs): Portable filesystem helpers: `mkdirAll`, `list`, `walk`, `removeAll`, `tempFile`, `tempDir`, `atomicWrite` and byte streams.

```fun
use 'fs.fun';
var d = fs.tempDir('fun-ontology-');
?. d <> '';
fs.removeAll(d);
```
- `use 'cli.fun';` (module.cli): A command-line framework: subcommands, flags, aliases, env fallback, required flags, hooks and help.

```fun
?. 'See fun/lib/cli.fun';
```
- `use 'http-server.fun'; var s = HttpServer(8080);` (module.http-server): An HTTP server with routing, path parameters, middleware, static files and a blocking poll loop. Handlers are `fun(req, res)`.

```fun
?. 'See fun/lib/http-server.fun';
```
- `use 'http-client.fun';` (module.http-client): An HTTP client with helpers for JSON, headers, timeouts and TLS. `use 'http-client.fun';`.

```fun
?. 'See fun/lib/http-client.fun';
```
- `use 'lib-fd.fun';` (module.lib-fd): FD parse and emit helpers. The underlying built-ins are `text.getJson(fd: true)` and `value.@toJson(fd: true)`.

```fun
var m = 'a 1'.getJson(fd: true);
?. m.a;
```
- `use 'lib-type.fun';` (module.lib-type): Type conversion helpers: `toStr`, `toNum`, `toTime`, `toByte`, `toChar`, `fromByte`, `eq` and `type`.

```fun
var n = 1;
?. n.type();
```
- `use 'lib-host.fun'; LibC().getapi(...)` (module.lib-host): Host detection and libc binding: `LibC()`, `IsWindows()`, `HostCurrPath()`, and the `'host'.arg()` facts.

```fun
use 'lib-host.fun';
var getpid = LibC().getapi('getpid', ':i');
?. getpid() > 0;
```
- `CWin32API('user32.dll', prototype)` (module.lib-cwinapi): Windows helper: `CWin32API('user32.dll', 'int MessageBoxA(HWND, LPCSTR, LPCSTR, UINT);')` parses a C prototype and exposes named arguments.

```fun
?. 'Windows only: use CWin32API(dll, prototype)';
```
- `CStruct(declaration, values)` (module.lib-cstruct): The call `CStruct('struct Point { int x; int y; };', [x: 3, y: 4])` computes offsets and padding and exposes a pointer-addressable buffer.

```fun
?. 'Use CStruct(declaration, values) for C layouts';
```

## Idioms

- `name = name or 'anonymous';` (idiom.default): Use `or` to supply a default for nil or false. `x = x or default;`.

```fun
fun greet(name)
  name = name or 'anonymous';
  result = 'Hi ' & name;
end fun;
?. greet(nil);
?. greet('Ada');
```
- `m.k = (m.k or 0) + 1;` (idiom.accumulator): Seed a counter explicitly when you want the intent to be obvious across builds: `m.k = (m.k or 0) + 1;`. On 9.5.7, `m.k += 1` also yields 1.

```fun
var m = new [];
m.k = (m.k or 0) + 1;
m.k = (m.k or 0) + 1;
?. m.k;
```
- `xs | map(f)` (idiom.pipeline): The pipeline `xs | map(f)` reads left to right. Add `use 'lib-set.fun';` first. `map` takes the list last and composes; `filter` takes the list first.

```fun
use 'lib-set.fun';
var xs = [1, 2, 3, 4];
?. (xs | map(a -> a * a)).@toJson();
?. filter(xs, a -> a > 2).@toJson();
```
- `fun adder(n) result = a -> a + n; end fun;` (idiom.closure): A function value captures its defining scope. Capture an argument to build a specialized function without a class.

```fun
fun adder(n)
  result = a -> a + n;
end fun;
var add2 = adder(2);
?. add2(3);
?. add2(10);
```
- `var m = s.getJson(json: true); ...; m.@toJson(json: true)` (idiom.json-roundtrip): Parse with `.getJson(json: true)`, inspect with member access, emit with `.@toJson(json: true)`.

```fun
var s = '{"users": [{"name": "Ada"}]}';
var m = s.getJson(json: true);
?. m.users[0].name;
m.users[0].active = true;
?. m.@toJson(json: true);
```
- `var s = 'in.txt'.load(); 'out.txt'.save(s);` (idiom.file-io): The built-in `'path'.load()` reads a whole file; `'path'.save(text)` writes one. For directories, atomic writes and walking use `use 'fs.fun';`.

```fun
use 'fs.fun';
var p = fs.tempFile('fun-ontology-');
p.save('hello');
?. p.load();
fs.removeAll(p);
```
- `var first = 2.arg();` (idiom.cli): The expression `i.arg()` reads argv by position; `Argv()` (from `lib-cmdline`) returns the list. `use 'cli.fun';` gives flags, subcommands and help.

```fun
?. 0.arg().length() > 0;
```
- `var f = LibC().getapi('getpid', ':i'); f();` (idiom.ffi): The call `LibC().getapi(name, signature)` or `'libname'.getapi(...)` binds a native function. The signature is `argtypes:rettype`, e.g. `':i'` for no args returning int.

```fun
use 'lib-host.fun';
var getpid = LibC().getapi('getpid', ':i');
?. getpid() > 0;
```

## Pitfalls

- `if a = b then ...; if a <> b then ...;` (pit.double-equals): Use `=` for equality inside an expression, and `<>` or `!=` for inequality. `==` is not Fun.

```fun
?. (1 = 1);
?. (1 <> 2);
```
- `a = 1; b = 2;` (pit.newline-is-not-a-statement): A newline is whitespace. Put `;` between statements; a continuation line can silently join the previous expression.

```fun
var a = 1
  + 2;
?. a;
```
- `'a\nb'.escape()` (pit.backslash-escape): The literal `'\n'` is a backslash followed by `n`, not a newline. Call `.escape()` to decode it, or use `10.toChar()` or a multiline backtick string.

```fun
?. 'a\nb'.length();
?. 'a\nb'.escape().length();
?. ('a' & 10.toChar() & 'b').length();
```
- `a?.k? only` (pit.optional-chain): The form `x?.k?` makes the base and the member optional. It does not make a following call optional, and `f()?.x` is not the JS form; assign to a variable first.

```fun
fun pick(o, k) result = o?.k?; end fun;
?. pick(new [k: 7], 'k');
?. pick(nil, 'k') = nil;
```
- `m.@(0); m.@('group'); m.@@()` (pit.match-group): In a match object, `m.@(0)` is the whole match and `m.@('name')` a named group; `m.@@()` is also the whole match. `m.@()` with no argument is not valid.

```fun
var m = 'a12'.match(/(\d+)/);
?. m.@(0);
?. m.@(1);
```
- `m.@has('k')` (pit.missing-key-accumulate): A missing value compares equal to nil and to 0, so `if x = 0` cannot tell "absent" from "zero". Use `.@has(key)` when presence matters.

```fun
var m = new [];
?. m.k = nil;
?. m.k = 0;
?. m.@has('k');
m.k = 0;
?. m.@has('k');
```
- `[1,2,3] / new [k: v]` (pit.array-vs-map): A list literal `[1, 2]` is ordered; `new [a: 1]` is a string-keyed map. Do not use `{}` for either.

```fun
var xs = [10, 20];
var m = new [a: 10];
?. xs[1];
?. m.a;
```
- `result = expr; or return expr;` (pit.return-keyword): Inside `fun`, assigning `result` sets the return value; `return expr;` returns immediately. A bare `return;` returns the current `result`, which may be stale.

```fun
fun f()
  result = 1;
  return 2;
  result = 3;
end fun;
?. f();
```

## Tooling

- `fun hello.fun / fun test / fun pack` (tool.funcmd): The command `fun file.fun` runs a script; `fun test` runs a package's tests; `fun pack` builds one executable; `fun package init` creates a manifest.

```fun
?. 'Use: fun hello.fun';
```
- `use 'test.fun'; test('name', { assert.equal(a, b); });` (tool.test): Test files are `*_test.fun`; import `test.fun` and call `test('name', { assert.equal(a, b); });`. `fun test` runs each file in a child process.

```fun
?. 'Write this in a *_test.fun file, then run: fun test';
```
- `fun package init myapp && fun run` (tool.package): A project has a `package.fun` manifest. `fun package init/tidy/add/remove` creates and maintains it; `fun run` runs the manifest bin.

```fun
?. 'fun package init myapp';
```
- `fun-safe untrusted.fun` (tool.fun-safe): A restricted build with native code, arbitrary memory access, and file/compile access removed. Use it for plugins and untrusted scripts.

```fun
?. 'fun-safe script.fun';
```
- `WorkerFile('job.fun', 'entry', args)` (tool.mt): The `fun-mt` build is the opt-in multi-threaded build. A worker parses its own module and heap; results cross as strings, with `Shared` and `Channel` for named stores.

```fun
?. 'Requires fun-mt and use lib-worker.fun';
```

## Platforms

- `Windows 95..11 / Linux / macOS / LoongArch64 / riscv64` (platform.matrix): Windows 95 through Windows 11, Linux x64/arm64 (glibc 2.17+), macOS x64/arm64, and nightly LoongArch64/riscv64 builds. About 0.3 MB, zero external dependencies.

```fun
var h = 'host'.arg().getJson(fd: true);
?. h.os <> '';
```

## Tasks

- `parse -> mutate -> stringify` (task.json-transform): Parse a JSON document, update a nested value, and emit JSON again.

```fun
var doc = '{"items": [{"n": 1}, {"n": 2}]}'.getJson(json: true);
for i = 0 to doc.items.@count() - 1 do
  doc.items[i].n *= 10;
end do;
?. doc.@toJson(json: true);
```
- `HttpServer(8080).get('/health', handler)` (task.hello-server): Create `HttpServer(port)`, register a handler that writes JSON, and call `run()`. Requires a listening socket; not executed by the ontology checker.
- `LibC().getapi('getpid', ':i')()` (task.ffi-libc): Bind a libc function by name and signature, then call it from Fun. Use CStruct/CWin32API when a struct or a Windows prototype is involved.

```fun
use 'lib-host.fun';
var getpid = LibC().getapi('getpid', ':i');
?. getpid() > 0;
```
- `var a = 2.arg();` (task.cli-args): Read positional arguments with `i.arg()`, or use `Argv()`/`cli.fun` for flags and subcommands.

```fun
?. 0.arg().length() > 0;
```

