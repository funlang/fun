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
unit core;

interface

uses fun, base;

const
  _THIS   = 'this';
  _BASE   = 'base';
  _RESULT = 'result';
  _AT     = '@';

const
  _NotFound = ' not found';
  _Exists   = ' exists';

const
  CDoMethod    = $01;
  CPropertyGet = $02;
  CPropertySet = $04;

type
  CEnv  = class;
  CExp  = class;
  CVar  = class;
  CExps = class;
  CNew  = class;
  CObj  = class;
  CRuns = class;

  CNode = class(CBase)
  public
    name: fun.str;
    parent: CNode;
    constructor new(pn: CNode; isAdd: fun.bool = false);
    procedure add(cn: CNode); virtual;
    function call(env: CEnv; const exps: array of const): PValue; overload;
    function call(env: CEnv; exps: CExps): PValue; overload; virtual;
    function root: CNode;
    function UID(const n: fun.str): CVar; virtual;
    procedure use(n : CRuns; const id: fun.str = ''); virtual;
  end;
  
  CRun = class(CNode)
  public
    procedure run(env: CEnv); virtual;
  end;
  
  CRune = class(CRun)
  public
    row: fun.int;
  end;
  
  CRuna = class(CRune)
  end;
  
  CGoto = class(CRuna)
  protected
    exp: CExp;
    target: CRuns;
  public
    destructor Destroy; override;
    function parse(atarget: CNode; aexp: CExp): CNode;
    procedure run(env: CEnv); override;
  end;
  
  CReturn = class(CGoto)
  public
    procedure run(env: CEnv); override;
  end;
  
  CAssign = class(CRuna)
  protected
    evar: CExp;
    exp: CExp;
  public
    destructor Destroy; override;
    function parse(avar, aexp: CExp): CNode;
    procedure run(env: CEnv); override;
  end;

  // Assignment to a plain variable. The first run resolves the target slot
  // kind and caches it; later runs read/write the slots directly instead of
  // repeating the virtual assign -> stack.Push chain.
  CAssignFast = class(CAssign)
  private
    FInit: Boolean;
    FFast: Boolean;
    FTargetIsRE: Boolean;
    FSourceIsId: Boolean;
  public
    procedure run(env: CEnv); override;
  end;
  
  CCall = class(CRuna)
  protected
    exp: CExp;
  public
    destructor Destroy; override;
    function parse(aexp: CExp): CNode;
    procedure run(env: CEnv); override;
    {$IfDef IDE}
    property Expr: CExp read exp;
    {$EndIf}
  end;
  
  CEcho = class(CCall)
  protected
    extra: fun.str;
  public
    function parse(aexp: CExp; const aextra: fun.str = ''): CNode;
    procedure run(env: CEnv); override;
  end;
  
  CRuns = class(CRun)
  private
    function GetID(const name: fun.str): CVar;
    function GetND(i: fun.int): CRun;
    procedure SetID(const name: fun.str; Value: CVar);
  protected
    isExit: fun.bool;
    runs: CList;
    used: CList;
    vars: CHash;
  public
    constructor new(pn: CNode; isAdd: fun.bool = false);
    destructor Destroy; override;
    procedure add(cn: CNode); override;
    procedure run(env: CEnv); override;
    function UID(const n: fun.str): CVar; override;
    procedure use(n : CRuns; const id: fun.str = ''); override;
    property ID[const name: fun.str]: CVar read GetID write SetID;
    property ND[i: fun.int]: CRun read GetND; default;
  end;
  
  CModu = class(CRuns)
  private
    useLevel: fun.int;
  protected
    next: CModu;
    runed: fun.bool;
    function find(const fn: fun.str): CModu;
  public
    fileName: fun.str;
    function call(env: CEnv; exps: CExps): PValue; overload; override;
    procedure run(env: CEnv); override;
    function UID(const n: fun.str): CVar; override;
  end;
  
  CBloc = class(CRune)
  protected
    all: CRuns;
  public
    destructor Destroy; override;
    function parse: CNode;
  end;
  
  CFun = class(CBloc)
  private
    procedure doCall(env: CEnv; exps: CExps);
    procedure doCopy(items, exps: CExps);
    function doFind(const n: fun.str): CVar;
    function newObj: CObj;
  protected
    baseVar: CVar;
    evar: CVar;
    id: fun.str;
    isClass: fun.bool;
    params: CExps;
    stack: CFunStack;
    thisVar: CVar;
    upClass: CFun;
    vars: CHash;
    procedure popObj;
    procedure pushObj(obj: CObj);
  public
    constructor new(pn: CNode; isAdd: fun.bool = false);
    destructor Destroy; override;
    function call(env: CEnv; exps: CExps): PValue; overload; override;
    function parse(const id: fun.str; aps: CExps; aupClass: CFun = nil; aisClass: fun.bool = false): CNode;
    function UID(const n: fun.str): CVar; override;
  end;
  
  CExp = class(CNode)
  protected
    p_val: PValue;
    v_val: CValue;
    function Getitem(i: fun.int): CExp; virtual;
  public
    constructor new(pn: CNode; isAdd: fun.bool = false);
    function asBool: fun.bool;
    function asInt: fun.int;
    function asObj: CBase;
    procedure assign(obj: CBase); overload; virtual;
    procedure assign(exp: CExp); overload;
    procedure assign(obj: CNew); overload; virtual;
    procedure assign(const val: CValue); overload; virtual;
    procedure assign(val: PValue); overload; virtual;
    function asStr: fun.str;
    procedure calc(env: CEnv); virtual;
    function calcAsBool(env: CEnv): fun.bool;
    function calcValue(env: CEnv): PValue;
    function clone(env: CEnv): CExp; virtual;
    function count: fun.int; virtual;
    function parse(const val: CValue): CExp;
    function value: PValue; virtual;
    property item[i: fun.int]: CExp read Getitem;
  end;
  
  CExps = class(CHist)
  private
    procedure _append(p: fun.ptr);
  public
    function Add(p: fun.ptr): fun.int; override;
    procedure append(exps: CExps); overload;
    procedure append(exps: CHash); overload;
    procedure assign(exps: CExps);
    procedure calc(env: CEnv);
    function clone(env: CEnv): CExps;
    class function Count(exps: CExps): fun.int; overload;
    class function Find(exps: CExps; const id: fun.str; idx: fun.int): CExp;
    class function FindAsVal(exps: CExps; const id: fun.str; idx: fun.int; def: fun.bool): fun.bool; overload;
    class function FindAsVal(exps: CExps; const id: fun.str; idx: fun.int; def: fun.int): fun.int; overload;
    class function FindAsVal(exps: CExps; const id: fun.str; idx: fun.int; const def: fun.str): fun.str; overload;
  end;
  
  CVar = class(CExp)
  public
    constructor new(pn: CNode; isAdd: fun.bool = false); overload;
    class function findOwner(parent: CNode): CFun;
    class function new(pn: CRuns; const id: fun.str = ''; allowClass: fun.bool = false): CVar; overload;
  end;
  
  CVarRE = class(CVar)
  protected
    owner: CFun;
    stack: CVarStack;
  public
    destructor Destroy; override;
    procedure assign(obj: CBase); overload; override;
    procedure assign(obj: CNew); overload; override;
    procedure assign(const val: CValue); overload; override;
    procedure assign(val: PValue); overload; override;
    function DirectTarget: PValue;
  end;
  
  CLeft = class(CExp)
  end;
  
  CId = class(CLeft)
  protected
    evar: CExp;
    // Nil cell handed out when `x?` cannot resolve a name. The old code did
    // CExp.new(nil) on every evaluation, but evar is a borrowed field (nothing
    // del's it in Destroy), so every evaluation leaked one CExp -- a 20000
    // iteration loop grew RSS by 1.8MB. Allocate once and reset the value to nil
    // before handing it out: same observable behavior as a fresh cell every time,
    // without the allocation.
    enil: CExp;
    opt: fun.bool;
    procedure done(flag: fun.int); virtual;
    function find(isSet: fun.bool = false; needCalc: fun.bool = true): fun.int; virtual;
    function Getitem(i: fun.int): CExp; override;
  public
    id: fun.str;
    destructor Destroy; override;
    procedure assign(obj: CBase); overload; override;
    procedure assign(obj: CNew); overload; override;
    procedure assign(const val: CValue); overload; override;
    procedure assign(val: PValue); overload; override;
    function call(env: CEnv; exps: CExps): PValue; overload; override;
    function count: fun.int; override;
    function parse(const aid: fun.str; avar: CVar = nil; optional: fun.bool = false): CExp;
    function value: PValue; override;
  end;
  
  CId2 = class(CId)
  private
    enull: CExp;
    // Same as CId.enil: the nil cell handed out when `a.b?` has a nil base,
    // allocated once instead of per lookup.
    eopt: CExp;
  protected
    eole: CExp;
    exp: CExp;
    procedure done(flag: fun.int); override;
    function find(isSet: fun.bool = false; needCalc: fun.bool = true): fun.int; override;
  public
    destructor Destroy; override;
    procedure calc(env: CEnv); override;
    function call(env: CEnv; exps: CExps): PValue; overload; override;
    function parse(const aid: fun.str; aexp: CExp; optional: fun.bool = false): CExp;
    function value: PValue; override;
  end;
  
  CIdx = class(CId2)
  protected
    idx: CExp;
    // Result cell for string index reads. The old code did CExp.new(nil) on every
    // `s[i]` and evar is a borrowed field, so every read leaked one CExp -- 20000
    // reads of s[0] grew RSS by 3.2MB. One cell is enough: the string branch
    // always assigns the current value into it.
    estr: CExp;
    procedure done(flag: fun.int); override;
    function find(isSet: fun.bool = false; needCalc: fun.bool = true): fun.int; override;
  public
    destructor Destroy; override;
    procedure calc(env: CEnv); override;
    function parse(const aid: fun.str; aexp, aidx: CExp): CExp;
  end;
  
  CFunc = class(CExp)
  protected
    exp: CExp;
    fun2: fun.bool;
    ps: CExps;
  public
    destructor Destroy; override;
    procedure calc(env: CEnv); override;
    function call(env: CEnv; exps: CExps): PValue; overload; override;
    function parse(aexp: CExp; aps: CExps): CNode;
  end;
  
  CSet = class(CExp)
  private
    calced: fun.bool;
    exps: CExps;
  protected
    function Getitem(i: fun.int): CExp; override;
  public
    destructor Destroy; override;
    procedure calc(env: CEnv); override;
    function clone(env: CEnv): CExp; override;
    function count: fun.int; override;
    function items: CExps;
    function parse(aexps: CExps): CNode;
  end;
  
  CSet2 = class(CExp)
  protected
    eset: CExp;
  public
    destructor Destroy; override;
    procedure calc(env: CEnv); override;
    function parse(aset: CExp): CNode;
  end;
  
  CNew = class(CSet)
  end;
  
  CNew2 = class(CNew)
  end;
  
  CObj = class(CNew2)
  protected
    function fun: CFun;
  public
    function clone(env: CEnv): CExp; override;
    procedure pop;
    function push: fun.bool;
  end;
  
  CEnv = class(CBase)
  public
    lastError: CNode;
    lastNode: CNode;
    {$IfDef FunTraceback}
    // Live dynamic call chain (innermost last) and a snapshot taken the first
    // time the pending error leaves a function frame. `calls` unwinds normally
    // via try/finally, so a copy is needed to keep the traceback alive until the
    // handler prints it. Cleared per handled error (see traceErrorNode) so the
    // next error starts fresh.
    //
    // `calls` is a manual stack (callsTop is the live depth) so push/pop on the
    // function-call hot path cost an index write, not a SetLength; it only grows
    // geometrically. errCalls is the frozen copy printed by the handler.
    //
    // Compiled in only with -dFunTraceback: the default build has no per-call
    // bookkeeping at all and reports just the failing command (file:line).
    calls: array of CFun;
    callsTop: fun.int;
    errCalls: array of CFun;
    {$EndIf}
    function call(exp: CExp; const id: fun.str; exps: CExps; val: PValue; ct: fun.byte = CDoMethod): fun.bool; virtual;
    function clone: CEnv; virtual;
    procedure echo(const s: fun.str); virtual;
    function isCase: fun.bool;
    function lastErrorFun: fun.str;
    // Call chain of the pending error (or the live chain when none), innermost
    // first, one `  in <name>() (file:line)` line per function/class frame. Used
    // by the command-line driver to append a traceback to a runtime error.
    // Always present so the driver needs no conditional; returns '' unless the
    // build defines FunTraceback.
    function traceBack: fun.str;
    {$IfDef FunTraceback}
    procedure pushCall(f: CFun);
    procedure popCall;
    procedure snapshotError;
    {$EndIf}
    // Drop a frozen chain so the next run/error starts clean. No-op by default.
    procedure resetTrace;
    procedure trace(n: CNode); virtual;
    procedure traced(n: CNode; tracing: fun.bool = false); virtual;
    procedure traceErrorNode;
  end;
  

// for OLE lib - PropertyGet or Set
var _ENV: CEnv;

// Object-aware boolean coercion of a value. Unlike base.funBool (which relies
// on the implicit Variant->Boolean cast routed through the custom
// CVarObject.CastTo used on Delphi), this tests Fun collection/match objects
// (CExp subclasses) via their count, so it also works on FPC where that cast
// is not routed through CastTo.
function funBoolOf(const v: PValue): fun.bool;

implementation

uses SysUtils,
     flow;

//==============================================================
constructor CNode.new(pn: CNode; isAdd: fun.bool = false);
begin
  inherited Create;
  parent := pn;
  if isAdd and (pn <> nil) then pn.add(self);
end;

procedure CNode.add(cn: CNode);
begin
  // no action
end;

function CNode.call(env: CEnv; const exps: array of const): PValue;
var
  es: CExps;
  ee: CExp;
  e: TVarRec;
  i: fun.int;
begin
  es := CExps.Create();
  try
    for i := 0 to Length(exps) -1 do
    begin
      e  := exps[i];
      ee := CExp.new(nil);
      es.Add(ee);
      case e.VType of
        vtInteger:    ee.assign(e.VInteger);
        vtBoolean:    ee.assign(e.VBoolean);
        vtChar:       ee.assign(e.VChar);
        //vtExtended:   ee.assign(e.VExtended);
        vtString:     ee.assign(fun.str(e.VString));
        vtPointer:    ee.assign(e.VPointer);
        vtPChar:      ee.assign(fun.str(e.VPChar));
        vtObject:     ee.assign(CBase(e.VObject));
        //vtClass:      ee.assign(e.VClass);
        vtWideChar:   ee.assign(e.VWideChar);
        vtPWideChar:  ee.assign(fun.str(e.VPWideChar));
        vtAnsiString: ee.assign(fun.str(e.VAnsiString));
        //vtCurrency:   ee.assign(e.VCurrency);
        vtVariant:    ee.assign(e.VVariant^);
        //vtInterface:  ee.assign(e.VInterface);
        vtWideString: ee.assign(fun.str(e.VWideString));
        //vtInt64:      ee.assign(e.VInt64);
      end;
    end;
    result := call(env, es);
  finally
    del(es);
  end;
end;

function CNode.call(env: CEnv; exps: CExps): PValue;
begin
  // no action
  result := @NullValue;
end;

function CNode.root: CNode;
begin
  result := self;
  while result.parent <> nil do result := result.parent;
end;

function CNode.UID(const n: fun.str): CVar;
begin
  result := nil;
  if parent <> nil then result := parent.UID(n);
end;

procedure CNode.use(n : CRuns; const id: fun.str = '');
begin
  // no action
end;

//==============================================================
procedure CRun.run(env: CEnv);
begin
  // no action
end;

//==============================================================
destructor CGoto.Destroy;
begin
  del(exp);
  inherited Destroy;
end;

function CGoto.parse(atarget: CNode; aexp: CExp): CNode;
begin
  result := self;
  target := CRuns(atarget);
  exp    := aexp;
end;

procedure CGoto.run(env: CEnv);
var
  n: CNode;
begin
  /// target done in parser
  /// next, return -> CRuns
  /// exit -> CRuns - CLoop
  n := self;
  repeat
    n := n.parent;
    if n is CRuns then CRuns(n).isExit := true;
  until n = target;
  
end;

//==============================================================
procedure CReturn.run(env: CEnv);
var
  v: CVar;
  n: CNode;
begin
  /// var result
  if exp <> nil then
  begin
    v := CRuns(target).UID(_RESULT);
    if v <> nil then v.assign(exp.calcValue(env));
  end;
  
  n := self;
  repeat
    n := n.parent;
    if      n is CRuns then CRuns(n).isExit := true
    else if n is CLoop then CLoop(n).isExit := true;
  until n = target;
  
end;

//==============================================================
destructor CAssign.Destroy;
begin
  del(evar);
  del(exp);
  inherited Destroy;
end;

function CAssign.parse(avar, aexp: CExp): CNode;
begin
  result := self;
  evar   := avar;
  exp    := aexp;
end;

procedure CAssign.run(env: CEnv);
begin
  /// exp = evar op exp <- evar op= exp
  /// done in parser
  evar.assign(exp.calcValue(env));
end;

procedure CAssignFast.run(env: CEnv);
var
  t, s: CId;
  src, dst: PValue;
begin
  if not FInit then
  begin
    FInit := True;
    FFast := False;
    if not (evar is CId) or (evar is CId2) then Exit;
    t := CId(evar);
    t.find(true);
    if t.evar is CVarRE then
      FTargetIsRE := True
    else if t.evar is CVar then
      FTargetIsRE := False
    else
      Exit;
    if exp is CId and not (exp is CId2) then
    begin
      s := CId(exp);
      s.find(false);
      // Self-assignment can alias the target's stack slot; keep the generic
      // path for that rare case.
      if s.evar = t.evar then Exit;
      // Read p_val directly only for plain variables; other CId targets
      // (constants, optional cells) keep the generic value path.
      if (s.evar is CVarRE) or (s.evar is CVar) then
        FSourceIsId := True;
    end;
    FFast := True;
  end;

  if not FFast then
  begin
    inherited run(env);
    Exit;
  end;

  t := CId(evar);
  if FSourceIsId then
  begin
    s := CId(exp);
    s.find(false);
    src := CExp(s.evar).p_val;
  end
  else
    src := exp.calcValue(env);

  if FTargetIsRE then
  begin
    dst := CVarRE(t.evar).DirectTarget;
    if dst = nil then
    begin
      // A scope entry still has to push this variable's slot.
      CVarRE(t.evar).assign(src);
      Exit;
    end;
  end
  else
    dst := CExp(t.evar).p_val;

  if dst <> src then
    copyValue(dst, src);
end;

//==============================================================
destructor CCall.Destroy;
begin
  del(exp);
  inherited Destroy;
end;

function CCall.parse(aexp: CExp): CNode;
begin
  result := self;
  exp    := aexp;
end;

procedure CCall.run(env: CEnv);
begin
  exp.calc(env);
end;

//==============================================================
function CEcho.parse(aexp: CExp; const aextra: fun.str = ''): CNode;
begin
  result := inherited parse(aexp);
  extra  := aextra;
end;

procedure CEcho.run(env: CEnv);
var
  s: fun.str;
begin
  s := fun.str(exp.calcValue(env)^);
  if extra <> '' then s := s + extra;
  env.echo(s);
end;

//==============================================================
constructor CRuns.new(pn: CNode; isAdd: fun.bool = false);
begin
  inherited new(pn, isAdd);
  runs := CList.Create();
  vars := CHash.Create();
  used := CList.Create(false);
end;

destructor CRuns.Destroy;
begin
  del(runs);
  del(vars);
  del(used);
  inherited Destroy;
end;

procedure CRuns.add(cn: CNode);
begin
  runs.add(cn);
end;

function CRuns.GetID(const name: fun.str): CVar;
begin
  result := vars[name];
end;

function CRuns.GetND(i: fun.int): CRun;
begin
  result := CRun(runs[i]);
end;

procedure CRuns.run(env: CEnv);
var
  i: fun.int;
  n: CRun;
begin
  for i := 0 to runs.count - 1 do
  begin
    n := CRun(runs[i]);
  
    env.trace(n);
    n.run(env);
  
  {$IfDef IDE}
    env.traced(n);
  {$EndIf}
  
    if isExit then begin
      isExit := false;
      break;
    end;
  end;
end;

procedure CRuns.SetID(const name: fun.str; Value: CVar);
begin
  vars[name] := Value;
end;

function CRuns.UID(const n: fun.str): CVar;
var
  i: fun.int;
  r: CRuns;
begin
  result := ID[n];
  if result = nil then
  begin
    for i := used.count -1 downto 0 do
    begin
      r      := CRuns(used[i]);
      result := r.UID(n);
      if result <> nil then exit;
    end;
  end;
  if result = nil then result := inherited UID(n);
end;

procedure CRuns.use(n : CRuns; const id: fun.str = '');
begin
  base.add(n);
  add(n);
  if id <> '' then
    CVar.new(self, id).assign(n)
  else
    used.add(n)
  ;
end;

//==============================================================
function CModu.call(env: CEnv; exps: CExps): PValue;
begin
  inherited run(env);
  result := inherited call(env, exps);
end;

function CModu.find(const fn: fun.str): CModu;
var
  m: CModu;
begin
  result := nil;
  m := self;
  repeat
    if SameText(m.fileName, fn) then
    begin
      result := m;
      exit;
    end;
    m := m.next;
  until (m = nil) or (m = self);
end;

procedure CModu.run(env: CEnv);
begin
  if runed then exit;
  runed := true;
  inherited run(env);
end;

function CModu.UID(const n: fun.str): CVar;
begin
  result := nil;
  if useLevel > 0 then exit;
  Inc(useLevel);
  Result := inherited UID(n);
  Dec(useLevel);
end;

//==============================================================
destructor CBloc.Destroy;
begin
  del(all);
  inherited Destroy;
end;

function CBloc.parse: CNode;
begin
  if all = nil then all := CRuns.new(self);
  result := all;
end;

//==============================================================
constructor CFun.new(pn: CNode; isAdd: fun.bool = false);
begin
  inherited new(pn, isAdd);
  stack := CFunStack.Create();
  vars  := CHash.Create();
end;

destructor CFun.Destroy;
begin
  del(params);
  del(stack);
  del(vars);
  inherited Destroy;
end;

function CFun.call(env: CEnv; exps: CExps): PValue;
var
  o: CObj;
  {$IfDef FunTraceback}ok: fun.bool;{$EndIf}
begin
  //env.trace(self);
  // Frame bookkeeping (only with -dFunTraceback) rides on the try/finally each
  // branch already had: push on entry, and in the finally either drop the frame
  // (normal return) or, while an exception unwinds (`ok` still false), record
  // the chain at the deepest frame before dropping it. No handler frame is added
  // to the function-call hot path, and the default build has no bookkeeping
  // lines at all.
  if isClass then
  begin
    o := newObj;
    doCopy(o.items, exps);
    evar.assign(o);
    result := evar.value;

    pushObj(o);
    {$IfDef FunTraceback}
    env.pushCall(self);
    ok := false;
    {$EndIf}
    try
      doCall(env, exps);
      {$IfDef FunTraceback}
      ok := true;
      {$EndIf}
    finally
      popObj;
      {$IfDef FunTraceback}
      if not ok then env.snapshotError;
      env.popCall;
      {$EndIf}
    end;
  end
  else
  begin
    stack.Push;
    {$IfDef FunTraceback}
    env.pushCall(self);
    ok := false;
    {$EndIf}
    try
      if params <> nil then params.assign(exps);
      all.run(env);
      result := evar.value;
      {$IfDef FunTraceback}
      ok := true;
      {$EndIf}
    finally
      stack.Pop;
      {$IfDef FunTraceback}
      if not ok then env.snapshotError;
      env.popCall;
      {$EndIf}
    end;
  end;

  {$IfDef IDE}
  env.traced(self);
  {$EndIf}
end;

procedure CFun.doCall(env: CEnv; exps: CExps);
begin
  if upClass <> nil then upClass.doCall(env, exps);
  // Moved to doCopy()
  //if params <> nil then params.assign(exps);
  all.run(env);
end;

procedure CFun.doCopy(items, exps: CExps);
begin
  // Moved from doCall()
  if params <> nil then params.assign(exps);
  
  items.append(all.vars);
  if upClass <> nil then upClass.doCopy(items, exps);
end;

function CFun.doFind(const n: fun.str): CVar;
begin
  // var in cache, so ...
  {
  if thisVar <> nil then
  begin
    o := thisVar.asObj;
    if o is CObj then
    begin
      result := CObj(o).items[n];
      if result <> nil then exit;
    end;
  end;
  }
  result := all.ID[n];
  if result = nil then result := vars[n];
  if (result = nil) and (upClass <> nil) then result := upClass.doFind(n);
end;

function CFun.newObj: CObj;
begin
  result := CObj.new(self);
  result.FRefCount := 0;
  result.parse(CExps.Create());
end;

function CFun.parse(const id: fun.str; aps: CExps; aupClass: CFun = nil; aisClass: fun.bool = false): CNode;
var
  v: CVar;
begin
  result        := inherited parse();
  params        := aps;
  //name        := id;
  self.id       := id;
  if id <> '' then CVar.new(CRuns(parent), id).assign(self);
  // result
  evar          := CVar.new(all);
  evar.name     := _Result;
  vars[_Result] := evar;
  // @ -> result
  base.add(evar);
  vars[_AT]     := evar;
  // for Class
  upClass       := aupClass;
  isClass       := aisClass;
  // this/base
  if isClass then
  begin
    // this
    v           := CVar.new(all, '', true);
    v.name      := _This;
    v.assign(self);
    vars[_This] := v;
    thisVar     := v;
    // base
    v           := CVar.new(all, '', true);
    v.name      := _Base;
    vars[_Base] := v;
    baseVar     := v;
    if upClass = nil then
      v.assign(self)
    else
      v.assign(upClass)
    ;
    // stack
    stack.start := 0;
  end;
end;

procedure CFun.popObj;
begin
  stack.pop;
  if upClass <> nil then upClass.popObj;
end;

procedure CFun.pushObj(obj: CObj);
var
  i: fun.int;
  es: CExps;
  e, e2: CExp;
begin
  stack.push;
  es := obj.items;
  for i := 0 to es.count -1 do
  begin
    e  := CExp(es.Item[i]);
    e2 := CExp(all.ID[e.name]);
    if (e2 <> nil) and not (e2.asObj is CFun) then
    begin
      // push
      CVarRE(e2).stack.Push();
      // xx -> obj.xx
      e2.p_val := e.p_val;
    end;
  end;
  thisVar.assign(obj);
  if upClass = nil then
    baseVar.assign(self)
  else
    baseVar.assign(upClass)
  ;
  if upClass <> nil then upClass.pushObj(obj);
end;

function CFun.UID(const n: fun.str): CVar;
begin
  result := doFind(n);
  if result = nil then result := inherited UID(n);
end;

//==============================================================
constructor CExp.new(pn: CNode; isAdd: fun.bool = false);
begin
  inherited new(pn, isAdd);
  p_val := @v_val;
end;

function funBoolOf(const v: PValue): fun.bool;
var
  o: CBase;
begin
  o := base.asObj(v);
  if o = nil then
    result := funBool(v)
  else if o is CExp then
    // CSet / CMatch (and other countable collection values) are truthy only
    // when non-empty.
    result := CExp(o).count > 0
  else if o is CFun then
    result := true
  else
    result := true
  ;
end;

function CExp.asBool: fun.bool;
begin
  result := funBoolOf(value);
end;

function CExp.asInt: fun.int;
begin
  if isFloat(value) then begin
    result := Trunc(Double(value^));
    if (value^ < 0) and (result > value^) then Dec(result);
  end else
    result := fun.int(value^)
  ;
end;

function CExp.asObj: CBase;
begin
  result := base.asObj(value);
end;

procedure CExp.assign(obj: CBase);
begin
  setObj(p_val, obj);
end;

procedure CExp.assign(exp: CExp);
begin
  assign(exp.value);
end;

procedure CExp.assign(obj: CNew);
begin
  setObj(p_val, obj, VarObjNew);
end;

procedure CExp.assign(const val: CValue);
begin
  // Scalar assignments (every counter, loop variable and arithmetic result)
  // bypass VariantCopy; managed values still go through the RTL.
  copyValue(p_val, @val);
end;

procedure CExp.assign(val: PValue);
begin
  copyValue(p_val, val);
end;

function CExp.asStr: fun.str;
begin
  result := fun.str(value^);
end;

procedure CExp.calc(env: CEnv);
begin
  // no action
end;

function CExp.calcAsBool(env: CEnv): fun.bool;
begin
  calc(env);
  result := asBool;
end;

function CExp.calcValue(env: CEnv): PValue;
begin
  calc(env);
  result := value;
end;

function CExp.clone(env: CEnv): CExp;
begin
  calc(env);
  if asObj is CSet then
    result := CSet(asObj).clone(env)
  else
    result := CExp.new(nil).parse(value^)
  ;
end;

function CExp.count: fun.int;
begin
  result := 0;
end;

function CExp.Getitem(i: fun.int): CExp;
begin
  // no action
  result := nil;
end;

function CExp.parse(const val: CValue): CExp;
begin
  assign(val);
  result := self;
end;

function CExp.value: PValue;
begin
  result := p_val;
end;

//==============================================================
function CExps.Add(p: fun.ptr): fun.int;
begin
  Result := 0;
  if (p <> nil) and (CExp(p).name <> '') then
    ItemById[CExp(p).name] := p
  else
    Result := inherited Add(p)
  ;
end;

procedure CExps.append(exps: CExps);
var
  i: fun.int;
  e, p: CExp;
begin
  for i := 0 to CExps.Count(exps) -1 do
  begin
    e := exps.Item[i];
    p := CExp.new(nil);
    p.name := e.name;
    p.assign(e);
    Add(p);
  end;
end;

procedure CExps.append(exps: CHash);
begin
  CExps(exps).Each(_append);
end;

procedure CExps.assign(exps: CExps);
var
  i: fun.int;
  e, p: CExp;
  v: CValue;
begin
  for i := 0 to List.Count -1 do
  begin
    e := Item[i];
    p := nil;
  
    if exps <> nil then
    begin
      p := exps[e.name];
      if (p = nil) and (i < exps.Count) then p := exps.Item[i];
    end;
  
    // name of "var" arg <=> name of refed var
    if (p <> nil) and ( (p.name='') or SameText(p.name,e.name) or (p is CVar) ) then
    begin
      if p is CVar then
        e.p_val := p.p_val
      else
      begin
        v := p.value^; // get param value before to fix bug of recursion
        // resume not "var" --> restore p_val if not "var"
        e.p_val := @e.v_val;
        e.assign(v);   // assign to active GC and/or recursion stack
      end;
    end
    else
    begin
      // resume not "var" --> restore p_val if not "var"
      e.p_val := @e.v_val;
      e.assign(@NullValue)
    end;
  end;
end;

procedure CExps.calc(env: CEnv);
var
  i: fun.int;
begin
  for i := 0 to List.Count -1 do
  begin
    CExp(List[i]).calc(env);
  end;
end;

function CExps.clone(env: CEnv): CExps;
var
  i: fun.int;
  e: CExp;
begin
  result := CExps.create;
  for i := 0 to count -1 do
  begin
    e := CExp(Item[i]).clone(env);
    e.name := CExp(Item[i]).name;
    result.add(e);
  end;
end;

class function CExps.Count(exps: CExps): fun.int;
begin
  if exps <> nil then
    result := exps.Count
  else
    result := 0
  ;
end;

class function CExps.Find(exps: CExps; const id: fun.str; idx: fun.int): CExp;
begin
  result := nil;
  if exps <> nil then
  begin
    result := exps[id];
    if (result = nil) and (idx < exps.Count) then
    begin
      result := exps.Item[idx];
      if (result.name <> '') and not SameText(id, result.name) then
        result := nil
      ;
    end;
  end;
end;

class function CExps.FindAsVal(exps: CExps; const id: fun.str; idx: fun.int; def: fun.bool): fun.bool;
var
  e: CExp;
begin
  e := Find(exps, id, idx);
  if e <> nil then
    result := e.value^
  else
    result := def
  ;
end;

class function CExps.FindAsVal(exps: CExps; const id: fun.str; idx: fun.int; def: fun.int): fun.int;
var
  e: CExp;
begin
  e := Find(exps, id, idx);
  if e <> nil then
    result := e.value^
  else
    result := def
  ;
end;

class function CExps.FindAsVal(exps: CExps; const id: fun.str; idx: fun.int; const def: fun.str): fun.str;
var
  e: CExp;
begin
  e := Find(exps, id, idx);
  if e <> nil then
    result := e.value^
  else
    result := def
  ;
end;

procedure CExps._append(p: fun.ptr);
var
  e, p2: CExp;
begin
  p2 := CExp(p);
  if ItemById[p2.name] = nil then
  begin
    e := CExp.new(nil);
    e.name := p2.name;
    e.assign(p2);
    Add(e);
  end;
end;

//==============================================================
constructor CVar.new(pn: CNode; isAdd: fun.bool = false);
begin
  inherited new(pn, isAdd);
end;

class function CVar.findOwner(parent: CNode): CFun;
var
  n: CNode;
begin
  n := parent;
  while (n <> nil) and not (n is CFun) do
  begin
    n := n.parent;
  end;
  result := CFun(n);
end;

class function CVar.new(pn: CRuns; const id: fun.str = ''; allowClass: fun.bool = false): CVar;
var
  o: CFun;
begin
  o := findOwner(pn);
  // var in cache, so ...
  {
  // Only fun, Ignore class, Except this/base
  if (o <> nil) and (not o.isClass or allowClass) then
  }
  if o <> nil then
  begin
    result := CVarRE.new(pn, false);
    with CVarRE(result) do
    begin
      owner := o;
      stack := CVarStack.Create(o.stack, p_val, @p_val);
    end;
  end
  else
  begin
    result := CVar.new(pn, false);
  end;
  if (id <> '') and (pn <> nil) then pn.ID[id] := result;
  result.name  := id;
end;

//==============================================================
destructor CVarRE.Destroy;
begin
  del(stack);
  inherited Destroy;
end;

procedure CVarRE.assign(obj: CBase);
begin
  stack.Push();
  inherited assign(obj);
end;

procedure CVarRE.assign(obj: CNew);
begin
  stack.Push();
  inherited assign(obj);
end;

procedure CVarRE.assign(const val: CValue);
begin
  stack.Push();
  inherited assign(val);
end;

procedure CVarRE.assign(val: PValue);
begin
  stack.Push();
  inherited assign(val);
end;

function CVarRE.DirectTarget: PValue;
begin
  result := stack.DirectTarget;
end;

//==============================================================
procedure CId.assign(obj: CBase);
var
  f: fun.int;
begin
  f := find(true);
  evar.assign(obj);
  done(f);
end;

procedure CId.assign(obj: CNew);
var
  f: fun.int;
begin
  f := find(true);
  evar.assign(obj);
  done(f);
end;

procedure CId.assign(const val: CValue);
var
  f: fun.int;
begin
  f := find(true);
  evar.assign(val);
  done(f);
end;

procedure CId.assign(val: PValue);
var
  f: fun.int;
begin
  f := find(true);
  evar.assign(val);
  done(f);
end;

function CId.call(env: CEnv; exps: CExps): PValue;
begin
  find;
  if evar.asObj is CNode then
  begin
    result := CNode(evar.asObj).call(env, exps);
  end
  else
    result := inherited call(env, exps)
  ;
end;

function CId.count: fun.int;
begin
  find;
  if evar.asObj is CSet then
    result := CSet(evar.asObj).count()
  else
    result := evar.count()
  ;
end;

procedure CId.done(flag: fun.int);
begin
  // no action
end;

function CId.find(isSet: fun.bool = false; needCalc: fun.bool = true): fun.int;
begin
  result := 0;
  if evar = nil then evar := UID(id);
  if evar = nil then begin
    if opt then begin
      if enil = nil then enil := CExp.new(nil) else enil.assign(NullValue);
      evar := enil;
    end
    else raise EBase.Create(id + _NotFound);
  end;
end;

destructor CId.Destroy;
begin
  del(enil);
  inherited Destroy;
end;

function CId.Getitem(i: fun.int): CExp;
begin
  find;
  if evar.asObj is CSet then
    result := CSet(evar.asObj).Getitem(i)
  else
    result := evar.Getitem(i)
  ;
end;

function CId.parse(const aid: fun.str; avar: CVar = nil; optional: fun.bool = false): CExp;
begin
  result := self;
  id     := aid;
  evar   := avar;
  opt    := optional;
end;

function CId.value: PValue;
begin
  find;
  result := evar.value;
end;

//==============================================================
destructor CId2.Destroy;
begin
  del(exp);
  del(eole);
  del(enull);
  del(eopt);
  inherited Destroy;
end;

procedure CId2.calc(env: CEnv);
begin
  exp.calc(env);
end;

function CId2.call(env: CEnv; exps: CExps): PValue;
var
  o: CBase;
  pushed: fun.bool;
begin
  calc(env);
  o := exp.asObj;
  if o is CObj then
  begin
    pushed := CObj(o).push;
    try
      result := p_val;
      // Native collection methods (@count / @each / @has / @toJson / @clone)
      // are dispatched through the libraries, but this branch used to go
      // straight to the class scope, so they all returned nil on a class
      // instance. Members still win: only the '@' namespace (reserved for
      // interpreter methods, see _AT in CFun.parse) is offered to the libs,
      // and a miss falls back to normal member lookup.
      if (id = '') or (id[1] <> '@') or not env.call(exp, id, exps, result) then
        Result := inherited call(env, exps)
      ;
    finally
      if pushed then CObj(o).pop;
    end;
  end
  else
  begin
    result := p_val;
    if not env.call(exp, id, exps, result) then
      Result := inherited call(env, exps)
    ;
  end;
end;

procedure CId2.done(flag: fun.int);
begin
  if (flag = 8) and (_ENV <> nil) then
  begin
    _ENV.call(exp, id, nil, eole.value, CPropertySet)
  end;
end;

function CId2.find(isSet: fun.bool = false; needCalc: fun.bool = true): fun.int;
var
  o: CBase;
begin
  result := 0;
  if isSet and needCalc and (_ENV <> nil) then
  begin
    calc(_ENV);
  end;
  
  o := exp.asObj;
  if o <> nil then
  begin
    if o is CSet then // obj or set
    begin
      evar := CSet(o).items[id];
      if evar = nil then // not found
      begin
        if isSet then
        begin
          evar := CExp.new(nil);
          evar.name := id;
          CSet(o).items[id] := evar;
        end
        else
        begin
          if enull = nil then enull := CExp.new(nil);
          evar := enull;
        end;
      end;
    end
    else if o is CFun then // fun or class
    begin
      evar := CFun(o).doFind(id);
      if evar = nil then // not found
      begin
        evar := CVar.new(CFun(o).all, id);
      end;
    end
    else if o is CRuns then // use, including forwarding modules
      evar := CRuns(o).UID(id)
    ;
  end
  else if isOle(exp.value) then
  begin
    if eole = nil then eole := CExp.new(nil); // ole
    evar := eole;
    result := 8;
  end
  else
    // Base value is nil. evar must be cleared here: every other branch
    // assigns it, and leaving the previous lookup in place made `a?.x?` hand
    // back the value found by an earlier call at the same node (x?.k? stale).
    evar := nil
  ;
  if evar = nil then begin
    if opt then begin
      if eopt = nil then eopt := CExp.new(nil) else eopt.assign(NullValue);
      evar := eopt;
    end
    else raise EBase.Create('.' + id + _NotFound);
  end;
end;

function CId2.parse(const aid: fun.str; aexp: CExp; optional: fun.bool = false): CExp;
begin
  result := inherited parse(aid, nil, optional);
  exp    := aexp;
end;

function CId2.value: PValue;
begin
  if isOle(exp.value) and (_ENV <> nil) then //exp not calc yet?
  begin
    result := p_val;
    _ENV.call(exp, id, nil, result, CPropertyGet);
    exit;
  end;
  Result := inherited value;
end;

//==============================================================
destructor CIdx.Destroy;
begin
  del(idx);
  del(estr);
  inherited Destroy;
end;

procedure CIdx.calc(env: CEnv);
begin
  inherited calc(env);
  idx.calc(env);
end;

procedure CIdx.done(flag: fun.int);
var
  s: PChar;
  p: fun.ptr;
  cv: fun.str;
  i, j, n: fun.int;
begin
  if flag = 9 then begin
    s := PData(exp.value).VPointer; n := Length(exp.asStr); // Variant length; strlen(s) stops at the first #0
    j := idx.asInt;
    i := calcIndex(j, n);
    // Documented range is 0..N-1 / -N..-1 (see fun/lib/lib-string.fun).
    // A raw write outside it corrupts the string header or the heap.
    if (i < 0) or (i >= n) then
      raise EBase.Create('string index out of range: ' + IntToStr(j));
    if isFloat(idx.value) and (idx.value^ > j) then begin
    {$IfDef Unicode}
      p := s + i;
      // fun.int() would truncate the address on a 64-bit target
      if idx.value^ >= j + 0.5 then p := fun.ptr(fun.uintptr(p) + 1);
      PByte(p)^ := fun.byte(evar.asInt mod 256);
    {$Else}
      (s+i)^ := fun.char(evar.asInt);
    {$EndIf}
    end else
    begin
      cv := evar.asStr;
      if Length(cv) = 0 then
        (s+i)^ := #0
      else
        (s+i)^ := cv[1]
      ;
    end;
  end else
  inherited done(flag);
end;

function CIdx.find(isSet: fun.bool = false; needCalc: fun.bool = true): fun.int;
var
  o: CBase;
  s: fun.str;
  i, j, n: fun.int;
begin
  result := 0;
  evar := nil;
  if isSet and needCalc and (_ENV <> nil) then
  begin
    calc(_ENV);
  end;
  
  if (id = '') and isNum(idx.value, true) then //if isNum(idx.p_val) then
  begin
    o := exp.asObj;
    if o is CSet then
    begin
      // A list is also usable as a sparse integer-keyed map (lib-unicode-lnx
      // does _gbRev[cp] = ... with cp up to 0xFFFF), so an in-range-but-not-yet-
      // allocated index grows the backing array in CList.Add. GetItem is
      // bounds-checked now, so a read past Count is nil instead of a raw read.
      // Only a negative index below -Count (calcIndex cannot wrap it) is an
      // error: a read is nil and a write must not silently append.
      n := CSet(o).count();
      i := idx.asInt;
      if calcIndex(i, n) < 0 then
      begin
        if isSet then
          raise EBase.Create('index out of range: ' + IntToStr(i));
        if enull = nil then enull := CExp.new(nil);
        evar := enull;
      end
      else
      begin
        evar := CSet(o).Item[i];
        if evar = nil then // not found
        begin
          if isSet then
          begin
            evar := CExp.new(nil);
            CSet(o).items.Item[i] := evar;
          end
          else
          begin
            if enull = nil then enull := CExp.new(nil);
            evar := enull;
          end;
        end;
      end;
    end
    else if isStr(exp.value) then
    begin
      if estr = nil then estr := CExp.new(nil);
      evar := estr;
      s := exp.asStr; n := Length(s);
      j := idx.asInt;
      i := calcIndex(j, n);
      if (i < 0) or (i >= n) then
      begin
        // Documented range is 0..N-1 / -N..-1 (see fun/lib/lib-string.fun):
        // reads out of range yield nil (like a list), writes raise.
        if isSet then
          raise EBase.Create('string index out of range: ' + IntToStr(j));
        evar.assign(NullValue);
      end
      else if isFloat(idx.value) and (idx.value^ > j) then
      begin
      {$IfDef Unicode}
        // the float form selects a byte of char i+1 (1-based): .5 picks the
        // high byte, .0 the low byte. s[i+1] is in range (i < Length(s)), so
        // both reads stay inside the buffer.
        if idx.value^ >= j + 0.5 then
          evar.assign(fun.int(s[i+1]) div 256)
        else
          evar.assign(fun.int(s[i+1]) mod 256)
        ;
      {$Else}
        evar.assign(fun.int(s[i+1]));
      {$EndIf}
      end
      else
        evar.assign(s[i+1])
      ;
      result := 9;
    end;
  end;
  if evar = nil then
  begin
    id := idx.asStr;
    result := inherited find(isSet, false);
  end;
end;

function CIdx.parse(const aid: fun.str; aexp, aidx: CExp): CExp;
begin
  result := inherited parse(aid, aexp);
  idx    := aidx;
end;

//==============================================================
destructor CFunc.Destroy;
begin
  del(exp);
  del(ps);
  inherited Destroy;
end;

procedure CFunc.calc(env: CEnv);
begin
  if ps <> nil then ps.calc(env);
  
  if not fun2 then
  begin
    p_val^ := NullValue;
    assign(exp.call(env, ps));
  end
  else
  begin
    exp.calc(env);
    assign(CBase(self))
  end;
end;

function CFunc.call(env: CEnv; exps: CExps): PValue;
var
  ps2: CExps;
begin
  if not fun2 then
  begin
    // Chained call: this node sits in a callee position, as in f(..)(..).
    // Evaluate this call first, then dispatch its result as the callee -- the
    // same pattern as CId.call/CId2.call dispatching on asObj (a fun2 partial,
    // a CFun, a CModu and friends are CNode). A non-callable result keeps the
    // legacy silent Null via inherited (CNode.call); diagnostics come later.
    calc(env);
    if asObj is CNode then
      result := CNode(asObj).call(env, exps)
    else
      result := inherited call(env, exps)
    ;
    exit;
  end;
  
  if exps <> nil then exps.calc(env);
  ps2 := CExps.Create();
  ps2.append(ps);
  ps2.append(exps);
  try
    result := exp.call(env, ps2);
  finally
    del(ps2);
  end;
end;

function CFunc.parse(aexp: CExp; aps: CExps): CNode;
begin
  result := self;
  exp    := aexp;
  ps     := aps;
end;

//==============================================================
destructor CSet.Destroy;
begin
  del(exps);
  inherited Destroy;
end;

procedure CSet.calc(env: CEnv);
begin
  if not calced then // calc only once
  begin
    calced := true;
    items.calc(env);
  end;
end;

function CSet.clone(env: CEnv): CExp;
begin
  result := CNew.new(nil);
  result.FRefCount := 0;
  if exps <> nil then CSet(result).parse(exps.clone(env))
                 else CSet(result).parse(CExps.create)
end;

function CSet.count: fun.int;
begin
  result := CExps.Count(exps);
end;

function CSet.Getitem(i: fun.int): CExp;
var
  N: fun.int;
begin
  // L = N - 1
  //  0 1 2 3 4 5 >> ++ >> L(ast)
  // -N << -- << -4 -3 -2 -1
  N := items.count();
  i := calcIndex(i, n);
  if (i < 0) or (i >= N) then
    result := nil
  else
    result := CExp(exps.Item[i])
  ;
end;

function CSet.items: CExps;
begin
  if exps = nil then exps := CExps.Create;
  result := exps;
end;

function CSet.parse(aexps: CExps): CNode;
begin
  result := self;
  exps   := aexps;
  assign(CBase(self));
end;

//==============================================================
destructor CSet2.Destroy;
begin
  del(eset);
  inherited Destroy;
end;

procedure CSet2.calc(env: CEnv);
begin
  assign( CNew( CSet(eset).clone(env) ) );
end;

function CSet2.parse(aset: CExp): CNode;
begin
  result := self;
  eset   := aset;
end;

//==============================================================
function CObj.clone(env: CEnv): CExp;
begin
  result := CObj.new(parent);
  result.FRefCount := 0;
  if exps <> nil then CSet(result).parse(exps.clone(env))
                 else CSet(result).parse(CExps.create)
end;

function CObj.fun: CFun;
begin
  result := CFun(parent);
end;

procedure CObj.pop;
begin
  fun.popObj;
end;

function CObj.push: fun.bool;
begin
  result := fun.thisVar.asObj <> self;
  if result then fun.pushObj(self);
end;

//==============================================================
function CEnv.call(exp: CExp; const id: fun.str; exps: CExps; val: PValue; ct: fun.byte = CDoMethod): fun.bool;
begin
  // no action
  result := false;
end;

function CEnv.clone: CEnv;
begin
  result := CEnv.create;
end;

procedure CEnv.echo(const s: fun.str);
begin
  // no action
end;

function CEnv.isCase: fun.bool;
begin
  // todo
  result := false;
end;

function CEnv.lastErrorFun: fun.str;
var
  n: CNode;
begin
  result := '';
  n := lastError;
  while n <> nil do
  begin
    if (n is CFun) and (CFun(n).id <> '') then
    begin
      result := CFun(n).id;
      if lastError is CRune then result := result + '/' + IntToStr(CRune(lastError).row);
      exit;
    end;
    n := n.parent;
  end;
end;

{$IfDef FunTraceback}
const
  // Innermost-first cap on the frozen/printed traceback: deep recursion then
  // shows the last 10 frames instead of thousands.
  MaxTraceFrames = 10;

function CEnv.traceBack: fun.str;
var
  i, n: fun.int;

  function FrameOf(f: CFun): fun.str;
  var
    m: CModu;
    s: fun.str;
  begin
    result := '';
    if f.id = '' then exit;
    if f.root is CModu then m := CModu(f.root) else m := nil;
    if (m <> nil) and (m.fileName <> '') then
      s := m.fileName + ':' + IntToStr(f.row)
    else
      s := 'line ' + IntToStr(f.row)
    ;
    if f.isClass then
      result := '  in class ' + f.id + ' (' + s + ')' + #10
    else
      result := '  in ' + f.id + '() (' + s + ')' + #10
    ;
  end;
begin
  result := '';
  if Length(errCalls) > 0 then
  begin
    for i := Length(errCalls) - 1 downto 0 do
      result := result + FrameOf(errCalls[i]);
  end
  else
  begin
    n := callsTop;
    if n > MaxTraceFrames then n := MaxTraceFrames;
    for i := 0 to n - 1 do
      result := result + FrameOf(calls[callsTop - 1 - i]);
  end;
end;

procedure CEnv.pushCall(f: CFun);
begin
  if callsTop >= Length(calls) then
    SetLength(calls, Length(calls) * 2 + 8)
  ;
  calls[callsTop] := f;
  Inc(callsTop);
end;

procedure CEnv.popCall;
begin
  if callsTop > 0 then Dec(callsTop);
end;

procedure CEnv.snapshotError;
var
  i, n, base: fun.int;
begin
  // Only the first (deepest) frame records, so the traceback is not overwritten
  // by the outer frames as the exception unwinds through their finally blocks.
  // Freeze at most the innermost MaxTraceFrames frames.
  if Length(errCalls) = 0 then
  begin
    n := callsTop;
    if n > MaxTraceFrames then n := MaxTraceFrames;
    base := callsTop - n;
    SetLength(errCalls, n);
    for i := 0 to n - 1 do
      errCalls[i] := calls[base + i];
  end;
end;

{$Else}

function CEnv.traceBack: fun.str;
begin
  result := '';
end;

{$EndIf}

procedure CEnv.resetTrace;
begin
  {$IfDef FunTraceback}
  errCalls := nil;
  {$EndIf}
end;

procedure CEnv.trace(n: CNode);
begin
  lastNode := n;
end;

procedure CEnv.traced(n: CNode; tracing: fun.bool = false);
begin
  // no action
end;

procedure CEnv.traceErrorNode;
begin
  lastError := lastNode;
  // The error is being handled by a script try/except, so the pending traceback
  // is consumed; a later uncaught error must snapshot a fresh chain.
  resetTrace;
end;

end.
