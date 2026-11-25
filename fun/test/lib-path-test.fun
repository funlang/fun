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

?. PathRel('/a/b', '/a/b/c') = 'c';
?. PathRel('/a/b', '/a/x') = '..' & S & 'x';
?. PathRel('/a', '/b') = '..' & S & 'b';
?. PathRel('/a/b', '/a/b') = '.';

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
  ?. PathRel('C:/a/b', 'C:/a/c') = '..' & S & 'c';
  ?. PathRel('C:/a', 'c:/a/b') = 'b';
  ?. PathRel('C:/a', 'D:/b') = nil;
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
  ?. true;
  ?. true;
  ?. true;
end if;

//--- PathMatch: glob matching without filesystem access ---
?. PathMatch('*.fun', 'a.fun');
?. not PathMatch('*.fun', 'a.txt');
?. PathMatch('*', 'a');
?. not PathMatch('*', 'a' & S & 'b');
?. PathMatch('*/*', 'a' & S & 'b');
?. PathMatch('a?c', 'abc');
?. not PathMatch('a?c', 'a' & S & 'c');
?. PathMatch('[a-c].txt', 'b.txt');
?. not PathMatch('[a-c].txt', 'd.txt');
?. PathMatch('[!a-c].txt', 'd.txt');
?. PathMatch('[^a-c].txt', 'd.txt');
?. not PathMatch('[!a-c].txt', 'b.txt');
?. PathMatch('a*b', 'ab');
?. PathMatch('a*b', 'axxb');
?. not PathMatch('a*b', 'a' & S & 'b');
?. PathMatch('', '');
?. not PathMatch('', 'a');
?. not PathMatch('[abc', 'a');
?. not PathMatch('[z-a]', 'a');
?. PathMatch('[[]', '[');
?. PathMatch('**', 'abc');
?. not PathMatch('**', 'a' & S & 'b');
?. PathMatch('*' & S & '*', 'a' & S & 'b');

if IsWindows() then
  ?. PathMatch('a' & B & '*', 'a' & B & 'b');
  ?. not PathMatch('a' & B & '*', 'a*');
else
  ?. PathMatch('a' & B & '*', 'a*');
  ?. not PathMatch('a' & B, 'a');
end if;

//--- PathMatch: case, empty, classes, invalid patterns ---
?. not PathMatch('A', 'a');
?. not PathMatch('*.FUN', 'a.fun');
?. not PathMatch('[a-z]', 'B');
?. PathMatch('[A-Z]', 'B');
?. PathMatch('[!a-z]', 'B');
?. not PathMatch('[a-Z]', 'b');
?. PathMatch('[B-a]', 'B');
?. PathMatch('[a]', '/') = false;
?. PathMatch('[!a]', '/') = false;
?. PathMatch('?', '/') = false;
?. PathMatch('*', '');
?. not PathMatch('a', '');
?. PathMatch('[]]', ']');
?. PathMatch('[!]]', 'a');
?. PathMatch('[a-]', '-');
?. PathMatch('**/a', 'x/a');
?. not PathMatch('**/a', 'a');
?. PathMatch(nil, nil);
?. PathMatch('*', nil);

if '中'.length() = 3 then
  ?. PathMatch('???', '中');
  ?. not PathMatch('?', '中');
else
  ?. PathMatch('?', '中');
  ?. true;
end if;
