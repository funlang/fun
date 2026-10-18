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
unit regex;

interface

uses fun, base, core, host
     , pcre
     ;

type
  CRegex = class(CExp)
  private
    FCode: TPcreCode;
    FCodeOptions: CPcreOptions;
    function g: fun.bool;
    procedure prepare(re: CPcre);
  protected
    options: fun.str;
    pattern: fun.str;
  public
    destructor Destroy; override;
    procedure match(env: CEnv; const s: fun.str; exp: CExp; val: PValue);
    function parse(const r: fun.str): CExp; overload;
    function parse(const p, o: fun.str): CExp; overload;
    procedure replace(env: CEnv; const s: fun.str; exp: CExp; val: PValue);
  end;
  
  CMatch = class(CExp)
  protected
    FreeRE: fun.bool;
    FU: CNode;
    RE: TObject;
  public
    destructor Destroy; override;
    function action(obj: TObject): fun.str;
    function count: fun.int; override;
    function gcount: fun.int;
    procedure groups(val: PValue; e: CExp; idx: fun.int);
    function matched(const substi: fun.str = ''): fun.str;
    function missed: fun.str;
    function next: fun.bool;
    function parse(aRE: TObject; aFU: CNode = nil; aFreeRE: fun.bool = false): CMatch;
    function rest: fun.str;
  end;
  
  CLreg = class(CLib)
  public
    constructor Create;
    function accept(exp: CExp): fun.bool; override;
  end;
  
  CLmat = class(CLib)
  public
    constructor Create;
    function accept(exp: CExp): fun.bool; override;
  end;
  
implementation

uses SysUtils;

function ParseRegex(const r: fun.str; var o: fun.str): fun.str;
var
  i: fun.int;
  c: fun.char;
begin
  c := r[1]; // '/', '%' or '$'
  i := 0;
  if c = '$' then
  begin
    c := r[2];
    i := 1;
  end;
  
  result := Copy(r, 2+i, MaxInt);
  i := Pos(c, result);
  o := Copy(result, i+1, MaxInt);
  Delete(result, i, MaxInt);
end;

function ParseOptions(const o: fun.str): CPcreOptions;
var
  i: fun.int;
begin
  result := [];
  for i := 1 to Length(o) do
  begin
    case o[i] of
      'i': Include(result, preCaseLess);
      'm': Include(result, preMultiLine);
      's': Include(result, preSingleLine);
      'x': Include(result, preExtended);
      'u': Include(result, preUTF8);
    end;
  end;
end;

//==============================================================
procedure _match(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  CRegex(exp.asObj).match(env, CExps.FindAsVal(exps, '', 0, ''), CExps.Find(exps, 'action', 1), val)
end;

procedure _replace(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  CRegex(exp.asObj).replace(env, CExps.FindAsVal(exps, '', 0, ''), CExps.Find(exps, '', 1), val)
end;

//==============================================================
procedure _next(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  val^ := CMatch(exp.asObj).next();
end;

procedure _missed(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  val^ := CMatch(exp.asObj).missed();
end;

procedure _value(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  val^ := CMatch(exp.asObj).matched(CExps.FindAsVal(exps, '', 0, ''));
end;

procedure _rest(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  val^ := CMatch(exp.asObj).rest();
end;

procedure _gcount(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  val^ := CMatch(exp.asObj).gcount();
end;

procedure _groups(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  CMatch(exp.asObj).groups(val, CExps.Find(exps, '', 0), CExps.FindAsVal(exps, '', 1, 0));
end;

//==============================================================
function CRegex.g: fun.bool;
begin
  result := Pos('g', options) > 0;
end;

destructor CRegex.Destroy;
begin
  if FCode <> nil then FCode.Release;
  inherited Destroy;
end;

// Give the per-call CPcre a compiled pattern. A literal regex is evaluated
// many times, so the first call keeps the code here and later calls skip the
// global cache lookup entirely. Options are part of the key because the same
// CRegex is never reused with different options unless parse() is called again.
procedure CRegex.prepare(re: CPcre);
var
  o: CPcreOptions;
begin
  o := ParseOptions(options);
  re.Pattern := pattern;
  re.Options := o;
  if (FCode <> nil) and (FCodeOptions = o) then
  begin
    // Second use of this literal: JIT-compile it once, then every later call
    // gets the machine code through the shared extra block.
    FCode.EnableJit;
    re.UseCode(FCode);
  end
  else
  begin
    if FCode <> nil then
    begin
      FCode.Release;
      FCode := nil;
    end;
    re.Compile;
    FCode := re.Code;
    if FCode <> nil then
    begin
      FCode.AddRef;
      FCodeOptions := o;
    end;
  end;
end;

procedure CRegex.match(env: CEnv; const s: fun.str; exp: CExp; val: PValue);
var
  re: CPcre;
  mt: CMatch;
  se: CSet;
begin
  re := CPcre.Create;
  mt := nil;
  try
    prepare(re);
    re.Subject := s;
    if (exp <> nil) and (exp.asObj <> nil) then // fun call
    begin
      mt := CMatch.new(nil).parse(re, CNode(exp.asObj));
      re.PcreAction := mt.action;
      re.ActionTag  := env;
  
      if g then
        val^ := re.MatchAll
      else
        val^ := re.MatchOne
      ;
    end
    else
    begin
      // todo
      if g then
      begin
        se := CNew.new(nil);
        se.parse(CExps.Create);
        setObj(val, se, VarObjNew); del(se);
        while re.Match do
          se.items.add(CExp.new(nil).parse(re.Matched));
        ;
      end
      else
      begin
        re.Match;
        mt := CMatch.new(nil).parse(re, nil, true);
        // Keep re and mt
        setObj(val, mt, VarObjNew);
        re := nil;
      end;
    end;
  finally
    FreeAndNil(re);
    del(mt);
  end;
end;

function CRegex.parse(const r: fun.str): CExp;
var
  p, o: fun.str;
begin
  p      := ParseRegex(r, o);
  result := parse(p, o);
end;

function CRegex.parse(const p, o: fun.str): CExp;
begin
  if FCode <> nil then
  begin
    FCode.Release;
    FCode := nil;
  end;
  FCodeOptions := [];
  assign(CBase(self));
  result  := self;
  pattern := p;
  options := o;
end;

procedure CRegex.replace(env: CEnv; const s: fun.str; exp: CExp; val: PValue);
var
  re: CPcre;
  mt: CMatch;
begin
  re := CPcre.Create;
  mt := nil;
  try
    prepare(re);
    re.Subject := s;
    if exp.asObj <> nil then // fun call
    begin
      mt := CMatch.new(nil).parse(re, CNode(exp.asObj));
      re.PcreAction := mt.action;
      re.ActionTag  := env;
    end
    else
      re.Replacement := exp.asStr;
    ;
    if g then
      re.ReplaceAll
    else if re.Match then
      re.Replace
    ;
    val^ := re.Subject;
  finally
    FreeAndNil(re);
    del(mt);
  end;
end;

//==============================================================
destructor CMatch.Destroy;
begin
  if FreeRE then FreeAndNil(RE);
  inherited Destroy;
end;

function CMatch.action(obj: TObject): fun.str;
begin
  result := FU.call(CEnv(obj), [self])^;
end;

function CMatch.count: fun.int;
begin
  result := gcount;
end;

function CMatch.gcount: fun.int;
begin
  result := CPcre(RE).GroupCount;
end;

procedure CMatch.groups(val: PValue; e: CExp; idx: fun.int);
var
  I: fun.int;
begin
  with CPcre(RE) do
  begin
    if isNum(e.value) then
    begin
      I := e.asInt; // todo: pos of UTF8
      if idx = 1 then
      begin
        FStart := FStart + I;
        val^   := FStart - 1;
      end
      else if idx = 2 then
      begin
        val^   := Copy(Subject, FStart, I);
        FStart := FStart + I;
      end
      else
        val^ := Groups[I]
      ;
    end
    else if idx = 1 then
      val^ := NamedGroup(e.asStr)
    else
      val^ := Groups[NamedGroup(e.asStr)]
    ;
  end;
end;

function CMatch.matched(const substi: fun.str = ''): fun.str;
var
  p, q: fun.ptr;
begin
  with CPcre(RE) do
  if substi = '' then
    result      := Matched
  else if substi = '*' then
  begin
    SetLength(result, GroupCount * 8);
    p := @result[1];
    q := @Offsets[0];
    System.Move(q^, p^, Length(result));
  end
  else
  begin
    Replacement := substi;
    result      := ComputeReplacement;
  end;
end;

function CMatch.missed: fun.str;
begin
  result := CPcre(RE).SubjectLeft;
end;

function CMatch.next: fun.bool;
begin
  result := CPcre(RE).Match;
end;

function CMatch.parse(aRE: TObject; aFU: CNode = nil; aFreeRE: fun.bool = false): CMatch;
begin
  result := self;
  RE     := aRE;
  FU     := aFU;
  FreeRE := aFreeRE;
end;

function CMatch.rest: fun.str;
begin
  result := CPcre(RE).SubjectRight;
end;

//==============================================================
constructor CLreg.Create;
begin
  inherited Create;
  ids['match']   := CExp.new(nil).parse(Int64(fun.uintptr(@_match)));
  ids['replace'] := CExp.new(nil).parse(Int64(fun.uintptr(@_replace)));
end;

function CLreg.accept(exp: CExp): fun.bool;
begin
  result := exp.asObj is CRegex;
end;

//==============================================================
constructor CLmat.Create;
begin
  inherited Create;
  ids['match']  := CExp.new(nil).parse(Int64(fun.uintptr(@_next)));
  ids['missed'] := CExp.new(nil).parse(Int64(fun.uintptr(@_missed)));
  ids['value']  := CExp.new(nil).parse(Int64(fun.uintptr(@_value)));
  ids['rest']   := CExp.new(nil).parse(Int64(fun.uintptr(@_rest)));
  ids['gcount'] := CExp.new(nil).parse(Int64(fun.uintptr(@_gcount)));
  ids['groups'] := CExp.new(nil).parse(Int64(fun.uintptr(@_groups)));
  ids['@@']     := CExp.new(nil).parse(Int64(fun.uintptr(@_value)));
  ids['@']      := CExp.new(nil).parse(Int64(fun.uintptr(@_groups)));
end;

function CLmat.accept(exp: CExp): fun.bool;
begin
  result := exp.asObj is CMatch;
end;

end.
