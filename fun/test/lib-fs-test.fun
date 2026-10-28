// fs: directory, walk, temp and atomic-write behavior. Paths stay local to a
// temporary fixture; the snapshot contains booleans only.
use 'fun/lib/fs.fun';
use 'fun/lib/lib-host.fun';

var _fsWalked = new [];
var _fsWalkedLinks = new [];

fun collectWalk(p, isDir)
  _fsWalked.@add(p);
end fun;

fun collectWalkLinks(p, isDir)
  _fsWalkedLinks.@add(p);
end fun;

fun makeLink(target, link)
  var f = LibC().getapi('symlink', 'ss:i');
  result = f(target, link) = 0;
end fun;

fun _fsHasItem(xs, v)
  result = false;
  for i = 0 to xs.@count() - 1 do
    if xs[i] = v then result = true; return; end if;
  end do;
end fun;

var root = fs.tempDir('fun-fs-test-');

?. root <> nil;
?. fs.isDir(root);
?. fs.mkdirAll(PathJoin([root, 'a', 'b']));
?. fs.isDir(PathJoin([root, 'a', 'b']));
?. fs.mkdirAll(PathJoin([root, 'a', 'b']));

PathJoin([root, 'file.txt']).save('x');
PathJoin([root, 'a', 'child.txt']).save('y');

var names = fs.list(root);
?. names.@count() = 2;
?. names[0] = 'a';
?. names[1] = 'file.txt';

?. fs.isFile(PathJoin([root, 'file.txt']));
?. fs.isDir(PathJoin([root, 'file.txt'])) = false;
?. fs.exists(root & '/missing') = false;
?. fs.list(root & '/missing').@count() = 0;
?. fs.list('').@count() = 0;
?. fs.list(nil).@count() = 0;
?. fs.list(PathJoin([root, 'file.txt'])).@count() = 0;

fs.walk(root, collectWalk);
?. _fsWalked.@count() = 4;
?. fs.walk(root & '/missing', collectWalk) = false;

?. fs.mkdirAll(PathJoin([root, 'file.txt'])) = false;
?. fs.atomicWrite(PathJoin([root, 'new', 'sub', 'atomic.txt']), 'hello');
?. PathJoin([root, 'new', 'sub', 'atomic.txt']).load() = 'hello';
?. fs.atomicWrite(PathJoin([root, 'new', 'sub', 'atomic.txt']), 'hi');
?. PathJoin([root, 'new', 'sub', 'atomic.txt']).load() = 'hi';
var zeroPath = PathJoin([root, 'new', 'sub', 'zero.txt']);
?. fs.atomicWrite(zeroPath, '0');
?. zeroPath.load() = '0';
?. fs.atomicWrite(zeroPath, 0);
?. zeroPath.load() = '0';
fs.removeAll(zeroPath);
?. fs.atomicWrite('', 'x') = false;
?. fs.atomicWrite(PathJoin([root, 'new']), 'x') = false;
?. fs.isDir(PathJoin([root, 'new']));
?. fs.list(root).@count() = 3;

?. fs.removeAll(PathJoin([root, 'a']));
?. fs.exists(PathJoin([root, 'a'])) = false;
?. fs.removeAll(root & '/missing') = true;

var outside = fs.tempDir('fun-fs-test-');
fs.mkdirAll(PathJoin([outside, 'target']));
PathJoin([outside, 'target', 'keep.txt']).save('keep');
var linkDir = PathJoin([root, 'linkdir']);
var linkFile = PathJoin([root, 'linkfile']);
var brokenLink = PathJoin([root, 'broken']);

if IsWindows() then
  ?. true;
  ?. true;
  ?. true;
  ?. true;
  ?. true;
  ?. true;
  ?. true;
  ?. true;
  ?. true;
  ?. true;
  ?. true;
  ?. true;
  ?. true;
  ?. true;
  ?. true;
  ?. true;
  ?. true;
  ?. true;
else
  ?. makeLink(PathJoin([outside, 'target']), linkDir);
  ?. fs.isDir(linkDir);
  ?. fs.walk(linkDir & HostSep(), collectWalkLinks) = false;
  ?. fs.atomicWrite(linkDir, 'x') = false;
  ?. _fsHasItem(fs.list(root), 'linkdir');
  fs.walk(root, collectWalkLinks);
  ?. _fsWalkedLinks.@count() = 5;
  ?. not _fsHasItem(_fsWalkedLinks, PathJoin([outside, 'target', 'keep.txt']));
  ?. fs.removeAll(linkDir & HostSep());
  ?. not _fsHasItem(fs.list(root), 'linkdir');
  ?. fs.exists(PathJoin([outside, 'target', 'keep.txt']));
  ?. makeLink(PathJoin([root, 'file.txt']), linkFile);
  ?. fs.removeAll(linkFile);
  ?. not _fsHasItem(fs.list(root), 'linkfile');
  ?. fs.isFile(PathJoin([root, 'file.txt']));
  ?. makeLink(PathJoin([root, 'missing']), brokenLink);
  ?. _fsHasItem(fs.list(root), 'broken');
  ?. fs.removeAll(brokenLink);
  ?. not _fsHasItem(fs.list(root), 'broken');
end if;

?. fs.removeAll(outside);
?. fs.exists(outside) = false;

var tf = fs.tempFile('fun-fs-test-');
?. tf <> nil;
?. fs.isFile(tf);
?. fs.removeAll(tf);
?. fs.exists(tf) = false;

var tf2 = fs.tempFile('fun-fs-test-');
?. tf2 <> nil;
?. tf2 <> tf;
?. fs.removeAll(tf2);

var td = fs.tempDir('fun-fs-test-');
?. td <> nil;
?. fs.isDir(td);
?. fs.list(td).@count() = 0;
?. fs.removeAll(td);
?. fs.exists(td) = false;

var td2 = fs.tempDir('fun-fs-test-');
?. td2 <> nil;
?. td2 <> td;
?. fs.removeAll(td2);

var udir = fs.tempDir('fun-fs-test-');
?. fs.atomicWrite(PathJoin([udir, '中文.txt']), 'u');
?. _fsHasItem(fs.list(udir), '中文.txt');
?. fs.isFile(PathJoin([udir, '中文.txt']));
?. fs.removeAll(udir);
?. fs.exists(udir) = false;

if IsWindows() then
  ?. true;
else
  ?. makeLink(PathJoin([root, 'missing']), PathJoin([root, 'tree-broken']));
end if;

?. fs.removeAll(root);
?. fs.exists(root) = false;
