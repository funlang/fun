// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

function _Comp(env: CEnv; e1, e2: PValue): ECompResult;
begin
  result := varComp(e1, e2, env.isCase);
end;

function _CompIn(env: CEnv; e1, e2: PValue): fun.bool;
var
  i: fun.int;
begin
  result := false;
  if asObj(e2) is CSet then
  begin
    with CSet(asObj(e2)) do
    begin
      for i := 0 to count() -1 do
      begin
        if varComp(e1, item[i].value, env.isCase) = EQ then
        begin
          result := true;
          exit;
        end;
      end;
    end;
  end;
end;

function _Match(env: CEnv; e1, e2: PValue): CValue;
var
  exp: CExp;
  exs: CExps;
begin
  exp := CExp.new(nil);
  exp.assign(e1);
  exs := CExps.create;
  exs.add(CExp.new(nil).parse(e2^));
  try
    env.call(exp, 'match', exs, @result);
  finally
    del(exp);
    del(exs);
  end;
end;

function _MatchNot(env: CEnv; e1, e2: PValue): fun.bool;
var
  mv: CValue;
begin
  mv := _Match(env, e1, e2);
  result := not funBoolOf(@mv);
end;

{$IfDef FPC}
//--------------------------------------------------------------
// FPC's RTL Variant arithmetic *propagates* Empty/Null (Empty + 1 = Empty),
// while Delphi/COM treat Empty as 0 (or '' when concatenating) and Fun's own
// comparison already treats null as 0/'' too. So before handing + - * / div mod
// to the RTL, replace a null operand with the zero the operation expects; this
// keeps arithmetic consistent with '=' and with the Delphi build.
//
// This is FPC-only: Delphi/COM already normalize Empty the same way, so gating it
// keeps the Delphi (Windows 32-bit) arithmetic hot path free of the VType checks
// and the extra Variant copy. Semantics per target are unchanged - FPC gets the
// normalization, Delphi keeps its stock RTL behavior.
//
// Only VType <= varNull (varEmpty/varNull) is touched - a real numeric 0 or an
// empty string is left as is, so no existing behavior changes.
//
// e1 is the accumulator (the result is written back to it), so it may be
// normalized in place. e2 must NOT be written: it can be a live variable
// (e.g. `1 + x`), so a normalized copy is returned instead.
procedure _NullNumE1(e: PValue);
begin
  if PData(e)^.VType <= varNull then
    e^ := 0;
end;

procedure _NullAddE1(e1, e2: PValue);
begin
  if PData(e1)^.VType <= varNull then
  begin
    if isStr(e2) then e1^ := '' else e1^ := 0;
  end;
end;

function _Num2(e2: PValue): CValue;
begin
  if PData(e2)^.VType <= varNull then result := 0 else result := e2^;
end;

function _Add2(e1, e2: PValue): CValue;
begin
  if PData(e2)^.VType <= varNull then
  begin
    if isStr(e1) then result := '' else result := 0;
  end
  else result := e2^;
end;
{$EndIf}

//==============================================================
procedure C01(env: CEnv; e1, e2: PValue);
{$IfDef CalcOpt}
  procedure _C01;
{$IfDef FPC}
  var t: CValue;
{$EndIf}
  begin
{$IfDef FPC}
    if (PData(e1)^.VType <= varNull) or (PData(e2)^.VType <= varNull) then
    begin
      _NullAddE1(e1, e2);
      t := _Add2(e1, e2);
      e1^ := e1^ + t; // +
    end
    else
      e1^ := e1^ + e2^; // +
{$Else}
    e1^ := e1^ + e2^; // +
{$EndIf}
  end;

var i: fun.int; j: fun.dword;
label _;
begin
  with PData(e1)^ do
  begin
    if VType = VarInteger then
    begin
      case PData(e2).VType of
        VarInteger:
        begin
          i        := VInteger + PData(e2).VInteger;
          // Signed-overflow test in plain Pascal (no flags/asm), so this fast
          // path also builds on non-x86 targets.
          if ((i xor VInteger) and (i xor PData(e2).VInteger)) < 0 then goto _;
          VInteger := i;
          exit;
        end;
        VarDouble:
        begin
          VDouble  := VInteger + PData(e2).VDouble;
          VType    := VarDouble;
          exit;
        end;
      end;
    end
    else if VType = VarDouble then
    begin
      case PData(e2).VType of
        VarInteger:
        begin
          VDouble  := VDouble  + PData(e2).VInteger;
          exit;
        end;
        VarDouble:
        begin
          VDouble  := VDouble  + PData(e2).VDouble;
          exit;
        end;
      end;
    end
    else if (VType = VarLongWord) and (PData(e2).VType = VarLongWord) then
    begin
      j         := VLongWord + PData(e2).VLongWord;
      // Unsigned carry: the sum wrapped below the first operand.
      if j < VLongWord then goto _;
      VLongWord := j;
      exit;
    end;
  end;

  _: _C01;
{$Else}
{$IfDef FPC}
var t: CValue;
begin
  if (PData(e1)^.VType <= varNull) or (PData(e2)^.VType <= varNull) then
  begin
    _NullAddE1(e1, e2);
    t := _Add2(e1, e2);
    e1^ := e1^ + t; // +
  end
  else
    e1^ := e1^ + e2^; // +
{$Else}
begin
  e1^ := e1^ + e2^; // +
{$EndIf}
{$EndIf}
end;

procedure C02(env: CEnv; e1, e2: PValue);
{$IfDef CalcOpt}
  procedure _C02;
{$IfDef FPC}
  var t: CValue;
{$EndIf}
  begin
{$IfDef FPC}
    if (PData(e1)^.VType <= varNull) or (PData(e2)^.VType <= varNull) then
    begin
      _NullNumE1(e1);
      t := _Num2(e2);
      e1^ := e1^ - t; // -
    end
    else
      e1^ := e1^ - e2^; // -
{$Else}
    e1^ := e1^ - e2^; // -
{$EndIf}
  end;

var i: fun.int;
label _;
begin
  with PData(e1)^ do
  begin
    if VType = VarInteger then
    begin
      case PData(e2).VType of
        VarInteger:
        begin
          i        := VInteger - PData(e2).VInteger;
          // Signed-overflow test: operands differ in sign and the result's
          // sign differs from the minuend's.
          if ((VInteger xor PData(e2).VInteger) and (VInteger xor i)) < 0 then goto _;
          VInteger := i;
          exit;
        end;
        VarDouble:
        begin
          VDouble  := VInteger - PData(e2).VDouble;
          VType    := VarDouble;
          exit;
        end;
      end;
    end
    else if VType = VarDouble then
    begin
      case PData(e2).VType of
        VarInteger:
        begin
          VDouble  := VDouble  - PData(e2).VInteger;
          exit;
        end;
        VarDouble:
        begin
          VDouble  := VDouble  - PData(e2).VDouble;
          exit;
        end;
      end;
    end;
  end;

  _: _C02;
{$Else}
{$IfDef FPC}
var t: CValue;
begin
  if (PData(e1)^.VType <= varNull) or (PData(e2)^.VType <= varNull) then
  begin
    _NullNumE1(e1);
    t := _Num2(e2);
    e1^ := e1^ - t; // -
  end
  else
    e1^ := e1^ - e2^; // -
{$Else}
begin
  e1^ := e1^ - e2^; // -
{$EndIf}
{$EndIf}
end;

procedure C03(env: CEnv; e1, e2: PValue);
{$IfDef CalcOpt}
  procedure _C03;
{$IfDef FPC}
  var t: CValue;
{$EndIf}
  begin
{$IfDef FPC}
    if (PData(e1)^.VType <= varNull) or (PData(e2)^.VType <= varNull) then
    begin
      _NullNumE1(e1);
      t := _Num2(e2);
      e1^ := e1^ * t; // *
    end
    else
      e1^ := e1^ * e2^; // *
{$Else}
    e1^ := e1^ * e2^; // *
{$EndIf}
  end;

var i: fun.int;
{$IfDef CalcOpt}
    i64: fun.int64;
{$EndIf}
label _;
begin
  with PData(e1)^ do
  begin
    if VType = VarInteger then
    begin
      case PData(e2).VType of
        VarInteger:
        begin
          i64      := fun.int64(VInteger) * fun.int64(PData(e2).VInteger);
          if (i64 < Low(Integer)) or (i64 > High(Integer)) then goto _;
          i        := i64;
          VInteger := i;
          exit;
        end;
        VarDouble:
        begin
          VDouble  := VInteger * PData(e2).VDouble;
          VType    := VarDouble;
          exit;
        end;
      end;
    end
    else if VType = VarDouble then
    begin
      case PData(e2).VType of
        VarInteger:
        begin
          VDouble  := VDouble  * PData(e2).VInteger;
          exit;
        end;
        VarDouble:
        begin
          VDouble  := VDouble  * PData(e2).VDouble;
          exit;
        end;
      end;
    end;
  end;

  _: _C03;
{$Else}
{$IfDef FPC}
var t: CValue;
begin
  if (PData(e1)^.VType <= varNull) or (PData(e2)^.VType <= varNull) then
  begin
    _NullNumE1(e1);
    t := _Num2(e2);
    e1^ := e1^ * t; // *
  end
  else
    e1^ := e1^ * e2^; // *
{$Else}
begin
  e1^ := e1^ * e2^; // *
{$EndIf}
{$EndIf}
end;

{$IfDef FPC}
// Fun raises EZeroDivide for floating '/ 0' (as Delphi and the x86/ARM32
// builds do through the hardware FP trap). AArch64 leaves the FP exceptions
// masked, so the same expression yields +Inf there. Check the divisor
// explicitly so every target raises the same way; non-numeric operands are
// left to the Variant division, which reports its own coercion error.
procedure _CheckDivZero(const v: CValue);
var
  d: Double;
begin
  if PData(@v)^.VType <= varNull then
    raise EZeroDivide.Create(SZeroDivide)
  ;
  try
    d := v;
    if d = 0 then raise EZeroDivide.Create(SZeroDivide);
  except
    on E: EZeroDivide do raise;
    on E: Exception do ; // let the division report the coercion error
  end;
end;
{$EndIf}

procedure C04(env: CEnv; e1, e2: PValue);
{$IfDef CalcOpt}
  procedure _C04;
{$IfDef FPC}
  var t: CValue;
{$EndIf}
  begin
{$IfDef FPC}
    if (PData(e1)^.VType <= varNull) or (PData(e2)^.VType <= varNull) then
    begin
      _NullNumE1(e1);
      t := _Num2(e2);
      _CheckDivZero(t);
      e1^ := e1^ / t; // /
    end
    else
    begin
      _CheckDivZero(e2^);
      e1^ := e1^ / e2^; // /
    end;
{$Else}
    e1^ := e1^ / e2^; // /
{$EndIf}
  end;

//var i: fun.int;
label _;
begin
  with PData(e1)^ do
  begin
    if VType = VarInteger then
    begin
      case PData(e2).VType of
        VarInteger:
        begin
          // AArch64 leaves FP exceptions masked, so x/0 would yield +Inf
          // instead of raising here; fall back to _C04, which checks the
          // divisor explicitly on FPC.
          if PData(e2).VInteger = 0 then goto _;
          {i        := VInteger / PData(e2).VInteger;
          asm
            jo _
          end;
          VInteger := i;}
          VDouble  := VInteger / PData(e2).VInteger;
          VType    := VarDouble;
          exit;
        end;
        VarDouble:
        begin
          if PData(e2).VDouble = 0 then goto _;
          VDouble  := VInteger / PData(e2).VDouble;
          VType    := VarDouble;
          exit;
        end;
      end;
    end
    else if VType = VarDouble then
    begin
      case PData(e2).VType of
        VarInteger:
        begin
          if PData(e2).VInteger = 0 then goto _;
          VDouble  := VDouble  / PData(e2).VInteger;
          exit;
        end;
        VarDouble:
        begin
          if PData(e2).VDouble = 0 then goto _;
          VDouble  := VDouble  / PData(e2).VDouble;
          exit;
        end;
      end;
    end;
  end;

  _: _C04;
{$Else}
{$IfDef FPC}
var t: CValue;
begin
  if (PData(e1)^.VType <= varNull) or (PData(e2)^.VType <= varNull) then
  begin
    _NullNumE1(e1);
    t := _Num2(e2);
    _CheckDivZero(t);
    e1^ := e1^ / t; // /
  end
  else
  begin
    _CheckDivZero(e2^);
    e1^ := e1^ / e2^; // /
  end;
{$Else}
begin
  e1^ := e1^ / e2^; // /
{$EndIf}
{$EndIf}
end;

// Integer div/mod keep the Variant path as the source of truth for exceptional
// cases: a zero divisor and Low(Integer) div/mod -1 both fall through to the
// RTL, so the exception type and message stay exactly as before.
procedure C05(env: CEnv; e1, e2: PValue);
{$IfDef CalcOpt}
  procedure _C05;
{$IfDef FPC}
  var t: CValue;
{$EndIf}
  begin
{$IfDef FPC}
    if (PData(e1)^.VType <= varNull) or (PData(e2)^.VType <= varNull) then
    begin
      _NullNumE1(e1);
      t := _Num2(e2);
      e1^ := e1^ div t; // d
    end
    else
      e1^ := e1^ div e2^; // d
{$Else}
    e1^ := e1^ div e2^; // d
{$EndIf}
  end;

var i: fun.int;
label _;
begin
  with PData(e1)^ do
  begin
    if VType = VarInteger then
    begin
      case PData(e2).VType of
        VarInteger:
        begin
          // Zero and Low(Integer) / -1 both raise on the RTL path.
          if (PData(e2).VInteger = 0) or
             ((VInteger = Low(Integer)) and (PData(e2).VInteger = -1)) then
            goto _;
          i := VInteger div PData(e2).VInteger;
          VInteger := i;
          exit;
        end;
        {VarDouble:
        begin
          VDouble  := VInteger div PData(e2).VDouble;
          VType    := VarDouble;
          exit;
        end;
      end;
    end
    else if VType = VarDouble then
    begin
      case PData(e2).VType of
        VarInteger:
        begin
          VDouble  := VDouble  div PData(e2).VInteger;
          exit;
        end;
        VarDouble:
        begin
          VDouble  := VDouble  div PData(e2).VDouble;
          exit;
        end;}
      end;
    end;
  end;

  _: _C05;
{$Else}
{$IfDef FPC}
var t: CValue;
begin
  if (PData(e1)^.VType <= varNull) or (PData(e2)^.VType <= varNull) then
  begin
    _NullNumE1(e1);
    t := _Num2(e2);
    e1^ := e1^ div t; // d
  end
  else
    e1^ := e1^ div e2^; // d
{$Else}
begin
  e1^ := e1^ div e2^; // d
{$EndIf}
{$EndIf}
end;

// See C05: only the plain Integer/Integer case is fast-pathed.
procedure C06(env: CEnv; e1, e2: PValue);
{$IfDef CalcOpt}
  procedure _C06;
{$IfDef FPC}
  var t: CValue;
{$EndIf}
  begin
{$IfDef FPC}
    if (PData(e1)^.VType <= varNull) or (PData(e2)^.VType <= varNull) then
    begin
      _NullNumE1(e1);
      t := _Num2(e2);
      e1^ := e1^ mod t; // m
    end
    else
      e1^ := e1^ mod e2^; // m
{$Else}
    e1^ := e1^ mod e2^; // m
{$EndIf}
  end;

var i: fun.int;
label _;
begin
  with PData(e1)^ do
  begin
    if VType = VarInteger then
    begin
      case PData(e2).VType of
        VarInteger:
        begin
          // Zero and Low(Integer) mod -1 both raise on the RTL path.
          if (PData(e2).VInteger = 0) or
             ((VInteger = Low(Integer)) and (PData(e2).VInteger = -1)) then
            goto _;
          i := VInteger mod PData(e2).VInteger;
          VInteger := i;
          exit;
        end;
        {VarDouble:
        begin
          VDouble  := VInteger mod PData(e2).VDouble;
          VType    := VarDouble;
          exit;
        end;
      end;
    end
    else if VType = VarDouble then
    begin
      case PData(e2).VType of
        VarInteger:
        begin
          VDouble  := VDouble  mod PData(e2).VInteger;
          exit;
        end;
        VarDouble:
        begin
          VDouble  := VDouble  mod PData(e2).VDouble;
          exit;
        end;}
      end;
    end;
  end;

  _: _C06;
{$Else}
{$IfDef FPC}
var t: CValue;
begin
  if (PData(e1)^.VType <= varNull) or (PData(e2)^.VType <= varNull) then
  begin
    _NullNumE1(e1);
    t := _Num2(e2);
    e1^ := e1^ mod t; // m
  end
  else
    e1^ := e1^ mod e2^; // m
{$Else}
begin
  e1^ := e1^ mod e2^; // m
{$EndIf}
{$EndIf}
end;

procedure C07(env: CEnv; e1, e2: PValue);
begin
  e1^ := power(e1^, e2^); // ^
end;

procedure C08(env: CEnv; e1, e2: PValue);
begin
  e1^ := not PData(e1).VLongWord; // N
end;

procedure C09(env: CEnv; e1, e2: PValue);
begin
  e1^ := PData(e1).VLongWord and PData(e2).VLongWord; // A
end;

procedure C10(env: CEnv; e1, e2: PValue);
begin
  e1^ := PData(e1).VLongWord or  PData(e2).VLongWord; // O
end;

procedure C11(env: CEnv; e1, e2: PValue);
begin
  e1^ := PData(e1).VLongWord xor PData(e2).VLongWord; // X
end;

procedure C12(env: CEnv; e1, e2: PValue);
begin
  e1^ := PData(e1).VLongWord shl PData(e2).VLongWord; // L
end;

procedure C13(env: CEnv; e1, e2: PValue);
begin
  e1^ := PData(e1).VLongWord shr PData(e2).VLongWord; // R
end;

// Small non-negative integers are the most common thing concatenated to text
// (counters, indexes, loop variables). Caching their decimal form avoids a
// fresh IntToStr allocation per `&`. Filled once in InitCalc, read-only after.
var
  _intStr: array[0..1023] of fun.str;

function _StrVal(p: PValue): fun.str;
var
  v: fun.int;
begin
  if PData(p).VType = VarInteger then
  begin
    v := PData(p).VInteger;
    if (v >= 0) and (v <= High(_intStr)) then
      result := _intStr[v]
    else
      result := IntToStr(v);
  end
  else
    result := fun.str(p^);
end;

procedure C14(env: CEnv; e1, e2: PValue);
var
  s: fun.str;
begin
  // Avoid two Variant->AnsiString casts when both sides already are varString
  // (the common `s1 & s2` case). The result and the assignment below are the
  // same; only the conversion path is shorter.
  if (PData(e1).VType = varString) and (PData(e2).VType = varString) then
    e1^ := fun.str(PData(e1).VString) + fun.str(PData(e2).VString) // &
  else
  begin
    s := _StrVal(e1) + _StrVal(e2);
    // `'' & 1` can return the cached "1" buffer itself. Raw primitives such as
    // fromByte write through the pointer without COW, so make sure the result
    // never aliases a cache entry.
    UniqueString(s);
    e1^ := s; // &
  end;
end;

procedure C15(env: CEnv; e1, e2: PValue);
{$IfDef CalcOpt}
var i: fun.int;
{$EndIf}
begin
{$IfDef CalcOpt}
  if (PData(e1).VType = VarInteger) and (PData(e2).VType = VarInteger) then
  begin
    // Same three-way test as varComp's integer branch (including its current
    // subtraction overflow behaviour), just without the call/null/object scan.
    i := PData(e1).VInteger - PData(e2).VInteger;
    setBool(e1, i = 0); // =
    exit;
  end;
{$EndIf}
  setBool(e1, _Comp(env, e1, e2) = EQ); // =
end;

procedure C16(env: CEnv; e1, e2: PValue);
{$IfDef CalcOpt}
var i: fun.int;
{$EndIf}
begin
{$IfDef CalcOpt}
  if (PData(e1).VType = VarInteger) and (PData(e2).VType = VarInteger) then
  begin
    i := PData(e1).VInteger - PData(e2).VInteger;
    setBool(e1, i <> 0); // !
    exit;
  end;
{$EndIf}
  setBool(e1, _Comp(env, e1, e2) <> EQ); // !
end;

procedure C17(env: CEnv; e1, e2: PValue);
{$IfDef CalcOpt}
var i: fun.int;
{$EndIf}
begin
{$IfDef CalcOpt}
  if (PData(e1).VType = VarInteger) and (PData(e2).VType = VarInteger) then
  begin
    i := PData(e1).VInteger - PData(e2).VInteger;
    setBool(e1, i < 0); // <
    exit;
  end;
{$EndIf}
  setBool(e1, _Comp(env, e1, e2) = LT); // <
end;

procedure C18(env: CEnv; e1, e2: PValue);
{$IfDef CalcOpt}
var i: fun.int;
{$EndIf}
begin
{$IfDef CalcOpt}
  if (PData(e1).VType = VarInteger) and (PData(e2).VType = VarInteger) then
  begin
    i := PData(e1).VInteger - PData(e2).VInteger;
    setBool(e1, i <= 0); // l
    exit;
  end;
{$EndIf}
  setBool(e1, _Comp(env, e1, e2) <> GT); // l
end;

procedure C19(env: CEnv; e1, e2: PValue);
{$IfDef CalcOpt}
var i: fun.int;
{$EndIf}
begin
{$IfDef CalcOpt}
  if (PData(e1).VType = VarInteger) and (PData(e2).VType = VarInteger) then
  begin
    i := PData(e1).VInteger - PData(e2).VInteger;
    setBool(e1, i > 0); // >
    exit;
  end;
{$EndIf}
  setBool(e1, _Comp(env, e1, e2) = GT); // >
end;

procedure C20(env: CEnv; e1, e2: PValue);
{$IfDef CalcOpt}
var i: fun.int;
{$EndIf}
begin
{$IfDef CalcOpt}
  if (PData(e1).VType = VarInteger) and (PData(e2).VType = VarInteger) then
  begin
    i := PData(e1).VInteger - PData(e2).VInteger;
    setBool(e1, i >= 0); // g
    exit;
  end;
{$EndIf}
  setBool(e1, _Comp(env, e1, e2) <> LT); // g
end;

procedure C21(env: CEnv; e1, e2: PValue);
begin
  setBool(e1, _CompIn(env, e1, e2)); // i
end;

procedure C22(env: CEnv; e1, e2: PValue);
begin
  e1^ := _Match(env, e1, e2); // ~
end;

procedure C23(env: CEnv; e1, e2: PValue);
begin
  setBool(e1, _MatchNot(env, e1, e2)); // $
end;

procedure C24(env: CEnv; e1, e2: PValue);
begin
  setBool(e1, not funBoolOf(e1)); // n
end;

procedure C25(env: CEnv; e1, e2: PValue);
begin
  setBool(e1, funBoolOf(e1) and funBoolOf(e2)); // a
end;

procedure C26(env: CEnv; e1, e2: PValue);
begin
  setBool(e1, funBoolOf(e1) or  funBoolOf(e2)); // o
end;

procedure C27(env: CEnv; e1, e2: PValue);
begin
  setBool(e1, funBoolOf(e1) xor funBoolOf(e2)); // x
end;

//==============================================================
var
  CX: array[#33..#126] of fun.ptr;

procedure InitCalc();
var
  i: fun.int;
begin
  for i := 0 to High(_intStr) do _intStr[i] := IntToStr(i);
  CX['+'] := @C01;
  CX['-'] := @C02;
  CX['*'] := @C03;
  CX['/'] := @C04;
  CX['d'] := @C05;
  CX['m'] := @C06;
  CX['^'] := @C07;
  CX['N'] := @C08;
  CX['A'] := @C09;
  CX['O'] := @C10;
  CX['X'] := @C11;
  CX['L'] := @C12;
  CX['R'] := @C13;
  CX['&'] := @C14;
  CX['='] := @C15;
  CX['!'] := @C16;
  CX['<'] := @C17;
  CX['l'] := @C18;
  CX['>'] := @C19;
  CX['g'] := @C20;
  CX['i'] := @C21;
  CX['~'] := @C22;
  CX['$'] := @C23;
  CX['n'] := @C24;
  CX['a'] := @C25;
  CX['o'] := @C26;
  CX['x'] := @C27;
end;

//==============================================================
type
  CA = procedure (env: CEnv; e1, e2: PValue);

procedure DoCalc(env: CEnv; e1, e2: PValue; op: fun.char);
begin
  if CX[op] = nil then
    e1^ := NullValue
  else
    CA(CX[op])(env, e1, e2);
end;
