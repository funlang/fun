// lib-url: PercentEncode (RFC 3986 unreserved set) and UrlEncode (PHP-style).
//
// The two differ only in the space and tilde rules, so both go through the
// same table; these cases pin the exact byte output for ASCII, reserved
// characters, and UTF-8 text.
use 'fun/lib/lib-url.fun';
use 'fun/lib/uuid.fun';

fun ok(cond, name)
  if cond then
    ?. 'PASS ' & name;
  else
    ?. 'FAIL ' & name;
  end if;
end fun;

//--- PercentEncode: ALPHA / DIGIT / '-' '.' '_' '~' stay literal ---
ok(PercentEncode('') = '', 'empty string');
ok(PercentEncode('AZaz09-._~') = 'AZaz09-._~', 'unreserved set');
ok(PercentEncode(' ') = '%20', 'space is %20');
ok(PercentEncode('a b*~') = 'a%20b%2A~', 'tilde stays literal');
ok(PercentEncode('+/=&?#%') = '%2B%2F%3D%26%3F%23%25', 'reserved set');
ok(PercentEncode('!''()*') = '%21%27%28%29%2A', 'sub-delims and parens');
ok(PercentEncode('中文') = '%E4%B8%AD%E6%96%87', 'UTF-8 text');

//--- UrlEncode: space is '+', and '~' is escaped like PHP urlencode() ---
ok(UrlEncode('') = '', 'url: empty string');
ok(UrlEncode('AZaz09-._~') = 'AZaz09-._%7E', 'url: tilde is escaped');
ok(UrlEncode('a b*~') = 'a+b%2A%7E', 'url: space is +');
ok(UrlEncode('+/=&?#%') = '%2B%2F%3D%26%3F%23%25', 'url: reserved set');
ok(UrlEncode('中文') = '%E4%B8%AD%E6%96%87', 'url: UTF-8 text');

// byte-level path: every UTF-8 byte is percent-encoded exactly once
ok(PercentEncode('é') = '%C3%A9', 'two-byte UTF-8');
ok(PercentEncode('ÿ') = '%C3%BF', 'high-bit byte');

// uuid.fun also keeps a module-level hex table; loading both must not change
// the upper-case escapes above or break UUID's lower-case output.
var u = UUID();
ok(PercentEncode('%') = '%25', 'hex table independent of uuid');
ok(u.length() = 36 and u = u.lower(), 'uuid still loads after lib-url');

//--- UrlParse / UrlBuild ---
var full = 'https://user:pass@example.com:8080/a/b?x=1#frag';
var p = UrlParse(full);
ok(p['scheme'] = 'https', 'parse: scheme');
ok(p['user'] = 'user', 'parse: user');
ok(p['password'] = 'pass', 'parse: password');
ok(p['host'] = 'example.com', 'parse: host');
ok(p['port'] = '8080', 'parse: port');
ok(p['path'] = '/a/b', 'parse: path');
ok(p['query'] = 'x=1', 'parse: query');
ok(p['fragment'] = 'frag', 'parse: fragment');
ok(UrlBuild(p) = full, 'build: full round-trip');

var rel = UrlParse('/a/b?x=1#f');
ok(rel['scheme'].type() = 0 and rel['host'].type() = 0, 'parse: relative');
ok(rel['path'] = '/a/b' and rel['query'] = 'x=1' and rel['fragment'] = 'f', 'parse: relative parts');
ok(UrlBuild(rel) = '/a/b?x=1#f', 'build: relative');

var net = UrlParse('//example.com/a');
ok(net['scheme'].type() = 0 and net['host'] = 'example.com', 'parse: network path');
ok(UrlBuild(net) = '//example.com/a', 'build: network path');

var mail = UrlParse('mailto:user@example.com');
ok(mail['scheme'] = 'mailto' and mail['host'].type() = 0, 'parse: mailto');
ok(mail['path'] = 'user@example.com', 'parse: mailto path');
ok(UrlBuild(mail) = 'mailto:user@example.com', 'build: mailto');

var file = UrlParse('file:///tmp/x');
ok(file['scheme'] = 'file' and file['host'] = '', 'parse: empty host');
ok(file['path'] = '/tmp/x', 'parse: file path');
ok(UrlBuild(file) = 'file:///tmp/x', 'build: file');

var ipv6 = UrlParse('http://[::1]:8080/a');
ok(ipv6['host'] = '::1' and ipv6['port'] = '8080', 'parse: ipv6');
ok(UrlBuild(ipv6) = 'http://[::1]:8080/a', 'build: ipv6');

var q0 = UrlParse('http://x/a?');
var f0 = UrlParse('http://x/a#');
ok(q0['query'].type() = 8 and q0['query'].length() = 0, 'parse: empty query');
ok(f0['fragment'].type() = 8 and f0['fragment'].length() = 0, 'parse: empty fragment');
ok(UrlBuild(q0) = 'http://x/a?' and UrlBuild(f0) = 'http://x/a#', 'build: empty delimiters');

var pct = UrlParse('http://x/a%2Fb?q=%E4%B8%AD');
ok(pct['path'] = '/a%2Fb' and pct['query'] = 'q=%E4%B8%AD', 'parse: keep percent text');
ok(UrlBuild(pct) = 'http://x/a%2Fb?q=%E4%B8%AD', 'build: keep percent text');

var upper = UrlParse('HTTP://EXAMPLE.COM/A');
ok(upper['scheme'] = 'http' and upper['host'] = 'EXAMPLE.COM', 'parse: lower scheme only');

var empty = UrlParse('');
ok(empty['scheme'].type() = 0 and empty['host'].type() = 0 and empty['path'] = '', 'parse: empty url');
ok(UrlBuild(empty) = '', 'build: empty url');
