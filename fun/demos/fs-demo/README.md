# fs-demo

A small filesystem walkthrough: create nested directories, write files, list
and walk them, then write a file atomically and clean up.

```fun
use 'fs.fun';

fs.mkdirAll('demo-out/src/nested');
fs.walk('demo-out', (path, isDir) { ... });
fs.atomicWrite('demo-out/out/result.txt', data);
fs.removeAll('demo-out');
```

Run from this directory with the in-tree interpreter:

```text
../../../src/prj/fun/funcmd src/main.fun
```

The demo creates and removes `demo-out`; it does not modify the repository.
