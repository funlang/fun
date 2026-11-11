// jwt: HS256/384/512, claims, malformed tokens. Booleans only.
use 'fun/lib/jwt.fun';
use 'fun/lib/auth/util.fun';

fun errHas(r, s)
  result = not r['ok'] and ('' & (r['error'] or '')).subpos(s) >= 0;
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

fun tamperLast(s)
  var c = s[s.length() - 1];
  var d = 'X';
  if c = 'X' then d = 'Y'; end if;
  result = s.substr(0, s.length() - 1) & d;
end fun;

var secret = 'secret';

// --- HMAC-SHA256/384/512: RFC 4231 vectors -------------------------------
var k = 0x0b.toChar().x(20);
?. AuthHmacHex(k, 'Hi There', 'sha256') =
  'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7';
?. AuthHmacHex(k, 'Hi There', 'sha384') =
  'afd03944d84895626b0825f4ab46907f15f9dadbe4101ec682aa034c7cebc59cfaea9ea9076ede7f4af152e8b2fa9cb6';
?. AuthHmacHex(k, 'Hi There', 'sha512') =
  '87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854';

// --- known HS256 token ----------------------------------------------------
var known = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';
var kr = jwt.verify(known, 'your-256-bit-secret', [now: 1516239023]);
?. kr['ok'];
?. kr['claims']['sub'] = '1234567890';
?. kr['claims']['name'] = 'John Doe';
?. not jwt.verify(known, 'wrong-secret', [now: 1516239023])['ok'];

// --- sign/verify round-trip for all HMAC algorithms ----------------------
var t256 = jwt.sign([sub: 'u1', exp: 2000000000], secret);
?. jwt.verify(t256, secret)['ok'];
?. jwt.verify(t256, secret)['claims']['sub'] = 'u1';
var t384 = jwt.sign([sub: 'u1', exp: 2000000000], secret, [alg: 'HS384']);
?. jwt.verify(t384, secret)['ok'];
var t512 = jwt.sign([sub: 'u1', exp: 2000000000], secret, [alg: 'HS512']);
?. jwt.verify(t512, secret)['ok'];
?. not jwt.verify(t512, secret, [algorithms: ['HS256']])['ok'];
?. jwt.verify(t256, secret, [algorithms: 'HS256'])['ok'];

// --- tamper and decode ----------------------------------------------------
var badSig = tamperLast(t256);
?. not jwt.verify(badSig, secret)['ok'];
var p1 = t256.subpos('.');
var badPayload = t256.substr(0, p1 + 1) & 'x' & t256.substr(p1 + 2);
?. not jwt.verify(badPayload, secret)['ok'];
?. jwt.decode(badPayload)['ok'];
?. jwt.decode(t256)['claims']['sub'] = 'u1';
?. jwt.decode(t256)['header']['typ'] = 'JWT';

// --- malformed tokens -----------------------------------------------------
?. errHas(jwt.verify('', secret), 'three parts');
?. errHas(jwt.verify('abc', secret), 'three parts');
?. errHas(jwt.verify('a.b', secret), 'three parts');
?. errHas(jwt.verify('a.b.c.d', secret), 'three parts');
?. errHas(jwt.verify('a..c', secret), 'three parts');
?. errHas(jwt.verify('a.b.', secret), 'three parts');
?. errHas(jwt.verify('%' & t256.substr(t256.subpos('.')), secret), 'invalid header');
var h = AuthB64UrlEncode('{"alg":"HS256","typ":"JWT"}');
var p = AuthB64UrlEncode('{"sub":"u1"}');
var s = AuthB64UrlEncode(AuthHmacRaw(secret, h & '.' & p, 'sha256'));
?. jwt.verify(h & '.' & p & '.' & s, secret)['ok'];
?. errHas(jwt.verify(AuthB64UrlEncode('not json') & '.' & p & '.' & s, secret), 'invalid header');
var badP = AuthB64UrlEncode('not json');
var badPs = AuthB64UrlEncode(AuthHmacRaw(secret, h & '.' & badP, 'sha256'));
?. errHas(jwt.verify(h & '.' & badP & '.' & badPs, secret), 'invalid claims');
?. errHas(jwt.verify('%' & '.' & p & '.' & s, secret), 'invalid header');
var hn = AuthB64UrlEncode('{"alg":"none","typ":"JWT"}');
?. not jwt.verify(hn & '.' & AuthB64UrlEncode('{}') & '.x', secret)['ok'];
var hu = AuthB64UrlEncode('{"alg":"HS999","typ":"JWT"}');
?. not jwt.verify(hu & '.' & AuthB64UrlEncode('{}') & '.x', secret)['ok'];
var lc = AuthB64UrlEncode('{"alg":"hs256","typ":"JWT"}');
var ls = AuthB64UrlEncode(AuthHmacRaw(secret, lc & '.' & p, 'sha256'));
?. errHas(jwt.verify(lc & '.' & p & '.' & ls, secret), 'unsupported alg');
var hc = AuthB64UrlEncode('{"alg":"HS256","typ":"JWT","crit":["exp"]}');
var cs = AuthB64UrlEncode(AuthHmacRaw(secret, hc & '.' & p, 'sha256'));
?. errHas(jwt.verify(hc & '.' & p & '.' & cs, secret), 'unsupported header');
var hb = AuthB64UrlEncode('{"alg":"HS256","typ":"JWT","b64":false}');
var bs = AuthB64UrlEncode(AuthHmacRaw(secret, hb & '.' & p, 'sha256'));
?. errHas(jwt.verify(hb & '.' & p & '.' & bs, secret), 'unsupported header');
var br = jwt.verify(tamperLast(t256), secret);
?. br['claims'] = nil;
?. br['header'] = nil;
?. raises(((){ jwt.sign([sub: 'u1'], secret, [alg: 'hs256']); }));
?. raises(((){ jwt.sign([sub: 'u1'], secret, [headers: [crit: ['exp']]]); }));

// --- exp / nbf / iat / leeway --------------------------------------------
var expired = jwt.sign([exp: 1000], secret);
?. not jwt.verify(expired, secret, [now: 1000])['ok'];
?. errHas(jwt.verify(expired, secret, [now: 1000]), 'expired');
?. jwt.verify(expired, secret, [now: 1001, leeway: 10])['ok'];
?. jwt.verify(expired, secret, [now: 999])['ok'];
var noExp = jwt.sign([sub: 'u1'], secret);
?. jwt.verify(noExp, secret)['ok'];
?. errHas(jwt.verify(noExp, secret, [requireExp: true]), 'missing exp');
?. errHas(jwt.verify(jwt.sign([exp: 'soon'], secret), secret, [now: 1000]), 'invalid exp');
var early = jwt.sign([nbf: 2000], secret);
?. errHas(jwt.verify(early, secret, [now: 1999]), 'not yet valid');
?. jwt.verify(early, secret, [now: 1999, leeway: 2])['ok'];
var future = jwt.sign([iat: 2000], secret);
?. errHas(jwt.verify(future, secret, [now: 1999]), 'issued in the future');
?. jwt.verify(future, secret, [now: 1999, leeway: 2])['ok'];

// --- iss / aud / sub / jti ----------------------------------------------
var claims = jwt.sign([iss: 'app', aud: ['a', 'b'], sub: 'u1', jti: 'j1'], secret);
?. jwt.verify(claims, secret, [issuer: 'app', audience: 'b', subject: 'u1', jwtid: 'j1'])['ok'];
?. jwt.verify(claims, secret, [audience: ['c', 'a']])['ok'];
?. errHas(jwt.verify(claims, secret, [issuer: 'other']), 'issuer');
?. errHas(jwt.verify(claims, secret, [audience: 'c']), 'audience');
?. errHas(jwt.verify(claims, secret, [subject: 'u2']), 'subject');
?. errHas(jwt.verify(claims, secret, [jwtid: 'j2']), 'jwtid');
?. errHas(jwt.verify(jwt.sign([aud: 7], secret), secret, [audience: 'a']), 'audience');
var caseClaims = jwt.sign([iss: 'App', aud: 'A', sub: 'U', jti: 'J'], secret);
?. errHas(jwt.verify(caseClaims, secret, [issuer: 'app']), 'issuer');
?. errHas(jwt.verify(caseClaims, secret, [audience: 'a']), 'audience');
?. errHas(jwt.verify(caseClaims, secret, [subject: 'u']), 'subject');
?. errHas(jwt.verify(caseClaims, secret, [jwtid: 'j']), 'jwtid');
var uni = jwt.sign([name: '张三', aud: ['测试', 'a']], secret);
var unir = jwt.verify(uni, secret, [audience: '测试']);
?. unir['ok'];
?. unir['claims']['name'] = '张三';
var emptyAud = jwt.sign([aud: ''], secret);
?. jwt.verify(emptyAud, secret, [audience: ''])['ok'];

// --- relative options and custom headers ---------------------------------
var rel = jwt.sign([sub: 'u1'], secret, [expiresIn: 60, notBefore: 10, now: 1000]);
var rr = jwt.verify(rel, secret, [now: 1010]);
?. rr['ok'];
?. rr['claims']['exp'] = 1060;
?. rr['claims']['nbf'] = 1010;
?. not jwt.verify(rel, secret, [now: 1009])['ok'];
var hk = jwt.sign([sub: 'u1'], secret, [headers: [kid: 'k1']]);
?. jwt.decode(hk)['header']['kid'] = 'k1';

// --- parameter misuse raises --------------------------------------------
?. raises(((){ jwt.sign([sub: 'u1'], ''); }));
?. raises(((){ jwt.sign([sub: 'u1'], 7); }));
?. raises(((){ jwt.sign([1, 2], secret); }));
?. raises(((){ jwt.sign([sub: 'u1'], secret, [alg: 'none']); }));
?. raises(((){ jwt.sign([sub: 'u1'], secret, [nope: 1]); }));
?. raises(((){ jwt.sign([sub: 'u1'], secret, [expiresIn: -1]); }));
?. raises(((){ jwt.verify(t256, ''); }));
?. raises(((){ jwt.verify(t256, secret, [nope: 1]); }));
?. raises(((){ jwt.verify(t256, secret, [algorithms: ['RS256']]); }));
?. raises(((){ jwt.verify(t256, secret, [algorithms: ['hs256']]); }));
?. raises(((){ jwt.verify(t256, secret, [leeway: -1]); }));
?. not jwt.verify(7, secret)['ok'];

// --- clock ---------------------------------------------------------------
?. jwt.now() > 1700000000;
