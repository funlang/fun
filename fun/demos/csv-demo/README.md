# csv-demo

A small streaming CSV walkthrough: write rows to a temporary file with
`csv.writer`, read them back with `csv.reader`, and clean up.

```fun
use 'csv.fun';

var g = fs.open('users.csv', 'w');
var w = csv.writer(g);
w.write(['name', 'age', 'note']);
g.close();

var f = fs.open('users.csv', 'r');
var r = csv.reader(f);
var row = r.read();
while row <> nil do ... row = r.read(); end do;
f.close();
```

Run from this directory with the in-tree interpreter:

```text
../../../src/prj/fun/funcmd src/main.fun
```

The demo creates a temporary directory via `fs.tempDir` and removes it; it
does not modify the repository.
