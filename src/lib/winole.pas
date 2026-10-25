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
unit winole;

interface

uses fun, base, core, host;

type
  CLole = class(CLib)
  public
    function accept(exp: CExp): fun.bool; override;
    function call(env: CEnv; exp: CExp; const id: fun.str; exps: CExps; val: PValue; ct: fun.byte = CDoMethod): fun.bool; override;
  end;
  
  CEvent = class(CCallObj, IUnknown, IDispatch)
  private
    Conn: fun.int;
    DispIDs: fun.str;
    EventID: TGUID;
    Source: IDispatch;
  protected
    function GetIDsOfNames(const IID: TGUID; Names: fun.ptr; NameCount, LocaleID: fun.int; DispIDs: fun.ptr): HResult; stdcall;
    function GetTypeInfo(Index, LocaleID: fun.int; out TypeInfo): HResult; stdcall;
    function GetTypeInfoCount(out Count: fun.int): HResult; stdcall;
    function Invoke(DispID: fun.int; const IID: TGUID; LocaleID: fun.int; Flags: Word; var Params; VarResult, ExcepInfo, ArgErr: fun.ptr): HResult; stdcall;
    function Parse(exp: CExp; exps: CExps; theEnv: CEnv): IDispatch;
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
  public
    destructor Destroy; override;
  end;
  

procedure _newobj(env: CEnv; exp: CExp; exps: CExps; val: PValue);
procedure _toEvent(env: CEnv; exp: CExp; exps: CExps; val: PValue);

implementation

uses Variants, ComObj, ActiveX, SysUtils;

//==============================================================
function _classId(const c: fun.str): TGUID;
begin
  if (Length(c) > 0) and (c[1] = '{') then
    Result := StringToGUID(c)
  else
    Result := ProgIDToClassID(c);
  ;
end;

function _newOle(const c: fun.str; isGet: fun.bool = false): IDispatch;
var
  ClassID: TCLSID;
  Unknown: IUnknown;
begin
  ClassID := _classId(c);
  
  if not isGet then
    OleCheck(CoCreateInstance(ClassID, nil, CLSCTX_INPROC_SERVER or
      CLSCTX_LOCAL_SERVER, IDispatch, Result))
  else
  begin
    OleCheck(GetActiveObject(ClassID, nil, Unknown));
    OleCheck(Unknown.QueryInterface(IDispatch, Result));
  end;
end;

// c.newobj(get = false)
//   c -> class name or guid
// 0.newobj() -> null IDispatch
procedure _newobj(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  with PData(exp.value)^ do if isNum(VType) then //and (VInteger = 0) then
  begin
    PData(val).VType    := VarDispatch;
    PData(val).VInteger := VInteger;
    exit;
  end;

  {$IfDef FunSafe}
  SafeDeny('COM object creation');
  {$EndIf}
  val^ := _newOle(exp.asStr, CExps.FindAsVal(exps, 'get', 0, false));
end;

//==============================================================
// f.@toEvent(obj = null [, Source, EventID, DispIDs])
//   DispIDs: 1 or 1,2,3
procedure _toEvent(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  {$IfDef FunSafe}
  SafeDeny('COM event binding');
  {$EndIf}
  val^ := CEvent.Create.Parse(exp, exps, env);
end;

//==============================================================
function CLole.accept(exp: CExp): fun.bool;
begin
  result := isOle(exp.value);
end;

function CLole.call(env: CEnv; exp: CExp; const id: fun.str; exps: CExps; val: PValue; ct: fun.byte = CDoMethod): fun.bool;
var
  calltype, reftype: fun.byte;
  name: fun.str;
  isSub: fun.bool;
  
  procedure dispInvoke;
  var
    cd: TCallDesc;
  
    procedure set2array(s: CSet; v: PValue);
    var
      vs: array of Variant;
      ii, i: fun.int;
    begin
      ii := s.count();
      SetLength(vs, ii);
      for i := 0 to ii -1 do
      begin
        vs[i] := s.item[i].value^;
      end;
      v^ := VarArrayOf(vs);
    end;
  
    procedure setName(const n: fun.str; var p: fun.int);
    var
      i: fun.int;
    begin
      for i := 1 to Length(n) do
      begin
        cd.ArgTypes[p] := fun.byte(n[i]);
        Inc(p);
      end;
      cd.ArgTypes[p] := 0;
      Inc(p);
    end;
  
  var
    ii, i2, i, p: fun.int;
    arg, ret, pcd: LongWord;
    e: CExp;
    v: PValue;
    o: CBase;
    bs: array of Variant;
  begin
    ii := CExps.count(exps);
    i2 := 0;
  
    // Property Set
    if ct = CPropertySet then i2 := 1;
  
    cd.CallType      := calltype;
    cd.ArgCount      := ii + i2;
    cd.NamedArgCount := 0;
  
    // Params
    for i := ii + i2 - 1 downto 0 do
    begin
      e := nil;
      if i = ii then // Property Set
        v := val
      else
      begin
        e := CExp(exps.Item[i]);
        v := e.value;
  
        // Named params
        // Now supported !!!
        if e.name <> '' then cd.NamedArgCount := ii - i;
      end;
      o   := asObj(v);
  
      reftype := $00;
      with CData(v^) do
      begin
        arg := VLongWord;
        if (e <> nil) and (e is CVar) and (VType = varInteger) then
        begin
          reftype := $80; // atByRef
          arg     := LongWord(@VLongWord);
        end;
        if (VType <> varOleStr) and isStr(VType) then
        begin
          arg := LongWord(fun.ptr(StrToOleStr(fun.str(arg))));
          SetLength(bs, Length(bs)+1);
          with CData(bs[Length(bs)-1]) do
          begin
            VType     := VarOleStr;
            VLongWord := arg;
          end;
          cd.ArgTypes[i] := VarOleStr;// or reftype;
        end
        else if (o <> nil) and (o is CSet) and not (o is CObj) then // [], new []
        begin
          set2array(CSet(o), v);
          arg := LongWord(v);
          cd.ArgTypes[i] := $8c;
        end
        else if VType > $ff then // byte array - 8209 ($2011)
        begin
          arg := LongWord(v);
          cd.ArgTypes[i] := $8c;
        end
        else
          cd.ArgTypes[i] := VType or reftype
        ;
        asm
          push arg // Param
        end;
      end;
    end;
  
    // Name
    p := ii + i2;
    setName(name, p);
  
    // Params Named
    for i := ii - cd.NamedArgCount to ii - 1 do
    begin
      e := CExp(exps.Item[i]);
      setName(e.name, p);
    end;
  
    pcd := fun.int(@cd);
    arg := LongWord(exp.value);
    //if isSub then ret := 0 else
    ret := LongWord(val);
    ii  := (ii + i2 + 3) * 4;
    asm
      push pcd // CallDesc
      push arg // Dispatch
      push ret // Result
      call Variants.@DispInvoke
      add  esp, ii
    end;
  end;
  
begin
  calltype := ct;
  name     := id;
  //isSub    := false;
  
  if calltype = CDoMethod then
  begin
    if name[1] = _AT then
    begin
      calltype := CPropertyGet;
      Delete(name, 1, 1);
      if name[1] = _AT then
      begin
        calltype := CPropertySet;
        Delete(name, 1, 1);
      end;
    end;
  
    //if name[Length(name)] = _AT then
    //begin
    //  isSub := true;
    //  Delete(name, Length(name), 1);
    //end;
  end;
  
  dispInvoke();
  result := true;
end;

//==============================================================
destructor CEvent.Destroy;
begin
  if Conn <> 0 then InterfaceDisconnect(Source, EventID, Conn);
  inherited Destroy;
end;

function CEvent.GetIDsOfNames(const IID: TGUID; Names: fun.ptr; NameCount, LocaleID: fun.int; DispIDs: fun.ptr): HResult;
begin
  Result := S_OK;
end;

function CEvent.GetTypeInfo(Index, LocaleID: fun.int; out TypeInfo): HResult;
begin
  Result := E_NOTIMPL;
  //fun.ptr(TypeInfo) := nil;
end;

function CEvent.GetTypeInfoCount(out Count: fun.int): HResult;
begin
  Result := E_NOTIMPL;
  //Count  := 0;
end;

function CEvent.Invoke(DispID: fun.int; const IID: TGUID; LocaleID: fun.int; Flags: Word; var Params; VarResult, ExcepInfo, ArgErr: fun.ptr): HResult;
  
  procedure Proc(const ps: PVariantArgList; ii: fun.int);
  var
    es: CExps;
    e: CExp;
    i: fun.int;
  begin
    if Conn <> 0 then
    begin
      if Pos(','+IntToStr(DispID)+',', DispIDs) <= 0 then exit;
    end;
  
    es := CExps.Create();
    try
      for i := ii -1 downto 0 do
      begin
        e := CExp.new(nil);
        es.Add(e);
        e.assign( CValue( ps[i] ) );
      end;
  
      VarResult := PData(call(self.env, es)).VPointer;
    finally
      del(es);
    end;
  end;
  
begin
  // Flags - CallType
  with TDispParams(Params) do Proc(rgvarg, cArgs);
  Result := S_OK;
end;

function CEvent.Parse(exp: CExp; exps: CExps; theEnv: CEnv): IDispatch;
var
  e: CExp;
begin
  result := self;
  del(self);
  inherited parse(exp, exps, theEnv);
  
  e := CExps.Find(exps, 'Source',  1);
  if e = nil then exit;
  Source := e.value^;
  
  e := CExps.Find(exps, 'EventID', 2);
  if e = nil then exit;
  EventID := _classId(e.asStr);
  
  e := CExps.Find(exps, 'DispIDs', 3);
  if e = nil then exit;
  DispIDs := ',' + e.asStr + ',';
  
  InterfaceConnect(Source, EventID, result, Conn);
end;

function CEvent.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  Result := E_NOINTERFACE;
  //fun.ptr(Obj) := nil;
  if GetInterface(IID, Obj) or IsEqualGUID(EventID, IID) and GetInterface(IDispatch, Obj) then Result := S_OK;
end;


initialization
  CoInitialize(nil);

end.
