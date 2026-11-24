# AGENTS.md snippet

Use this block in an agent instruction file, a system prompt, or a tool description.

```text
When writing Fun (files end in .fun, .foo or .fxx):
- Statements end with `;`. Blocks end with `end if;`, `end fun;`, `end class;`, `end do;`, `end loop;`, `end try;`.
- `?.` prints a line; `var x = 1;` declares; `fun f(a) result = a; end fun;` returns.
- `[1,2]` is a list; `new [k: v]` is a string-keyed map; missing keys compare equal to nil.
- Nil enters arithmetic as 0, and a missing value also compares equal to 0. Use `m.@has(k)` when presence matters.
- Built-in methods use `@`: `x.@toJson()`, `s.@count()`, `m.@(0)`.
- `=` is equality inside expressions, `<>` is not-equal; there is no `==`.
- Always initialize `result` at function entry; it is not cleared between calls.
- Verify with `fun check` (MCP) or `fun ontology/tools/build.fun --check`.
```

## Task pack

```text
# Fun language context

> Fun Language AI Ontology v0.1.0 for Fun 9.5.7

Fun is a ~0.3 MB, zero-dependency scripting language. Statements end with `;`. Blocks end with `end if;`, `end fun;`, `end class;`, `end do;`. `?.` prints. `fun f(a) result = a; end fun;` returns. `[1,2]` is a list; `new [k: v]` is a map. Missing values compare equal to nil and to 0, so use `m.@has(k)` when presence matters.

## Task

general Fun development

## Concepts

### Named functions (`syntax.function`)

A `fun name(params) ... end fun;` returns the value assigned to `result`; `return expr;` exits early. `result` is not reset on entry, so initialize it explicitly.

```fun
fun f(a, b) result = a + b; end fun;```

Transfer: js `function f(a, b) { return a + b; }`; py `def f(a, b): return a + b`; c `int f(int a, int b) { return a + b; }`;


### The fun command (`tool.funcmd`)

The command `fun file.fun` runs a script; `fun test` runs a package's tests; `fun pack` builds one executable; `fun package init` creates a manifest.

```fun
fun hello.fun / fun test / fun pack```

Transfer: js `node hello.js`; py `python hello.py`;


### fun-safe (`tool.fun-safe`)

A restricted build with native code, arbitrary memory access, and file/compile access removed. Use it for plugins and untrusted scripts.

```fun
fun-safe untrusted.fun```


### There is no == (`pit.double-equals`)

Use `=` for equality inside an expression, and `<>` or `!=` for inequality. `==` is not Fun.

```fun
if a = b then ...; if a <> b then ...;```

Transfer: js `===`; py `==`; c `==`;


### result vs return (`pit.return-keyword`)

Inside `fun`, assigning `result` sets the return value; `return expr;` returns immediately. A bare `return;` returns the current `result`, which may be stale.

```fun
result = expr; or return expr;```

Transfer: js `return x`; py `return x`;


### Hello world (`syntax.hello`)

A Fun script is a sequence of statements; `?.` prints a value and a newline.

```fun
?. 'Hello, Fun!';```

Transfer: js `console.log('Hello')`; py `print('Hello')`; c `puts("Hello");`;


- `stmt; block ... end block;` (syntax.statement)

### Lambdas (`syntax.lambda`)

A lambda `a -> expr` takes one argument; `(a, b) -> expr` takes several. A braced body is a block that must assign `result`.

```fun
f = a -> a * 2;```

Transfer: js `a => a * 2`; py `lambda a: a * 2`;


- `use 'lib-set.fun';` (syntax.use)

## Pitfalls

```