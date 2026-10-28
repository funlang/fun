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

type
  CKeyValue = record
    key     : fun.str;
    value   : fun.int;
  end;

const
  Ids : array [1..40] of CKeyValue =
    (
      ( key: 'and'     ; value:   opAnd     ),
      ( key: 'as'      ; value: _as         ),
      ( key: 'atom'    ; value: _atom       ),
      ( key: 'bit'     ; value:   opBit     ),
      ( key: 'case'    ; value: _case       ),
      ( key: 'class'   ; value: _class      ),
      ( key: 'div'     ; value:   opMulDiv  ),
      ( key: 'do'      ; value: _do         ),
      ( key: 'else'    ; value: _else       ),
      ( key: 'elsif'   ; value: _elsif      ),
      ( key: 'end'     ; value: _end        ),
      ( key: 'except'  ; value: _except     ),
      ( key: 'exit'    ; value: _exit       ),
      ( key: 'false'   ; value: _false      ),
      ( key: 'finally' ; value: _finally    ),
      ( key: 'for'     ; value: _for        ),
      ( key: 'fun'     ; value: _fun        ),
      ( key: 'if'      ; value: _if         ),
      ( key: 'in'      ; value: _in         ),
      ( key: 'is'      ; value: _is         ),
      ( key: 'loop'    ; value: _loop       ),
      ( key: 'mod'     ; value:   opMulDiv  ),
      ( key: 'new'     ; value: _new        ),
      ( key: 'next'    ; value: _next       ),
      ( key: 'nil'     ; value: _null       ),
      ( key: 'not'     ; value:   opNot     ),
      ( key: 'null'    ; value: _null       ),
      ( key: 'or'      ; value:   opOr      ),
      ( key: 'raise'   ; value: _raise      ),
      ( key: 'return'  ; value: _return     ),
      ( key: 'step'    ; value: _step       ),
      ( key: 'then'    ; value: _then       ),
      ( key: 'to'      ; value: _to         ),
      ( key: 'true'    ; value: _true       ),
      ( key: 'try'     ; value: _try        ),
      ( key: 'use'     ; value: _use        ),
      ( key: 'var'     ; value: _var        ),
      ( key: 'when'    ; value: _when       ),
      ( key: 'while'   ; value: _while      ),
      ( key: 'xor'     ; value:   opOr      )
    );

const
  _Error = 256;

function ParseId({$IfNDef _C_}const {$EndIf}s: fun.str): fun.int;
var
  L, H, k, i: integer;
  // Reserved words are valid member names: obj.fun / obj?.fun.
  function IsMemberPosition: boolean;
  begin
    // Member access.  The parser driver flags a shifted '.' by asking the
    // generated action table whether the resulting state accepts an
    // expression start (Num).  That distinguishes `obj.fun` / `obj?.fun`
    // from the echo operator `?. exp` without a hand-written token list.
    result := (yyPrevToken = Ord('.')) and yyDotIsMember;
  end;
begin
  {$IfDef _C_}
  s := ParseAlias(s);
  {$EndIf}
  result := Id;
  L := Low (Ids);
  H := High(Ids);
  while L <= H do
  begin
    k := L + (H - L) div 2;
    i := CompareStr(s, Ids[k].key);
    if i > 0 then L := k + 1 else
    if i < 0 then H := k - 1 else
    begin
      result := Ids[k].value;
      if (result <> Id) and IsMemberPosition then
      begin
        return(Id);
        exit;
      end;
      break;
    end;
  end;

  // `bit` is a two-token operator.  `yyPrevToken = _bit` is the pending
  // prefix; its continuation must be the next identifier in this lex call.
  if yyPrevToken = _bit then
  begin
    yyPrevToken := 0;
    if result = opNot then
      result := opBitNot
    else if (result = opAnd) or (result = opOr) then
      result := opBit
    else if result <> Id then
      result := _Error;
  end
  else if result = opBit then
  begin
    yyPrevToken := _bit;
    exit;
  end;

  return(result);
end;
