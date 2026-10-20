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
unit utils;

// FunPack is the full feature (create bundles + run them). FunPackUser is the
// consumer-only subset (run a bundle, no "fun pack" subcommand). Defining
// FunPack implies FunPackUser, so existing -dFunPack builds are unchanged.
{$IfDef FunPack}
  {$Define FunPackUser}
{$EndIf}

interface

uses fun;

procedure InitTick;
function GetTick: fun.uint;
{$IfDef FunStartupTiming}
// Nanosecond-resolution monotonic clock for startup profiling
// (-dFunStartupTiming in funcmd.dpr). Not part of the script-visible API.
function GetNanoTick: fun.uint64;
// Startup profiling hooks, also used inside this unit (FindCmdLine), so the
// caller only has to start the clock once with TimeMark('main').
procedure TimeMark(const name: fun.str);
procedure DumpProfile;
{$EndIf}

function FindParam(const id: fun.str; idx: fun.int = 0): fun.str;
function FindParamAsBool(const id: fun.str; idx: fun.int = 0): fun.bool;

function FindCmdLine: fun.bool;
procedure FreeCmdLine;
function SetStdOut(const fn: fun.str): fun.int;
// Write a diagnostic string to standard error. Standalone (not the RTL text
// file StdErr/ErrOutput) because Delphi 7 declares neither: StdErr is an FPC
// name, and ErrOutput only appeared in later Delphi versions. Going through the
// OS handle also does not depend on the APPTYPE CONSOLE directive having opened
// the file at startup, so an -gui run that later attaches to a console works.
procedure WriteErr(const s: fun.str);

// Write a string to standard output as raw bytes. FPC tags the standard Output
// text file with GetConsoleOutputCP() (OpenStdIO in the RTL), so the RTL Write()
// re-encodes every write from the string codepage to the console codepage (e.g.
// CP1252 -> CP65001) and mangles any non-ASCII output. Fun's output is a byte
// stream (see the CRLF convention in the regression docs), so bypass the RTL
// text file on Windows, exactly as WriteErr does for stderr. The Unix and
// Delphi builds are byte-exact already and keep the plain RTL write.
procedure WriteOut(const s: fun.str);

{$IfDef FunPack}
// ---------------------------------------------------------------- fun tools
// "fun <tool>" runs lib/tools/fun-<tool>.fun from the release tree (next to
// the executable) or from fun/lib/tools in a development checkout. The tool
// takes the script's argv slot, so it still sees 1.arg() = its own path.
//
// To add a tool, list its command name here; the script name is derived as
// fun-<command>.fun, so no other dispatch change is needed.
function IsFunTool(const name: fun.str): fun.bool;
function FindFunTool(const name: fun.str): fun.str;
{$EndIf}

{$IfDef FunPackUser}
// ---------------------------------------------------------------- bundled app
// A packaged single-file app is this executable with a zip payload (STORE
// entries only) and a 16-byte trailer ('FUNBUNDL' + uint64 payload size)
// appended by fun/lib/tools/fun-pack.fun. UnpackBundle extracts the payload to
// a temp directory and returns the entry script's path; '' means "no bundle".
// BundleDir is that temp directory, or '' when nothing was unpacked.
var
  BundleDir: fun.str;

function UnpackBundle(const exe: fun.str): fun.str;
// Remove the bundle's temp directory after the script has run.
procedure FreeBundle;
{$EndIf}

implementation

uses SysUtils
     {$IfNDef UNIX}, Windows{$Else}
       {$IfDef Linux}, Linux{$EndIf}
       , unixtype
       {$IfDef Darwin}, unix{$EndIf}
     {$EndIf}
     , io
     ;

// A leading '-' introduces a switch on every platform. Windows also accepts
// '/switch', so the prefix set keeps '/' there; on Linux (and other Unixes)
// '/' starts an absolute path, and treating it as a switch would silently
// drop path arguments such as '/etc/x'. Isolated by a compile-time condition.
{$IfDef UNIX}
const
  SwitchPrefix: set of AnsiChar = ['-'];
{$Else}
const
  SwitchPrefix: set of AnsiChar = ['-', '/'];
{$EndIf}

function IsSwitch(const s: fun.str): fun.bool; inline;
begin
  result := (s <> '') and (s[1] in SwitchPrefix);
end;

//==============================================================
var
  tick: fun.uint;
{$IfDef FunStartupTiming}
  {$IfNDef UNIX}
  qpcFreq: int64 = 0;
  {$EndIf}
  profileStart:  fun.uint64;
  profilePrev:   fun.uint64;
  profileLog:    fun.str;
  profileDumped: fun.bool;
{$EndIf}

function GetTickCount: fun.uint;
{$IfDef UNIX}
var
  {$IfDef Darwin}
  tv: timeval;
  {$Else}
  ts: timespec;
  {$EndIf}
{$EndIf}
begin
{$IfNDef UNIX}
  result := Windows.GetTickCount;
{$Else}
  {$IfDef Darwin}
  // macOS has clock_gettime only since 10.12; gettimeofday is always present.
  if fpgettimeofday(@tv, nil) = 0 then
    result := fun.uint(int64(tv.tv_sec) * 1000 + tv.tv_usec div 1000)
  else
    result := 0;
  {$Else}
  // Monotonic clock in ms; modular (uint32) wraparound mirrors GetTickCount.
  if clock_gettime(CLOCK_MONOTONIC, @ts) = 0 then
    result := fun.uint(int64(ts.tv_sec) * 1000 + ts.tv_nsec div 1000000)
  else
    result := 0;
  {$EndIf}
{$EndIf}
end;

procedure InitTick;
begin
  tick := GetTickCount;  
end;

function GetTick: fun.uint;
var
  i: fun.uint;
begin
  i      := GetTickCount;
  result := i - tick;
  tick   := i;
end;

{$IfDef FunStartupTiming}
function GetNanoTick: fun.uint64;
{$IfDef UNIX}
var
  {$IfDef Darwin}
  tv: timeval;
  {$Else}
  ts: timespec;
  {$EndIf}
{$Else}
var
  qpc: int64;
{$EndIf}
begin
{$IfDef UNIX}
  {$IfDef Darwin}
  if fpgettimeofday(@tv, nil) = 0 then
    result := int64(tv.tv_sec) * 1000000000 + int64(tv.tv_usec) * 1000
  else
    result := 0;
  {$Else}
  if clock_gettime(CLOCK_MONOTONIC, @ts) = 0 then
    result := int64(ts.tv_sec) * 1000000000 + int64(ts.tv_nsec)
  else
    result := 0;
  {$EndIf}
{$Else}
  qpc := 0;
  if qpcFreq = 0 then QueryPerformanceFrequency(qpcFreq);
  if (qpcFreq > 0) and QueryPerformanceCounter(qpc) then
    // Do not multiply the whole counter first: qpc * 1e9 overflows Int64
    // after ~15 minutes of uptime at the usual 10 MHz QPC frequency.
    result := (qpc div qpcFreq) * 1000000000
            + ((qpc mod qpcFreq) * 1000000000) div qpcFreq
  else
    result := int64(Windows.GetTickCount) * 1000000;
{$EndIf}
end;

procedure DumpProfile;
begin
  if not profileDumped and (profileLog <> '') then
  begin
    profileDumped := true;
    WriteErr(profileLog);
    profileLog := '';
  end;
end;

procedure TimeMark(const name: fun.str);
var
  t: fun.uint64;
begin
  t := GetNanoTick;
  if profileStart = 0 then profileStart := t;
  if profilePrev  = 0 then profilePrev  := t;
  // Buffer the lines: a WriteFile to a Windows console costs close to 1 ms,
  // which would otherwise land in the next phase's delta and dominate it.
  profileLog := profileLog + 'FUNTIME ' + name +
                ' total=' + IntToStr(t - profileStart) +
                'ns delta=' + IntToStr(t - profilePrev) + 'ns' + sLineBreak;
  profilePrev := t;
  if name = 'cleanup' then DumpProfile;
end;
{$EndIf}

//==============================================================
function FindParamById(const id: fun.str): fun.str;
var
  i, ii, j, l, len: fun.int;
  s: fun.str;
begin
  result := '';
  if id = '' then exit;
  
  ii := ParamCount;
  for i := 1 to ii do
  begin
    s := ParamStr(i);
    if IsSwitch(s) then
    begin
      j := Pos(id, s);
      if j = 2 then
      begin
        l   := Length(id);
        len := Length(s);
        Inc(j, l);
        if (len > j) and (s[j] in [':', '=']) then Inc(j);
        s := Copy(s, j, len - j + l);
        if s = '' then s := 'true';
        result := s;
        exit; 
      end;      
    end;
  end;
end;

function FindParam(const id: fun.str; idx: fun.int): fun.str;
var
  i, ii: fun.int;
begin
  result := FindParamById(id);
  if (result = '') and (idx > 0) then
  begin
    ii := ParamCount;
    for i := idx to ii do
    begin
      result := ParamStr(i);
      if not IsSwitch(result) then exit;
    end;
    result := '';
  end;
end;

function FindParamAsBool(const id: fun.str; idx: fun.int): fun.bool;
begin
  result := StrToBoolDef(FindParam(id, idx), false);
end;

//==============================================================
{$IfNDef UNIX}
{$IfNDef WinCE}
//function AttachConsole(dwProcessId: fun.int): fun.int; stdcall;
//         external kernel32 name 'AttachConsole';
type AttachConsoleProc = function (dwProcessId: fun.int): fun.int; stdcall;
var  AttachConsole: AttachConsoleProc;
{$EndIf}
{$EndIf}

function FindCmdLine: fun.bool;
begin
{$IfNDef UNIX}
{$IfNDef WinCE}
  try
    {$IfDef FunStartupTiming}TimeMark('cmdline-getproc');{$EndIf}
    AttachConsole := GetProc(LoadLib(kernel32), 'AttachConsole');
    {$IfDef FunStartupTiming}TimeMark('cmdline-attach');{$EndIf}
    result := AttachConsole(-1) <> 0;
    {$IfDef FunStartupTiming}TimeMark('cmdline-attached');{$EndIf}
  except
    result := false;
  end;
{$Else}
  result := true;
{$EndIf}
{$Else}
  result := true;
{$EndIf}
end;

procedure FreeCmdLine;
begin
{$IfNDef UNIX}
{$IfNDef WinCE}
  FreeConsole;
  // Press Enter Key
  //keybd_event(13, 0, 0, 0);
{$EndIf}
{$EndIf}
end;

function SetStdOut(const fn: fun.str): fun.int;
begin
{$IfNDef UNIX}
  result := FileCreate(fn);
{$IfNDef WinCE}
  SetStdHandle(STD_OUTPUT_HANDLE, result);
{$EndIf}
{$Else}
  result := 0;
{$EndIf}
end;

procedure WriteErr(const s: fun.str);
{$IfDef UNIX}
begin
  if s <> '' then
  begin
    Write(StdErr, s);
    Flush(StdErr);
  end;
end;
{$Else}
{$IfDef WinCE}
begin
  // WinCE has no console; keep diagnostics on the RTL text device.
  if s <> '' then
  begin
    Write(Output, s);
    Flush(Output);
  end;
end;
{$Else}
var
  h: THandle;
  n: DWORD;
  b: AnsiString;
begin
  if s = '' then exit;
  h := GetStdHandle(STD_ERROR_HANDLE);
  if (h = 0) or (h = INVALID_HANDLE_VALUE) then exit;
  b := s;
  WriteFile(h, b[1], Length(b), n, nil);
end;
{$EndIf}
{$EndIf}

procedure WriteOut(const s: fun.str);
{$IfDef FPC}
{$IfNDef UNIX}
{$IfNDef WinCE}
var
  h: THandle;
  n: DWORD;
  b: AnsiString;
{$EndIf}
{$EndIf}
{$EndIf}
begin
{$IfDef FPC}
{$IfNDef UNIX}
{$IfNDef WinCE}
  if s <> '' then
  begin
    h := GetStdHandle(STD_OUTPUT_HANDLE);
    if (h <> 0) and (h <> INVALID_HANDLE_VALUE) then
    begin
      b := s;
      WriteFile(h, b[1], Length(b), n, nil);
      exit;
    end;
  end;
{$EndIf}
{$EndIf}
{$EndIf}
  // Unix, WinCE and Delphi: the RTL write is already byte-exact.
  Write(Output, s);
end;

{$IfDef FunPack}
//==============================================================
// "fun <tool>" dispatch
//==============================================================
const
  // Enabled tool commands. The script is lib/tools/fun-<name>.fun.
  FunTools: array[0..1] of fun.str = ('pack', 'package');

function IsFunTool(const name: fun.str): fun.bool;
var
  i: Integer;
begin
  result := false;
  if name = '' then exit;
  for i := Low(FunTools) to High(FunTools) do
    if FunTools[i] = name then begin result := true; exit; end;
end;

function FindFunTool(const name: fun.str): fun.str;
var
  rel: fun.str;
begin
  rel := 'lib' + PathDelim + 'tools' + PathDelim + 'fun-' + name + '.fun';
  result := ExtractFilePath(ParamStr(0)) + rel;
  if FileExists(result) then exit;
  // a development build lives in src/prj/fun, three levels below the repo root
  result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + '..' + PathDelim +
            '..' + PathDelim + 'fun' + PathDelim + rel;
  if FileExists(result) then exit;
  result := 'fun' + PathDelim + rel;
  if FileExists(result) then exit;
  result := ExtractFilePath(ParamStr(0)) + rel;   // reported when nothing was found
end;
{$EndIf}

{$IfDef FunPackUser}
//==============================================================
// Bundled-app runtime (consumer side)
//==============================================================
const
  _BundleMagic = 'FUNBUNDL';

// little-endian value of n (<= 8) bytes at at; -1 on a short read
function _LE(h: THandle; at: Int64; n: Integer): Int64;
var
  b: array[0..7] of Byte;
  i: Integer;
begin
  result := 0;
  if n > 8 then n := 8;
  if FileSeek(h, at, 0) < 0 then begin result := -1; exit; end;
  if FileRead(h, b, n) <> n then begin result := -1; exit; end;
  for i := n - 1 downto 0 do
    result := (result shl 8) or b[i];
end;

function _ReadStr(h: THandle; at: Int64; n: Integer): fun.str;
var
  s: fun.str;
begin
  s := '';
  if n <= 0 then begin result := s; exit; end;
  SetLength(s, n);
  if FileSeek(h, at, 0) < 0 then exit;
  if FileRead(h, s[1], n) <> n then s := '';
  result := s;
end;

function _TrimRel(s: fun.str): fun.str;
begin
  result := s;
  while (result <> '') and ((result[Length(result)] = #13) or
        (result[Length(result)] = #10) or (result[Length(result)] = ' ')) do
    SetLength(result, Length(result) - 1);
end;

// GetTempDir is not available in older Delphi (2006); GetTempPath is.
function _TempDir: fun.str;
{$IfDef UNIX}
begin
  result := GetTempDir;
end;
{$Else}
var
  buf: array[0..MAX_PATH] of Char;
  n: DWORD;
begin
  buf[0] := #0;
  n := GetTempPath(SizeOf(buf), buf);
  if (n > 0) and (n < SizeOf(buf)) then
  begin
    buf[n] := #0;
    result := buf;
  end
  else
    result := '.';
end;
{$EndIf}

procedure _DeleteTree(const dir: fun.str);
var
  sr: TSearchRec;
  p: fun.str;
begin
  p := IncludeTrailingPathDelimiter(dir);
  // Qualify these: on Windows the RTL unit also exports DeleteFile/FindClose
  // with different signatures (PChar / handle), and it shadows SysUtils here.
  if SysUtils.FindFirst(p + '*', faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Name <> '.') and (sr.Name <> '..') then
      begin
        if (sr.Attr and faDirectory) <> 0 then
          _DeleteTree(p + sr.Name)
        else
          SysUtils.DeleteFile(p + sr.Name);
      end;
    until SysUtils.FindNext(sr) <> 0;
    SysUtils.FindClose(sr);
  end;
  SysUtils.RemoveDir(dir);
end;

// zip entry name -> a relative path with the host separator, or '' when the
// name is unsafe (absolute, drive-qualified, or has an empty/'.'/'..' segment).
function _SafeRel(name: fun.str): fun.str;
var
  seg, rest, out: fun.str;
  k: Integer;
begin
  result := '';
  if (name = '') or (Pos(':', name) > 0) or (Pos('\', name) > 0) then exit;
  if name[1] = '/' then exit;
  out  := '';
  rest := name;
  while rest <> '' do
  begin
    k := Pos('/', rest);
    if k > 0 then
    begin
      seg  := Copy(rest, 1, k - 1);
      rest := Copy(rest, k + 1, Length(rest));
    end
    else
    begin
      seg  := rest;
      rest := '';
    end;
    if (seg = '') or (seg = '.') or (seg = '..') then exit;
    if out = '' then out := seg else out := out + PathDelim + seg;
  end;
  result := out;
end;

function UnpackBundle(const exe: fun.str): fun.str;
var
  h, fo: THandle;
  size, zipStart, zipLen, i, ents, cd, p, method, nl, xl, cl, loff,
  dataOff, csize, left, got, stopAt, cdOfs: Int64;
  tmp, name, rel, dest: fun.str;
  buf: array[0..65535] of Byte;
  marker, failed: fun.bool;
begin
  result := '';
  BundleDir := '';
  if not FileExists(exe) then exit;
  h := FileOpen(exe, fmOpenRead or fmShareDenyNone);
  if h = THandle(-1) then exit;
  fo := THandle(-1);
  try
    size := FileSeek(h, 0, 2);
    if size < 64 then exit;
    if _ReadStr(h, size - 16, 8) <> _BundleMagic then exit;
    zipLen := _LE(h, size - 8, 8);
    if (zipLen <= 0) or (zipLen > size - 16) then exit;
    zipStart := size - 16 - zipLen;
    cd := -1;
    i  := zipStart + zipLen - 22;
    stopAt := i - 65557;              // EOCD + max archive comment
    if stopAt < zipStart then stopAt := zipStart;
    while i >= stopAt do
    begin
      if _LE(h, i, 4) = $06054B50 then begin cd := i; break; end;
      Dec(i);
    end;
    if cd < 0 then exit;
    ents  := _LE(h, cd + 10, 2);
    cdOfs := _LE(h, cd + 16, 4);
    if (ents < 0) or (cdOfs < 0) or (cdOfs >= zipLen) then exit;
    p     := zipStart + cdOfs;
    tmp  := IncludeTrailingPathDelimiter(_TempDir) + 'fun-pack-' + IntToStr(GetTickCount);
    while DirectoryExists(tmp) do tmp := tmp + 'x';
    ForceDirectories(tmp);
    BundleDir := tmp;
    marker := false;
    failed := false;
    // Int64 cannot be a Delphi for-loop control variable (E2032).
    i := 0;
    while i < ents do
    begin
      if _LE(h, p, 4) <> $02014B50 then begin failed := true; break; end;
      method := _LE(h, p + 10, 2);
      csize  := _LE(h, p + 20, 4);
      nl     := _LE(h, p + 28, 2);
      xl     := _LE(h, p + 30, 2);
      cl     := _LE(h, p + 32, 2);
      loff   := _LE(h, p + 42, 4);
      name   := _ReadStr(h, p + 46, nl);
      if method <> 0 then begin failed := true; break; end;
      if (csize < 0) or (nl < 0) or (loff < 0) or (loff >= zipLen) then
      begin failed := true; break; end;
      dataOff := zipStart + loff + 30 + _LE(h, zipStart + loff + 26, 2)
                                    + _LE(h, zipStart + loff + 28, 2);
      if (dataOff < zipStart) or (dataOff + csize > zipStart + zipLen) then
      begin failed := true; break; end;
      if name = '.funpack/entry' then
      begin
        rel    := _TrimRel(_ReadStr(h, dataOff, csize));
        marker := rel <> '';
      end
      else
      begin
        dest := _SafeRel(name);
        if dest <> '' then
        begin
          dest := tmp + PathDelim + dest;
          if ExtractFileDir(dest) <> '' then ForceDirectories(ExtractFileDir(dest));
          fo := FileCreate(dest);
          if fo = THandle(-1) then begin failed := true; break; end;
          if FileSeek(h, dataOff, 0) < 0 then begin failed := true; break; end;
          left := csize;
          while left > 0 do
          begin
            got := left; if got > SizeOf(buf) then got := SizeOf(buf);
            if FileRead(h, buf, got) <> got then begin failed := true; break; end;
            if FileWrite(fo, buf, got) <> got then begin failed := true; break; end;
            left := left - got;
          end;
          FileClose(fo);
          fo := THandle(-1);
          if failed then break;
        end;
      end;
      p := p + 46 + nl + xl + cl;
      Inc(i);
    end;
    if marker and not failed then
      result := tmp + PathDelim + _SafeRel(rel)
    else
    begin
      _DeleteTree(tmp);
      BundleDir := '';
    end;
  finally
    if fo <> THandle(-1) then FileClose(fo);
    FileClose(h);
  end;
end;

procedure FreeBundle;
begin
  if BundleDir <> '' then
  begin
    _DeleteTree(BundleDir);
    BundleDir := '';
  end;
end;
{$EndIf}

end.
