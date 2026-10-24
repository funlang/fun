// lib-path: lexical path helpers. Expected values use HostSep() so the same
// snapshot holds on POSIX and Windows; Windows-only cases run conditionally.
use 'fun/lib/lib-path.fun';
use 'fun/lib/lib-host.fun';

var S = HostSep();
var B = 92.toChar();

?. PathJoin(['a', 'b']) = 'a' & S & 'b';
?. PathJoin(['a', '', 'b']) = 'a' & S & 'b';
?. PathJoin([]) = '';
?. PathJoin(['/a', 'b']) = S & 'a' & S & 'b';
?. PathJoin(['a', '/b']) = 'a' & S & 'b';
?. PathJoin(['a/', 'b']) = 'a' & S & 'b';

?. PathClean('a//b/./c/../d') = 'a' & S & 'b' & S & 'd';
?. PathClean('') = '.';
?. PathClean('/') = S;
?. PathClean('a/../../b') = '..' & S & 'b';
?. PathClean('a/..') = '.';

?. PathDir('a') = '.';
?. PathDir('a/b') = 'a';
?. PathDir('a/b/') = 'a' & S & 'b';
?. PathDir('/a') = S;

?. PathBase('') = '.';
?. PathBase('a/b/') = 'b';
?. PathBase('/') = S;

?. PathExt('a/b.txt') = '.txt';
?. PathExt('.bashrc') = '.bashrc';
?. PathExt('a/b') = '';

?. PathIsAbs(HostFullPath('.')) = true;
?. PathIsAbs('a') = false;

?. PathToSlash('a' & B & 'b') = 'a/b';
?. PathFromSlash('a/b') = 'a' & S & 'b';

if IsWindows() then
  ?. PathClean('C:/a/../b') = 'C:' & S & 'b';
  ?. PathClean('//server/share/a/../b') = S & S & 'server' & S & 'share' & S & 'b';
  ?. PathJoin(['C:/', 'x']) = 'C:' & S & 'x';
  ?. PathDir('C:/a/b') = 'C:' & S & 'a';
  ?. PathDir('C:/a') = 'C:' & S;
  ?. PathDir('C:/') = 'C:' & S;
  ?. PathDir('//server/share/a') = S & S & 'server' & S & 'share' & S;
  ?. PathIsAbs('C:/a') = true;
  ?. PathIsAbs('/a') = false;
  ?. PathIsAbs('C:a') = false;
  ?. PathIsAbs(B & 'a') = false;
  ?. PathToSlash('C:' & S & 'a') = 'C:/a';
  ?. PathFromSlash('C:/a') = 'C:' & S & 'a';
else
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
end if;
