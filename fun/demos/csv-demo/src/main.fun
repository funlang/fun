use '../../../lib/fs.fun';
use '../../../lib/csv.fun';
use '../../../lib/lib-path.fun';

var root = fs.tempDir('fun-csv-demo-');
var p = PathJoin([root, 'users.csv']);

var f = fs.open(p, 'w');
var w = csv.writer(f);
w.write(['name', 'age', 'note']);
w.write(['张三', 30, 'hello, world']);
w.write(['李四', 25, 'say "hi"']);
f.close();

?. 'read:';
var g = fs.open(p, 'r');
var r = csv.reader(g);
loop
  var row = r.read();
  exit when row = nil;
  ?. '  ' & row.@toJson(0, json: true);
end loop;
g.close();

fs.removeAll(root);
