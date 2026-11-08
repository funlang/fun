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
