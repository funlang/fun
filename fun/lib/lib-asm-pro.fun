// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

use 'lib-asm.fun';
use 'lib-zlib.fun';
//use 'lib-sse-compress.fun';

// _ptr2hex / int2hex64 / the `<name>` callback resolver (_nameAddr) live in
// lib-asm.fun now (shared with lib-asm-a64). The `mov r64, imm64` entries
// injected in AsmsInit below consume the 8-byte form _ptr2hex produces on a
// 64-bit host.
var asms = AsmsInit();
fun AsmsInit()
  var all;
  var sse = false;
  if zlib then //?. 'gz';
    #* use ':asm-list.fd.gz' as gz;
    all = inflate(gz); #
    // Rebuild the derived table with fun/lib/tools/make-asm-list.fun
    // (sort -> prefix dedup -> raw deflate); see port-decisions.md D23.
    use ':asm-list.fd2.gz' as gz;
    //?, gz.length(); ?, str2hex(gz.substr(len:4)); ?, str2hex(gz.substr(-4));
    all = inflate(gz); //?. all.length();
    //all = SseDecompress(all);
    sse = true;
  else
    // No zlib. The old fallback read the uncompressed ':asm-list.fd' beside
    // this module, but `use ':file'` embeds the file at PARSE time
    // (parse.pas: CIO.Load + CreateStr), so that ~1MB blob was paid on every
    // host even when the zlib branch ran. lib-zlib now covers Windows
    // (zlib.dll) and Linux (libz.so.1), so the fallback is unreachable;
    // raise and keep only the compressed table.
    raise 'lib-asm-pro: zlib is required for the asm list';
  end if;
  result = all.getJson(fd: true, sse: sse); //?, 'asms'; ?. result.@count();
  if _asm_bits = 64 then
    // `mov r64, imm64` (REX.W + B8+rd, then 8 little-endian bytes). The table
    // is 32-bit oriented and only carries 4-byte `mov r,%8`, which cannot hold
    // a 64-bit host address: on Linux a @toCallback address is an mmap'd
    // libffi closure above 4GB. `%16` is the 8-byte form produced by int2hex64.
    result['mov rax,%16'] = '48B8%16';
    result['mov rcx,%16'] = '48B9%16';
    result['mov rdx,%16'] = '48BA%16';
    result['mov rbx,%16'] = '48BB%16';
    result['mov rsp,%16'] = '48BC%16';
    result['mov rbp,%16'] = '48BD%16';
    result['mov rsi,%16'] = '48BE%16';
    result['mov rdi,%16'] = '48BF%16';
  end if;
end fun;

Assembly = AssemblyPro;
class AssemblyPro = AssemblyBase()
  var arch = 'x86';

  fun Compile(c)
    if c =~ /^#!asm\b/ then
      c = c.replace(/^#!asm\b(?:[:=]?\s*+(\w*+:\w*+))?/, m->GetArgs(m))
           .replace(/^\s*+([@\w][^;\r\n]+[^;\s])?\s*(;.*)?$/gm, (m){
        var a = m.@(1).replace(/\s++(?=[>)\]+*:,])|(?<=[<(\[+*:-])\s++/g, '')
                      .replace(/,\s++/g, ',')
                      .replace(/(?<=\s)\s++|\s++$/g, ''); //?. a;
        exit when a = nil;
        var asm = a;
        if asms[a] = nil then
          // function names in fun
          asm = asm.replace(/<(\w++)>/g, (n){
            result = _nameAddr(n.@(1), names);
          });
          // numbers
          a = asm.replace(/[-+]?(?<!\*)\$?\b([\dA-F]++\b)/g, (n){
            var j = n.@(1).length();
            result = '%$j'.eval();
          });
        end if;
        if asms[a] = nil then
          raise '$a not found.'.eval();
        else
          result = asms[a];
          // numbers. %(\d++) so the injected 64-bit `mov r64, imm64` (%16)
          // placeholder is consumed whole, not as "%1" + "6".
          if result =~ /%/ then
            var r = result;
            asm.replace(/[-+]?(?<!\*)(\$)?\b([\dA-F]++\b)/g, (n){
              r = r.replace(/%(\d++)/, (o){
                var h = n.@(2);
                if n.@(1) = '$' then
                  if h.length() = 8 then
                    h = h.substr(6, 2) & h.substr(4, 2) & h.substr(2, 2) & h.substr(0, 2);
                  elsif h.length() = 4 then
                    h = h.substr(2, 2) & h.substr(0, 2);
                  end if;
                end if;
                if n.@@() =~ /^-/ then
                  // todo
                  if h.length() = 2 then h = h div 1; //?. h;
                    h = h bit xor 0xff + 1;           //?. h;
                    h = byte2hex(h);                  //?. h;
                  end if;
                end if;
                result = h;
              });
            });
            result = r;
          end if;
        end if;
      }).replace(/\W++/g, '');
      return c;
    else
      return base.Compile(c);
    end if;
  end fun;
end class;
