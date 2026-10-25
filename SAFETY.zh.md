# Fun 内核安全标注清单(Safe Mode,按分支精析)

> 目标:编译期安全构建(`SAFE=... ./make-linux-x86_64.sh`)中,凡触及**危险分支**
> 的内核操作**直接抛 `EBase`**。默认构建不包含这些分支。
> **原则:不打整个内置函数,只打具体危险的"分支/参数"。** 因为同一内置名的默认用法往往是安全的,整函数拦截会误伤合法代码。
>
> 文中 `行号` 以 `src/` 为准。

> **2026-09-14 更新**：本文档的**越界（MEM 类的"分支/参数"）部分已落地**——见
> `art/notes/safety-bounds.md` 与 `port-decisions.md` D21：`s[i]` 读/写、
> `.toByte/.fromByte/.toNum(ptr:)/.movs/.x/.toStr`、`CList.Count/GetItem` 都加了边界校验
> （写越界 raise，读越界给安全默认值）。
>
> **2026-10-25 更新：编译期安全构建已落地并分级。** `SAFE=strict|readonly|
> readwrite|custom ./make-linux-x86_64.sh` 生成独立的 `funcmd-safe`
> （`-dFunSafe` 加 `-dFunSafeAllowRead/Write/Compile`）。严格档拦
> NAT/MEM/FSR/FSW/SRC；只读档放开 FSR；读写档再放开 FSW；`custom` 通过
> `SAFE_ALLOW=read,write,compile` 选择。默认构建与回归基线完全不变。没有
> 运行时 `-safe` 开关：需要安全能力时单独编译。测试见
> `fun/test/safe-mode-test.fun` / `safe-readonly-test.fun` 与
> `fun/test/run-safe-regression.sh`，CI 是独立的 `linux-safe` job，只在
> 手动触发（`safe_only`）时运行。
>
> 作者同日定：
> - **不做 COW**：字符串赋值/传参保持**引用语义**（`b := a; b[i] = x` 改到 `a` 是预期行为）。
> - **`s.move(numDest)` / `toNum(ptr:-1)`** 保留为"不安全内存操作"；安全构建拦
>   `move`，`toNum(ptr:-1)` 只返回字符串地址，单独无法读写，暂不拦。
> - **`movs` 管好**（已加边界）；**超大分配**（`@count(超大)`/`l[超大]`/`.x(超大)`）先放过。
>
> 本文档剩下的 MEM/NAT/FSW 拦截（`s.move(numDest)`、`getapi/@toCallback/COM`）
> 已由 2026-10-25 的编译期安全构建实现。`toNum(ptr:-1)` 与 `toNum(ptr:1/2/3)`
> 保留：前者只把字符串地址当整数返回，后者只读字符串缓冲自身且已有长度校验。

---

## 0. 能力分类(策略可按类单独开/关)

与其"全函数拦截",不如把危险操作按**能力类别**分类,`-safe` 默认拦哪类可单独配置:

| 类 | 能力 | 危险程度 | 严格档 |
|---|---|---|---|
| **NAT** | 本机代码执行(加载 DLL、调用导出函数、生成可执行内存、TCC/JIT/汇编) | 最高 | **拦** |
| **MEM** | 任意内存读写(数值当指针) | 高 | **拦** |
| **FSW** | 文件系统**写/删**(写文件、改名、删除) | 高 | **拦** |
| **FSR** | 文件系统**读**(读文件、列目录、元数据) | 中 | 拦(或仅提示) |
| **SRC** | 动态加载源码 / 代码注入(`compile` 读文件 + `inline`) | 中高 | 拦 |
| **ENV** | 读进程参数 / 全局状态 | 低 | 不拦 |

> 关键:同是 `move`,`s.move(intDest)` 是 **MEM**,而 `f.move(dest)` 是 **FSW**,能力类别不同,不能一刀切。

---

## 1. 具体内置:按分支逐个分析

### 1.1 `move` — `src/lib/libase.pas` `_move`(行 537)

三个分支,能力完全不同:

| 调用形态 | 触发条件(行) | 实际行为 | 类别 | 判定 |
|---|---|---|---|---|
| `s.move(numDest[, len])` | `isNum(e.value)` 行 546 → 548,`Move(q^,p^,...)` 行 553 | `numDest` 当**原始指针**,任意地址写 `len` 字节;若接收者本身是数值,`q := fun.ptr(exp.asInt)` 行 552 → **任意地址读**再写 | MEM | **拦** |
| `f.move(f2)` | `else` 分支 → `CIO.Move` 行 555 | 文件改名 / `f2=null` 时**删除文件** | FSW | **拦** |
| `s.movs(...)` | 见 §1.2 | 字符串目标内的带边界移动 | — | **不拦** |

### 1.2 `movs` — `_movs`(行 560)

`movs` 是 `move` 的安全版本，设计上**只接受字符串目标**。
**已有边界检查**(越界 `raise 'out of bounds'`)。
- `dest` 不是字符串时直接返回，不写内存，也不把数值当指针解引用。
- 判定:**不拦**。真正的任意地址写只有 `move` 的数值分支。

### 1.3 `toNum` — `_toNum`(行 641)

`ptr` 参数决定行为:

| `ptr` | 行为(行) | 类别 | 判定 |
|---|---|---|---|
| `0`(默认) | `CParser.StrToNum(exp.value^)` 行 652 字符串→数 | — | **安全** |
| `-1` | `PData(exp.value).VInteger` 行 657 读整型位模式 | MEM(弱) | 提示 |
| `1/2/3` | 把**接收者自己的字符串缓冲**当 `int/single/double` 读，长度不足返回 0 | MEM(弱) | **不拦**（有长度校验，不能越界） |

### 1.4 `fromByte` / `toByte` — `_fromByte`、`_toByte`

- `fromByte`:向**接收者自己的字符串缓冲** `i` 偏移写字节，已有
  `(i < 0) or (i >= Length(s))` 检查。它不是任意地址写，和 `s[i] = c` 同级。
  判定:**不拦**。
- `toByte`:仅 `s[1+pos]` 读字符串缓冲，越界返回 #0。判定:**不拦**。

> 这两项曾被旧清单按 MEM 拦，属于限制过度。真正的任意地址写只有
> `move` 的**数值目标**；`movs` 只写字符串目标。

### 1.5 `eval` — `_eval`(行 344)

**只是字符串内 `$id` 变量展开**(`e := exp.UID(v); v := e.asStr` 行 371–374),类似 shell `$VAR`,**不是代码执行**。
- 类别:ENV(读取变量值)。判定:**默认安全**,不要拦。

### 1.6 `compile` — `_compile`(行 777)

两个入口,能力不同:
- `FileExists(fn)` → `CParser.ParseOrLoad(fn,...)` 行 790–791:**读文件**并解析(FSR/SRC)。
- 否则 `CParser.Parse(s,...)` 行 793:纯解析字符串(安全)。
- `inline:true` 时挂入当前作用域(行 795,可被随后执行 → 代码注入)。
- 判定:拦"读文件"与"inline 注入"两个分支;纯 `compile(字符串)` 可不拦。

### 1.7 文件系统家族 — `_load`、`_save`、`_copy`、`_find`、`_hash`、`_size`、`_time`

- 读类:`load/find/hash/size/time(读)` → **FSR**。
- 写类:`save`、`copy`、`move(文件)`、`time(set:)` → **FSW**。
- `hash` 读取完整文件内容后返回摘要：`f.hash()` 是 MD5（32 位十六进制），
  `f.hash(1)` 是 SHA1（40 位）。它仍会读文件内容，按 FSR 处理；摘要不能还原
  内容，但可做内容匹配/存在性探测。
- `size` 在 Unix 已改为 `stat`（不再 open/seek），Windows 用
  `FindFirstFile`，两者都是纯 metadata 读取。
- `time` 的 `set` 参数会调用 `SetFileTime`/`FileSetDate`，所以必须按写能力
  单独判断；`set` 为 0 或省略时才是读。
- 判定:按 FSR/FSW 策略拦。`find` 会遍历目录、泄露文件结构，读类中偏重。

### 1.8 `arg` / `set` / `random` — `_arg`(70)、`_set`(80)、`_random`(115)

- `arg` 读 `ParamStr`(行 75):ENV,泄露宿主参数。判定**默认不拦**(沙箱可提示)。
- `set('defaultCodePage',...)`(行 82):改全局编码。ENV 全局状态。低危。
- `random(-1, seed)`(行 124–128):改写 `RandSeed`。低危。
- 判定:三者**均不拦**(除非开严格沙箱)。

---

## 2. 本机代码执行层(类别 NAT,基本必拦)

| 入口 | 位置 | 行为 |
|---|---|---|
| `getapi` | `winapi.pas` `_getapi` 行 87 | `LoadLib(name)`(行 99)+ `GetProc`(行 114)→ 拿到任意 DLL 任意导出函数指针 |
| `CWinFun.call` | `winapi.pas` 行 167–272 | `asm push ret / call CWinAPI(hfun)`(行 243–249)**原始机器码调用**任意函数 |
| `@toCallback` / `@toEvent` | `winapi.pas` `_toCallback` 行 122;`host.pas` CLfun 行 223–232 | 生成可执行回调 |
| `CCallback.GetProc` | `winapi.pas` 行 285 | `VirtualAlloc(..., PAGE_EXECUTE_READWRITE)` 分配可执行内存并写机器码 |
| `NewObj`(COM) | `winole.pas` | 创建 / 调用任意 COM 对象 |

**放大层**(自我宿主库,底层依赖上面原语,连锁抛异常即预期):`lib-tcc.fun`、`lib-jit.fun`、`lib-asm-pro.fun`、`lib-asm.fun`、`lib-winapi.fun`、`lib-winsock.fun`、`lib-registry.fun`、`lib-zlib.fun`。

> 注意:NAT 类确实"整个内置都危险"(getapi 没有安全用法),但它的个数少、边界清晰,与"打击面大"是两回事——被误伤的通常是 MEM 类的共享内置名,见 §1。

---

## 3. 解释器内核路径(不走 `CLib.call`,需单独挂钩)

`src/core/core.pas`:
- `CIdx.done`:字符串索引赋值 `s[i]=x`,浮点下标分支写字符串缓冲内的一个字节,
  前面已有 `(i < 0) or (i >= Length(s))` 检查。类别 MEM(弱,限界内)。
- `CIdx.find`(行 1522–1543):字符串索引**读**字节(`s[i+1]`、`div/mod 256`)。类别 MEM(弱)。

`CIdx.done` 的浮点下标分支仍在 `(i < 0) or (i >= Length(s))` 检查之后，最多
写到字符串的终止字节，不构成任意地址写。它和 `fromByte` 一样属于**限界内的
字符串字节写**，因此安全构建不拦。`CIdx.find` 是限界内读，不拦。

---

## 4. 判定汇总表(建议)

| 内置 / 分支 | 触发条件 | 类别 | `-safe` |
|---|---|---|---|
| `move` 数值分支 | `dest`/接收者为数值 | MEM | 拦 |
| `move` 文件分支 | `dest` 为字符串 | FSW | 拦 |
| `movs` | `dest` 为数值 | — | 不拦（被忽略） |
| `toNum` | `ptr∈{1,2,3}` | MEM(弱) | 不拦（仅缓冲内重解释） |
| `toNum` | `ptr=0/-1` | — | 不拦 |
| `fromByte` | 任意 | MEM(弱，限界内) | 不拦 |
| `toByte` | 任意(读) | — | 不拦 |
| `eval` | 任意 | ENV | **不拦** |
| `compile` | 文件加载 / `inline` | SRC | 拦 |
| `load/find/hash/size/time(读)` | 任意 | FSR | 拦（只读档放开） |
| `save/copy/move(文件)/time(set)` | 任意 | FSW | 拦（读写档放开） |
| `getapi` / `@toCallback` / COM `NewObj` | 任意 | NAT | 拦 |
| `use` 外部路径 | 不在脚本目录/cwd/lib/app/FUN_PATH 下 | SRC | 拦（`compile` 档放开） |
| `CIdx.done` 字节写 | 浮点下标赋值 | MEM(弱，限界内) | 不拦 |

---

## 5. 实现方式

实际实现放弃了运行时 `SafeRun` 开关，改为**编译期分支**：

1. 危险分支包在 `{$IfDef FunSafe}` 里，默认构建直接不生成这些检查。
2. 能力档位用编译期宏控制：`FunSafeAllowRead`、`FunSafeAllowWrite`、
   `FunSafeAllowCompile`。构建脚本把 `SAFE=...` 映射到这些宏。
3. 统一用 `SafeDeny()`（`src/core/base.pas`）抛 `EBase`，错误以
   `safe mode: ...` 开头，脚本可以 `try/except` 捕获。
4. 普通构建和 safe 构建使用不同的 FPC 单元输出目录（`units/` 与
   `units-safe/`），避免互相复用定义不同的 `.ppu`。

---

## 6. 验收

- 普通模式行为不变(回归全过,含 `test-jit-cb.fun`)。
- 安全构建（`funcmd-safe`）下:
  - `'abc'.move(123456)`、`getapi` → 抛;
  - `'ab'.fromByte(0, 65)`、`'abcd'.toNum(ptr:1)` → 不抛（限界内）;
  - `'123'.toNum()`、`'$name'.eval()`、`f.move(f2)`(如仍允许文件则可)按策略;
  - `getapi`、`lib-tcc/lib-jit/lib-asm` 路径 → 抛;
  - 纯数据处理(JSON/FD、字符串、集合、正则)不受影响。

## 7. 实现方式(2026-10-25)

没有运行时开关。`-dFunSafe` 把拦截写进编译产物，危险分支在 safe 二进制里
只剩 `SafeDeny`（`src/core/base.pas`）。默认构建不包含这些分支，所以行为与
性能都不变。

```sh
cd src/prj/fun
SAFE=strict ./make-linux-x86_64.sh   # 产出 funcmd-safe（默认严格档）
fun/test/run-safe-regression.sh strict

SAFE=readonly ./make-linux-x86_64.sh # 放开文件读
fun/test/run-safe-regression.sh readonly

SAFE=readwrite ./make-linux-x86_64.sh # 再放开文件写
SAFE=custom SAFE_ALLOW=read,write,compile ./make-linux-x86_64.sh
```

档位与宏：

| `SAFE=` | 放开的宏 | FSR | FSW | SRC | NAT | MEM |
|---|---|---|---|---|---|---|
| `strict` / `1` | 无 | 拦 | 拦 | 拦 | 拦 | 拦 |
| `readonly` | `FunSafeAllowRead` | 放 | 拦 | 拦 | 拦 | 拦 |
| `readwrite` | `Read` + `Write` | 放 | 放 | 拦 | 拦 | 拦 |
| `custom` | `SAFE_ALLOW` | 可选 | 可选 | 可选 | 拦 | 拦 |

落点：

- `src/lib/libase.pas`：`move` 数值分支、`compile(文件/inline)`、
  `load/find/hash/size/time`、`save/copy/move(文件)`。
- `src/lib/lffi.pas` / `winapi.pas` / `winole.pas`：`getapi`、`@toCallback`、
  COM `NewObj` / `@toEvent`。
- `src/lib/host.pas`：`getlib`。
- `src/parse/parse.pas`：`use` 路径限制（脚本目录、cwd、解释器 lib/app、
  `FUN_PATH`；`FunSafeAllowCompile` 时放开）。
- `src/core/io.pas`：Unix `size` 改用 `stat`。

`SAFE` 目前只接在 Linux 构建脚本上；拦截本身是平台无关的编译条件，后续
需要时可在 macOS/Windows 构建脚本里加同一组 `-dFunSafe*` 宏。
