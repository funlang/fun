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
unit calc;

interface

uses fun, base, core;

const
  OP_AND  = 'a';
  OP_OR   = 'o';

type

  CCCTwo = class of CCTwo;

  CCalc = class(CExp)
  end;
  
  CCone = class(CCalc)
  protected
    exp: CExp;
    op: fun.char;
  public
    destructor Destroy; override;
    procedure calc(env: CEnv); override;
    function parse(aexp: CExp; aop: fun.char): CNode;
  end;
  
  CCtwo = class(CCone)
  protected
    exp2: CExp;
  public
    destructor Destroy; override;
    procedure calc(env: CEnv); override;
    function parse(aexp: CExp; aop: fun.char; aexp2: CExp): CNode;
  end;
  
  CCAnd = class(CCtwo)
  public
    procedure calc(env: CEnv); override;
  end;
  
  CCOr = class(CCtwo)
  public
    procedure calc(env: CEnv); override;
  end;


// for flow
function _CompIn(env: CEnv; e1, e2: PValue): fun.bool;
function _Match(env: CEnv; e1, e2: PValue): CValue;

implementation

uses Math, SysUtils, SysConst;

{$I 'calc.inc'}

//==============================================================
destructor CCone.Destroy;
begin
  del(exp);
  inherited Destroy;
end;

procedure CCone.calc(env: CEnv);
begin
  // Value Assign (one capture; p_val must not alias exp's storage)
  copyValue(p_val, exp.calcValue(env));
  DoCalc(env, p_val, @NullValue, op);
end;

function CCone.parse(aexp: CExp; aop: fun.char): CNode;
begin
  result := self;
  exp    := aexp;
  op     := aop;
end;

//==============================================================
destructor CCtwo.Destroy;
begin
  del(exp2);
  inherited Destroy;
end;

procedure CCtwo.calc(env: CEnv);
var
  v: CValue;
  p: PValue;
begin
  // The left operand must be captured on the Pascal stack, not in p_val: a
  // recursive call on the right re-enters this same AST node and overwrites
  // p_val (fact(n) = n * fact(n-1) depends on this). Assigning p_val only after
  // the right side is evaluated keeps that reentry safe while avoiding the
  // extra CValue(v) temporary the old code built.
  v      := (exp.calcValue(env))^;
  p      := exp2.calcValue(env);
  copyValue(p_val, @v);
  DoCalc(env, p_val, p, op);
end;

function CCtwo.parse(aexp: CExp; aop: fun.char; aexp2: CExp): CNode;
begin
  result := inherited parse(aexp, aop);
  exp2   := aexp2;
end;

//==============================================================
procedure CCAnd.calc(env: CEnv);
var
  v: CValue;
  p: PValue;
begin
  v := (exp.calcValue(env))^;
  if funBoolOf(@v) then
  begin
    p      := exp2.calcValue(env);
    copyValue(p_val, p);
  end
  else
    copyValue(p_val, @v);
end;

//==============================================================
procedure CCOr.calc(env: CEnv);
var
  v: CValue;
  p: PValue;
begin
  v := (exp.calcValue(env))^;
  if not funBoolOf(@v) then
  begin
    p      := exp2.calcValue(env);
    copyValue(p_val, p);
  end
  else
    copyValue(p_val, @v);
end;

initialization
  InitCalc();

end.
