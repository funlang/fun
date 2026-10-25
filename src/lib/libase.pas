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
unit libase;

// LinuxFFI (Linux), DarwinFFI (macOS) and WinFFI (win64, via ffi.dll) all
// mean "libffi-backed getapi". Kept in sync with host.pas, which is
// compiled first and normally sets the symbol.
{$IfNDef UnixFFI}
  {$IfDef LinuxFFI}{$Define UnixFFI}{$EndIf}
  {$IfDef DarwinFFI}{$Define UnixFFI}{$EndIf}
  {$IfDef WinFFI}{$Define UnixFFI}{$EndIf}
{$EndIf}

// FunPack (full: create and run bundles) implies FunPackUser (run only).
{$IfDef FunPack}
  {$Define FunPackUser}
{$EndIf}

interface

uses fun, base, core, host;

type
  CLbase = class(CLib)
  public
    constructor Create;
    function accept(exp: CExp): fun.bool; override;
  end;

{$IfDef FunPackUser}
// Bundled-app mode (a single-file exe with a zip trailer): the launcher sets
// these so the script sees 1.arg() = the bundled entry and 2.arg() = its first
// real argument, exactly like `funcmd app.fun ...`.
var
  ArgScript: fun.str = '';
  ArgShift : fun.int = 0;
{$EndIf}

implementation

{$IfDef Unicode}{$WARN WIDECHAR_REDUCED OFF}{$EndIf}

uses SysUtils, Variants,
     {$IfNDef UNIX}Windows,{$Else}
       {$IfDef Linux}Linux,{$EndIf}
       unixtype, baseunix, termio,
     {$EndIf}
     io, parse
     {$IfDef WinCOM}  , winole  {$EndIf}
     {$IfDef WinAPI}  , winapi  {$EndIf}
     {$IfDef UnixFFI}, lffi    {$EndIf}
     {$IfDef Regex}   , regex   {$EndIf}
     ;
type PValue = base.PValue;

// macOS has clock_gettime(2) since 10.12, but FPC exposes it only through the
// Linux unit. Declare it here so the monotonic-clock probes below work on
// Darwin too (CLOCK_MONOTONIC == 6 there).
{$IfDef Darwin}
const
  CLOCK_MONOTONIC = 6;
function clock_gettime(clk_id: LongInt; tp: Pointer): LongInt; cdecl; external name 'clock_gettime';
{$EndIf}

//==============================================================
// 'I am'.@uthor()
// '....'.@uthor()
procedure _author(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  david: fun.str;
  i: fun.int;
begin
  if exp.asStr <> 'I am' then
  begin
    val^ := 'Wisdom ZHANG';
    exit;
  end;

  david := 'Ykbmd,Tfjglmd'; //'Zhang/Weidong';
  for i := 1 to Length(david) do
    david[i] := fun.char(fun.byte(david[i]) xor 3);
  ;
  val^  := david;
end;

//==============================================================
// 'host'.arg()   -- host environment facts, as a small FD document
//
// Zero-cost by design: every fact below is baked in at compile time from
// preprocessor/compiler switches, so the call performs no runtime OS query
// (no uname / GetVersionEx / cpuid). It just returns a static FD string.
//
// Schema (flat FD, one key per line, parseable by '.getJson(fd:true)'):
//   fun       -> interpreter version, e.g. "9.0"
//   os        -> operating system,  e.g. "windows" | "linux" | "wince"
//   cpu       -> cpu model/arch,    e.g. "i386" | "x86_64" | "arm" | "arch64"
//   compiler  -> compiler + version,e.g. "fpc 3.2.2" | "delphi"
//   bits      -> cpu word size,     e.g. 64 | 32
//   chars     -> char width in bytes (SizeOf(Char)), e.g. 1 | 2
//   version   -> numeric build stamp, YYYYMMDD; identical to what N.time()
//                returns for any N in 2010..2099, so a script can probe either
//                way (both read the funVersion constant in core/fun.pas).
//
// Because 'fun' is a Fun keyword, .fun code reads it back as
//   var h = 'host'.arg().getJson(fd:true);   // h.os, h.cpu, h.compiler, h.bits, h.chars, h.version
//   var v = h['fun'];                        // version string (bracket access)
// or simply parses the text with a regex.
function _hostOs: fun.str;
begin
  {$IfDef WinCE}
  result := 'wince';
  {$Else}
  {$IfDef Darwin}
  result := 'macos';
  {$Else}
  {$IfDef Linux}
  result := 'linux';
  {$Else}
  {$IfDef MSWINDOWS}
  result := 'windows';
  {$Else}
  {$IfDef Windows}
  result := 'windows';
  {$Else}
  {$IfDef WIN32}
  result := 'windows';
  {$Else}
  {$IfDef WIN64}
  result := 'windows';
  {$Else}
  {$IfDef Win64}
  result := 'windows';
  {$Else}
  result := 'unknown';
  {$EndIf}{$EndIf}{$EndIf}{$EndIf}{$EndIf}{$EndIf}{$EndIf}{$EndIf}
end;

function _hostCompiler: fun.str;
begin
  {$IfDef FPC}
  result := 'fpc ' + {$I %FPCVERSION%};
  {$Else}
  result := 'delphi';
  {$EndIf}
end;

function _hostCpu: fun.str;
begin
  {$IfDef CPUX86_64}
  result := 'x86_64';
  {$Else}
  {$IfDef CPUAMD64}
  result := 'x86_64';
  {$Else}
  {$IfDef CPUAARCH64}
  result := 'arch64';
  {$Else}
  {$IfDef CPUARM}
  result := 'arm';
  {$Else}
  {$IfDef CPU386}
  result := 'i386';
  {$Else}
  {$IfDef CPU86}
  result := 'i386';
  {$Else}
  {$IfDef CPU64}
  result := 'cpu64';
  {$Else}
  result := 'cpu';
  {$EndIf}{$EndIf}{$EndIf}{$EndIf}{$EndIf}{$EndIf}{$EndIf}
end;

function _hostInfo: fun.str;
begin
  // FD values stay unquoted where unambiguous; only the numeric-looking
  // version string ("9.0") keeps quotes so it is read back as a string, not 9.0.
  result :=
      'fun '      + '"' + funRelease + '"' + #10 +
      'os '       + _hostOs       + #10 +
      'cpu '      + _hostCpu      + #10 +
      'compiler ' + _hostCompiler + #10 +
      'bits '     + IntToStr(SizeOf(fun.ptr) * 8) + #10 +
      'chars '    + IntToStr(SizeOf(fun.char)) + #10 +
      'version '  + IntToStr(funVersion);
end;

//==============================================================
// 0.arg()
// 1.arg()
// 'host'.arg()
procedure _arg(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  i: fun.int;
begin
  // 'host'.arg() returns compile-time host facts (FD document).
  if isStr(exp.value) and (exp.asStr = 'host') then
  begin
    val^ := _hostInfo();
    exit;
  end;
  i := exp.asInt;
{$IfDef FunPackUser}
  if i = 0 then
    val^ := ParamStr(0)
  else if (i = 1) and (ArgScript <> '') then
    val^ := ArgScript
  else
    val^ := ParamStr(i + ArgShift);
{$Else}
  val^ := ParamStr(i);
{$EndIf}
end;

//==============================================================
// 'defaultCodePage'.set(936)
procedure _set(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  if exp.asStr = 'defaultCodePage' then
  begin
    defaultCodePage := CExps.FindAsVal(exps, '', 0, 0);
  end;
end;

//==============================================================
procedure _exp(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  val^ := System.Exp(exp.value^);
end;

procedure _log(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  val^ := System.Ln(exp.value^);
end;

procedure _sin(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  val^ := System.Sin(exp.value^);
end;

procedure _cos(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  val^ := System.Cos(exp.value^);
end;

procedure _atan(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  val^ := System.ArcTan(exp.value^);
end;

// 1.random(), 0.random(), a.random(), -1.random(seed = 0)
procedure _random(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  i, j: fun.int;
begin
  i := exp.asInt;
  if i > 1 then
    val^ := System.Random(i)
  else if i = -1 then
  begin
    j := CExps.FindAsVal(exps, 'seed', 0, 0);
    if j = 0 then
      val^ := RandSeed
    else
      RandSeed := j
    ;
  end
  else
  begin
    if i <= 0 then System.Randomize;
    val^ := System.Random;
  end;
end;

//==============================================================
procedure _length(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  val^ := Length(exp.asStr);
end;

procedure _lower(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  val^ := LowerCase(exp.asStr);
end;

procedure _upper(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  val^ := UpperCase(exp.asStr);
end;

// a.subpos(sub)
procedure _subpos(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  i: fun.int;
  s: fun.str;
begin
  i := -1;
  if CExps.Count(exps) > 0 then
  begin
    s := CExp(exps.Item[0]).asStr;
    i := Pos(s, exp.asStr) - 1;
  end;
  val^ := i;
end;

// a.substr(pos = 0, len = MAX)
procedure _substr(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  i, j, ii: fun.int;
  s: fun.str;
begin
  i := CExps.FindAsVal(exps, 'pos', 0, 0);
  j := CExps.FindAsVal(exps, 'len', 1, MaxInt);
  s := exp.asStr;
  ii := Length(s);
  i := calcIndex(i, ii);
  j := calcIndex(j, ii);
  val^ := Copy(s, i+1, j);
end;

// a.x(n), if n = -1 reverse it, -2 sort it
procedure _x(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  i, ii, l: fun.int;
  s, ss: fun.str;
  p: PChar;

  procedure sort();
  var
    nums: array of fun.int;
    i, j: fun.int;
  begin
    // count by low byte: fun.char is 2 bytes on Unicode targets, and Ord()
    // would index past this 256-entry table.
    SetLength(nums, 256);
    for i := 1 to l do
    begin
      Inc(nums[fun.byte(s[i])]);
    end;
    SetLength(ss, l);
    ii := 1;
    for i := 0 to 255 do
    begin
      for j := 1 to nums[i] do
      begin
        ss[ii] := fun.char(i);
        Inc(ii);
      end;
    end;
    SetLength(nums, 0);
  end;
begin
  ii := CExps.FindAsVal(exps, '', 0, 0);
  s  := exp.asStr;
  l  := Length(s);
  if ii >= 0 then
  begin
    if Int64(l) * Int64(ii) > Int64(MaxInt) then
      raise EBase.Create('x(n): result too large');
    SetLength(ss, l * ii);
    if l * ii > 0 then
    begin
      p := fun.ptr(ss);
      for i := 0 to ii-1 do
      begin
        Move(fun.ptr(s)^, p^, l*SizeOf(Char));
        Inc(p, l);
      end;
    end;
  end
  else if ii = -1 then
  begin
    SetLength(ss, l);
    for i := 0 to l-1 do ss[i+1] := s[l-i];
  end
  else if ii = -2 then
  begin
    sort();
  end;
  val^ := ss;
end;

  // \b \t \n \f \r
  // \" \' \` \/ \\
  // \xHH
  // \uHHHH
  function esc(const s: fun.str): fun.str;
  var
    i, j, p, ii: fun.int;
    c: fun.char;
    cp: fun.int;
    lo: fun.int;
  begin
    ii := Length(s);
    SetLength(result, ii);
    i  := 1;
    j  := 1;
    while i <= ii do
    begin
      c := s[i];
      if (c = '\') and (i < ii) then
      begin
        Inc(i);
        c := s[i];
        p := Pos(c, 'btnvfr');
        if (p > 0) and (p <> 4) then
          result[j] := fun.char(8 + p - 1) // #8..#13
        else if c in ['"', '''', '`', '/', '\'] then
          result[j] := c
        else if (c = 'x') and (i+1 < ii) then
        begin
          // StrToInt accepts x-prefix hex on both FPC and Delphi — verified
          result[j] := fun.char(StrToInt(Copy(s, i, 3)));
          Inc(i, 2);
        end
      {$IfDef Unicode}
        else if (c = 'u') and (i+3 < ii) then
        begin
          result[j] := fun.char(StrToInt('x' + Copy(s, i+1, 4)));
          Inc(i, 4);
        end
      {$Else}
        // Non-Unicode build (FPC/Linux): strings are UTF-8, so decode
        // \uHHHH into its UTF-8 bytes. Surrogate pairs are combined.
        else if (c = 'u') and (i+3 < ii) then
        begin
          cp := StrToInt('x' + Copy(s, i+1, 4));
          Inc(i, 4);
          if (cp >= $D800) and (cp <= $DBFF) and (i+5 < ii)
             and (s[i+1] = '\') and (s[i+2] = 'u') then
          begin
            lo := StrToInt('x' + Copy(s, i+3, 4));
            if (lo >= $DC00) and (lo <= $DFFF) then
            begin
              cp := $10000 + ((cp - $D800) shl 10) + (lo - $DC00);
              Inc(i, 6);
            end
          end;
          if cp < $80 then
            result[j] := fun.char(cp)
          else if cp < $800 then
          begin
            result[j] := fun.char($C0 or (cp shr 6));
            Inc(j);
            result[j] := fun.char($80 or (cp and $3F));
          end
          else if cp < $10000 then
          begin
            result[j] := fun.char($E0 or (cp shr 12));
            Inc(j);
            result[j] := fun.char($80 or ((cp shr 6) and $3F));
            Inc(j);
            result[j] := fun.char($80 or (cp and $3F));
          end
          else
          begin
            result[j] := fun.char($F0 or (cp shr 18));
            Inc(j);
            result[j] := fun.char($80 or ((cp shr 12) and $3F));
            Inc(j);
            result[j] := fun.char($80 or ((cp shr 6) and $3F));
            Inc(j);
            result[j] := fun.char($80 or (cp and $3F));
          end
        end
      {$EndIf}
        else
        begin
          result[j] := '\';
          Inc(j);
          result[j] := c;
        end;
      end
      else
        result[j] := c
      ;
      Inc(i);
      Inc(j);
    end;
    SetLength(result, j-1);
  end;

// \[btnfr"'`/\] \xHH \uHHHH
procedure _escape(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  val^ := esc(exp.asStr);
end;

// String:
//  %s
// Number:
//  ###...
// DateTime:
//  yyyy-mm-dd hh:nn:ss:zzz
procedure _format(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  ii, i: fun.int;
  vs: array of TVarRec;
  {$IfDef FPC}
  strs: array of fun.str;
  {$EndIf}
begin
  with PData(exp.value)^ do
  case VType of
    VarDate: val^ := FormatDateTime(CExps.FindAsVal(exps, '', 0, ''), VDate);

    else if VType in [varSmallint..varCurrency, varShortInt..varInt64] then
      val^ := FormatFloat(CExps.FindAsVal(exps, '', 0, ''), exp.value^)
    else
    begin
      ii := CExps.Count(exps);
      SetLength(vs, ii);
      {$IfDef FPC}
      // Keep the argument strings alive (and refcounted) while Format runs.
      // Storing fun.ptr(asStr) of an inline temporary leaves a dangling
      // pointer because the temporary is released immediately.
      SetLength(strs, ii);
      {$EndIf}
      for i := 0 to ii -1 do
      begin
      {$IfDef FPC}
        {$IfDef Unicode}
        strs[i]       := CExp(exps.Item[i]).asStr;
        vs[i].VWideString := fun.ptr(strs[i]);
        vs[i].VType       := vtWideString;
        {$Else}
        strs[i]       := CExp(exps.Item[i]).asStr;
        vs[i].VAnsiString := fun.ptr(strs[i]);
        vs[i].VType       := vtAnsiString;
        {$EndIf}
      {$Else}
        vs[i].VVariant := fun.ptr(CExp(exps.Item[i]).value);
        vs[i].VType    := vtVariant;
      {$EndIf}
      end;
      val^ := Format(exp.asStr, vs);
    end;
  end;
end;

// $id
// $@@ - last error
procedure _eval(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  s, v: fun.str;
  i, j, ii, siz: fun.int;
  c: fun.char;
  e: CExp;
const
  k4 = 4096;
label
  rep;
begin
  s   := exp.asStr;
  ii  := Length(s);
  siz := ((ii div k4) + 1) * k4;
  SetLength(s, siz);
  i  := 1;
  while i <= ii do
  begin
    c := s[i];
    Inc(i);
    if c = '$' then
    begin
      for j := i to ii+1 do
      begin
        if (j > ii) or (not (s[j] in ['_', '@'..'Z', 'a'..'z', '0'..'9'])) then
        begin
          v := Copy(s, i, j-i);
          e := exp.UID(v);
          if e <> nil then
          begin
            v := e.asStr;
      rep:  Delete(s, i-1, j-i+1);
            Inc(ii, Length(v) - (j-i+1));
            if ii > siz then
            begin
              siz := ((ii div k4) + 1) * k4;
              SetLength(s, siz);
            end;
            Insert(v, s, i-1);
            Inc(i,  Length(v) - 1);
          end
          else if v = '@@' then
          begin
            v := env.lastErrorFun();
            goto rep;
          end;
          break;
        end;
      end;
    end;
  end;
  SetLength(s, ii);
  val^ := s;
end;

//==============================================================
// 0.time(), a.time(), qpf/qpc: -1/-2.time(), file/dir.time(params, set)
procedure _time(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  i: fun.int;
  e: CExp;
  t: fun.time;
  i64: fun.int64;
  {$IfDef UNIX}
  ts: timespec;
  {$EndIf}
begin
  if isNum(exp.value) then
  begin
    i := exp.asInt;
    if i = 0 then
      val^ := Time
    else if (i >= 2010) and (i < 2100) then
      val^ := funVersion // from core/fun.pas: one source for both probes
    else if i < 0 then
    begin
    {$IfNDef UNIX}
      if i = -1 then QueryPerformanceFrequency(i64)
                else QueryPerformanceCounter  (i64);
    {$Else}
      if clock_gettime(CLOCK_MONOTONIC, @ts) = 0 then
      begin
        // qpf (-1): ticks per second; qpc (-2): current monotonic counter.
        // CLOCK_MONOTONIC resolution is 1 ns, so count = ns and freq = 1e9/s.
        if i = -1 then i64 := 1000000000
                  else i64 := int64(ts.tv_sec) * 1000000000 + ts.tv_nsec;
      end
      else i64 := 0;
    {$EndIf}
      val^ := i64;
    end
    else
      val^ := Now;
    ;
  end
  else begin
    {$IfDef FunSafe}
    SafeDeny('file time');
    {$EndIf}
    e := CExps.Find(exps, 'set', 1);
    if e <> nil then
      t := e.value^
    else
      t := 0
    ;

    val^ := CIO.Time(exp.asStr, CExps.FindAsVal(exps, '', 0, 0), t)
  end;
end;

procedure _size(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  {$IfDef FunSafe}
  SafeDeny('file size');
  {$EndIf}
  val^ := CIO.Time(exp.asStr, 8);
  PData(val).VType := VarLongWord;
end;

//==============================================================
// 0-MD5, 1-SHA1
procedure _hash(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  {$IfDef FunSafe}
  SafeDeny('file hash');
  {$EndIf}
  val^ := CIO.Load(exp.asStr, 0, CExps.FindAsVal(exps, '', 0, 0));
end;

// s.load(cp = 0)
procedure _load(env: CEnv; exp: CExp; exps: CExps; val: PValue);
{$IfNDef Unicode}
begin
  {$IfDef FunSafe}
  SafeDeny('file read');
  {$EndIf}
  val^ := NullValue;
  val^ := CIO.Load(exp.asStr, CExps.FindAsVal(exps, 'cp', 0, 0));
{$Else}
var
  e : CExp;
  cp: fun.word;
begin
  {$IfDef FunSafe}
  SafeDeny('file read');
  {$EndIf}
  cp := 0;
  e  := CExps.Find(exps, 'cp', 0);
  if e <> nil then cp := fun.word(e.asInt);
  val^ := NullValue;
  val^ := CIO.Load(exp.asStr, cp);
  if (e <> nil) and (e is CVar) then e.value^ := CP_Last;
{$EndIf}
end;

// f.save(str, cp = 0, append = false)
// cp 10056 - utf8 without bom
procedure _save(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  s: fun.str;
  e: CExp;
begin
  {$IfDef FunSafe}
  SafeDeny('file write');
  {$EndIf}
  s := CExps.FindAsVal(exps, '', 0, '');
  CIO.Save(exp.asStr, s, CExps.FindAsVal(exps, 'cp', 1, 0), CExps.FindAsVal(exps, 'append', 2, false));
end;

//==============================================================
// Console input, the read-side sibling of '?.':
//
//   'line'.input([prompt])       read one line (line ending stripped)
//   'char'.input([prompt])       read one keypress (a single key on a terminal)
//   'all'.input([prompt])        read everything up to end of input
//
// The receiver string selects the mode; an optional argument (positional, or
// named 'prompt') is written through env.echo first, so it obeys the runner's
// log/GUI setting.
//
// Linux reads standard input byte by byte, so all three modes work and a
// UTF-8 terminal is passed through as is; 'char' flips the terminal to raw
// mode for the single keypress and restores it at once.
//
// Windows keeps it simple and only reads lines, through the RTL ReadLn: the
// text comes back in the same encoding the build uses for strings (ANSI, or
// Unicode on Delphi 2009), so a multi-byte character is never split into
// bytes. 'char' and 'all' are treated as 'line' there.
//
// End of input is reported as nil for 'line' and 'char' ('all' just returns
// whatever was left, '' when nothing). Fun treats '' and nil as equal, though,
// so a blank line is not distinguishable from EOF by the return value alone:
// pass a variable as the second argument (or as 'ok:') and it is set true
// when a line/char/key was read and false at end of input:
//   var ok; var line = 'line'.input(ok: ok);
//   while ok loop ?. line; line = 'line'.input(ok: ok); end do;
//

// One byte from standard input. raw = true asks the terminal for a single
// keypress (no echo, no Enter). Returns false at end of input.
{$IfDef UNIX}
function _inputCh(var c: fun.str; raw: fun.bool): fun.bool;
var
  t0, t1: termios;
  b: fun.byte;
begin
  result := false;
  if raw and (tcgetattr(0, t0) = 0) then
  begin
    t1 := t0;
    t1.c_lflag := t1.c_lflag and not (ICANON or ECHO);
    t1.c_cc[VMIN]  := 1;
    t1.c_cc[VTIME] := 0;
    tcsetattr(0, TCSANOW, t1);
    result := fpRead(0, b, 1) = 1;
    tcsetattr(0, TCSANOW, t0);
  end
  else
    result := fpRead(0, b, 1) = 1;
  if result then c := fun.char(b);
end;
{$EndIf}

procedure _input(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  prompt, s: fun.str;
  has: fun.bool;
  e: CExp;
{$IfDef UNIX}
  mode, c: fun.str;
{$EndIf}
begin
  prompt := CExps.FindAsVal(exps, 'prompt', 0, '');
  val^   := NullValue;

  if prompt <> '' then env.echo(prompt);

  has := false;
  s   := '';

{$IfDef UNIX}
  mode := LowerCase(exp.asStr);
  if mode = 'all' then
  begin
    while _inputCh(c, false) do
    begin
      has := true;
      s := s + c;
    end;
    val^ := s;
  end
  else if mode = 'char' then
  begin
    has := _inputCh(c, true);
    if has then val^ := c;
  end
  else
  begin
    // 'line' (default)
    while _inputCh(c, false) do
    begin
      has := true;
      if c = #10 then break;        // LF ends the line
      if c <> #13 then s := s + c; // drop CR (CRLF input)
    end;
    if has then val^ := s;
  end;
{$Else}
{$IfDef WinCE}
  // WinCE has no console: the RTL's ReadLn(Input, ...) does not even compile
  // there once the Windows unit is in scope. 'input' is unsupported on WinCE
  // and simply yields no value; a CE build is a server/embedding target.
  has := false;
{$Else}
  // Windows: read one line through the RTL, so the text comes back in
  // the build's string encoding and is never split into bytes.
  {$I-}
  ReadLn(Input, s);
  {$I+}
  has := IOResult = 0;
{$EndIf}
  if has then val^ := s;
{$EndIf}

  // 'ok' out-parameter: a variable receives whether anything was read.
  e := CExps.Find(exps, 'ok', 1);
  if (e <> nil) and (e is CLeft) then e.assign(has);
end;

// f.find(sub = false, size = false, rel = false)
// f -> file default
// f -> directory if endswith '\'
// Callback for CIO.Find: append each hit to the CNew collection passed as tag.
// Kept as a module-level (non-nested) procedure: a nested routine has a hidden
// frame pointer and cannot be called through CIO.Find's plain CFindEach proc
// pointer on FPC (it would misalign its args and crash).
procedure _find_collect(const f: fun.str; p: fun.ptr; size: fun.int = -1);
var
  fs: CNew;
  e: CExp;
begin
  fs := CNew(p);
  e := CExp.new(nil);
  if size >= 0 then
  begin
    e.name := f;
    e.parse(size);
  end
  else e.parse(f);
  fs.items.add(e);
end;

procedure _find(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  fs: CNew;
begin
  {$IfDef FunSafe}
  SafeDeny('file search');
  {$EndIf}
  fs := CNew(core.CNew.new(nil).parse(CExps.Create()));
  setObj(val, fs, VarObjNew); del(fs);
  CIO.Find(exp.asStr, CExps.FindAsVal(exps, 'sub', 0, false), CExps.FindAsVal(exps, 'size', 1, false), CExps.FindAsVal(exps, 'rel', 2, false), @_find_collect, fs);
end;

// f.copy(f2, f3, ...)
procedure _copy(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  s: fun.str;
  i: fun.int;
begin
  {$IfDef FunSafe}
  SafeDeny('file copy');
  {$EndIf}
  s := exp.asStr;
  for i := 0 to CExps.Count(exps) -1 do
    CIO.Copy(s, CExp(exps.Item[i]).asStr)
  ;
end;

// f.move(f2), delete f if f2 = null
// s.move(intDest)
// i.move(intDest, intLen) ???
procedure _move(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  e: CExp;
  s: string;
  p, q: fun.ptr;
  i: fun.int;
begin
  {$IfDef FunSafe}
  // Both branches are unsafe: a numeric destination is arbitrary memory, a
  // string destination renames or deletes a file.
  SafeDeny('move');
  {$EndIf}
  s := exp.asStr;
  e := CExps.Find(exps, 'dest', 0);
  if (e <> nil) and isNum(e.value) then
  begin
    p := asPtr(e.value);
    q := @s[1];
    i := CExps.FindAsVal(exps, 'len', 1, 0);
    if i = 0 then i := Length(s);
    if isNum(PData(exp.value)^.VType) then q := asPtr(exp.value);
    Move(q^, p^, i * sizeof(char));
  end else
    CIO.Move(s, CExps.FindAsVal(exps, '', 0, ''))
  ;
end;

// s.movs(dest, len, pos, pod)
procedure _movs(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  ed: CExp;
  s, d: fun.str;
  pos, pod, len, ls, ld: fun.int;
  ps, pd: fun.ptr;
begin
  s  := exp.asStr;
  if not isStr(exp.value) or (s = '') then exit;
  ed := CExps.Find(exps, 'dest', 0);
  if ed = nil then exit;
  {$IfDef FunSafe}
  if isNum(ed.value) then SafeDeny('movs to a numeric address');
  {$EndIf}
  d  := fun.str(rawPtr(ed.value));
  if not isStr(ed.value) or (d = '') then exit;

  ls  := Length(s);
  ld  := Length(d);
  len := calcIndex(CExps.FindAsVal(exps, 'len', 1, 0), ls);
  pos := calcIndex(CExps.FindAsVal(exps, 'pos', 2, 0), ls);
  pod := calcIndex(CExps.FindAsVal(exps, 'pod', 3, 0), ld);
  if len = 0 then len := ls - pos;

  // 64-bit sums so a huge len cannot wrap past the checks and hand Move a
  // negative (i.e. enormous) count or an out-of-range source pointer.
  if (pos < 0) or (len < 0) or (pod < 0)
     or (Int64(pos) + Int64(len) > Int64(ls))
     or (Int64(pod) + Int64(len) > Int64(ld)) then
    raise EBase.Create('out of bounds');

  ps := @s[1 + pos];
  pd := fun.ptr(fun.uintptr(rawPtr(ed.value)) + fun.uintptr(pod));
  Move(ps^, pd^, len * sizeOf(char));
  val^ := len;
end;

//==============================================================
// index: 0, -2: UnicodeString
procedure _toStr(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  i: fun.int;
  s: fun.str;
  v: PVarArray;
  p: fun.ptr;
  {$IfDef Unicode}
  a: AnsiString;
  j: fun.int;
  {$Else}
  o: WideString;
  {$EndIf}
begin
  i := CExps.FindAsVal(exps, 'index', 0, 0);
  with PData(exp.value)^ do
    if VType = VarArray+VarVariant then
    begin
      v := PData(exp.value).VArray;
      if (i < 0) or (i >= v.Bounds[0].ElementCount) then
        val^ := NullValue      // out-of-range read, instead of a raw read
      else
        val^ := exp.value^[i]  // Array of Variant
      ;
    end
    else if VType = VarArray+VarByte then
    begin
      v := PData(exp.value).VArray;
      i := v.Bounds[0].ElementCount;
      SetLength(s, i);
    {$IfDef Unicode}
      SetLength(a, i);
      p := @a[1];
      System.Move(v.Data^, p^, i);
      for j := 1 to i do s[j] := fun.char(a[j]);
    {$Else}
      p := @s[1];
      System.Move(v.Data^, p^, i);
    {$EndIf}
      val^ := s;
    end
    {$IfNDef Unicode}
    else if i = -2 then
    begin
      s := exp.asStr;
      SetLength(o, Length(s));
      for i := 1 to Length(s) do o[i] := WideChar(s[i]);
      val^ := o;
    end
    {$EndIf}
    else
      val^ := exp.asStr
    ;
end;

// ptr:  1-intPtr, 2-floatPtr, 3-doublePtr,
// ptr: -1:ptr
procedure _toNum(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  p: fun.int;
  s: fun.str;
  i: ^fun.uint;
  f: ^Single;
  d: ^fun.real;
begin
  //val^ := exp.value^ * 1;
  p := CExps.FindAsVal(exps, 'ptr', 0, 0);
  if p = 0 then
    val^ := CParser.StrToNum(exp.value^)
  else
  begin
    s := exp.asStr();
    if p = -1 then
      val^ := fun.intptr(rawPtr(exp.value))
    else if p = 1 then
    begin
      // Reading a fixed-width scalar out of the buffer requires that many
      // bytes; a shorter string would read past it. Yield 0 if too short.
      if Length(s) < SizeOf(fun.uint) then val^ := 0
      else begin i := @s[1]; val^ := i^; end;
    end
    else if p = 2 then
    begin
      if Length(s) < SizeOf(Single) then val^ := 0
      else begin f := @s[1]; val^ := f^; end;
    end
    else if p = 3 then
    begin
      if Length(s) < SizeOf(fun.real) then val^ := 0
      else begin d := @s[1]; val^ := d^; end;
    end;
  end;
end;

procedure _toTime(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  // todo
  val^ := ToFunTime(exp.asStr);
end;

// s.toByte(pos = 0)
procedure _toByte(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  s: fun.str;
  c: fun.char;
  i: fun.int;
begin
  s := exp.asStr;
  i := CExps.FindAsVal(exps, 'pos', 0, 0);
  // An out-of-range read is a caller bug: yield 0 (as for an empty string)
  // instead of reading past the string buffer.
  if (s = '') or (i < 0) or (i >= Length(s)) then
    c := #0
  else
    c := s[1 + i]
  ;
  val^ := fun.int(c);
end;

// s.fromByte(pos, byte)
procedure _fromByte(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  i, j: fun.int;
  s: fun.str;
  p: PByte;
begin
  {$IfDef FunSafe}
  SafeDeny('fromByte raw write');
  {$EndIf}
  i := CExps.FindAsVal(exps, 'pos',  0, 0);
  j := CExps.FindAsVal(exps, 'byte', 1, 0);
  s := exp.asStr;
  // A raw write past the buffer corrupts the heap; past the start corrupts the
  // string header. Both are rejected.
  if (i < 0) or (i >= Length(s)) then
    raise EBase.Create('fromByte index out of range: ' + IntToStr(i));
  p := fun.ptr(s);
  Inc(p, i);
  p^ := j;
end;

procedure _toChar(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  s: fun.str;
begin
  s    := #0;
  s[1] := fun.char(fun.uint(exp.value^) mod 65536);
  val^ := s;
end;

//==============================================================
// Basic-value type ids and strict comparison.
//
// Delphi's raw VType is not portable at the script level: FPC/Linux strings are
// varString (256) while Delphi Unicode uses varUString (258), and the object tag
// differs too ($201 vs 2010). So a.type() reports a normalized id whose core
// numbers match COM VARENUM (VT_*), the table behind Delphi's VType and ADO's
// DataTypeEnum. Integer widths collapse into 3 (VT_I4), floats into 5 (VT_R8),
// every string form into 8 (VT_BSTR). 100+ is reserved for Fun-only object
// kinds; those are values of the object libraries, so they are out of scope
// here (CLbase only sees non-object values).
const
  tyEmpty =  0; // nil                      VT_EMPTY
  tyInt   =  3; // int (all integer widths) VT_I4
  tyReal  =  5; // real (single/double)     VT_R8
  tyCurr  =  6; // currency (COM/ADO)       VT_CURRENCY
  tyTime  =  7; // time/date                VT_DATE
  tyStr   =  8; // str (all string forms)   VT_BSTR
  tyBool  = 11; // bool                     VT_BOOL
  tyOther = -1; // not a basic value

function funType(vt: TVarType): fun.int;
begin
  if vt <= varNull then
    result := tyEmpty
  else if vt = varBoolean then
    result := tyBool
  else if isStr(vt) then
    result := tyStr
  else if vt = varDate then
    result := tyTime
  else if vt = varCurrency then
    result := tyCurr
  else if isFloat(vt) then
    result := tyReal
  else if isNum(vt) then
    result := tyInt
  else
    result := tyOther
  ;
end;

// a.type() -> stable logical type id (see funType)
procedure _type(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  val^ := funType(PData(exp.value)^.VType);
end;

// a.eq(b) -> strict equality: same logical type AND same value. Unlike '=' there
// is no coercion: nil/0/''/false are all distinct, '1' <> 1, 'ABC' <> 'abc',
// 1 <> 1.0. Only basic values are handled; object identities stay with '='.
procedure _eq(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  e: CExp;
  a, b: PData;
  ta: fun.int;
begin
  val^ := false;
  e := CExps.Find(exps, '', 0);
  if e = nil then exit;
  a := PData(exp.value);
  b := PData(e.value);
  ta := funType(a.VType);
  if ta <> funType(b.VType) then exit;
  case ta of
    tyEmpty: val^ := true;
    // Byte-exact and case-sensitive; routing through fun.str normalizes mixed
    // string forms (varString/varUString/varOleStr) before comparing.
    tyStr:   val^ := fun.str(exp.value^) = fun.str(e.value^);
    tyOther: val^ := false;
  else
    // Same logical family (int/real/currency/time/bool); the Variant operator
    // compares across widths exactly, with no string/number coercion.
    val^ := exp.value^ = e.value^;
  end;
end;

// s.toRegex(= ''), options
procedure _toRegex(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  e: CExp;
begin
  {$IfDef Regex}
  e := CRegex.new(nil).parse(exp.asStr, CExps.FindAsVal(exps, '', 0, ''));
  setObj(val, e, VarObjNew); del(e);
  {$EndIf}
end;

//==============================================================
// x.match(y, action = nil)
procedure _match(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  e: CExp;
begin
  e := CExps.Find(exps, '', 0);
  if e = nil then
    val^ := NullValue
  else
  begin
    if e.asObj = nil then
      val^ := Pos(e.asStr, exp.asStr) > 0
    else
      {$IfDef Regex}
      CRegex(e.asObj).match(env, exp.asStr, CExps.Find(exps, 'action', 1), val)
      {$EndIf}
    ;
  end;
end;

procedure _replace(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  e, e2: CExp;
begin
  e  := CExps.Find(exps, '', 0);
  e2 := CExps.Find(exps, '', 1);
  if e = nil then
    val^ := NullValue
  else
  begin
    if e.asObj = nil then
      val^ := NewStringReplace(exp.asStr, e.asStr, e2.asStr, [rfReplaceAll, rfIgnoreCase])
      //val^ := NewStringReplace(exp.asStr, e.asStr, e2.asStr, [rfReplaceAll])
    else
      {$IfDef Regex}
      CRegex(e.asObj).replace(env, exp.asStr, e2, val)
      {$EndIf}
    ;
  end;
end;

//==============================================================
// s.compile(inline = false)
procedure _compile(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  s, fn: fun.str;
  b: fun.bool;
  n: CNode;
begin
  s := exp.asStr;
  n := env.lastNode.root;
  if Length(s) < 256 then // Length of FileName
    fn := _ParserClass.ParseFileName(s, n)
  ;
  b := CExps.FindAsVal(exps, 'inline', 0, false);
  {$IfDef FunSafe}
  if b or FileExists(fn) then SafeDeny('compile from a file or inline');
  {$EndIf}
  {if not b then} n := nil;
  if FileExists(fn) then
    n  := CParser.ParseOrLoad(fn, n, _ParserClass)
  else
    n  := CParser.Parse(s, _ParserClass, '', n)
  ;
  if b then n.parent := env.lastNode;
  setObj(val, n, VarObjNew); del(n);
end;

//==============================================================
function SseDecompress(const Input: fun.str): fun.str;
var
  i, L, num, j, lineStart: fun.int;
  o, line: fun.str;
begin
  Result := '';
  o := '';
  i := 1;
  L := Length(Input);
  while i <= L do
  begin
    lineStart := i;
    while (i <= L) and not (Input[i] in [#10, #13]) do Inc(i);
    line := Copy(Input, lineStart, i - lineStart);

    num := 0;
    j := 1;
    while (j <= Length(line)) and (line[j] in ['0'..'9']) do Inc(j);
    if (j > 1) and (j <= Length(line)) and (line[j] = ')') then
    begin
      num := StrToInt(Copy(line, 1, j-1));
      Delete(line, 1, j);
    end;

    if num > 0 then
      o := Copy(o, 1, num) + line
    else
      o := line;

    Result := Result + o;
    while (i <= L) and (Input[i] in [#10, #13]) do
    begin
      Result := Result + Input[i];
      Inc(i);
    end;
  end;
end;

//==============================================================
function _ParseJson(const s: fun.str; json: fun.bool = false; fd: fun.bool = false; sse: fun.bool = false; strict: fun.bool = false): CNode;
const
  // Deepest allowed [] / {} nesting (shared by the JSON scan and the FD scan
  // below). Parsing itself is iterative, but the resulting tree is destroyed,
  // cloned and serialized recursively, so an unbounded document could blow the
  // stack (DoS). 512 is far deeper than any real document needs.
  MaxNestDepth = 512;
var
  Root: CSet;
  Level: fun.int;
  Stack: array of fun.ptr;
  StackObj: array of fun.bool;   // parallel to Stack: True where that open
                                 // container is an object; used by strict for
                                 // the key-slot and close-bracket checks
  PushCnt, PopCnt: fun.int;
  curPos: fun.int;
  st: fun.int;                   // strict separator state (see ParseJSON)

  // Drop the partially built tree and the parse stack. Called on any hard
  // error so an aborted parse does not leak the nodes it already created.
  procedure ReleaseTree;
  begin
    if Root <> nil then del(Root);
    Root := nil;
    SetLength(Stack, 0);
    SetLength(StackObj, 0);
    Level := 0;
  end;

  // Single strict-failure exit: no-op unless strict, otherwise release the
  // partial tree and raise through the same EBase channel as 'nesting too
  // deep'. Call sites pass only the message and the byte position.
  procedure StrictFail(const msg: fun.str; const at: fun.int);
  begin
    if not strict then Exit;
    ReleaseTree;
    raise EBase.Create('strict: ' + msg + ' @ ' + IntToStr(at));
  end;

  function Peek(): CExps;
  begin
    Result := Stack[Level -1];
  end;

  procedure Push(const name: fun.str; isObj: fun.bool = false); forward;
  procedure GetVal(const name: fun.str; vv: PData);
  var
    e: CExp;
  begin
    if (Level = 0) and (Length(Stack) = 0) then Push('');
    e := CExp.new(nil);
    e.name := name;
    e.assign(PValue(vv));
    Peek.Add(e);
  end;

  procedure Push(const name: fun.str; isObj: fun.bool = false);
  var
    n: CSet;
    v: CData;
  begin
    if Level >= MaxNestDepth then
    begin
      // Release the partial tree (depth is capped at MaxNestDepth, so this is
      // safe) and report an error instead of building an unusable structure.
      ReleaseTree;
      raise EBase.Create('nesting too deep (max ' + IntToStr(MaxNestDepth) + ')');
    end;

    // Empty the Data
    v.VType := VarEmpty;

    if isObj then
      n := CNew2.new(nil)
    else
      n := CNew.new(nil)
    ;
    n.parse(CExps.create);
    if Level = 0 then
      Root := n
    else
    begin
      setObj(PValue(@v), n, VarObjNew); del(n);
      GetVal(name, @v);                 del(n);
    end;
    Inc(Level);
    SetLength(Stack, Level);
    SetLength(StackObj, Level);
    Stack[Level -1] := n.items;
    StackObj[Level -1] := isObj;
  end;

  procedure Pop();
  begin
    Inc(PopCnt);
    if Level > 1 then Dec(Level)
    else if Level = 0 then
      StrictFail('unbalanced close', curPos);
  end;

  procedure ParseJSON;
  var
    i, ii, oi, bs, p: fun.int;
    c: fun.char;
    kv, k, kk: fun.str;
    vv: CData;
  label
    _STR, _NUM, _KEY;
  begin
    ii := Length(s);
    i  := 1;
    vv.VType := VarEmpty;
    while i <= ii do
    begin
      c  := s[i];
      oi := i;
      curPos := i;
      // ---- strict pre-checks: RFC-only char set + separator grammar -------
      // st is the separator state, shared by every nesting level because a
      // container can only be opened from a value slot: when it closes the
      // enclosing state is always recomputed as 1 (value just completed), so
      // no per-level save is needed.
      //   0 expect a value/key (root start, container just opened)
      //   1 a value just completed
      //   2 just after ','
      //   3 just after an object key
      //   4 just after ':' (expect the value)
      // Whitespace never changes st and passes every check.
      if strict then
      begin
        if c in [';', '='] then
          StrictFail('unexpected char ''' + c + '''', oi);
        if c in ['''', '`'] then
          StrictFail('string quotes must be double quotes', oi);
        if c = '@' then
          StrictFail('unexpected char ''@''', oi);
        if not (c in [' ', #9, #10, #13]) then
        begin
          // A value already completed at the top level: nothing but whitespace
          // may follow (rejects ',', a second ']'/'}', and a trailing scalar).
          if (st = 1) and (PopCnt = PushCnt) then
            StrictFail('unexpected trailing value', oi);
          // Separator grammar for the current state.
          case st of
            1: if not (c in [',', ']', '}']) then
                 StrictFail('missing separator', oi);
            2: if c in [']', '}', ',', ':'] then
                 StrictFail('unexpected separator', oi);
            0: if (c = ',') or (c = ':') then
                 StrictFail('unexpected separator', oi);
            3: if c <> ':' then
                 StrictFail('expected '':'' after key', oi);
            4: if c in [',', ']', '}', ':'] then
                 StrictFail('missing value for key ''' + k + '''', oi);
          end;
          // In an object, states 0/2 expect a key: the only legal starts are a
          // string (or '}' closing an empty object). One check here covers
          // every value branch (number / bareword / '[' / '{') at once.
          if (Level > 0) and StackObj[Level - 1] and (st in [0, 2]) and
             (c <> '"') and not ((st = 0) and (c = '}')) then
            StrictFail('object key must be a string', oi);
        end;
      end;
      case c of
        '"', '''', '`':
  _STR: begin
          if strict then
          begin
            // strict strings, one pass: walk to the closing quote while
            // enforcing RFC 8259 string syntax (no raw control chars, and only
            // the RFC escapes). esc() below still performs the single decode;
            // folding the checks in here avoids a separate validation
            // traversal. In strict only '"' reaches this label (''' and '`'
            // are rejected by the pre-check above).
            i := oi + 1;
            while i <= ii do
            begin
              if s[i] = c then Break;
              if s[i] < #32 then
                StrictFail('raw control char in string', i);
              if s[i] = '\' then
              begin
                Inc(i);
                if i > ii then Break;      // unterminated, reported below
                if not (s[i] in ['"', '\', '/', 'b', 'f', 'n', 'r', 't', 'u']) then
                  StrictFail('invalid escape ''\' + s[i] + '''', i);
                if s[i] = 'u' then
                begin
                  if i + 4 > ii then
                    StrictFail('invalid \u escape', i);
                  for p := 1 to 4 do
                    if not (s[i + p] in ['0'..'9', 'A'..'F', 'a'..'f']) then
                      StrictFail('invalid \u escape', i);
                  Inc(i, 4);
                end;
              end;
              Inc(i);
            end;
            if not ((i <= ii) and (s[i] = c)) then
              StrictFail('string not closed', oi);
            kv := Copy(s, oi + 1, i - oi - 1);
          end
          else
          begin
            bs := 0;
            repeat
              if s[i] = '\' then Inc(bs)
                            else bs := 0;
              Inc(i);
            until (i > ii) or (s[i] = c) and ((bs mod 2 = 0) or not json);
            if (i <= ii) and (s[i] = c) then
              kv := Copy(s, oi + 1, i - oi - 1)
            else
              kv := Copy(s, oi + 1, i - oi)
            ;
          end;
          if (Level > 0) and StackObj[Level -1] and (st in [0, 2]) then
            st := 3                          // this string is an object key
          else
            st := 1                          // otherwise it is a value
          ;
          if s[oi-1] = '@' then
            CValue(vv) := StrToDateTime(kv)
          else if json then
          begin
            kv := esc(kv);
            CValue(vv) := kv;
          end
          else
            CValue(vv) := kv
          ;
          kk := c;
        end;

        '0':
        begin
          if s[i+1] in ['x', 'X'] then
          begin
            StrictFail('hex number not allowed', oi);
            Inc(i, 2);
            repeat
              Inc(i);
            until not (s[i] in ['0'..'9', 'A'..'F', 'a'..'f']) or (i > ii);
            kv := Copy(s, oi, i - oi);
            CValue(vv) := CParser.StrToNum(kv);
            st := 1;
            Continue;
          end
          else goto _NUM;
        end;

        '1'..'9', '-', '.':
  _NUM: begin
          repeat
            Inc(i);
          until not (s[i] in ['0'..'9', '.', 'e', 'E', '-', '+']) or (i > ii);
          kv := Copy(s, oi, i - oi);
          if s[i] in ['$', '_', 'A'..'Z', 'a'..'z'] then
            StrictFail('invalid number ''' + kv + '''', oi);
          // strict: a number token with no digit at all ('.', '-', '--') is
          // malformed. Digit-bearing forms stay lenient on purpose (.5, 03, 1.).
          if strict then
          begin
            p := 1;
            while (p <= Length(kv)) and not (kv[p] in ['0'..'9']) do Inc(p);
            if p > Length(kv) then
              StrictFail('invalid number ''' + kv + '''', oi);
          end;
          CValue(vv) := CParser.StrToNum(kv);
          st := 1;
          Continue;
        end;

        '@':
        begin
          if s[i+1] in ['"', '''', '`'] then
          begin
            Inc(i);
            Continue;
          end
          else goto _KEY;
        end;

        '$', '_', 'A'..'Z', 'a'..'z':
  _KEY: begin
          repeat
            Inc(i);
          until not (s[i] in ['$', '_', '@'..'Z', 'a'..'z', '0'..'9']) or (i > ii);
          kv := Copy(s, oi, i - oi);
          if (kv = 'null') or (kv = 'nil') then
          begin
            if kv = 'nil' then
              StrictFail('bareword ''nil'' not allowed', oi);
            CValue(vv) := NullValue;
          end
          else if kv = 'true' then
            CValue(vv) := true
          else if kv = 'false' then
            CValue(vv) := false
          else
          begin
            StrictFail('bareword ''' + kv + ''' not allowed', oi);
            CValue(vv) := kv;
          end;
          st := 1;
          Continue;
        end;

        ':', '=':
        begin
          k  := kv;
          st := 4;
        end;

        ',', ';':
        begin
          if k + kv + kk <> '' then GetVal(k, @vv);
          k  := '';
          kv := '';
          kk := '';
          st := 2;
        end;

        '[', '{':
        begin
          Push(k, c = '{');
          Inc(PushCnt);
          k  := '';
          kv := '';
          kk := '';
          st := 0;
        end;

        ']', '}':
        begin
          if (Level >= 1) and (StackObj[Level -1] <> (c = '}')) then
            StrictFail('mismatched close', oi);
          if k + kv + kk <> '' then GetVal(k, @vv);
          k  := '';
          kv := '';
          kk := '';
          Pop();
          st := 1;
        end;
        else
          if not (c in [' ', #9, #10, #13]) then
            StrictFail('unexpected char ''' + c + '''', oi);
      end;
      Inc(i);
    end;
    // Any bracket-count mismatch left at end of input (one message is enough:
    // too many closes and too few are both "brackets don't balance").
    if PopCnt <> PushCnt then
      StrictFail('unbalanced brackets', i);
    // End of input terminates a pending entry just like a trailing separator,
    // so the last key/value (or set element) is kept instead of dropped.
    // A bare scalar is a legal root (RFC 8259), so commit unconditionally.
    if k + kv + kk <> '' then
      GetVal(k, @vv);
    // strict: an empty or whitespace-only document has no JSON value.
    if Root = nil then
      StrictFail('no JSON value', i);
  end;

  {$I 'libfd.inc'}

begin
  Root  := nil;
  Level := 0;
  PushCnt := 0;
  PopCnt := 0;
  curPos := 0;
  st := 0;
  SetLength(StackObj, 0);

  if fd then
  begin
    if sse then ParseFD(SseDecompress(s))
           else ParseFD(s);
  end else
    ParseJSON
  ;

  Result := Root;
end;

// json = false, fd = false, sse = false
procedure _GetJson(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  n: CNode;
  lv: fun.int;
begin
  lv := CExps.FindAsVal(exps, 'json', 0, 0);
  n := _ParseJson(exp.asStr, lv <> 0, CExps.FindAsVal(exps, 'fd', 1, false), CExps.FindAsVal(exps, 'sse', 2, false), lv >= 2);
  if n = nil then n := CNew.new(nil).parse(CExps.create);
  setObj(val, n, VarObjNew); del(n);
end;

{$IfDef MD5}
//{$I 'libmd5.inc'}
procedure _md5(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  i: fun.int;
  s: fun.str;
begin
  s := exp.asStr;
  i := Length(s);
  val^ := MD5(fun.ptr({$IfDef Unicode}ToRawString{$EndIf}(s))^, i);
end;

procedure _sha1(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  i: fun.int;
  s: fun.str;
begin
  s := exp.asStr;
  i := Length(s);
  val^ := SHA(fun.ptr({$IfDef Unicode}ToRawString{$EndIf}(s))^, i);
end;
{$EndIf}

//==============================================================
constructor CLbase.Create;
begin
  inherited Create;
  // Easter egg
  ids['@uthor']  := CExp.new(nil).parse(Int64(fun.uintptr(@_author)));
  
  // Arg or param
  ids['arg']     := CExp.new(nil).parse(Int64(fun.uintptr(@_arg)));
  ids['set']     := CExp.new(nil).parse(Int64(fun.uintptr(@_set)));
  
  // Math
  ids['exp']     := CExp.new(nil).parse(Int64(fun.uintptr(@_exp)));
  ids['log']     := CExp.new(nil).parse(Int64(fun.uintptr(@_log)));
  ids['sin']     := CExp.new(nil).parse(Int64(fun.uintptr(@_sin)));
  ids['cos']     := CExp.new(nil).parse(Int64(fun.uintptr(@_cos)));
  ids['atan']    := CExp.new(nil).parse(Int64(fun.uintptr(@_atan)));
  ids['random']  := CExp.new(nil).parse(Int64(fun.uintptr(@_random)));
  
  // String
  ids['length']  := CExp.new(nil).parse(Int64(fun.uintptr(@_length)));
  ids['lower']   := CExp.new(nil).parse(Int64(fun.uintptr(@_lower)));
  ids['upper']   := CExp.new(nil).parse(Int64(fun.uintptr(@_upper)));
  ids['subpos']  := CExp.new(nil).parse(Int64(fun.uintptr(@_subpos)));
  ids['substr']  := CExp.new(nil).parse(Int64(fun.uintptr(@_substr)));
  ids['x']       := CExp.new(nil).parse(Int64(fun.uintptr(@_x)));
  ids['movs']    := CExp.new(nil).parse(Int64(fun.uintptr(@_movs)));
  ids['escape']  := CExp.new(nil).parse(Int64(fun.uintptr(@_escape)));
  ids['format']  := CExp.new(nil).parse(Int64(fun.uintptr(@_format)));
  ids['eval']    := CExp.new(nil).parse(Int64(fun.uintptr(@_eval)));
  
  // Time
  ids['time']    := CExp.new(nil).parse(Int64(fun.uintptr(@_time)));
  
  // File
  ids['hash']    := CExp.new(nil).parse(Int64(fun.uintptr(@_hash)));
  ids['load']    := CExp.new(nil).parse(Int64(fun.uintptr(@_load)));
  ids['save']    := CExp.new(nil).parse(Int64(fun.uintptr(@_save)));
  ids['find']    := CExp.new(nil).parse(Int64(fun.uintptr(@_find)));
  ids['copy']    := CExp.new(nil).parse(Int64(fun.uintptr(@_copy)));
  ids['move']    := CExp.new(nil).parse(Int64(fun.uintptr(@_move)));
  ids['size']    := CExp.new(nil).parse(Int64(fun.uintptr(@_size)));
  
  // Path
  // in env
  
  // Set/List
  // not in libase
  // @count(), @each(), @add(), @clone()
  // @toJSON()
  
  // Console input
  ids['input']   := CExp.new(nil).parse(Int64(fun.uintptr(@_input)));
  
  // Fun Lib
  ids['GetLib']  := CExp.new(nil).parse(Int64(fun.uintptr(@_getlib)));
  
  // Win API
  {$IfDef WinAPI}
  // f.getapi(name, type)
  //   f    -> filename
  //   name -> method name or address
  //   type -> xxx...:x
  // getfun? getmethod?
  ids['GetApi']  := CExp.new(nil).parse(Int64(fun.uintptr(@_getapi)));
  {$EndIf}
  
  // Unix: dlopen/dlsym via libffi (winapi unit stays Windows-only)
  {$IfDef UnixFFI}
  ids['GetApi']  := CExp.new(nil).parse(Int64(fun.uintptr(@_lgetapi)));
  {$EndIf}

  // Win COM
  {$IfDef WinCOM}
  // c.newobj(get = false)
  //   c -> class name or guid
  // newole? newobject?
  ids['NewObj']  := CExp.new(nil).parse(Int64(fun.uintptr(@_newobj)));
  {$EndIf}
  
  // Type conversions
  ids['toStr']   := CExp.new(nil).parse(Int64(fun.uintptr(@_toStr)));
  ids['toNum']   := CExp.new(nil).parse(Int64(fun.uintptr(@_toNum)));
  ids['toTime']  := CExp.new(nil).parse(Int64(fun.uintptr(@_toTime)));
  ids['toByte']  := CExp.new(nil).parse(Int64(fun.uintptr(@_toByte)));
  ids['fromByte']:= CExp.new(nil).parse(Int64(fun.uintptr(@_fromByte)));
  ids['toChar']  := CExp.new(nil).parse(Int64(fun.uintptr(@_toChar)));
  // toRegex
  ids['toRegex'] := CExp.new(nil).parse(Int64(fun.uintptr(@_toRegex)));

  // Strict comparison and logical type id (basic values only)
  ids['eq']      := CExp.new(nil).parse(Int64(fun.uintptr(@_eq)));
  ids['type']    := CExp.new(nil).parse(Int64(fun.uintptr(@_type)));
  
  // Regex
  // match
  // s.match(r) and r.match(s)
  // s =~ /../. and /../. =~ s
  //   return CMatches if 'g'
  //          CMatches is a Set/List of CMatch
  //   or
  //   return CMatch
  //          CMatch is a Obj inherited Set
  //            0: match, 1~n: groups
  //            .@next(): match next
  //            .@value(), @matched(): [0]
  //            .@missed(): un-matched
  ids['match']   := CExp.new(nil).parse(Int64(fun.uintptr(@_match)));
  // replace
  // s.replace(r, s2) and r.replace(s, s2)
  ids['replace'] := CExp.new(nil).parse(Int64(fun.uintptr(@_replace)));
  
  // Parse ...
  // parseAsJSON
  // parseAsFUN, parseAsScript, compile
  //   带 inline 参数
  // parseAsXML, 这个可以作为正则用 fun 来做
  // parseAsINI, 这个可以作为正则用 fun 来做
  // ...
  ids['compile'] := CExp.new(nil).parse(Int64(fun.uintptr(@_compile)));
  ids['GetJson'] := CExp.new(nil).parse(Int64(fun.uintptr(@_GetJson)));
  
  {$IfDef MD5}
  ids['md5']     := CExp.new(nil).parse(Int64(fun.uintptr(@_md5)));
  ids['sha1']    := CExp.new(nil).parse(Int64(fun.uintptr(@_sha1)));
  {$EndIf}
end;

function CLbase.accept(exp: CExp): fun.bool;
begin
  result := exp.asObj = nil;
end;


end.
