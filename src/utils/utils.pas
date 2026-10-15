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

interface

uses fun;

procedure InitTick;
function GetTick: fun.uint;

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
    AttachConsole := GetProc(LoadLib(kernel32), 'AttachConsole');
    result := AttachConsole(-1) <> 0;
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

end.
