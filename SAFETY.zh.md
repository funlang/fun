# Fun 内核安全标注清单(Safe Mode,按分支精析)

> 目标:未来以 `fun.exe -safe ...` 启动时,凡触及**危险分支**的内核操作**直接抛 `EBase`**。
> **原则:不打整个内置函数,只打具体危险的"分支/参数"。** 因为同一内置名的默认用法往往是安全的,整函数拦截会误伤合法代码。
>
> 文中 `行号` 以 `src/` 为准。

> **2026-09-14 更新**：本文档的**越界（MEM 类的"分支/参数"）部分已落地**——见
> `art/notes/safety-bounds.md` 与 `port-decisions.md` D21：`s[i]` 读/写、
> `.toByte/.fromByte/.toNum(ptr:)/.movs/.x/.toStr`、`CList.Count/GetItem` 都加了边界校验
> （写越界 raise，读越界给安全默认值）。
>
> **2026-10-25 更新：编译期安全构建已落地。** `SAFE=1 ./make-linux-x86_64.sh`
> 生成独立的 `funcmd-safe`（`-dFunSafe`），下面列出的 NAT/MEM/FSR/FSW/SRC
> 拦截点在该二进制中生效；默认构建与回归基线完全不变。没有运行时 `-safe`
> 开关，也没有等级或权限列表：需要安全能力时单独编译。测试见
> `fun/test/safe-mode-test.fun` 与 `fun/test/run-safe-regression.sh`，CI 是
> 独立的 `linux-safe` job，默认不跑完整回归。
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

| 类 | 能力 | 危险程度 | `-safe` 默认 |
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
| `s.movs(...)` | 见 §1.2 | 字符串缓冲内带边界移动 | MEM(弱) | 见 1.2 |

### 1.2 `movs` — `_movs`(行 560)

在字符串 `s` 与目标 `d` 之间做内存移动。**已有边界检查**(行 581,越界 `raise 'out of bounds'`)。
- 类别:MEM,但目标 `d` 来自 `PData(ed.value).VInteger`(行 571)——即 `dest` 若是**数值**,就是任意地址读。
- 判定:默认用法(`dest` 为字符串)基本安全;`dest` 为**数值**时按 MEM 拦。

### 1.3 `toNum` — `_toNum`(行 641)

`ptr` 参数决定行为:

| `ptr` | 行为(行) | 类别 | 判定 |
|---|---|---|---|
| `0`(默认) | `CParser.StrToNum(exp.value^)` 行 652 字符串→数 | — | **安全** |
| `-1` | `PData(exp.value).VInteger` 行 657 读整型位模式 | MEM(弱) | 提示 |
| `1/2/3` | 把**接收者自己的字符串缓冲**当 `int/single/double` 读，长度不足返回 0 | MEM(弱) | **不拦**（有长度校验，不能越界） |

### 1.4 `fromByte` / `toByte` — `_fromByte`(行 698)、`_toByte`(行 683)

- `fromByte`:`p := fun.ptr(s); Inc(p,i); p^ := j` 行 707–709 —— 向字符串缓冲 `i` 偏移**写字节**;`i` 越界即缓冲溢出。类别:MEM,判定**拦**。
- `toByte`:仅 `s[1+pos]` 读字符(行 692)。**读**,越界读返回 #0/越界访问,低危。判定**默认安全**(可加边界校验)。

### 1.5 `eval` — `_eval`(行 344)

**只是字符串内 `$id` 变量展开**(`e := exp.UID(v); v := e.asStr` 行 371–374),类似 shell `$VAR`,**不是代码执行**。
- 类别:ENV(读取变量值)。判定:**默认安全**,不要拦。

### 1.6 `compile` — `_compile`(行 777)

两个入口,能力不同:
- `FileExists(fn)` → `CParser.ParseOrLoad(fn,...)` 行 790–791:**读文件**并解析(FSR/SRC)。
- 否则 `CParser.Parse(s,...)` 行 793:纯解析字符串(安全)。
- `inline:true` 时挂入当前作用域(行 795,可被随后执行 → 代码注入)。
- 判定:拦"读文件"与"inline 注入"两个分支;纯 `compile(字符串)` 可不拦。

### 1.7 文件系统家族 — `_load`(454)、`_save`(475)、`_copy`(523)、`_find`(496)、`_hash`(448)、`_size`(440)、`_time`(401)

- 读类:`load/find/hash/size/time(文件)` → **FSR**。
- 写类:`save`、`copy`、`move(文件)` → **FSW**。
- 判定:按 FSR/FSW 策略拦。`find` 会遍历目录、泄露文件结构,读类中偏重。

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
- `CIdx.done`(行 1471–1483):字符串索引赋值 `s[i]=x`,浮点下标分支执行 `PByte(p)^ := fun.byte(...)`(行 1479)/ `(s+i)^ := ...` —— **原始字节写**。类别 MEM,**拦**。
- `CIdx.find`(行 1522–1543):字符串索引**读**字节(`s[i+1]`、`div/mod 256`)。类别 MEM(弱)。

这两处无内置名可查,`-safe` 需在 `done`/`find` 加检查。

---

## 4. 判定汇总表(建议)

| 内置 / 分支 | 触发条件 | 类别 | `-safe` |
|---|---|---|---|
| `move` 数值分支 | `dest`/接收者为数值 | MEM | 拦 |
| `move` 文件分支 | `dest` 为字符串 | FSW | 拦 |
| `movs` | `dest` 为数值 | MEM | 拦 |
| `toNum` | `ptr∈{1,2,3}` | MEM(弱) | 不拦（仅缓冲内重解释） |
| `toNum` | `ptr=0/-1` | — | 不拦 |
| `fromByte` | 任意 | MEM | 拦 |
| `toByte` | 任意(读) | — | 不拦 |
| `eval` | 任意 | ENV | **不拦** |
| `compile` | 文件加载 / `inline` | SRC | 拦 |
| `load/find/hash/size/time` | 任意 | FSR | 拦 |
| `save/copy/move(文件)` | 任意 | FSW | 拦 |
| `getapi` / `@toCallback` / COM `NewObj` | 任意 | NAT | 拦 |
| `CIdx.done` 字节写 | 浮点下标赋值 | MEM | 拦 |

---

## 5. 实现建议(最小改动)

1. `fun.pas` 加全局 `SafeRun: Boolean`;`fun.exe`(`funcmd.dpr`)解析 `-safe`。
2. 因拦截点细化到**分支**,在 `CLib.call`(host.pas 行 209)处加一个**回调钩子**最灵活:
   ```pascal
   // CLib 增加: unsafeAttr: CHash  // id -> bitmask 类别
   // 及一个 virtual: procedure SafeGuard(id; attr; exp; exps); 
   // 默认空;CEnv2 在 SafeRun 时对 MEM/NAT/FSW 类别抛 EBase。
   ```
   内置在入口判断具体参数(如 `toNum` 的 `ptr`、`move` 的 `isNum(dest)`),**再决定是否抛**。这比"按 id 一刀切"精准。
3. `core.pas` `CIdx.done`/`CIdx.find` 字节分支同样在 `SafeRun` 时抛 `ESafe`。
4. 异常统一继承 `EBase` 的子类 `ESafe`,便于 `try/catch` 区分。

---

## 6. 验收

- 普通模式行为不变(回归全过,含 `test-jit-cb.fun`)。
- 安全构建（`funcmd-safe`）下:
  - `'abc'.move(123456)`、`'ab'.fromByte(5, 65)` → 抛;
  - `'123'.toNum()`、`'$name'.eval()`、`f.move(f2)`(如仍允许文件则可)按策略;
  - `getapi`、`lib-tcc/lib-jit/lib-asm` 路径 → 抛;
  - 纯数据处理(JSON/FD、字符串、集合、正则)不受影响。

## 7. 实现方式(2026-10-25)

没有运行时开关。`-dFunSafe` 把拦截写进编译产物，危险分支在 safe 二进制里
只剩 `SafeDeny`（`src/core/base.pas`）。默认构建不包含这些分支，所以行为与
性能都不变。

```sh
cd src/prj/fun
SAFE=1 ./make-linux-x86_64.sh        # 产出 funcmd-safe，不覆盖 funcmd
fun/test/run-safe-regression.sh      # 只跑 safe 能力测试
```

落点：

- `src/lib/libase.pas`：`move`、`movs(数值目标)`、`fromByte`、
  `compile(文件/inline)`、`load/find/hash/size/time(文件)`、`save/copy/move(文件)`。
- `src/lib/lffi.pas` / `winapi.pas` / `winole.pas`：`getapi`、`@toCallback`、
  COM `NewObj` / `@toEvent`。
- `src/core/core.pas`：`CIdx.done` 的浮点下标字节写。

`SAFE=1` 目前只接在 Linux 构建脚本上；拦截本身是平台无关的编译条件，后续
需要时可在 macOS/Windows 构建脚本里加同一个 `-dFunSafe`。
