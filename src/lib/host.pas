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
unit host;

// Unix FFI (getapi via FPC's bundled libffi unit) is requested by make-linux-x86_64.sh
// as -dLinuxFFI and by make-darwin.sh as -dDarwinFFI. Both map to the single
// UnixFFI symbol used throughout the engine. Guarded because FPC keeps a defined
// symbol globally across the units of one build.
{$IfNDef UnixFFI}
  {$IfDef LinuxFFI}{$Define UnixFFI}{$EndIf}
  {$IfDef DarwinFFI}{$Define UnixFFI}{$EndIf}
{$EndIf}

interface

uses fun, base, core;

type
  CPasFun = procedure (env: CEnv; exp: CExp; exps: CExps; val: PValue);

  CCallObj = class(CNode)
  private
    f: CFun;
    o: CObj;
  protected
    env: CEnv;
  public
    function call(env: CEnv; exps: CExps): PValue; overload; override;
    procedure parse(exp: CExp; exps: CExps; theEnv: CEnv);
  end;
  
  CEnv2 = class(CEnv)
  protected
    libs: CList;
  public
    constructor Create;
    destructor Destroy; override;
    function call(exp: CExp; const id: fun.str; exps: CExps; val: PValue; ct: fun.byte = CDoMethod): fun.bool; override;
    function clone: CEnv; override;
  end;
  
  CLib = class(CBase)
  protected
    ids: CHash;
  public
    constructor Create;
    destructor Destroy; override;
    function accept(exp: CExp): fun.bool; virtual;
    function call(env: CEnv; exp: CExp; const id: fun.str; exps: CExps; val: PValue; ct: fun.byte = CDoMethod): fun.bool; virtual;
  end;
  
  CLfun = class(CLib)
  public
    constructor Create;
    function accept(exp: CExp): fun.bool; override;
  end;
  

procedure _getlib(env: CEnv; exp: CExp; exps: CExps; val: PValue);

implementation

uses libase, libset
     {$IfDef WinCOM}, winole{$EndIf}
     {$IfDef WinAPI}, winapi{$EndIf}
     {$IfDef UnixFFI}, lffi  {$EndIf}
     {$IfDef Regex} , regex {$EndIf}
     {$IfDef FunUI} , ui    {$EndIf}
     ;

//==============================================================
procedure _getlib(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  name: fun.str;
begin
  name := exp.asStr;
  {$IfDef FunUI}
  if name = 'ui' then
  begin
    setObj(val, uilib, VarObject);
    exit;
  end;
  {$EndIf}
end;

//==============================================================
function CCallObj.call(env: CEnv; exps: CExps): PValue;
var
  pushed: fun.bool;
begin
  pushed := false;
  if o <> nil then pushed := CObj(o).push;
  try
    result := f.call(env, exps);
  finally
    if pushed then CObj(o).pop;
  end;
end;

procedure CCallObj.parse(exp: CExp; exps: CExps; theEnv: CEnv);
var
  e: CExp;
begin
  f := CFun(exp.asObj);
  e := CExps.Find(exps, 'obj', 0);
  if e <> nil then o := CObj(e.asObj);
  if CExps.FindAsVal(exps, 'thread', 9, false) then
  begin
    self.env := theEnv.clone();
  end else
    self.env := theEnv
  ;
end;

//==============================================================
constructor CEnv2.Create;
begin
  inherited Create;
  libs := CList.Create();
  
  // win ole
  {$IfDef WinCOM}
  libs.add(CLole.Create());
  {$EndIf}
  
  // base lib
  libs.add(CLbase.Create());
  
  // regex lib
  {$IfDef Regex}
  libs.add(CLreg.Create());
  libs.add(CLmat.Create());
  {$EndIf}
  
  // set lib
  libs.add(CLset.Create());
  
  // fun lib
  libs.add(CLfun.Create());
  
  // win api
  {$IfDef WinAPI}
  libs.add(CLapi.Create());
  {$EndIf}
  
  // linux ffi
  {$IfDef UnixFFI}
  libs.add(CLffiApi.Create());
  {$EndIf}

  // ui lib
  {$IfDef FunUI}
  libs.add(uilib);
       add(uilib);
  libs.add(uiform);
       add(uiform);
  {$EndIf}
end;

destructor CEnv2.Destroy;
begin
  del(libs);
  inherited Destroy;
end;

function CEnv2.call(exp: CExp; const id: fun.str; exps: CExps; val: PValue; ct: fun.byte = CDoMethod): fun.bool;
var
  i: fun.int;
  lib: CLib;
begin
  result := false;
  for i := 0 to libs.count -1 do
  begin
    lib := CLib(libs[i]);
    if lib.accept(exp) then
    begin
      result := lib.call(self, exp, id, exps, val, ct);
      if result then exit; // or find another lib
    end;
  end;
end;

function CEnv2.clone: CEnv;
begin
  result := CEnv2.create;
end;

//==============================================================
constructor CLib.Create;
begin
  inherited Create;
  ids := CHash.Create();
end;

destructor CLib.Destroy;
begin
  del(ids);
  inherited Destroy;
end;

function CLib.accept(exp: CExp): fun.bool;
begin
  // no action
  result := false;
end;

function CLib.call(env: CEnv; exp: CExp; const id: fun.str; exps: CExps; val: PValue; ct: fun.byte = CDoMethod): fun.bool;
var
  v: CExp;
begin
  result := false;
  v := ids[id];
  if v <> nil then
  begin
    // asPtr: full-width read, so dispatch still works when code addresses
    // exceed 32 bits (PIE / Win64 builds).
    CPasFun(asPtr(v.value))(env, exp, exps, val);
    result := true;
  end;
end;

//==============================================================
constructor CLfun.Create;
begin
  inherited Create;
  {$IfDef WinCOM}
  ids['@toEvent'] := CExp.new(nil).parse(Int64(fun.uintptr(@_toEvent)));
  {$EndIf}
  {$IfDef WinAPI}
  ids['@toCallback'] := CExp.new(nil).parse(Int64(fun.uintptr(@_toCallback)));
  {$EndIf}
  {$IfDef UnixFFI}
  ids['@toCallback'] := CExp.new(nil).parse(Int64(fun.uintptr(@_ltoCallback)));
  {$EndIf}
end;

function CLfun.accept(exp: CExp): fun.bool;
begin
  result := exp.asObj is CFun;
end;


end.
