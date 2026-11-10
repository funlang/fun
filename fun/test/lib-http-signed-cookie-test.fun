// http-server signed cookies and the auth util primitives. Booleans only.
use 'fun/lib/http-server.fun';
use 'fun/lib/auth/util.fun';

fun errIs(r, s)
  result = not r['ok'] and ('' & (r['error'] or '')) = s;
end fun;

fun scToken(line)
  var eq = line.subpos('=');
  var semi = line.subpos(';');
  if semi < 0 then semi = line.length(); end if;
  result = line.substr(eq + 1, semi - eq - 1);
end fun;

fun signedReq(token)
  result = signedReqN('uid', token);
end fun;

fun signedReqN(name, token)
  var r = HttpReq();
  r.cookies = new [];
  if token <> nil then r.cookies[name] = token; end if;
  result = r;
end fun;

fun raises(fn)
  var bad = false;
  try
    fn();
  except
    bad = true;
  end try;
  result = bad;
end fun;

var key = 'secret';

// --- HMAC-SHA256: RFC 4231 vectors ---------------------------------------
?. AuthHmacSha256Hex(0x0b.toChar().x(20), 'Hi There') =
  'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7';
?. AuthHmacSha256Hex('Jefe', 'what do ya want for nothing?') =
  '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843';
?. AuthHmacSha256Hex(0xaa.toChar().x(131),
  'Test Using Larger Than Block-Size Key - Hash Key First') =
  '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54';
?. AuthHmacSha256Raw(key, 'abc').length() = 32;

// --- Base64URL -----------------------------------------------------------
?. AuthB64UrlEncode('hello') = 'aGVsbG8';
?. AuthB64UrlDecode('aGVsbG8') = 'hello';
?. AuthB64UrlEncode(0xfb.toChar() & 0xff.toChar()) = '-_8';
?. AuthB64UrlDecode('-_8') = 0xfb.toChar() & 0xff.toChar();
?. AuthB64UrlEncode('') = '';
?. AuthB64UrlDecode('') = '';

var bytes = '';
for i = 0 to 255 do bytes &= i.toChar(); end do;
var enc = AuthB64UrlEncode(bytes);
?. AuthB64UrlDecode(enc) = bytes;
?. enc.subpos('+') < 0 and enc.subpos('/') < 0 and enc.subpos('=') < 0;
?. raises(((){ AuthB64UrlDecode('a+b'); }));
?. raises(((){ AuthB64UrlDecode('a'); }));
?. raises(((){ AuthB64UrlDecode('aGVsbG8='); }));

// --- signed cookies: set and read back -----------------------------------
var res = HttpRes();
res.hdrs = new [];
res.signedCookie('uid', 'u1', key, [path: '/', httpOnly: true, sameSite: 'Lax']);
var line = res.hdrs['set-cookie'];
?. line.substr(0, 4) = 'uid=';
?. line.subpos('; Path=/; HttpOnly; SameSite=Lax') >= 0;
var token = scToken(line);
?. token.subpos('.') > 0;
var got = signedReq(token).signedCookie('uid', key);
?. got['ok'];
?. got['value'] = 'u1';
?. got['error'] = nil;

// --- missing, tampered, wrong key ---------------------------------------
?. errIs(signedReq(nil).signedCookie('uid', key), 'missing cookie');
?. errIs(signedReq(token.substr(0, token.length() - 1) & 'X').signedCookie('uid', key), 'invalid signature');
?. errIs(signedReq(token).signedCookie('uid', 'other'), 'invalid signature');
var tampered = 'z' & token.substr(1);
?. errIs(signedReq(tampered).signedCookie('uid', key), 'invalid signature');

// --- malformed tokens ----------------------------------------------------
?. errIs(signedReq('').signedCookie('uid', key), 'missing cookie');
?. errIs(signedReq('abc').signedCookie('uid', key), 'invalid signed cookie');
?. errIs(signedReq('.').signedCookie('uid', key), 'invalid signed cookie');
?. errIs(signedReq('a.').signedCookie('uid', key), 'invalid signed cookie');
?. errIs(signedReq('a.b.c').signedCookie('uid', key), 'invalid signed cookie');
?. not signedReq('a+b.c').signedCookie('uid', key)['ok'];

// --- empty value, Unicode and special characters ------------------------
var re = HttpRes();
re.hdrs = new [];
re.signedCookie('e', '', key);
var et = scToken(re.hdrs['set-cookie']);
?. et.substr(0, 1) = '.';
var er = signedReqN('e', et).signedCookie('e', key);
?. er['ok'];
?. er['value'].length() = 0;

var rv = '你好 & =;,/' & 0.toChar() & 'ok';
var ru = HttpRes();
ru.hdrs = new [];
ru.signedCookie('v', rv, key);
var ur = signedReqN('v', scToken(ru.hdrs['set-cookie'])).signedCookie('v', key);
?. ur['ok'];
?. ur['value'] = rv;

// --- parameter misuse raises --------------------------------------------
?. raises(((){ var r = HttpRes(); r.hdrs = new []; r.signedCookie('x', 'v', ''); }));
?. raises(((){ var r = HttpRes(); r.hdrs = new []; r.signedCookie('x', 'v', 7); }));
?. raises(((){ var r = HttpRes(); r.hdrs = new []; r.signedCookie('x', 7, key); }));
?. raises(((){ var r = HttpRes(); r.hdrs = new []; r.signedCookie('bad name', 'v', key); }));
?. raises(((){ signedReq(token).signedCookie('uid', ''); }));

// --- constant-time byte compare -----------------------------------------
?. AuthBytesEqual('abc', 'abc');
?. not AuthBytesEqual('abc', 'abd');
?. not AuthBytesEqual('abc', 'ab');
