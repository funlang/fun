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
unit winapi;

interface

uses fun, base, core, host;

type
  // FARPROC
  CWinAPI = function(): fun.int; far;
  PCallDesc = ^CCallDesc;
  CCallDesc = packed record
    Eax : fun.byte; // mov  eax, obj
    obj : fun.ptr;
    Call: fun.byte; // call proc
    proc: fun.ptr;
    Ret : fun.byte; // ret  num
    num : fun.word;
  end;

  CLapi = class(CLib)
  public
    function accept(exp: CExp): fun.bool; override;
    function call(env: CEnv; exp: CExp; const id: fun.str; exps: CExps; val: PValue; ct: fun.byte = CDoMethod): fun.bool; override;
  end;
  
  CWinFun = class(CExp)
  private
    flag: fun.str;
    hfun: fun.ptr;
    hlib: fun.uint;
  public
    constructor Create(alib: fun.uint; afun: fun.ptr; const atype: fun.str);
    destructor Destroy; override;
    function call(env: CEnv; exps: CExps): PValue; override;
  end;
  
  CCallback = class(CCallObj)
  private
    FProc: PCallDesc;
    Types: fun.str;
    function GetProc: PCallDesc;
    procedure MyProc;
  protected
    function Parse(exp: CExp; exps: CExps; theEnv: CEnv): CCallback;
  public
    destructor Destroy; override;
    property Proc: PCallDesc read GetProc;
  end;
  

procedure _getapi(env: CEnv; exp: CExp; exps: CExps; val: PValue);
procedure _toCallback(env: CEnv; exp: CExp; exps: CExps; val: PValue);

implementation

uses Windows,
     io;

type PValue = base.PValue;

// f.getapi(name, type)
//   f    -> filename
//   name -> method name or address
//   type -> xxx...:x
//           n(umber)   i(nt)      l(ong)     f(loat)
//           s(tring)   w(idestr)  a(nsistr)  r(awstr)
//           p(ointer)  c(allback) v(oid)    
procedure _getapi(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  name: fun.str;
  hlib: fun.uint;
  hfun: fun.ptr;
  wfun: CWinFun;
  e: CExp;
begin
  {$IfDef FunSafe}
  SafeDeny('getapi native call');
  {$EndIf}
  hlib := 0;
  name := exp.asStr;
  if name <> '' then
  begin
    hlib := LoadLib(name);
  end;

  hfun := nil;
  e    := CExps.Find(exps, 'name', 0);
  if e <> nil then
  begin
    if isNum(e.value) then
      hfun := asPtr(e.value)   // numeric address: read full width
    else
      name := e.asStr
    ;
  end;
  if hfun = nil then
  begin
    hfun := GetProc(hlib, name);
  end;
  wfun := CWinFun.Create(hlib, hfun, CExps.FindAsVal(exps, 'type', 1, ''));
  setObj(val, wfun, VarObjNew); del(wfun);
end;

// f.@toCallback(obj, type, ptr)
//    type -> :C // cdecl
procedure _toCallback(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  c: CCallback;
  e: CExp;
begin
  {$IfDef FunSafe}
  SafeDeny('native callback');
  {$EndIf}
  c := CCallback.Create.Parse(exp, exps, env);
  e := CExps.Find(exps, 'ptr', 2);
  if (e <> nil) and e.asBool then
    val^ := LongWord(c.Proc) // todo: mem leak
  else
  begin
    setObj(val, c, VarObjNew); del(c);
  end;
end;

//==============================================================
function CLapi.accept(exp: CExp): fun.bool;
begin
  result := exp.asObj is CWinFun;
end;

function CLapi.call(env: CEnv; exp: CExp; const id: fun.str; exps: CExps; val: PValue; ct: fun.byte = CDoMethod): fun.bool;
begin
  // id = 'call'
  // x.call(...)
  // x(...)
  val^ := CWinFun(exp.asObj).call(env, exps)^;
  result := true;
end;

//==============================================================
constructor CWinFun.Create(alib: fun.uint; afun: fun.ptr; const atype: fun.str);
begin
  inherited new(nil);
  hlib := alib;
  hfun := afun;
  flag := atype;
end;

destructor CWinFun.Destroy;
begin
  FreeLib(hlib);
  inherited Destroy;
end;

function CWinFun.call(env: CEnv; exps: CExps): PValue;
var
  e: CExp;
  
  procedure _call(val: PValue);
  var
    s: Single;
    i, ri: fun.int;
    ret: LongWord absolute s;
    e: CExp;
  begin
    // params: n, i, l, f, s, w, a, r, p, c, v
    for i := CExps.count(exps) - 1 downto 0 do
    begin
      e := CExp(exps.Item[i]);
      with CData(e.value^) do
      case flag[i + 1] of
        'n', 'i', 'l':
        begin
          if isNum(VType) then
            ret := VLongWord
          else
            ret := LongWord(e.value^)
          ;
        end;
  
        'a':
          ret := LongWord(fun.ptr(AnsiString(fun.str(VString))));
  
        'w':
          ret := LongWord(fun.ptr(WideString(fun.str(VString))));
  
      {$IfDef Unicode}
        's':
          ret := LongWord(fun.ptr(WideString(fun.str(VString))));
  
        'r':
          ret := LongWord(fun.ptr(ToRawString(fun.str(VString))));
      {$Else}
        's', 'r':
          ret := LongWord(fun.ptr(AnsiString(fun.str(VString))));
      {$EndIf}
  
        'p':
        begin
          if isStr(VType) then
            ret := LongWord(fun.ptr(fun.str(VString)))
          else
            ret := LongWord(@VLongWord)
          ;
        end;
  
        'c': // callback
        begin
          ret := 0;
          if e.asObj is CCallback then ret := LongWord(CCallback(e.asObj).Proc);
        end;
  
        'f':
        begin
          if VType = varDouble then
          begin
            s := VDouble;
          end
          else if VType = varSingle then
          begin
            s := VSingle;
          end else
            ret := LongWord(e.value^)
          ;
        end;
  
        else // 'v'
          ret := 0;
      end;
  
      asm
        push ret
      end;
    end;
  
    // call
    ri := CWinAPI(hfun)();
    ret := LongWord(ri);
  
    // return
    case flag[Length(flag)] of
      's': val^ := fun.str(PChar(ret));
      'w': val^ := fun.str(PWideChar(ret));
      'a': val^ := fun.str(PAnsiChar(ret));
      'i': val^ := ri;
      else val^ := ret;
    end;
  end;
  
begin
  if CExps.count(exps) = 1 then
  begin
    e := exps.Item[0];
    if e.asObj is CSet then
      exps := CSet(e.asObj).items
    ;
  end;
  _call(p_val);
  result := p_val;
end;

//==============================================================
destructor CCallback.Destroy;
begin
  if FProc <> nil then
  begin
    VirtualFree(FProc, 0, MEM_RELEASE);
    FProc := nil;
  end;
  inherited Destroy;
end;

function CCallback.GetProc: PCallDesc;
begin
  if FProc = nil then
  begin
    FProc := VirtualAlloc(nil, SizeOf(CCallDesc), MEM_COMMIT, PAGE_EXECUTE_READWRITE);
  
    with FProc^ do
    begin
      Eax  := $b8;
      obj  := self;
      Call := $e8;
      proc := fun.ptr(fun.int(@CCallback.MyProc) - fun.int(FProc) - 10);
      Ret  := $c2;
      if Types[Length(Types)] = 'C' then
        num := 0
      else
        num  := fun.word( (Length(Types)-2) * 4 );
    end;
  end;
  Result := FProc;
end;

procedure CCallback.MyProc;
var
  p: fun.ptr;
  
  procedure DoProc;
  var
    es: CExps;
    e: CExp;
    i: fun.int;
  begin
    es := CExps.Create();
    try
      p := fun.ptr(fun.int(p) + 8);
      for i := 1 to Length(Types) -2 do
      begin
        p := fun.ptr(fun.int(p) + 4);
        e := CExp.new(nil);
        es.Add(e);
        case Types[i] of
          's', 'p': e.assign(fun.str(PChar(p^)));
          'w'     : e.assign(fun.str(PWideChar(p^)));
          'W'     : e.assign(fun.str(ToRawString(WideString(fun.ptr(p^)))));
          'a'     : e.assign(fun.str(PAnsiChar(p^)));
          'v', 'c': ;
          'i'     : e.assign(fun.int(p^));
          else      e.assign(LongWord(p^));
        end;
      end;
  
      p := PData(call(self.env, es)).VPointer;
      case Types[Length(Types)] of
        'a': p := fun.ptr(AnsiString(fun.str(p)));
      end;
    finally
      del(es);
    end;
  end;
  
begin
  {$IfNDef Win64}
    asm
      mov p, ebp
    end;
  
    DoProc;
  
    asm
      mov eax, p
    end;
  {$EndIf}
end;

function CCallback.Parse(exp: CExp; exps: CExps; theEnv: CEnv): CCallback;
begin
  result := self;
  //del(self);
  inherited parse(exp, exps, theEnv);
  
  Types :=  CExps.FindAsVal(exps, 'type', 1, '');
end;


end.
