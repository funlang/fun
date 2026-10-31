// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

########################################
# lib-md5
########################################
#   built-in (2)
#     str.md5 ()
#     str.sha1()
########################################
var Cr = nil;

fun SHA256 (msg)
  try
    //var libCr = 'lib-crypt.fun';
    if Cr = nil then //and libCr.find() then
      //Cr = libCr.compile();
      // `use ... as X` binds X only inside the block that contains it, so the
      // alias must be copied to Cr in the same branch (assigning after the
      // inner `end if` raises "libCr not found" and the except below would
      // silently fall back to the slow, non-wrapping pure implementation).
      // Import the real Unix backend directly. The `-lnx` wrapper is a
      // compatibility name; using `-unx` here avoids one forwarding hop. (An
      // alias of the wrapper also works now that aliases re-export their
      // module's `use` chain.)
      if 'host'.arg().getJson(fd: true).os = 'linux' or
         'host'.arg().getJson(fd: true).os = 'macos' then
        use 'lib-crypt-unx.fun' as libCr;
        Cr = libCr;
      else
        use 'lib-crypt.fun' as libCr;
        Cr = libCr;
      end if;
      //Cr();
    end if;
    return Cr.Crypt(msg, Cr.CALG_Sha256);
  except
  end try;

  #=============================================================================
  fun sigma0 (x)
    return ((x >> 2) bit or (x << 30))  bit xor ((x >> 13) bit or (x << 19)) bit xor ((x >> 22) bit or (x << 10));
  end fun;

  fun sigma1 (x)
    return ((x >> 6) bit or (x << 26))  bit xor ((x >> 11) bit or (x << 21)) bit xor ((x >> 25) bit or (x << 7));
  end fun;

  fun gamma0 (x)
    return ((x >> 7) bit or (x << 25))  bit xor ((x >> 18) bit or (x << 14)) bit xor (x >> 3);
  end fun;

  fun gamma1 (x)
    return ((x >> 17) bit or (x << 15)) bit xor ((x >> 19) bit or (x << 13)) bit xor (x >> 10);
  end fun;

  #=============================================================================
  fun b32a2hex (binarray)
    result = "";
    var hex_tab = "0123456789abcdef";
    var length = binarray.@count() * 4;

    for i = 0 to length - 1 do
      var srcByte = binarray[i >> 2] >> ((3 - (i mod 4)) * 8);
      result &= hex_tab.substr((srcByte >> 4) bit and 0xf, 1) &
                hex_tab.substr(srcByte bit and 0xf, 1);
    end do;
  end fun;

  fun to64bit(i)
    result = '';
    for j = 1 to 8 do
      result = (i mod 256).toChar() & result;
      i = i >> 8;
    end do;
  end fun;

  fun toDWord(str)
    result = 0;
    for i = 0 to str.length()-1 do
      result = result << 8;
      result += str.toByte(i);
    end do;
  end fun;

  #=============================================================================
  var K = [
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
      0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
      0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
      0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
      0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
      0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
      0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
      0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
      0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ];

  var N = new [
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ];

  #=============================================================================
  var msgLen = msg.length();
  var extra0 = 55 - msgLen mod 64;
  if extra0 < 0 then extra0 += 64; end if;
  msg &= 0x80.toChar() & 0.toChar().x(extra0) & to64bit(msgLen * 8);

  #=============================================================================
  for i = 0 to msg.length()-1 step 64 loop
    var a = N[0];
    var b = N[1];
    var c = N[2];
    var d = N[3];
    var e = N[4];
    var f = N[5];
    var g = N[6];
    var h = N[7];

    var W = new [];
    for t = 0 to 63 do
      if t < 16 then
        W[t] = toDWord(msg.substr(i + t*4, 4));
      else
        var x = W[t- 2];
        var y = W[t-15];
        W[t] = #gamma1(x)
               ((x >> 17) bit or (x << 15)) bit xor ((x >> 19) bit or (x << 13)) bit xor (x >> 10)
             + W[t- 7]
             + #gamma0(y)
               ((y >> 7) bit or (y << 25))  bit xor ((y >> 18) bit or (y << 14)) bit xor (y >> 3)
             + W[t-16];
      end if;

      var T1 = h
             + #sigma1(e)
               ((e >> 6) bit or (e << 26))  bit xor ((e >> 11) bit or (e << 21)) bit xor ((e >> 25) bit or (e << 7))
             + (e bit and f) bit xor (bit not e bit and g) + K[t] + W[t];
      var T2 = #sigma0(a)
               ((a >> 2) bit or (a << 30))  bit xor ((a >> 13) bit or (a << 19)) bit xor ((a >> 22) bit or (a << 10))
             + (a bit and b) bit xor (a bit and c) bit xor (b bit and c);
      h = g;
      g = f;
      f = e;
      e = d  + T1;
      d = c;
      c = b;
      b = a;
      a = T1 + T2;
    end do;

    N[0] = (N[0] + a) bit and 0xffffffff;
    N[1] = (N[1] + b) bit and 0xffffffff;
    N[2] = (N[2] + c) bit and 0xffffffff;
    N[3] = (N[3] + d) bit and 0xffffffff;
    N[4] = (N[4] + e) bit and 0xffffffff;
    N[5] = (N[5] + f) bit and 0xffffffff;
    N[6] = (N[6] + g) bit and 0xffffffff;
    N[7] = (N[7] + h) bit and 0xffffffff;
  end loop;

  return b32a2hex(N);
end fun;
