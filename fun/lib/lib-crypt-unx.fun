// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-crypt-unx: the Unix backend of lib-crypt (OpenSSL libcrypto).
//
// The Windows lib-crypt.fun is CryptoAPI-shaped (HCRYPTPROV/HCRYPTHASH/HCRYPTKEY),
// so like lib-proc/lib-unicode it keeps the plain name and this backend carries
// the same public API for Unix callers (use 'lib-crypt-unx.fun').
//
// Kept identical: Crypt(msg, typ) -> hex digest, AES/Encode(msg, key, isDecode, args),
// AES_CBC(msg, key, isDecode), and the CALG_* / CRYPT_MODE_* constants.
// AES accepts the same CryptoAPI PLAINTEXTKEYBLOB that Windows produces, or a
// plain raw key (16/24/32 bytes -> AES-128/192/256).
//
// Unix additions: RandomBytes(n) (RAND_bytes) and RSA_PEM(msg, pem, isDecode)
// for RSA with a PEM key (PEM_read_bio_PrivateKey/PUBKEY). The Windows RSA()
// which has no portable meaning here, so it raises.
//
// Native handles are module-level getapi variables, not a map: on this Fun
// version a handle stored in a set member is not reliably callable from a
// function body, while a plain variable is (the lib-crypt.fun / lib-asm.fun
// pattern).

use 'lib-utils.fun';
use 'lib-host.fun';

var PROV_RSA_AES = 24;
var CALG_MD5     = 32771;
var CALG_Sha1    = 32772;
var CALG_Sha256  = 32780;
var CALG_Sha384  = 32781;
var CALG_Sha512  = 32782;
var CALG_AES_128 = 0x0000660e;
var CALG_AES_192 = 0x0000660f;
var CALG_AES_256 = 0x00006610;
var CRYPT_MODE_CBC = 1;
var CRYPT_MODE_ECB = 2;
var ZERO_PADDING   = 3;

var _LIB = nil;
var _MD5 = nil; var _SHA1 = nil; var _SHA256 = nil; var _SHA384 = nil; var _SHA512 = nil;
var _RAND = nil;
var _CTXNEW = nil; var _CTXFREE = nil; var _SETPAD = nil;
var _ENCINIT = nil; var _DECINIT = nil; var _ENCUPDATE = nil; var _DECUPDATE = nil;
var _ENCFINAL = nil; var _DECFINAL = nil;
var _AES128CBC = nil; var _AES192CBC = nil; var _AES256CBC = nil;
var _AES128ECB = nil; var _AES192ECB = nil; var _AES256ECB = nil;
var _BIO_NEW = nil; var _BIO_FREE = nil;
var _PEM_PRIV = nil; var _PEM_PUB = nil;
var _PKEY_SIZE = nil; var _PKEY_CTX_NEW = nil; var _PKEY_CTX_FREE = nil; var _PKEY_FREE = nil;
var _PKEY_ENC_INIT = nil; var _PKEY_ENC = nil; var _PKEY_DEC_INIT = nil; var _PKEY_DEC = nil;

fun _clear()
  _MD5 = nil; _SHA1 = nil; _SHA256 = nil; _SHA384 = nil; _SHA512 = nil;
  _RAND = nil;
  _CTXNEW = nil; _CTXFREE = nil; _SETPAD = nil;
  _ENCINIT = nil; _DECINIT = nil; _ENCUPDATE = nil; _DECUPDATE = nil;
  _ENCFINAL = nil; _DECFINAL = nil;
  _AES128CBC = nil; _AES192CBC = nil; _AES256CBC = nil;
  _AES128ECB = nil; _AES192ECB = nil; _AES256ECB = nil;
  _BIO_NEW = nil; _BIO_FREE = nil;
  _PEM_PRIV = nil; _PEM_PUB = nil;
  _PKEY_SIZE = nil; _PKEY_CTX_NEW = nil; _PKEY_CTX_FREE = nil; _PKEY_FREE = nil;
  _PKEY_ENC_INIT = nil; _PKEY_ENC = nil; _PKEY_DEC_INIT = nil; _PKEY_DEC = nil;
end fun;

fun _init()
  result = true;
  // Linux ships libcrypto as libcrypto.so.N; on macOS the bare name resolves
  // to the system LibreSSL, which aborts the process on load; only explicit
  // Homebrew / MacPorts paths are probed here.
  var libs = DyLibList(
    ['libcrypto.so.3', 'libcrypto.so.1.1', 'libcrypto.so.10', 'libcrypto.so'],
    ['/opt/homebrew/opt/openssl/lib/libcrypto.dylib',
     '/usr/local/opt/openssl/lib/libcrypto.dylib',
     '/opt/homebrew/lib/libcrypto.3.dylib',
     '/usr/local/lib/libcrypto.dylib']);
  var found = false;
  for n in libs do
    if not found then
      try
        _MD5    = n.getapi('MD5',    'snp:p');
        _SHA1   = n.getapi('SHA1',   'snp:p');
        _SHA256 = n.getapi('SHA256', 'snp:p');
        _SHA384 = n.getapi('SHA384', 'snp:p');
        _SHA512 = n.getapi('SHA512', 'snp:p');
        _RAND   = n.getapi('RAND_bytes', 'pi:i');
        _CTXNEW  = n.getapi('EVP_CIPHER_CTX_new',        ':p');
        _CTXFREE = n.getapi('EVP_CIPHER_CTX_free',       'p:v');
        _SETPAD  = n.getapi('EVP_CIPHER_CTX_set_padding', 'pi:i');
        _ENCINIT = n.getapi('EVP_EncryptInit_ex', 'pppss:i');
        _DECINIT = n.getapi('EVP_DecryptInit_ex', 'pppss:i');
        _ENCUPDATE = n.getapi('EVP_EncryptUpdate', 'pppsi:i');
        _DECUPDATE = n.getapi('EVP_DecryptUpdate', 'pppsi:i');
        _ENCFINAL = n.getapi('EVP_EncryptFinal_ex', 'ppp:i');
        _DECFINAL = n.getapi('EVP_DecryptFinal_ex', 'ppp:i');
        _AES128CBC = n.getapi('EVP_aes_128_cbc', ':p');
        _AES192CBC = n.getapi('EVP_aes_192_cbc', ':p');
        _AES256CBC = n.getapi('EVP_aes_256_cbc', ':p');
        _AES128ECB = n.getapi('EVP_aes_128_ecb', ':p');
        _AES192ECB = n.getapi('EVP_aes_192_ecb', ':p');
        _AES256ECB = n.getapi('EVP_aes_256_ecb', ':p');
        _BIO_NEW  = n.getapi('BIO_new_mem_buf', 'pi:p');
        _BIO_FREE = n.getapi('BIO_free', 'p:i');
        _PEM_PRIV = n.getapi('PEM_read_bio_PrivateKey', 'pp:p');
        _PEM_PUB  = n.getapi('PEM_read_bio_PUBKEY', 'pp:p');
        _PKEY_SIZE    = n.getapi('EVP_PKEY_size', 'p:i');
        _PKEY_CTX_NEW = n.getapi('EVP_PKEY_CTX_new', 'pp:p');
        _PKEY_CTX_FREE = n.getapi('EVP_PKEY_CTX_free', 'p:v');
        _PKEY_FREE     = n.getapi('EVP_PKEY_free', 'p:v');
        _PKEY_ENC_INIT = n.getapi('EVP_PKEY_encrypt_init', 'p:i');
        _PKEY_ENC      = n.getapi('EVP_PKEY_encrypt', 'pppsi:i');
        _PKEY_DEC_INIT = n.getapi('EVP_PKEY_decrypt_init', 'p:i');
        _PKEY_DEC      = n.getapi('EVP_PKEY_decrypt', 'pppsi:i');
        _LIB = n;
        found = true;
      except
        _clear();
      end try;
    end if;
  end do;
  // macOS: hashes come from CommonCrypto (libSystem, always present) so they
  // work without Homebrew OpenSSL; OpenSSL here only serves AES/RSA.
  if 'host'.arg().getJson(fd: true).os = 'macos' then
    var Sys = 'libSystem.B.dylib';
    _MD5    = Sys.getapi('CC_MD5',    'snp:p');
    _SHA1   = Sys.getapi('CC_SHA1',   'snp:p');
    _SHA256 = Sys.getapi('CC_SHA256', 'snp:p');
    _SHA384 = Sys.getapi('CC_SHA384', 'snp:p');
    _SHA512 = Sys.getapi('CC_SHA512', 'snp:p');
  end if;
  result = found;
end fun;
_init();

fun Crypt(msg, typ)
  if _MD5 = nil then raise 'lib-crypt-unx: hash functions not available'; end if;
  var out;
  if typ = CALG_MD5 then
    out = ' '.x(16); _MD5(msg, msg.length(), out.toNum(-1));
  elsif typ = CALG_Sha1 then
    out = ' '.x(20); _SHA1(msg, msg.length(), out.toNum(-1));
  elsif typ = CALG_Sha256 then
    out = ' '.x(32); _SHA256(msg, msg.length(), out.toNum(-1));
  elsif typ = CALG_Sha384 then
    out = ' '.x(48); _SHA384(msg, msg.length(), out.toNum(-1));
  elsif typ = CALG_Sha512 then
    out = ' '.x(64); _SHA512(msg, msg.length(), out.toNum(-1));
  else
    raise 'lib-crypt-unx: unsupported algorithm: ' & typ;
  end if;
  result = str2hex(out);
end fun;

// Rebuild the AES key from a CryptoAPI PLAINTEXTKEYBLOB
// (BLOBHEADER + DWORD cbKey + key) so Windows-produced keys keep working,
// or accept plain raw key bytes.
fun _aeskey(key)
  result = key;
  if key.length() >= 12 and key.toByte(0) = 0x08 then
    var cb = str2int(key, 8);
    if cb > 0 and 12 + cb <= key.length() then
      result = key.substr(12, cb);
    end if;
  end if;
end fun;

fun AES(msg, key, isDecode, args)
  if _LIB = nil then raise 'lib-crypt-unx: libcrypto not available'; end if;
  var k = _aeskey(key);
  if k.length() <> 16 and k.length() <> 24 and k.length() <> 32 then
    raise 'lib-crypt-unx: AES key must be 16/24/32 bytes, got ' & k.length();
  end if;
  // Read options without `?.`: an optional member (`x?.k?`) that misses can hand
  // back the value cached at that same AST node by an earlier call, so the nil
  // case must be an explicit guard.
  var mode = CRYPT_MODE_CBC;
  var zeroPad = false;
  var iv = nil;
  if args <> nil then
    if args.mode <> nil then mode = args.mode; end if;
    if args.padding = ZERO_PADDING then zeroPad = true; end if;
    iv = args.iv;
  end if;
  var block = 16;
  var input = msg;
  if not isDecode and zeroPad then
    var r = input.length() mod block;
    if r <> 0 then input = input & 0.toChar().x(block - r); end if;
  end if;
  if mode <> CRYPT_MODE_ECB and iv = nil then iv = k.substr(0, block); end if;
  var ctx = _CTXNEW();
  if ctx = nil then raise 'lib-crypt-unx: EVP_CIPHER_CTX_new failed'; end if;
  var bits = k.length() * 8;
  var ok = false;
  var cipher = nil;
  if isDecode then
    if mode = CRYPT_MODE_ECB then
      if bits = 128 then cipher = _AES128ECB();
      elsif bits = 192 then cipher = _AES192ECB();
      else cipher = _AES256ECB(); end if;
    else
      if bits = 128 then cipher = _AES128CBC();
      elsif bits = 192 then cipher = _AES192CBC();
      else cipher = _AES256CBC(); end if;
    end if;
    ok = _DECINIT(ctx, cipher, nil, k, iv);
  else
    if mode = CRYPT_MODE_ECB then
      if bits = 128 then cipher = _AES128ECB();
      elsif bits = 192 then cipher = _AES192ECB();
      else cipher = _AES256ECB(); end if;
    else
      if bits = 128 then cipher = _AES128CBC();
      elsif bits = 192 then cipher = _AES192CBC();
      else cipher = _AES256CBC(); end if;
    end if;
    ok = _ENCINIT(ctx, cipher, nil, k, iv);
  end if;
  if not ok then
    _CTXFREE(ctx);
    raise 'lib-crypt-unx: AES init failed';
  end if;
  if zeroPad then _SETPAD(ctx, 0); end if;
  var n1 = int2str(0);
  var out = 0.toChar().x(input.length() + block * 2 + 16);
  var l1 = 0; var l2 = 0;
  if isDecode then
    _DECUPDATE(ctx, out.toNum(-1), n1.toNum(-1), input, input.length());
    l1 = str2int(n1);
    _DECFINAL(ctx, out.toNum(-1) + l1, n1.toNum(-1));
    l2 = str2int(n1);
  else
    _ENCUPDATE(ctx, out.toNum(-1), n1.toNum(-1), input, input.length());
    l1 = str2int(n1);
    _ENCFINAL(ctx, out.toNum(-1) + l1, n1.toNum(-1));
    l2 = str2int(n1);
  end if;
  _CTXFREE(ctx);
  result = out.substr(len: l1 + l2);
end fun;

var Encode = AES;

fun AES_CBC(msg, key, isDecode)
  var k = _aeskey(key);
  var iv = k.length() >= 16 and k.substr(0, 16) or k;
  result = AES(msg, key, isDecode, new [mode: CRYPT_MODE_CBC, iv: iv, padding: ZERO_PADDING]);
end fun;

fun RSA(msg, key, isDecode)
  raise 'lib-crypt-unx: CryptoAPI key blobs are not portable to Unix; use RSA_PEM';
end fun;

// Pointer-width little-endian pack/unpack (size_t fields are 8 bytes on LP64;
// int2str/str2int are fixed at 4).
var _PTR = 'host'.arg().getJson(fd: true).bits div 8;
fun _pack(v)
  result = '';
  var u = v;
  for i = 0 to _PTR - 1 do
    result &= (u mod 256).toChar();
    u = u div 256;
  end do;
end fun;
fun _unpack(s)
  result = 0;
  var m = 1;
  for i = 0 to _PTR - 1 do
    result += s.toByte(i) * m;
    m *= 256;
  end do;
end fun;

fun _pkey_load(pem, isPriv)
  var bio = _BIO_NEW(pem.toNum(-1), pem.length());
  if bio = nil then raise 'lib-crypt-unx: BIO_new_mem_buf failed'; end if;
  if isPriv then
    result = _PEM_PRIV(bio, nil, nil, nil);
  else
    result = _PEM_PUB(bio, nil, nil, nil);
  end if;
  _BIO_FREE(bio);
end fun;

// RSA encrypt (isDecode=false) or decrypt (isDecode=true) using a PEM key
// (PKCS#1 v1.5 padding by default). A private key works both ways; a public key
// only encrypts. This is the portable replacement for the CryptoAPI-blob RSA().
fun RSA_PEM(msg, pem, isDecode)
  if _LIB = nil then raise 'lib-crypt-unx: libcrypto not available'; end if;
  var pkey = _pkey_load(pem, true);
  if pkey = nil then
    if isDecode then raise 'lib-crypt-unx: RSA_PEM needs a private key to decrypt'; end if;
    pkey = _pkey_load(pem, false);
  end if;
  if pkey = nil then raise 'lib-crypt-unx: RSA_PEM cannot read the key'; end if;
  var size = _PKEY_SIZE(pkey);
  var ctx = _PKEY_CTX_NEW(pkey, nil);
  if ctx = nil then
    _PKEY_FREE(pkey);
    raise 'lib-crypt-unx: EVP_PKEY_CTX_new failed';
  end if;
  var out = 0.toChar().x(size + 16);
  var outlen = _pack(out.length());
  var r;
  if isDecode then
    _PKEY_DEC_INIT(ctx);
    r = _PKEY_DEC(ctx, out.toNum(-1), outlen.toNum(-1), msg, msg.length());
  else
    _PKEY_ENC_INIT(ctx);
    r = _PKEY_ENC(ctx, out.toNum(-1), outlen.toNum(-1), msg, msg.length());
  end if;
  var l = _unpack(outlen);
  _PKEY_CTX_FREE(ctx);
  _PKEY_FREE(pkey);
  if r <= 0 then raise 'lib-crypt-unx: RSA_PEM operation failed'; end if;
  result = out.substr(0, l);
end fun;

fun RandomBytes(n)
  if _LIB = nil then raise 'lib-crypt-unx: libcrypto not available'; end if;
  var b = ' '.x(n);
  if _RAND(b.toNum(-1), n) <> 1 then raise 'lib-crypt-unx: RAND_bytes failed'; end if;
  result = b;
end fun;
