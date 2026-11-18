// riscv64-encode: dump lib-asm-riscv64's encoding of each instruction in a
// file.
//
// Usage (from the repo root):
//   src/prj/fun/funcmd fun/test/tools/riscv64-encode.fun <lines-file>
//
// Prints "<instruction><TAB><hex>" per non-empty, non-comment line. Used by
// fun/test/tools/asm-riscv64-diff.sh to compare against the GNU cross
// assembler. Runs on any host: only the pure Compile path is used, never
// Load().
use 'fun/lib/lib-asm-riscv64.fun';

var enc = AssemblyRiscv64('i:i', '', nil);
var file = 2.arg();
for l in split(/\r?\n/, file.load()) do
  var t = _rv_strip(l);
  if t <> '' and t.substr(0, 1) <> '#' then
    ?. t & 9.toChar() & enc.Compile('#!asm' & 10.toChar() & t);
  end if;
end do;
