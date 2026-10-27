use '../../../lib/fs.fun';
use '../../../lib/lib-path.fun';

fun showWalk(p, isDir)
  if isDir then
    ?. '  DIR  ' & p;
  else
    ?. '  FILE ' & p;
  end if;
end fun;

var root = 'demo-out';
fs.removeAll(root);
?. fs.mkdirAll(PathJoin([root, 'src', 'nested']));
PathJoin([root, 'src', 'hello.fun']).save('?. "hello";' & 10.toChar());
PathJoin([root, 'src', 'nested', 'data.txt']).save('data');

?. 'list:';
var names = fs.list(root);
for i = 0 to names.@count() - 1 do
  ?. '  ' & names[i];
end do;

?. 'walk:';
fs.walk(root, showWalk);

?. 'atomic:';
?. fs.atomicWrite(PathJoin([root, 'out', 'result.txt']), 'ok' & 10.toChar());
?. PathJoin([root, 'out', 'result.txt']).load();

fs.removeAll(root);
