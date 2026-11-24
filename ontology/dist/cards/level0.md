# Fun language card

Fun 9.5.7, ontology v0.1.0.

## Syntax

- `?. 'Hello, Fun!';` (syntax.hello): A Fun script is a sequence of statements; `?.` prints a value and a newline.
- `stmt; block ... end block` (syntax.statement): Statements end with `;`. The `;` after a block closer (`end if`, `end fun`, `end class`, `end do`, `end loop`, `end try`) is optional, and the last statement before `}` may omit it. Newlines are not statement boundaries.
- `# line / // line / #* block #` (syntax.comment): Both `#` and `//` start a line comment. `#* ... #` is a block comment; the next `#` closes it.
- `var x = expr;` (syntax.var): Declare with `var name = expr;` or `var name;` (nil). There is no `let` or `const`; identifiers are case-insensitive.
- `x = value; if a = b then ...` (syntax.assignment): A statement `x = expr;` assigns; the same `=` inside an expression compares. `<>` and `!=` both mean not-equal. Compound assignment uses `+= -= *= &=`.
- `? value; ?. value;` (syntax.print): Bare `?` prints with no separator, `?.` with a newline, `?,` with a space, and `?:` with a tab. All four accept any value.
- `fun f(a, b) result = a + b; end fun;` (syntax.function): A `fun name(params) ... end fun;` returns the value assigned to `result`; `return expr;` exits early. A one-expression function can also be written `var name(a, b) = expr;`. `result` is not reset on entry, so initialize it explicitly.
- `f = a -> a * 2;` (syntax.lambda): The arrow forms `a -> expr` and `(a, b) -> expr` return an expression. For a block body use `fun (a, b) { ... }` with `return` or `result`; a bare `{ ... }` is a zero-argument block function.
- `if c then ... end if; / if c { ... }` (syntax.if): The form `if c then ... elsif c2 then ... else ... end if;` supports branches. The shorthand `if c { ... }` is a single branch only and takes no `elsif` or `else`.
- `case x is when 1 do ... else ... end case;` (syntax.case): The form `case expr is when v do ... else ... end case;` matches values.
- `for i = 1 to 3 do ... end do;` (syntax.loop): Forms: `for i = a to b do ... end do;`, `for k: v in set do ... end do;`, `while c do ... end do;`, and `loop ... exit when c; ... end loop;`. `while c { ... }` and `for ... { ... }` are shorthands. `next when c;` skips.
- `try ... except ... end try;` (syntax.try): The form `try ... except ... finally ... end try;` catches `raise` and runtime errors. `runtime.lastError()` exposes message, file, line and stack.
- `class C(x) var x = x; fun get() result = x; end fun; end class;` (syntax.class): A `class Name(params) ... end class;` body runs as the constructor; `var` fields become members, `fun` declarations become methods, `this` is the instance and `base` the parent. Inherit with `class Child = Parent()`.
- `use 'lib-set.fun';` (syntax.use): The statement `use 'lib-set.fun';` links a module by file name; `use 'x.fun' as ns;` namespaces it. Paths resolve relative to the script and the runtime `lib/` directory.
- `var xs = [1,2]; var m = new [a: 1];` (syntax.collection): A list literal `[1, 2, 3]` is a list. `new [k: v]` is a string-keyed map (called a set in Fun). Both support `@count`, `@has`, `@add`, and JSON conversion.
- `obj.key / obj['key'] / a?.k?` (syntax.member): Forms `obj.key`, `obj['key']` and `obj.['1']` read members; a missing member compares equal to nil. Postfix `?` makes a member or its base optional: `x?.k?`.
- `value.@builtin(); obj.userMethod();` (syntax.method): Engine-provided methods use `@`: `x.@toJson()`, `s.@count()`, `m.@('group')`. Methods you write in a class are called without `@`.
- `xs | map(f) | filter(p)` (syntax.pipe): The pipe `value | f` passes the value as the last argument of `f`. `map(f)` takes the list last, so it composes; `filter(list, f)` takes the list first, so call it directly.
- `'a\nb'.escape() / backtick multiline` (syntax.string): Single, double and backtick quotes all delimit strings. Literals do not decode backslash escapes; call `.escape()` to decode `\n`, `\t`, etc., use `10.toChar()`, or use a multiline backtick string. `$name` interpolation is done by `.eval()`.
- `s.match(/\d+/g); s.replace(/\d+/g, fn); s =~ /^a/` (syntax.regex): Regex literals are `/pattern/flags`, `%pattern%flags` or `$'pattern'flags`. Use `=~` / `!~` to test, `.match()` to extract, `.replace()` to rewrite.
- `s.getJson(json: true); v.@toJson(json: true);` (syntax.json): The built-in `value.@toJson()` emits JSON; `value.@toJson(json: true)` quotes keys. Parse with `text.getJson(json: true)`. `text.getJson(fd: true)` parses FD.
- `s.getJson(fd: true); v.@toJson(fd: true);` (syntax.fd): FD is Fun's indentation data notation: `key value` lines, `- item` lists, no braces. `text.getJson(fd: true)` parses it and `value.@toJson(fd: true)` emits it.

## Semantics

- `missing = nil -> True` (sem.missing-is-nil): Reading a missing member, key or index yields a value that compares equal to nil. This makes `if x = nil then x = init; end if` safe.
- `nil + 1 -> 1; x += 1 works on a fresh key` (sem.nil-arithmetic): A nil operand in `+ - * / div mod` is treated as 0, and as '' for strings. `x += 1` therefore works on a fresh key. The flip side is that a missing value also compares equal to 0.
- `x = x or default;` (sem.or-value): Operators `or` and `and` return one of their operands, Lua style: `nil or 5` is 5, `7 or 5` is 7. This powers default values.
- `fun f() result = 0; ... end fun;` (sem.result): Each function has one `result` slot. It is not cleared on entry, so a call at the same stack depth can see the previous value. Always initialize `result`.
- `Foo = foo; o.NAME = o.name;` (sem.case-insensitive): Variables, functions, members and built-in method names all fold case. Avoid local names that differ from another symbol only by case.
- `f(b: 2, a: 1)` (sem.named-args): Call sites may name arguments: `f(b: 2, a: 1)`. Missing arguments are nil, so defaults are written as `if p = nil then p = default; end if`.

## Built-ins

- `value.@toJson(json: true);` (builtin.tojson): The built-in serializer. Default output is JSON-like with bare keys; `json: true` quotes keys, and `fd: true` emits FD.
- `'a\nb'.escape()` (builtin.escape): Decodes backslash escapes in a string: `'\n'.escape()` is a newline, `'\t'.escape()` a tab. Literals keep the backslash until `.escape()` is called.

## Modules

- `use 'lib-set.fun';` (module.lib-set): Collection helpers in pure Fun: `map`, `filter`, `find`, `sort`, `compose`, `range`, `@clone`, and more.
- `use 'lib-json.fun';` (module.lib-json): JSON and FD parse/stringify helpers. The underlying built-ins are `.getJson()` and `.@toJson()`, documented in `lib-json.fun`.

## Idioms

- `name = name or 'anonymous';` (idiom.default): Use `or` to supply a default for nil or false. `x = x or default;`.
- `m.k = (m.k or 0) + 1;` (idiom.accumulator): Seed a counter explicitly when you want the intent to be obvious across builds: `m.k = (m.k or 0) + 1;`. On 9.5.7, `m.k += 1` also yields 1.
- `xs | map(f)` (idiom.pipeline): The pipeline `xs | map(f)` reads left to right. Add `use 'lib-set.fun';` first. `map` takes the list last and composes; `filter` takes the list first.
- `var m = s.getJson(json: true); ...; m.@toJson(json: true)` (idiom.json-roundtrip): Parse with `.getJson(json: true)`, inspect with member access, emit with `.@toJson(json: true)`.

## Pitfalls

- `if a = b then ...; if a <> b then ...;` (pit.double-equals): Use `=` for equality inside an expression, and `<>` or `!=` for inequality. `==` is not Fun.
- `a = 1; b = 2;` (pit.newline-is-not-a-statement): A newline is whitespace. Put `;` between statements; a continuation line can silently join the previous expression.
- `'a\nb'.escape()` (pit.backslash-escape): The literal `'\n'` is a backslash followed by `n`, not a newline. Call `.escape()` to decode it, or use `10.toChar()` or a multiline backtick string.
- `m.@has('k')` (pit.missing-key-accumulate): A missing value compares equal to nil and to 0, so `if x = 0` cannot tell "absent" from "zero". Use `.@has(key)` when presence matters.
- `[1,2,3] / new [k: v]` (pit.array-vs-map): A list literal `[1, 2]` is ordered; `new [a: 1]` is a string-keyed map. Do not use `{}` for either.
- `result = expr; or return expr;` (pit.return-keyword): Inside `fun`, assigning `result` sets the return value; `return expr;` returns immediately. A bare `return;` returns the current `result`, which may be stale.

## Tooling

- `fun hello.fun / fun test / fun pack` (tool.funcmd): The command `fun file.fun` runs a script; `fun test` runs a package's tests; `fun pack` builds one executable; `fun package init` creates a manifest.

## Tasks

- `parse -> mutate -> stringify` (task.json-transform): Parse a JSON document, update a nested value, and emit JSON again.

