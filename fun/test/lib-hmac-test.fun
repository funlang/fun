// lib-hmac: RFC 2202 HMAC-SHA1 test vectors.
//
// The built-in str.sha1() returns hex, so the raw-digest conversion in
// lib-utils (hex2str) is what makes a pure-Fun HMAC possible. These vectors
// cover both padding branches: a key shorter than the 64-byte block and a key
// longer than it, plus the empty key/message case.
use 'fun/lib/lib-hmac.fun';

fun rep(byte, n)
  result = byte.toChar().x(n);
end fun;

fun ok(cond, name)
  if cond then
    ?. 'PASS ' & name;
  else
    ?. 'FAIL ' & name;
  end if;
end fun;

// key shorter than the block: 0x0b * 20
ok(HmacSha1Hex(rep(0x0b, 20), 'Hi There') =
  'b617318655057264e28bc0b6fb378c8ef146be00', 'short key, text data');

// ordinary text key and message
ok(HmacSha1Hex('Jefe', 'what do ya want for nothing?') =
  'effcdf6ae5eb2fa2d27416d5f184df9c259a7c79', 'text key');

// 0xaa * 20 key, 0xdd * 50 data
ok(HmacSha1Hex(rep(0xaa, 20), rep(0xdd, 50)) =
  '125d7342b9ac11cd91a39af48aa17b4f63f175d3', 'high-bit key and data');

// 25-byte key 0x01..0x19, 0xcd * 50 data
var key25 = '';
for i = 1 to 25 do
  key25 &= i.toChar();
end do;
ok(HmacSha1Hex(key25, rep(0xcd, 50)) =
  '4c9007f4026250c6bc8414f9bf50c86c2d7235da', '25-byte key');

ok(HmacSha1Hex(rep(0x0c, 20), 'Test With Truncation') =
  '4c1a03424b55e07fe7f27be1d58bb9324a9a5a04', 'truncation vector');

// key longer than the 64-byte block: hashed down first
ok(HmacSha1Hex(rep(0xaa, 80),
  'Test Using Larger Than Block-Size Key - Hash Key First') =
  'aa4ae5e15272d00e95705637ce8a3b55ed402112', 'long key hashed to a block');
ok(HmacSha1Hex(rep(0xaa, 80),
  'Test Using Larger Than Block-Size Key and Larger Than One Block-Size Data') =
  'e8e99d0f45237d786d6bbaa7965c7808bbff1a91', 'long key and multi-block data');

// the raw form is the 20-byte digest, not hex
ok(HmacSha1('key', 'The quick brown fox jumps over the lazy dog').length() = 20,
  'raw digest length');
ok(HmacSha1Hex('key', 'The quick brown fox jumps over the lazy dog') =
  'de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9', 'raw and hex agree');

// empty key and empty message
ok(HmacSha1Hex('', '') = 'fbdb1d1b18aa6c08324b7d64b71fb76370690e1d',
  'empty key and message');
