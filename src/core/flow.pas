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
unit flow;

interface

uses fun, base, core;

type

  CFlow = class(CBloc)
  end;
  
  CIf = class(CFlow)
  protected
    exps: CList;
    nelse: CRun;
    function isTrue(env: CEnv; i: fun.int): fun.bool; virtual;
  public
    destructor Destroy; override;
    function parse(aexp: CExp): CNode;
    procedure run(env: CEnv); override;
    function UID(const n: fun.str): CVar; override;
  end;
  
  CCase = class(CIf)
  protected
    evar: CVar;
    exp: CExp;
    function isTrue(env: CEnv; i: fun.int): fun.bool; override;
  public
    destructor Destroy; override;
    function parse(aexp: CExp): CNode;
    procedure run(env: CEnv); override;
  end;
  
  CLoop = class(CFlow)
  protected
    exp: CExp;
  public
    isExit: fun.bool;
    destructor Destroy; override;
    function parse(aexp: CExp): CNode;
    procedure run(env: CEnv); override;
  end;
  
  CForTo = class(CLoop)
  protected
    emax: CExp;
    estep: CExp;
    evar: CVar;
  public
    destructor Destroy; override;
    function parse(const id: fun.str; aexp, amax, astep: CExp): CNode;
    procedure run(env: CEnv); override;
  end;
  
  CForIn = class(CLoop)
  protected
    eidx: CVar;
    ekey: CVar;
    evar: CVar;
  public
    function parse(const id: fun.str; aexp: CExp; const key: fun.str = ''; const idx: fun.str = ''): CNode;
    procedure run(env: CEnv); override;
  end;
  
  CNext = class(CGoto)
  public
    procedure afterRun; virtual;
    procedure run(env: CEnv); override;
  end;
  
  CExit = class(CNext)
  public
    procedure afterRun; override;
  end;
  
  CTry = class(CFlow)
  protected
    evar: CVar;
    nexcept: CRuns;
    nfinally: CRun;
  public
    destructor Destroy; override;
    procedure run(env: CEnv); override;
  end;
  
  CRaise = class(CGoto)
  public
    procedure run(env: CEnv); override;
  end;

implementation

uses calc
     {$IfDef Regex}
     , regex
     {$EndIf}
     {$IfDef WinCOM}
     , ActiveX
     {$EndIf}
     ;

//==============================================================
destructor CIf.Destroy;
begin
  del(exps);
  del(nelse);
  inherited Destroy;
end;

function CIf.isTrue(env: CEnv; i: fun.int): fun.bool;
begin
  result := CExp(exps[i]).calcAsBool(env);
  /// @ <- =~
  // todo
end;

function CIf.parse(aexp: CExp): CNode;
begin
  inherited parse();
  if exps = nil then exps := CList.Create();
  exps.add(aexp);
  result := CRuns.new(self);
  all.add(result);
end;

procedure CIf.run(env: CEnv);
var
  i: fun.int;
begin
  for i := 0 to exps.count-1 do
  begin
    if isTrue(env, i) then
    begin
  {$IfDef IDE}
      env.traced(self, true);
  {$EndIf}
      all[i].run(env);
      exit;
    end;
  end;
  
  if nelse <> nil then
  begin
  {$IfDef IDE}
    env.traced(self, true);
  {$EndIf}
    nelse.run(env);
  end;
end;

function CIf.UID(const n: fun.str): CVar;
begin
  result := all.ID[n];
  if result = nil then result := inherited UID(n);
end;

//==============================================================
destructor CCase.Destroy;
begin
  del(exp);
  inherited Destroy;
end;

function CCase.isTrue(env: CEnv; i: fun.int): fun.bool;
var
  v2: PValue;
  mv: CValue;
begin
  v2 := CExp(exps[i]).calcValue(env);
  if asObj(v2) is CSet then
    result := _CompIn(env, exp.value, v2)
  {$IfDef Regex}
  else if asObj(v2) is CRegex then
  begin
    // _Match returns a CMatch object variant; on FPC assigning it directly to
    // Boolean does not route through CastTo, so coerce via funBoolOf.
    mv := _Match(env, exp.value, v2);
    result := funBoolOf(@mv);
  end
  {$EndIf}
  else
    result := varComp(exp.value, v2, env.isCase) = EQ
  ;
end;

function CCase.parse(aexp: CExp): CNode;
begin
  result := CBloc(self).parse();
  exp    := aexp;
  evar   := CVar.new(all, _AT);
  // prevent codes before "when" ...
  result := self;
end;

procedure CCase.run(env: CEnv);
begin
  /// @ <- exp
  evar.assign(exp.calcValue(env));
  inherited run(env);
end;

//==============================================================
destructor CLoop.Destroy;
begin
  del(exp);
  inherited Destroy;
end;

function CLoop.parse(aexp: CExp): CNode;
begin
  result := inherited parse();
  exp    := aexp;
end;

procedure CLoop.run(env: CEnv);
begin
  while (exp = nil) or exp.calcAsBool(env) do
  begin
  {$IfDef IDE}
    env.traced(self, true);
  {$EndIf}
    all.run(env);
  
    if isExit then begin
      isExit := false;
      break;
    end;
    env.trace(self);
  end;
end;

//==============================================================
destructor CForTo.Destroy;
begin
  del(emax);
  del(estep);
  inherited Destroy;
end;

function CForTo.parse(const id: fun.str; aexp, amax, astep: CExp): CNode;
begin
  result := inherited parse(aexp);
  emax   := amax;
  estep  := astep;
  evar   := CVar.new(all, id);
end;

procedure CForTo.run(env: CEnv);
var
  vi, si, mi: fun.int;
  vv: CData;
begin
  exp .calc(env);
  emax.calc(env);
  vi := exp .asInt;
  mi := emax.asInt;
  si := 1;
  if estep <> nil then
  begin
    estep.calc(env);
    si := estep.asInt;
  end;
  // CData
  vv.VType := VarInteger;
  
  while ((si > 0) and (vi <= mi)) or
        ((si < 0) and (vi >= mi)) do
  begin
    // CData
    vv.VInteger := vi;
    evar.assign(CValue(vv));
  {$IfDef IDE}
    env.traced(self, true);
  {$EndIf}
    all.run(env);
  
    if isExit then begin
      isExit := false;
      break;
    end;
    env.trace(self);
  
    inc(vi, si);
  end;
end;

//==============================================================
function CForIn.parse(const id: fun.str; aexp: CExp; const key: fun.str = ''; const idx: fun.str = ''): CNode;
begin
  result := inherited parse(aexp);
  evar   := CVar.new(all, id);
  if key <> '' then ekey := CVar.new(all, key);
  if idx <> '' then eidx := CVar.new(all, idx);
end;

procedure CForIn.run(env: CEnv);
var
  i, ii: fun.int;
  s, e: CExp;
  enum: {$IfDef WinCOM}IEnumVariant{$Else}Variant{$EndIf};
  v: OleVariant;
  l: LongWord;
begin
  exp.calc(env);
  s := exp;
  if not (s is CSet) and (s.asObj is CSet) then
    s := CSet(s.asObj)
  {$IfDef WinCOM}
  else if isOle(s.value) then
  begin
    enum := IUnknown(s.value^._NewEnum) as IEnumVariant;
    try
      while enum.Next(1, v, l) = 0 do
      begin
        try
          evar.assign(v);
        {$IfDef IDE}
          env.traced(self, true);
        {$EndIf}
          all.run(env);
        finally
          v := NullValue;
        end;
  
        if isExit then begin
          isExit := false;
          break;
        end;
        env.trace(self);
      end;
    finally
      enum := nil;
    end;
    exit;
  end
  {$EndIf}
  ;
  ii := s.count();
  for i := 0 to ii -1 do
  begin
    e := s.item[i];
    if e = nil then
      evar.assign(NullValue)
    else
      evar.assign(e)
    ;
    if ekey <> nil then ekey.assign(e.name);
    if eidx <> nil then eidx.assign(i);
  {$IfDef IDE}
    env.traced(self, true);
  {$EndIf}
    all.run(env);
  
    if isExit then begin
      isExit := false;
      break;
    end;
    env.trace(self);
  end;
end;

//==============================================================
procedure CNext.afterRun;
begin
  // no action
end;

procedure CNext.run(env: CEnv);
begin
  if (exp = nil) or exp.calcAsBool(env) then
  begin
    inherited run(env);
    afterRun();
  end;
end;

//==============================================================
procedure CExit.afterRun;
begin
  if target.parent is CLoop then CLoop(target.parent).isExit := true;
end;

//==============================================================
destructor CTry.Destroy;
begin
  del(nexcept);
  del(nfinally);
  inherited Destroy;
end;

procedure CTry.run(env: CEnv);
begin
  try
    try
  {$IfDef IDE}
      env.traced(self, true);
  {$EndIf}
      all.run(env);
    except
      on e: EBase do
      begin
        // Capture before the surrounding finally can overwrite lastNode.
        {$IfDef FunTraceback}
        env.beginError(e);
        {$EndIf}
        if nexcept <> nil then
        begin
          env.traceErrorNode(e.message, e.ClassName);
          /// var exception
          if evar = nil then evar := CVar.new(nexcept, _AT);
          evar.assign(e.message);
          nexcept.run(env);
          {$IfDef FunTraceback}
          env.endError(e);
          {$EndIf}
        end
        else
        begin
          raise;
        end;
      end;
    end;
  finally
    if nfinally <> nil then
    begin
      nfinally.run(env);
    end;
  end;
end;

//==============================================================
procedure CRaise.run(env: CEnv);
begin
  raise EBase.Create(exp.calcValue(env)^);
end;

end.
