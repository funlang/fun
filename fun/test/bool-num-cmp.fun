// Boolean vs number comparison must be symmetric regardless of operand
// order, and must treat true as VARIANT_BOOL -1 (Delphi/COM VarCmp).
// FPC's generic variant compare coerces by operand order instead, which
// made `1 = true` differ from `true = 1`. Fixed in src/core/base.pas
// (varComp, FPC-only branch).
//
// Run:  fun/funcmd fun/test/bool-num-cmp.fun

fun ok(cond, name)
  if cond then
    ?. 'PASS ' + name;
  else
    ?. 'FAIL ' + name;
  end if;
end fun;

var t = true;
var f = false;

// true is -1, false is 0
ok(t = -1, 'true = -1');
ok(-1 = t, '-1 = true');
ok(f = 0, 'false = 0');
ok(0 = f, '0 = false');

// symmetry of equality
ok((t = 1) = (1 = t), 'true=1 and 1=true symmetric');
ok((t = 1) = false, 'true = 1 is false');
ok((t = 0) = (0 = t), 'true=0 and 0=true symmetric');
ok((t = 0) = false, 'true = 0 is false');
ok((f = 1) = (1 = f), 'false=1 and 1=false symmetric');

// symmetry of ordering
ok((t > 0) = (0 < t), 'true>0 and 0<true symmetric');
ok((t > 0) = false, 'true > 0 is false (true is -1)');
ok((t < 2) = (2 > t), 'true<2 and 2>true symmetric');
ok((t < 2) = true, 'true < 2 is true');
ok((t < 0) = (0 > t), 'true<0 and 0>true symmetric');

// symmetry of <> and the relational aliases
ok((t <> 1) = (1 <> t), 'true<>1 and 1<>true symmetric');
ok((t <> 1) = true, 'true <> 1 is true');
ok((t <= 0) = (0 >= t), 'true<=0 and 0>=true symmetric');
ok((t >= 1) = (1 <= t), 'true>=1 and 1<=true symmetric');

// real operands
ok((t = 1.0) = (1.0 = t), 'true=1.0 and 1.0=true symmetric');
ok((t = 2.5) = (2.5 = t), 'true=2.5 and 2.5=true symmetric');
ok((t < 2.5) = (2.5 > t), 'true<2.5 and 2.5>true symmetric');

// bool vs bool and bool vs string are untouched
ok((t = t) = true, 'true = true');
ok((t = f) = false, 'true <> false');
ok((t = 'x') = false, 'true = x is false');
ok(('x' = t) = false, 'x = true is false');

// CI cache probe: a comment-only change under fun/ must not rebuild funcmd.
