# Fun pitfalls

Habits imported from other languages that break Fun. Each item is executable evidence.

## There is no == (pit.double-equals)

Use `=` for equality inside an expression, and `<>` or `!=` for inequality. `==` is not Fun.

- Do not: `if a = b then ...; if a <> b then ...;`

```fun
?. (1 = 1);
?. (1 <> 2);
```
Output:

```text
True
True
```

## Newlines do not end statements (pit.newline-is-not-a-statement)

A newline is whitespace. Put `;` between statements; a continuation line can silently join the previous expression.

- Do not: `a = 1; b = 2;`

```fun
var a = 1
  + 2;
?. a;
```
Output:

```text
3
```

## Literals do not decode backslash escapes (pit.backslash-escape)

The literal `'\n'` is a backslash followed by `n`, not a newline. Call `.escape()` to decode it, or use `10.toChar()` or a multiline backtick string.

- Do not: `'a\nb'.escape()`

```fun
?. 'a\nb'.length();
?. 'a\nb'.escape().length();
?. ('a' & 10.toChar() & 'b').length();
```
Output:

```text
4
3
3
```

## Optional chaining is limited (pit.optional-chain)

The form `x?.k?` makes the base and the member optional. It does not make a following call optional, and `f()?.x` is not the JS form; assign to a variable first.

- Do not: `a?.k? only`

```fun
fun pick(o, k) result = o?.k?; end fun;
?. pick(new [k: 7], 'k');
?. pick(nil, 'k') = nil;
```
Output:

```text
7
True
```

## Regex match group access (pit.match-group)

In a match object, `m.@(0)` is the whole match and `m.@('name')` a named group; `m.@@()` is also the whole match. `m.@()` with no argument is not valid.

- Do not: `m.@(0); m.@('group'); m.@@()`

```fun
var m = 'a12'.match(/(\d+)/);
?. m.@(0);
?. m.@(1);
```
Output:

```text
12
12
```

## A missing value also equals zero (pit.missing-key-accumulate)

A missing value compares equal to nil and to 0, so `if x = 0` cannot tell "absent" from "zero". Use `.@has(key)` when presence matters.

- Do not: `m.@has('k')`

```fun
var m = new [];
?. m.k = nil;
?. m.k = 0;
?. m.@has('k');
m.k = 0;
?. m.@has('k');
```
Output:

```text
True
True
False
True
```

## [] is a list, new [] is a map (pit.array-vs-map)

A list literal `[1, 2]` is ordered; `new [a: 1]` is a string-keyed map. Do not use `{}` for either.

- Do not: `[1,2,3] / new [k: v]`

```fun
var xs = [10, 20];
var m = new [a: 10];
?. xs[1];
?. m.a;
```
Output:

```text
20
10
```

## result vs return (pit.return-keyword)

Inside `fun`, assigning `result` sets the return value; `return expr;` returns immediately. A bare `return;` returns the current `result`, which may be stale.

- Do not: `result = expr; or return expr;`

```fun
fun f()
  result = 1;
  return 2;
  result = 3;
end fun;
?. f();
```
Output:

```text
2
```

