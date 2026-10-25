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
unit parse;

interface

uses fun, base, core, flow, calc
     {$IfDef Regex}, regex{$EndIf}
     ;

type
  YYSType = record
    {$IfNDef OnlyRuntime}
    index,
    leng,
    row,
    col : fun.int;
    {$EndIf}
    val:  fun.int;
    text: fun.str;
    node: fun.ptr;
  end;

{$IfDef _C_}
type
  CKeyAlias = record
    key     : fun.str;
    alias   : fun.str;
  end;

var
  KeyAlias: array of CKeyAlias;

procedure ParseKeyAlias(const fn: fun.str);
{$EndIf}

type
  CParserClass = class of CParser;

  CParser = class(CBase)
  private
    Yacc: fun.ptr;
    Root: CNode;
    Curr: CNode;
    FileN: fun.str;
    OldC: CParserClass;
    OldP: CParser;
    procedure DoLog(const a1: YYSType; var ret: YYSType); overload;
    procedure DoLog(const a1, a0: YYSType; var ret: YYSType); overload;
    procedure DoLogCmd(const a1: YYSType);
    procedure DoLogBegin(const r, a: YYSType; n: CBloc);
    procedure DoLogEnd(const r: YYSType; n: CBloc);
    procedure DoError(const a1: YYSType; const s: fun.str); overload;
    function DoFind(onlyFun: fun.bool = false): CNode;
    class procedure LinkRoots(node, prev: fun.ptr);
  protected
    procedure OnParse(p: CParser); overload; virtual;
    procedure OnParse(n: CRune); overload; virtual;
    procedure OnParse(const fn: fun.str; var s: fun.str; m: core.CModu = nil); overload; virtual;
  public
    class function ParseOrLoad(const fn: fun.str; prev: fun.ptr = nil; CCParser: CParserClass = nil): fun.ptr;
    class function Parse(const s: fun.str; CCParser: CParserClass; const fn: fun.str = ''; prev: fun.ptr = nil): CRun;
    {$IfDef IDE}
    // Parse a single expression against an existing scope. `s` is the raw
    // expression text (no leading '?'); it is wrapped as the echo command
    // `?'+s` so the normal grammar accepts it, then the expression node is
    // returned with its scope parent set to `scope` so identifiers resolve
    // against it (e.g. the debugger's current frame). `root` receives the
    // throwaway parse tree the caller must free; on a parse error it stays nil
    // and the exception propagates.
    class function ParseExp(const s: fun.str; scope: CNode; out root: CRun): CExp;
    {$EndIf}
    function DoParse(const s: fun.str; prev: fun.ptr = nil): CNode;
    procedure DoError(const s: fun.str); overload; virtual;
    procedure BuildError(const a1: YYSType);
    function BuildIf(const a1, a0, exp: YYSType; isElse: fun.bool = false): YYSType;
    function BuildElse(const a1: YYSType): YYSType;
    function BuildCase(const a1, a0, exp: YYSType): YYSType;
    function BuildWhen(const a1, a0, exp: YYSType): YYSType;
    function BuildLoop(const a1: YYSType): YYSType; overload;
    function BuildLoop(const a1, a0, exp: YYSType): YYSType; overload;
    function BuildFor(const a1, a0, id, exp, emax: YYSType; estep: fun.ptr = nil): YYSType;
    function BuildForIn(const a1, a0, id, exp: YYSType; const key: fun.str = ''; const idx: fun.str = ''): YYSType;
    function BuildTry(const a1: YYSType): YYSType;
    function BuildExcept(const a1: YYSType): YYSType;
    function BuildFinally(const a1: YYSType): YYSType;
    function BuildEnd(const a1, a0, id: YYSType): YYSType; overload;
    function BuildEnd(const a1: YYSType; ignoreName: fun.bool = false): YYSType; overload;
    function BuildExit(const a1: YYSType): YYSType; overload;
    function BuildExit(const a1, a0, exp: YYSType): YYSType; overload;
    function BuildNext(const a1: YYSType): YYSType; overload;
    function BuildNext(const a1, a0, exp: YYSType): YYSType; overload;
    function BuildReturn(const a1: YYSType): YYSType; overload;
    function BuildReturn(const a1, a0, exp: YYSType): YYSType; overload;
    function BuildRaise(const a1, a0, exp: YYSType): YYSType;
    function BuildUse(const a1, a0, estr: YYSType; const id: fun.str = ''): YYSType;
    function BuildVar(const a1, a0, id: YYSType; exp: fun.ptr = nil; upup: fun.bool = false): YYSType;
    function BuildSet(const a1, a0, evar, exp: YYSType; const op: fun.str = ''): YYSType;
    function BuildCall(const a1: YYSType): YYSType;
    function BuildEcho(const a1, a0, exp: YYSType; const extra: fun.str = ''): YYSType;
    function BuildFun(const a1, a0, id, names: YYSType): YYSType;
    function BuildClass(const a1, a0, id, names: YYSType; base: fun.ptr = nil): YYSType;
    function BuildFunDef(const a1, a0: YYSType; names: fun.ptr = nil; dontParse: fun.bool = false; const id: fun.str = ''): YYSType;
    function CreateExp(const a1, a0, exp, op, exp2: YYSType; isBit: fun.bool = false): YYSType; overload;
    function CreateExp(const a1, a0, op, exp: YYSType; isBit: fun.bool = false): YYSType; overload;
    function CreateExp(const a1, a0, exp: YYSType): YYSType; overload;
    function CreateId(const a1: YYSType; optional: fun.bool = false): YYSType; virtual;
    function CreateVarExp(const a1, a0, exp, id: YYSType; str: fun.bool = false; optional:  fun.bool = false): YYSType;
    function CreateNum(const a1: YYSType; const sign: fun.str = ''): YYSType;
    function CreateStr(const a1: YYSType; isUse: fun.bool = false): YYSType; virtual;
    function CreateTime(const a1: YYSType): YYSType;
    function CreateRegex(const a1: YYSType): YYSType;
    function CreateConst(const a1: YYSType; const v: CValue): YYSType;
    function CreateFunExp(const a1, a0, exp, values: YYSType): YYSType;
    function CreateFunFun(const a1, a0, exp: YYSType): YYSType;
    function CreateSetNew(const a1, a0, exp: YYSType): YYSType;
    function CreateRef(const a1, a0, id: YYSType): YYSType;
    function CreateDotAny(const a1, a0, exp, op, exp2: YYSType): YYSType;
    function CreateSetConst(const a1, a0, values: YYSType): YYSType;
    function CreateSetIndex(const a1, a0, exp, index: YYSType; const extra: fun.str = ''): YYSType;
    function CreateNames(const a1, a0, names: YYSType): YYSType; overload;
    function CreateNames(const a1: YYSType): YYSType; overload;
    function CreateNames(const a1, a0, names, id: YYSType): YYSType; overload;
    function CreateValues(const a1, a0, values, value: YYSType): YYSType; overload;
    function CreateValues(const a1: YYSType): YYSType; overload;
    function CreateValue(const a1, a0, id, exp: YYSType; str: fun.bool = false): YYSType;
    class function ParseFileName(const fn: fun.str; prev: CNode): fun.str;
    class function PlatformFile(const fn: fun.str; prev: CNode): fun.str;
    class function ParseString(const s: fun.str; str: fun.bool = false): fun.str;
    class function StrToNum(const s: fun.str): CValue;
  end;
  

// for f or s.compile()
var _ParserClass: CParserClass;

implementation

{$IfDef Unicode}{$WARN WIDECHAR_REDUCED OFF}{$EndIf}

uses SysUtils, Variants, Math,
     io;

const
  EmptyResult : YYSType =
  (
    {$IfNDef OnlyRuntime}
    index : -1;
    leng  : -1;
    row   : -1;
    col   : -1;
    {$EndIf}
    val   : -1;
    text  : '';
    node  : nil;
  );

const
  _SynErr   = 'syntax error';

{$IfDef _C_}
function ParseAlias(const s: fun.str): fun.str;
var
  L, H, k, i: integer;
begin
  result := s;
  L := Low (KeyAlias);
  H := High(KeyAlias);
  while L <= H do
  begin
    k := L + (H - L) div 2;
    i := CompareStr(s, KeyAlias[k].alias);
    if i > 0 then L := k + 1 else
    if i < 0 then H := k - 1 else
    begin
      result := KeyAlias[k].key;
      break;
    end;
  end;
end;

procedure ParseKeyAlias(const fn: fun.str);
var
  s, k, a: fun.str;
  i, l: fun.int;
  c: fun.char;
  b: fun.bool;
begin
  k := '';
  a := '';
  s := CIO.Load(fn);
  b := true;
  l := 0;
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if c = #13 then
    begin
      Inc(l);
      SetLength(KeyAlias, l);
      with KeyAlias[l -1] do
      begin
        key   := k;
        alias := a;
      end;
      k := '';
      a := '';
      b := true;
    end
    else if c = #10 then
      //
    else if c = '=' then
      b := false
    else if b then
      a := a + c
    else
      k := k + c
    ;
  end;
end;
{$EndIf}

{$I 'yacc.inc'}
{$I 'op.inc'}

type
  CIf   = class(flow.CIf)   end;
  CTry  = class(flow.CTry)  end;
  CFunc = class(core.CFunc) end;
  CModu = class(core.CModu) end;

//==============================================================
function CParser.BuildCall(const a1: YYSType): YYSType;
begin
  DoLog(a1, result);
  result.node := CCall.new(Curr, true).parse(a1.node);
  DoLogCmd(result);
end;

function CParser.BuildCase(const a1, a0, exp: YYSType): YYSType;
begin
  DoLog(a1, a0, result);
  DoLogBegin(result, a1, CCase.new(Curr, true));
  Curr := CCase(Curr).parse(exp.node);
end;

function CParser.BuildClass(const a1, a0, id, names: YYSType; base: fun.ptr = nil): YYSType;
var
  f: CFun;
  o: CBase;
begin
  DoLog(a1, a0, result);
  if names.node <> nil then
    Curr := CRuns(Curr).parent
  else
    Curr := CFun.new(Curr, true)
  ;
  
  f := nil;
  if base <> nil then
  begin
    o := CExp(base).asObj;
    if o is CFun then
    begin
      f := CFun(o);
    end;
    del(base);
  end;
  
  DoLogBegin(result, a1, CBloc(Curr));
  Curr := CFun(Curr).parse(id.text, names.node, f, true);
end;

function CParser.BuildEcho(const a1, a0, exp: YYSType; const extra: fun.str = ''): YYSType;
begin
  DoLog(a1, a0, result);
  result.node := CEcho.new(Curr, true).parse(exp.node, extra);
  DoLogCmd(result);
end;

function CParser.BuildElse(const a1: YYSType): YYSType;
begin
  DoLog(a1, result);
  if not (Curr.parent is flow.CIf) then
  begin
    DoError(result, 'if|case' + _NotFound);
    exit;
  end
  else if CIf(Curr.parent).nelse <> nil then
  begin
    DoError(result, a1.text + _Exists);
    exit;
  end;
  Curr := Curr.parent;
  CIf(Curr).nelse := CRuns.new(Curr);
  Curr := CIf(Curr).nelse;
end;

function CParser.BuildEnd(const a1: YYSType; ignoreName: fun.bool = false): YYSType;
var
  done: fun.bool;
begin
  DoLog(a1, result);
  if not (Curr.parent is CBloc) or (not ignoreName and (CBloc(Curr.parent).name <> '{')) then
  begin
    DoError(result, '{' + _NotFound);
    exit;
  end;
  done := Curr.parent = Root;
  DoLogEnd(result, CBloc(Curr.parent));
  
  if done and not ignoreName then
  begin
    TParser(yacc).builder := OldP;
    del(self);
    result.val := -1;
  end;
end;

function CParser.BuildEnd(const a1, a0, id: YYSType): YYSType;
begin
  DoLog(a1, a0, result);
  if not (Curr.parent is CBloc) or (CBloc(Curr.parent).name <> id.text) then
  begin
    DoError(result, id.text + _NotFound);
    exit;
  end;
  DoLogEnd(result, CBloc(Curr.parent));
end;

procedure CParser.BuildError(const a1: YYSType);
begin
  DoError(a1, _SynErr + '[' + a1.text + ']');
end;

function CParser.BuildExcept(const a1: YYSType): YYSType;
begin
  DoLog(a1, result);
  if not (Curr.parent is flow.CTry) then
  begin
    DoError(result, 'try' + _NotFound);
    exit;
  end
  else if CTry(Curr.parent).nexcept <> nil then
  begin
    DoError(result, a1.text + _Exists);
    exit;
  end;
  Curr := Curr.parent;
  CTry(Curr).nexcept := CRuns.new(Curr);
  Curr := CTry(Curr).nexcept;
end;

function CParser.BuildExit(const a1: YYSType): YYSType;
begin
  DoLog(a1, result);
  result.node := CExit.new(Curr, true).parse(DoFind(), nil);
  DoLogCmd(result);
end;

function CParser.BuildExit(const a1, a0, exp: YYSType): YYSType;
begin
  DoLog(a1, a0, result);
  result.node := CExit.new(Curr, true).parse(DoFind(), exp.node);
  DoLogCmd(result);
end;

function CParser.BuildFinally(const a1: YYSType): YYSType;
begin
  DoLog(a1, result);
  if not (Curr.parent is flow.CTry) then
  begin
    DoError(result, 'try' + _NotFound);
    exit;
  end
  else if CTry(Curr.parent).nfinally <> nil then
  begin
    DoError(result, a1.text + _Exists);
    exit;
  end;
  Curr := Curr.parent;
  CTry(Curr).nfinally := CRuns.new(Curr);
  Curr := CTry(Curr).nfinally;
end;

function CParser.BuildFor(const a1, a0, id, exp, emax: YYSType; estep: fun.ptr = nil): YYSType;
begin
  DoLog(a1, a0, result);
  DoLogBegin(result, a0, CForTo.new(Curr, true));
  Curr := CForTo(Curr).parse(id.text, exp.node, emax.node, estep);
end;

function CParser.BuildForIn(const a1, a0, id, exp: YYSType; const key: fun.str = ''; const idx: fun.str = ''): YYSType;
begin
  DoLog(a1, a0, result);
  DoLogBegin(result, a0, CForIn.new(Curr, true));
  Curr := CForIn(Curr).parse(id.text, exp.node, key, idx);
end;

function CParser.BuildFun(const a1, a0, id, names: YYSType): YYSType;
begin
  DoLog(a1, a0, result);
  if names.node <> nil then
    Curr := CRuns(Curr).parent
  else
    Curr := CFun.new(Curr, true)
  ;
  DoLogBegin(result, a1, CBloc(Curr));
  Curr := CFun(Curr).parse(id.text, names.node);
end;

function CParser.BuildFunDef(const a1, a0: YYSType; names: fun.ptr = nil; dontParse: fun.bool = false; const id: fun.str = ''): YYSType;
var
  p: CParser;
  f: CFun;
  e: CExp;
begin
  DoLog(a1, a0, result);
  if names <> nil then
    Curr := CRuns(Curr).parent
  else
    Curr := CFun.new(Curr, true)
  ;
  
  f := CFun(Curr);
  e := CExp.new(f);
  e.assign(f);
  result.node := e;
  
  if dontParse then
  begin
    f.parse(id, names);
    Curr := CTry(Curr).all;
    exit;
  end;
  
  Curr := Curr.parent;
  
  // Parse the fun ...
  p := OldC.Create;
  p.OldC := OldC;
  p.Yacc := Yacc;
  TParser(p.Yacc).Builder := p;
  p.OldP := self;
  p.Root := f;
  p.OnParse(self);
  p.DoLogBegin(result, a0, f);
  p.Curr := f.parse(id, names);
  TParser(p.Yacc).yacc_parse(true);
  // del p in BuildEnd()
end;

function CParser.BuildIf(const a1, a0, exp: YYSType; isElse: fun.bool = false): YYSType;
begin
  DoLog(a1, a0, result);
  if not isElse then
    DoLogBegin(result, a1, flow.CIf.new(Curr, true))
  else
  begin
    if not (Curr.parent is flow.CIf) then
    begin
      DoError(result, 'if' + _NotFound);
      exit;
    end;
    Curr := Curr.parent;
  end;
  Curr := flow.CIf(Curr).parse(exp.node);
end;

function CParser.BuildLoop(const a1: YYSType): YYSType;
begin
  DoLog(a1, result);
  DoLogBegin(result, a1, CLoop.new(Curr, true));
  Curr := CLoop(Curr).parse(nil);
end;

function CParser.BuildLoop(const a1, a0, exp: YYSType): YYSType;
begin
  DoLog(a1, a0, result);
  DoLogBegin(result, a0, CLoop.new(Curr, true));
  Curr := CLoop(Curr).parse(exp.node);
end;

function CParser.BuildNext(const a1: YYSType): YYSType;
begin
  DoLog(a1, result);
  result.node := CNext.new(Curr, true).parse(DoFind(), nil);
  DoLogCmd(result);
end;

function CParser.BuildNext(const a1, a0, exp: YYSType): YYSType;
begin
  DoLog(a1, a0, result);
  result.node := CNext.new(Curr, true).parse(DoFind(), exp.node);
  DoLogCmd(result);
end;

function CParser.BuildRaise(const a1, a0, exp: YYSType): YYSType;
begin
  DoLog(a1, a0, result);
  result.node := CRaise.new(Curr, true).parse(nil, exp.node);
  DoLogCmd(result);
end;

function CParser.BuildReturn(const a1: YYSType): YYSType;
begin
  DoLog(a1, result);
  result.node := CReturn.new(Curr, true).parse(DoFind(true), nil);
  DoLogCmd(result);
end;

function CParser.BuildReturn(const a1, a0, exp: YYSType): YYSType;
begin
  DoLog(a1, a0, result);
  result.node := CReturn.new(Curr, true).parse(DoFind(true), exp.node);
  DoLogCmd(result);
end;

function CParser.BuildSet(const a1, a0, evar, exp: YYSType; const op: fun.str = ''): YYSType;
var
  e: fun.ptr;
begin
  DoLog(a1, a0, result);
  if op = '' then
    e := exp.node
  else
  begin
    e := CCTwo.new(Curr).parse(evar.node, ParseOp(op), exp.node);
    base.add(evar.node);
  end;
  if (CExp(evar.node) is CId) and not (CExp(evar.node) is CId2) then
    result.node := CAssignFast.new(Curr, true).parse(CExp(evar.node), e)
  else
    result.node := CAssign.new(Curr, true).parse(CExp(evar.node), e);
  DoLogCmd(result);
end;

function CParser.BuildTry(const a1: YYSType): YYSType;
begin
  DoLog(a1, result);
  DoLogBegin(result, a1, flow.CTry.new(Curr, true));
  Curr := flow.CTry(Curr).parse();
end;

{$IfDef FunSafe}
// Is aPath inside aDir (after resolving relative components)? Both are
// compared as expanded absolute paths; Windows is case-insensitive.
function SafePathUnder(const aPath, aDir: fun.str): fun.bool;
var
  p, d: fun.str;
begin
  result := false;
  if (aPath = '') or (aDir = '') then exit;
  p := ExpandFileName(aPath);
  d := ExpandFileName(aDir);
  {$IfDef MSWINDOWS}
  p := LowerCase(p);
  d := LowerCase(d);
  {$EndIf}
  if Length(p) < Length(d) then exit;
  if Copy(p, 1, Length(d)) <> d then exit;
  if Length(p) = Length(d) then exit(true);
  result := p[Length(d) + 1] in ['/', '\'];
end;

// Safe builds only import modules from the script directory, the current
// directory, the interpreter's lib/app folders, or FUN_PATH. The import is
// still parse-time code loading, so it is gated by FunSafeAllowCompile.
function SafeUseAllowed(const fn: fun.str; root: CNode): fun.bool;
var
  base, fp, part, sep: fun.str;
  i, n: fun.int;
begin
  result := false;
  if root is CModu then
    result := SafePathUnder(fn, ExtractFilePath(CModu(root).fileName));
  if not result then
    result := SafePathUnder(fn, GetCurrentDir);
  if not result then
  begin
    base := ExtractFilePath(ParamStr(0));
    result := SafePathUnder(fn, base + 'lib') or SafePathUnder(fn, base + 'app');
  end;
  {$IfDef FunPack}
  if not result then
  begin
    fp := GetEnvironmentVariable('FUN_PATH');
    {$IfDef UNIX}sep := ':';{$Else}sep := ';';{$EndIf}
    i := 1;
    n := Length(fp);
    while (i <= n + 1) and not result do
    begin
      part := '';
      while (i <= n) and (Copy(fp, i, 1) <> sep) do
      begin
        part := part + fp[i];
        Inc(i);
      end;
      if part <> '' then
        result := SafePathUnder(fn, part);
      Inc(i);
    end;
  end;
  {$EndIf}
end;
{$EndIf}

function CParser.BuildUse(const a1, a0, estr: YYSType; const id: fun.str = ''): YYSType;
var
  f: fun.str;
  pf: fun.str;
  m: CRuns;
  temp: YYSType;
begin
  DoLog(a1, a0, result);
  // todo
  f := Copy(estr.text, 2, Length(estr.text)-2);
  
  // for include only
  if (f[1] = ':') and (id <> '') then
  begin
    Delete(f, 1, 1);
    f := ParseFileName(f, Root);
    {$IfDef FunSafe}
    {$IfNDef FunSafeAllowCompile}
    if not SafeUseAllowed(f, Root) then SafeDeny('use of ' + f);
    {$EndIf}
    {$EndIf}
    if FileExists(f) then
    begin
      temp.text := CIO.Load(f); // isUse - CreateStr
      temp.node := CreateStr(temp, true).node;
      temp.text := id;
      result.node := BuildVar(a1, a0, temp, temp.node).node;
      exit;
    end;
  end;
  
  pf := PlatformFile(f, Root);
  if pf <> '' then
    f := pf
  else
    f := ParseFileName(f, Root);
  {$IfDef FunSafe}
  {$IfNDef FunSafeAllowCompile}
  if not SafeUseAllowed(f, Root) then SafeDeny('use of ' + f);
  {$EndIf}
  {$EndIf}
  m := CModu(Root).find(ExpandFileName(f));
  if m <> nil then
    Curr.use(m, id)
  else if FileExists(f) then
  begin
    //m := CRuns(CParser.Parse(CIO.load(f), OldC, f, Root));
    m := CRuns(CParser.ParseOrLoad(f, Root, OldC));
    Curr.use(m, id);
    del(m);
  end
  else
    DoError(estr, f + _NotFound)
  ;
end;

function CParser.BuildVar(const a1, a0, id: YYSType; exp: fun.ptr = nil; upup: fun.bool = false): YYSType;
var
  v: CVar;
  e: CExp;
  c: CRuns;
begin
  DoLog(a1, a0, result);
  if not (Curr is CRuns) then
  begin
    DoError(result, _SynErr);
    exit;
  end;
  
  if upup then
    c := CRuns(Curr.parent.parent)
  else
    c := CRuns(Curr)
  ;
  
  v := CVar.new(c, id.text);
  if exp <> nil then
  begin
    // CVar or CId ?
    // => CId
    e := CId.new(c).parse(id.text, v);
    // Same node as a statement assignment: the target is always a plain CId
    // here, and the first run still falls back to the generic path when the
    // declared slot needs its initial scope push.
    result.node := CAssignFast.new(c, true).parse(e, exp);
    DoLogCmd(result);
  end
  else
    result.node := v;
  ;
end;

function CParser.BuildWhen(const a1, a0, exp: YYSType): YYSType;
begin
  DoLog(a1, a0, result);
  if not (Curr is CCase) then
  begin
    if not (Curr.parent is CCase) then
    begin
      DoError(result, 'case' + _NotFound);
      exit;
    end;
    Curr := Curr.parent;
  end;
  Curr := flow.CIf(Curr).parse(exp.node);
end;

function CParser.CreateConst(const a1: YYSType; const v: CValue): YYSType;
begin
  DoLog(a1, result);
  result.node := CExp.new(Curr).parse(v);
end;

function CParser.CreateDotAny(const a1, a0, exp, op, exp2: YYSType): YYSType;
var
  es: CExps;
begin
  DoLog(a1, a0, result);
  es := CExps.Create();
  es.add(exp2.node);
  result.node := core.CFunc.new(Curr).parse(CId2.new(Curr).parse(Copy(op.text, 2, MaxInt), exp.node), es);
end;

function CParser.CreateExp(const a1, a0, exp: YYSType): YYSType;
begin
  DoLog(a1, a0, result);
  result.node := exp.node;
end;

function CParser.CreateExp(const a1, a0, op, exp: YYSType; isBit: fun.bool = false): YYSType;
begin
  DoLog(a1, a0, result);
  result.node := CCOne.new(Curr).parse(exp.node, ParseOp(op.text, isBit));
end;

function CParser.CreateExp(const a1, a0, exp, op, exp2: YYSType; isBit: fun.bool = false): YYSType;
var
  o: fun.char;
  c: CCCTwo;
begin
  DoLog(a1, a0, result);
  o := ParseOp({$IfDef _C_}ParseAlias{$EndIf}(op.text), isBit);
  if o = OP_AND then
    c := CCAnd
  else if o = OP_OR then
    c := CCOr
  else
    c := CCTwo
  ;
  result.node := c.new(Curr).parse(exp.node, o, exp2.node);
end;

function CParser.CreateFunExp(const a1, a0, exp, values: YYSType): YYSType;
begin
  DoLog(a1, a0, result);
  result.node := core.CFunc.new(Curr).parse(exp.node, values.node);
end;

function CParser.CreateFunFun(const a1, a0, exp: YYSType): YYSType;
begin
  DoLog(a1, a0, result);
  result.node := exp.node;
  CFunc(exp.node).fun2 := true;
end;

function CParser.CreateId(const a1: YYSType; optional: fun.bool = false): YYSType;
begin
  DoLog(a1, result);
  result.node := CId.new(Curr).parse(a1.text, nil, optional);
end;

function CParser.CreateNames(const a1: YYSType): YYSType;
begin
  DoLog(a1, result);
  result.node := CExps.Create(false);
  // New CFun for Names - CVar s
  Curr := CBloc(CFun.new(Curr, true)).parse();
  CExps(result.node)[a1.text] := CVar.new(CRuns(Curr), a1.text);
end;

function CParser.CreateNames(const a1, a0, names: YYSType): YYSType;
begin
  DoLog(a1, a0, result);
  result.node := names.node;
end;

function CParser.CreateNames(const a1, a0, names, id: YYSType): YYSType;
begin
  DoLog(a1, a0, result);
  result.node := names.node;
  CExps(result.node)[id.text] := CVar.new(CRuns(Curr), id.text);
end;

function CParser.CreateNum(const a1: YYSType; const sign: fun.str = ''): YYSType;
begin
  DoLog(a1, result);
  result.node := CExp.new(Curr).parse(StrToNum(sign + a1.text));
end;

function CParser.CreateRef(const a1, a0, id: YYSType): YYSType;
begin
  DoLog(a1, a0, result);
  result.node := Curr.UID(id.text);
  base.add(result.node);
  if result.node = nil then
  begin
    result.node := CExp.new(Curr);
    DoError(id, id.text + _NotFound)
  end;
end;

function CParser.CreateRegex(const a1: YYSType): YYSType;
begin
  DoLog(a1, result);
  // Without -dRegex no CRegex is built; return an explicit nil node rather than
  // an uninitialized pointer (aarch64 otherwise dereferences the garbage).
  result.node := nil;
  {$IfDef Regex}
  result.node := CRegex.new(Curr).parse(a1.text);
  {$EndIf}
end;

function CParser.CreateSetConst(const a1, a0, values: YYSType): YYSType;
begin
  DoLog(a1, a0, result);
  result.node := CSet.new(Curr).parse(values.node);
end;

function CParser.CreateSetIndex(const a1, a0, exp, index: YYSType; const extra: fun.str = ''): YYSType;
begin
  DoLog(a1, a0, result);
  result.node := CIdx.new(Curr).parse(extra, exp.node, index.node);
end;

function CParser.CreateSetNew(const a1, a0, exp: YYSType): YYSType;
begin
  DoLog(a1, a0, result);
  result.node := core.CSet2.new(Curr).parse(CSet(exp.node));
end;

function CParser.CreateStr(const a1: YYSType; isUse: fun.bool = false): YYSType;
begin
  DoLog(a1, result);
  result.node := CExp.new(Curr).parse(ParseString(a1.text, not isUse));
end;

function CParser.CreateTime(const a1: YYSType): YYSType;
begin
  DoLog(a1, result);
  result.node := CExp.new(Curr).parse(ToFunTime(Copy(a1.text, 3, Length(a1.text)-3)));
end;

function CParser.CreateValue(const a1, a0, id, exp: YYSType; str: fun.bool = false): YYSType;
begin
  DoLog(a1, a0, result);
  result.node := exp.node;
  CExp(result.node).name := ParseString(id.text, str);
end;

function CParser.CreateValues(const a1: YYSType): YYSType;
begin
  DoLog(a1, result);
  result.node := CExps.Create();
  CExps(result.node).add(a1.node);
end;

function CParser.CreateValues(const a1, a0, values, value: YYSType): YYSType;
begin
  DoLog(a1, a0, result);
  result.node := values.node;
  CExps(result.node).add(value.node);
end;

function CParser.CreateVarExp(const a1, a0, exp, id: YYSType; str: fun.bool = false; optional:  fun.bool = false): YYSType;
begin
  DoLog(a1, a0, result);
  result.node := CId2.new(Curr).parse(ParseString(id.text, str), exp.node, optional);
end;

procedure CParser.DoError(const s: fun.str);
begin
  // no action
end;

procedure CParser.DoError(const a1: YYSType; const s: fun.str);
begin
  {$IfNDef OnlyRuntime}
  DoError(s + ' @ ' + IntToStr(a1.row) + ',' + IntToStr(a1.col));
  {$Else}
  DoError(s);
  {$EndIf}
end;

function CParser.DoFind(onlyFun: fun.bool = false): CNode;
var
  n, p: CNode;
begin
  p := Curr;
  repeat
    n := p;
    p := n.parent;
  until (p = nil) or ((p is CLoop)and(not onlyFun)) or (p is CFun);
  result := n;
end;

procedure CParser.DoLog(const a1: YYSType; var ret: YYSType);
begin
  {$IfNDef OnlyRuntime}
  ret.index := a1.index;
  ret.leng  := a1.leng;
  ret.row   := a1.row;
  ret.col   := a1.col;
  ret.text  := a1.text;
  {$EndIf}
end;

procedure CParser.DoLog(const a1, a0: YYSType; var ret: YYSType);
begin
  {$IfNDef OnlyRuntime}
  ret.index := a1.index;
  ret.leng  := a0.index + a0.leng - a1.index;
  ret.row   := a1.row;
  ret.col   := a1.col;
  if ret.leng > a1.leng then
    ret.text := a1.text + '...' + a0.text
  else
    ret.text := a1.text;
  ;
  {$EndIf}
end;

procedure CParser.DoLogBegin(const r, a: YYSType; n: CBloc);
begin
  Curr := n;
  n.name := a.text;
  {$IfNDef OnlyRuntime}
  n.row := r.row;
  OnParse(n);
  {$EndIf}
end;

procedure CParser.DoLogCmd(const a1: YYSType);
begin
  {$IfNDef OnlyRuntime}
  CRune(a1.node).row := a1.row;
  OnParse(CRune(a1.node));
  {$EndIf}
end;

procedure CParser.DoLogEnd(const r: YYSType; n: CBloc);
begin
  Curr := n;
  n.name := '';
  {$IfNDef OnlyRuntime}
  //n.all.row := r.row;
  {$EndIf}
  Curr := Curr.parent;
end;

function CParser.DoParse(const s: fun.str; prev: fun.ptr = nil): CNode;
var
  s2: fun.str;
begin
  Root   := core.CModu.new(nil);
  
  s2 := s;
  if FileN <> '' then
  begin
    CModu(Root).fileName := ExpandFileName(FileN);
    OnParse(CModu(Root).fileName, s2, CModu(Root));
  end;
  
  LinkRoots(Root, prev);
  Curr   := Root;
  result := Root;
  TParser(yacc).parse(s2);
end;

class procedure CParser.LinkRoots(node, prev: fun.ptr);
begin
  if prev <> nil then
  begin
    CModu(node).next := CModu(prev).next;
    if CModu(node).next = nil then CModu(node).next := CModu(prev);
    CModu(prev).next := CModu(node);
  end;
end;

procedure CParser.OnParse(p: CParser);
begin
  // no action
end;

procedure CParser.OnParse(n: CRune);
begin
  // no action
end;

procedure CParser.OnParse(const fn: fun.str; var s: fun.str; m: core.CModu = nil);
begin
  // no action
end;

class function CParser.Parse(const s: fun.str; CCParser: CParserClass; const fn: fun.str = ''; prev: fun.ptr = nil): CRun;
var
  p: CParser;
  y: TParser;
  ext: fun.str;
begin
  p := CCParser.Create;
  p.OldC    := CCParser;
  p.FileN   := fn;
  y := TParser.Create;
  p.Yacc    := y;
  y.Builder := p;
  try
    result := CRun(p.DoParse(s, prev));
  finally
    y.Free;
    del(p);
  end;
end;

{$IfDef IDE}
type
  // Parse errors must reach the caller of ParseExp; the base CParser.DoError
  // is a no-op (drivers report errors through their own override).
  CExpParser = class(CParser)
  public
    procedure DoError(const s: fun.str); override;
  end;

procedure CExpParser.DoError(const s: fun.str);
begin
  raise EBase.Create(s);
end;

class function CParser.ParseExp(const s: fun.str; scope: CNode; out root: CRun): CExp;
var
  n: CRun;
begin
  result := nil;
  root   := nil;
  n      := Parse('?' + s, CExpParser);
  root   := n;
  if n = nil then exit;
  n.parent := scope;
  if CRuns(n)[0] is CCall then
    result := CCall(CRuns(n)[0]).Expr;
end;
{$EndIf}

class function CParser.ParseFileName(const fn: fun.str; prev: CNode): fun.str;
var
  path, ret, fname: fun.str;
  {$IfDef FunPack}
  fp, dir, sep: fun.str;
  fpLen, i: Integer;
  {$EndIf}
begin
  fname  := CIO.Norm(fn);
  result := fname;
  {$IfDef FunPack}
  {$IfDef UNIX}
  sep := ':';
  {$Else}
  sep := ';';
  {$EndIf}
  {$EndIf}
  if not FileExists(result) then
  begin
    if (result[2] <> ':') and (Pos('\\', result) <> 1) then
    begin
      result := ExtractFilePath(CModu(prev).fileName) + result;
      if not FileExists(result) then
      begin
        path := ExtractFilePath(ParamStr(0));
        {$IfDef Debug}
        {$IfNDef UNIX}
        path := path + '..\..\..\fun\';
        {$Else}
        path := path + '../../../fun/';
        {$EndIf}
        {$EndIf}
        {$IfNDef UNIX}
        ret  := path + 'lib\' + fn;
        if not FileExists(ret) then ret := path + 'app\' + fn;
        {$Else}
        ret  := path + 'lib/' + fname;
        if not FileExists(ret) then ret := path + 'app/' + fname;
        {$EndIf}
        if     FileExists(ret) then result := ret;
        {$IfDef FunPack}
        if not FileExists(result) then
        begin
          // FUN_PATH: last-resort lookup for bare names (set by the package
          // runner); unset keeps the historical result unchanged.
          fp := GetEnvironmentVariable('FUN_PATH');
          if (fp <> '') and (Pos('/', fn) = 0) and (Pos('\', fn) = 0) and
             (Copy(fn, 1, 1) <> ':') then
          begin
            fpLen := Length(fp);
            i := 1;
            dir := '';
            while i <= fpLen + 1 do
            begin
              if (i > fpLen) or (Copy(fp, i, 1) = sep) then
              begin
                if dir <> '' then
                begin
                  ret := IncludeTrailingPathDelimiter(dir) + fname;
                  if FileExists(ret) then
                  begin
                    result := ret;
                    exit;
                  end;
                end;
                dir := '';
              end
              else
                dir := dir + Copy(fp, i, 1);
              Inc(i);
            end;
          end;
        end;
        {$EndIf}
      end;
    end;
  end;
end;

class function CParser.PlatformFile(const fn: fun.str; prev: CNode): fun.str;
// 'name.fun' -> the platform backend when one exists: 'name-darwin.fun' /
// 'name-lnx.fun', else the shared 'name-unx.fun'. Lets code use the neutral
// name while plain names stay the Windows implementation. '' = no variant.
var
  i: Integer;
  s: fun.str;
begin
  result := '';
  s      := '';
  i := Length(fn) - 3;
  if (i < 1) or (Copy(fn, i, 4) <> '.fun') then exit;
  {$IfDef Darwin}
  s := '-darwin';
  {$EndIf}
  {$IfDef Linux}
  s := '-lnx';
  {$EndIf}
  {$IfDef UNIX}
  if s <> '' then
  begin
    s := ParseFileName(Copy(fn, 1, i - 1) + s + '.fun', prev);
    if FileExists(s) then
    begin
      result := s;
      exit;
    end;
  end;
  s := ParseFileName(Copy(fn, 1, i - 1) + '-unx.fun', prev);
  if FileExists(s) then result := s;
  {$EndIf}
end;

class function CParser.ParseOrLoad(const fn: fun.str; prev: fun.ptr = nil; CCParser: CParserClass = nil): fun.ptr;
var
  s: fun.str;
begin
  if CCParser = nil then CCParser := _ParserClass;
  
  s := CIO.Load(fn);
  result  := Parse(s, CCParser, fn, prev);
end;

class function CParser.ParseString(const s: fun.str; str: fun.bool = false): fun.str;
begin
  result := s;
  if str then result := NewStringReplace(Copy(s, 2, Length(s)-2), s[1]+s[1], s[1], [rfReplaceAll]);
end;

class function CParser.StrToNum(const s: fun.str): CValue;
var
  i, ii: fun.int;
  u: fun.uint32;
begin
  ii := Length(s);
  if (ii > 2) and (s[1] = '0') and (s[2] in ['X', 'x', 'B', 'b']) then
  begin
    if s[2] in ['X', 'x'] then
      // Fun's 0x literals are 32-bit (type.fun pins 0xffffffff = 4294967295),
      // so ask for the 32-bit unsigned type explicitly. fun.uint is uint64
      // under {$IfDef Win64} (it is sized for pointers), and on that build
      // fun.uint(StrToInt('0xffffffff')) held a varUInt64 that the ANSI value
      // -> string path echoed as -1. uint32 is what fun.uint already is on the
      // other targets, so this is a no-op there.
      result := fun.uint32(StrToInt(s))
    else
    begin
      u := 0;
      for i := ii downto 3 do if s[i] = '1' then
      begin
        u := u or (1 shl (ii-i));
      end;
      result := u;
    end;
  end
  else if (Pos('.', s) >= 1) or (Pos('e', s) > 1) or (Pos('E', s) > 1) then
    result := StrToFloat(s)
  else
  begin
    if TryStrToInt(s, i) then
      result := i
    else
      result := StrToInt64(s)
    ;
  end;
end;


end.
