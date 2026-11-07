# clone/new hot-path benchmark

Measures the `CSet.clone` / `CSet2.calc` path used by `new [...]`, `a.@clone()`
and nested collection copies. The fix adds an ancestor stack to keep cycles
inside the copy, so the benchmark is the normal acyclic path where the only
change is the extra stack checks.

## Workload

`fun/demos/benchmarks/clone-bench.fun`, 100000 iterations. Each iteration
builds a set with a nested list, then a second set that clones the first:

```fun
var a = new [x: i, y: i + 1, z: [i, i + 1]];
var b = new [a: a, c: [i, i + 1]];
acc += b.a.x + b.c[0];
```

Checksum: `10000100000` on every run.

## How to reproduce

```sh
RUNS=7 FUNCMD=/path/to/baseline/funcmd fun/demos/benchmarks/run-clone-bench.sh
RUNS=7 FUNCMD=./fun/funcmd                 fun/demos/benchmarks/run-clone-bench.sh
```

The runner prints each run, the minimum, and the median. Use the same machine
and `RUNS` for both binaries.

## Environment

- Linux x86_64, Intel Xeon Platinum 8255C @ 2.50 GHz (Tencent Cloud CVM)
- Free Pascal 3.2.2, `-O2`
- Baseline: `funcmd` built before the clone-context change
- Fixed: `funcmd` with the `CEnv` clone ancestor stack

## Results (7 runs each)

| Binary | Min | Median | Delta vs baseline (min / median) |
|---|---:|---:|---:|
| baseline | 741.599 ms | 745.903 ms | - |
| fixed (ancestor stack) | 760.929 ms | 774.094 ms | +2.6% / +3.8% |

Raw baseline: 804.80, 745.90, 742.12, 745.01, 784.58, 749.07, 741.60 ms.

Raw fixed: 765.80, 774.09, 785.82, 760.93, 969.93, 797.29, 765.99 ms (one
outlier; min/median above).

## Rejected first attempt

The first implementation used a `CRefHash` keyed by object pointer for the
ancestor map. It was correct but about 2x slower on this workload (baseline
742 ms min, hash version 1479 ms min): one hash allocation per `new`, plus a
string key allocation and hash lookup per cloned set. Replacing it with a
per-`CEnv` dynamic ancestor stack removed the allocations and brought the
overhead down to the ~3% range.

## Correctness coverage

`fun/test/clone-cycle-test.fun` (snapshotted by the regression runner) covers:

- self-referencing set copied with `new [input: a]`
- nested cycles
- cyclic list
- object self-reference
- shared acyclic reference copied twice
- `a.@clone()` on a cyclic set
- cycle serialization as `"(Object)"`

The clone keeps the cycle inside the copy: mutating the copy does not affect
the source, and the copied cycle points at the copy.
