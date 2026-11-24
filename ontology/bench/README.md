# FunBench (seed)

A small, deterministic benchmark for AI-written Fun. It complements the
ontology: the ontology says what is true, FunBench measures whether an agent can
use it.

## Run

From the repository root:

```text
fun ontology/bench/run.fun --all                 # reference solutions: 10/10
fun ontology/bench/run.fun path/to/candidate.fun # one file against all tasks
```

A candidate file may define every task function, or be a single-task solution.
The runner concatenates the candidate and each hidden test, executes it in a
child process with a timeout, and compares stdout byte for byte.

## Tasks

`tasks.fd` is the source. Each task has:

- `id`: stable task id, also the reference solution name;
- `level`: 0 core, 1 common, 2 specialist;
- `prompt`: what the agent sees;
- `tests`: `code` appended after the candidate and exact `expect` output.

The seed has five tasks and ten tests: hello, sum, json-names, word-count and
class-point. Reference solutions are in `solutions/<id>.fun`.

## Scoring

```text
score = passed_tests / total_tests
```

The runner exits non-zero on any failure. It prints the expected and actual
output plus stderr, so a failure is directly actionable.

## Extending

Good benchmark tasks:

- test one concept and one or two pitfalls;
- have a short prompt and hidden tests;
- use only the standard library and no network;
- return deterministic output;
- add a reference solution that passes `--all`.

The next version should track first-shot pass rate, repair turns and token cost
per task, and should keep a private holdout set to avoid overfitting.
