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
unit libset;

interface

uses fun, base, core, host;

type
  CLset = class(CLib)
  public
    constructor Create;
    function accept(exp: CExp): fun.bool; override;
  end;
  

implementation

{$IfDef Unicode}{$WARN WIDECHAR_REDUCED OFF}{$EndIf}

uses SysUtils;

procedure _count(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  e: CExp;
  l: CList;
  i: fun.int;
begin
  e := CExps.Find(exps, '', 0);
  if e <> nil then
  begin
    l := CExps(CSet(exp.asObj).items).List;
    if isNum(e.value) then
    begin
      i := calcIndex(e.asInt, l.count);
      l.count := i;
      val^ := i;
      exit;
    end
    else if e.asStr = 'ptr' then
    begin
      // fun.intptr/fun.uintptr are pointer-wide (32-bit on 32-bit targets, 64-bit on 64-bit),
      // so the returned address is not truncated on x86_64/Win64.
      val^ := fun.intptr(l.List);
      exit;
    end;
  end;
  val^ := CSet(exp.asObj).count();
end;

// s.@has(key) -> true when the container has this key, even when its value is
// nil. 'm[key]' cannot tell a missing key from a nil value ('m['b'] = nil' is
// true for an absent key too), and 'key in m' scans the values instead of the
// keys; this tests key presence alone. A numeric key addresses a list slot
// exactly as m[key] does, any other key names a set member.
procedure _has(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  e: CExp;
  s: CExps;
  n, i: fun.int;
begin
  val^ := false;
  e := CExps.Find(exps, '', 0);
  if e = nil then exit;
  s := CSet(exp.asObj).items;
  if isNum(e.value, true) then
  begin
    n := CExps.Count(s);
    i := calcIndex(e.asInt, n);
    val^ := (i >= 0) and (i < n) and (s.Item[i] <> nil);
  end
  else
    val^ := s.ItemById[e.asStr] <> nil;
end;

// s.@each(fun, reverse = false)
procedure _each(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  es: CExps;
  e1, e2, e: CExp;
  ii, i: fun.int;
  f: CNode;
  step: fun.int;
begin
  val^ := exp.value^;

  e  := CExps.Find(exps, '', 0);
  if e = nil then exit;
  f  := CNode(e.asObj);
  if f = nil then exit;

  step := 1;
  if CExps.FindAsVal(exps, 'reverse', 1, false) then step := -1;

  es := CExps.Create;
  e1 := CExp.new(nil); es.add(e1);
  e2 := CExp.new(nil); es.add(e2);

  exp := CSet(exp.asObj);
  ii  := exp.count();
  try
    i := 0;
    if step < 0 then i := ii-1;
    while (step > 0) and (i < ii) or (step < 0) and (i >= 0) do
    begin
      e := exp.item[i];
      if e = nil then
      begin
        e1.assign(NullValue);
        e2.assign(NullValue);
      end
      else
      begin
        e1.assign(e);
        e2.assign(e.name);
      end;
      f.call(env, es);
      Inc(i, step);
    end;
  finally
    del(es);
  end;
end;

procedure _add(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  s: CExps;
  i: fun.int;
  e, e2: CExp;
begin
  val^ := exp.value^;
  s    := CSet(exp.asObj).items;

  for i := 0 to CExps.Count(exps) -1 do
  begin
    e  := exps.Item[i];
    e2 := s.ItemById[e.name];
    if e2 = nil then
    begin
      e2 := CExp.new(nil);
      e2.name := e.name;
      s.add(e2);
    end;
    e2.assign(e);
  end;
end;

procedure _clone(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  setObj(val, CSet(exp.asObj).clone(env), VarObjNew);
end;

//==============================================================
function unesc(const s: fun.str; isGbk: fun.bool = false): fun.str;
const
  abtnvfr = 'abtnvfr';
var
  ret: fun.str;
  i, k, l, n: fun.int;
  c: fun.char;
{$IfNDef Unicode}
  inGbk: fun.bool;
{$EndIf}

  procedure InsertAndInc(CopyOnly: fun.bool = false);
  var
    si, di: fun.ptr;
  begin
    si := @s[k];
    di := @ret[k+n];
    Move(si^, di^, (i-k+1) * sizeof(char));
    k := i+1;
    if not CopyOnly then
    begin
      ret[i+n] := '\';
      Inc(n);
    end;
  end;
begin
  k := 1;
  l := Length(s);
  n := 0;
  SetLength(ret, l * 2);
{$IfNDef Unicode}
  inGbk := false;
{$EndIf}
  for i := 1 to l do
  begin
    c := s[i];
    if Ord(c) in [8..10, 12, 13] then
    begin
      InsertAndInc();
      ret[i+n] := abtnvfr[Ord(c) - 6];
    end
    else if c = '"' then
    begin
      InsertAndInc();
      k := i;
    end
  {$IfNDef Unicode}
    else if isGbk and inGbk then
      inGbk := false
    else if isGbk and (Ord(c) > $80) then
      inGbk := true
  {$EndIf}
    else if c = '\' then
    begin
      if (i+4 < l) and (s[i+1] = 'u') and (s[i+2] in ['0'..'9', 'a'..'f', 'A'..'F']) then else
      begin
        InsertAndInc();
        k := i;
      end;
    end
    else if Ord(c) < 32 then
    begin
      InsertAndInc(true);
      ret[i+n] := '.'; // todo: ignore the control chars
    end;
  end;
  InsertAndInc(true);
  SetLength(ret, l+n);
  result := ret;
end;

function QuoteIt(const s: fun.str; isValue: fun.bool = false; json: fun.bool = false; isGbk: fun.bool = false): fun.str;
var
  i: fun.int;
  c: fun.char;
  f: set of (Quote, DQ, SQ, XQ);
begin
  if Length(s) = 0 then
  begin
    result := '""';
    exit;
  end;

  f := [];
  if json or isValue or (s[1] in ['0'..'9']) then Include(f, Quote);

  for i := 1 to Length(s) do
  begin
    c := s[i];
    case c of
      '$', '_', '@'..'Z', 'a'..'z', '0'..'9':
        ;

      '"':
        Include(f, DQ);

      '''':
        Include(f, SQ);

      '`':
        Include(f, XQ);

      else
        Include(f, Quote);
    end;
  end;

  if f <> [] then
  begin
    if json then
      result := '"' + unesc(s, isGbk) + '"'
    else if not (DQ in f) then
      result := '"'  + s + '"'
    else if not (SQ in f) then
      result := '''' + s + ''''
    else
      result := '`'  + NewStringReplace(s, '`', '``', [rfReplaceAll]) + '`'
    ;
  end
  else
    result := s
  ;
end;

function _asJson(hash: CHash; cs: CSet; lev: fun.int; format: fun.int = 0; json: fun.bool = False; isGbk: fun.bool = false; fd: fun.bool = false; kvd: fun.int = 32): fun.str; overload; forward;
function _asJson(hash: CHash; e: CExp; lev: fun.int; format: fun.int = 0; json: fun.bool = False; isGbk: fun.bool = false): fun.str; overload;
begin
  if e.asObj is CSet then
    result := _asJson(hash, CSet(e.asObj), lev, format, json, isGbk)
  else if e.asObj <> nil then
    result := '"(Object)"'
  else
  begin
    if PData(e.value).VType <= varNull then
      result := 'null'//'""'
    else
      result := e.asStr // todo, 8209 - byte array
    ;
    with PData(e.value)^ do
    begin
      if VType = VarBoolean then
        result := LowerCase(result)
      else if format < 0 then
        exit
      else if VType = VarDate then
      begin
        result := '"' + result + '"';
        if not json then result := '@' + result;
      end
      else if isStr(VType) or (VType = 8209) then // VarArray+VarByte, $2011
        result := QuoteIt(result, true, json, isGbk)
      else if json and (result <> '') and (result[1] = '.') then
        result := '0' + result;
      ;
    end;
  end;
end;

function _asJson(hash: CHash; cs: CSet; lev: fun.int; format: fun.int = 0; json: fun.bool = False; isGbk: fun.bool = false; fd: fun.bool = false; kvd: fun.int = 32): fun.str; overload;

  procedure add(const s: fun.str);
  begin
    result := result + s;
  end;

  procedure addLn();
  begin
    if fd then
      add(#10)
    else
      add({$IfDef Unix}#10{$Else}#13#10{$EndIf})
    ;
  end;

  procedure prefix(l: fun.int);
  begin
    while l > 0 do
    begin
      add(' ');
      Dec(l);
    end;
  end;

  procedure writeJson;
  var
    isObj: fun.bool;
    i, ii: fun.int;
    e: CExp;
    s: fun.str;
    b: fun.char;
  begin
    // Object identity key for cycle detection: use the full pointer, not
    // fun.uint (32-bit), so two live objects cannot collide on x86_64/Win64.
    s := SysUtils.Format('@%x', [fun.uintptr(cs.items)]);
    if hash.ItemById[s] <> nil then
    begin
      result := '"(Object)"'; //0x' + s + ')"';
      exit;
    end;
    hash.ItemById[s] := cs;

    isObj  := cs is CNew2;
    if format >= 0 then
    begin
      b := '[';
      if isObj                                 then b := '{'
      else if json then begin // json array ...
        if (CExps.Count(cs.items) > 0)         and
           (cs.items.Item[0] <> nil)           and
           (CExp(cs.items.Item[0]).name <> '') then b := '{';
      end;
      add(b);
    end;
    if format > lev then addLn();

    ii := CExps.Count(cs.items) -1;
    for i := 0 to ii do
    begin
      e := cs.items.Item[i];

      if format > lev then prefix(lev + 1);
      if (format >= 0) and ((b = '{') or (e <> nil) and (e.name <> '')) then
      begin
        add(QuoteIt(e.name, false, json, isGbk) + ':');
        if format > lev then add(' ');
      end;

      if e <> nil then add(_asJson(hash, e, lev + 1, format, json, isGbk));

      if (format >= 0) and (i < ii) then add(',');
      if format > lev then addLn();
    end;

    if format > lev then prefix(lev);
    if format < 0 then
    else if b = '{' then
      add('}')
    else
      add(']')
    ;
  end;
  
  procedure writeFd;
  {$I libfdw.inc}

begin
  result := '';

  if fd then
    writeFd
  else
    writeJson
  ;
end;

type
  CHash = class(base.CHash)
  protected
    procedure FreeItem(p: fun.ptr); override;
  end;
  
  procedure CHash.FreeItem(p: fun.ptr);
  begin
    // No Action
  end;

// s.@toJson(format = 0, json = false, isGbk = false, fd = false, kvd = 32)
procedure _toJson(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  hash: CHash;
begin
  hash := CHash.Create;
  val^ := _asJson(hash, CSet(exp.asObj), 0, CExps.FindAsVal(exps, 'format', 0, 0), CExps.FindAsVal(exps, 'json', 1, False), CExps.FindAsVal(exps, 'isGbk', 2, False), CExps.FindAsVal(exps, 'fd', 3, False), CExps.FindAsVal(exps, 'kvd', 4, 32));
  hash.Free;
end;

//==============================================================
constructor CLset.Create;
begin
  inherited Create;
  ids['@count']  := CExp.new(nil).parse(Int64(fun.uintptr(@_count)));
  ids['@length'] := CExp.new(nil).parse(Int64(fun.uintptr(@_count)));
  ids['@has']    := CExp.new(nil).parse(Int64(fun.uintptr(@_has)));
  ids['@each']   := CExp.new(nil).parse(Int64(fun.uintptr(@_each)));
  ids['@add']    := CExp.new(nil).parse(Int64(fun.uintptr(@_add)));
  ids['@clone']  := CExp.new(nil).parse(Int64(fun.uintptr(@_clone)));
  ids['@toJson'] := CExp.new(nil).parse(Int64(fun.uintptr(@_toJson)));
end;

function CLset.accept(exp: CExp): fun.bool;
begin
  result := exp.asObj is CSet;
end;


end.
