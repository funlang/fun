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

{$IfNdef FunDll}
program funcmd;
{$Else}
library funcmd;
{$EndIf}

{$IfNDef FPC}
{$IF CompilerVersion >= 21.0}
  {$WEAKLINKRTTI ON}
  {$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}
{$IFEND}
{$EndIf}

//{$APPTYPE CONSOLE}

uses
{$IfDef UNIX}{$IfNDef FunDll}
{$IfDef UseCThreads}
  // Thread-safe FPC heap. Only needed when a C library invokes a @toCallback
  // closure from a pthread it created itself, i.e. when Fun evaluates on a
  // foreign thread. The lock on every allocation costs ~20% on every run, so
  // this is opt-in: build with -dUseCThreads. The single-threaded poll(2)
  // server (lib-winsock-lnx) and same-thread FFI callbacks do not need it.
  // See art/notes/linux-threading.md.
  cthreads,
{$EndIf}
{$EndIf}{$EndIf}
  SysUtils,
  Classes,
  fun in '..\..\core\fun.pas',
  base in '..\..\core\base.pas',
  core in '..\..\core\core.pas',
  flow in '..\..\core\flow.pas',
{$IfNDef UNIX}
  atom in '..\..\core\atom.pas',
{$EndIf}
  calc in '..\..\core\calc.pas',
  io in '..\..\core\io.pas',
  parse in '..\..\parse\parse.pas',
  libase in '..\..\lib\libase.pas',
  libset in '..\..\lib\libset.pas',
{$IfDef WinAPI}
  winapi in '..\..\lib\winapi.pas',
{$EndIf}
{$IfDef WinCOM}
  winole in '..\..\lib\winole.pas',
{$EndIf}
{$IfDef Regex}
  regex in '..\..\regex\regex.pas',
  pcre in '..\..\regex\pcre\pcre.pas',
  pcrd in '..\..\regex\pcre\pcrd.pas',
{$EndIf}
{$IfDef FunUI}
  ie in '..\..\lib\ui\ie.pas',
  ui in '..\..\lib\ui\ui.pas',
{$EndIf}
  {$IfDef MD5}{$IfDef UNIX}
  funhash in '..\..\lib\funhash.pas',
  {$EndIf}{$EndIf}
  host in '..\..\lib\host.pas',
  utils in '..\..\utils\utils.pas';

{$R *.res}

type
  CFunParser = class(CParser)
  public
    procedure DoError(const s: fun.str); override;
  end;

  CFunRunner = class(CEnv2)
  public
    procedure echo(const s: fun.str); override;
    function clone: CEnv; override;
  end;

// var
var
  isLog: fun.bool;
  hadError: fun.bool;

// `file:line: ` prefix for the command currently executing, taken from the
// environment's last traced node (see CRuns.run / CEnv.trace). Empty during
// parsing (nothing has run yet) and when the source file is unknown.
function ErrPos: fun.str;
var
  n: CNode;
  m: CModu;
begin
  result := '';
  if _ENV = nil then exit;
  n := _ENV.lastNode;
  if n = nil then exit;
  if n.root is CModu then m := CModu(n.root) else m := nil;
  if (m <> nil) and (m.fileName <> '') and (n is CRune) then
    result := m.fileName + ':' + IntToStr(CRune(n).row) + ': '
  ;
end;

// All diagnostics go to stderr (the `?.`/echo output keeps stdout), so a script
// like `a.fun && b.fun`, CI, or cron can tell success from failure. The exit
// code itself is set at _Exit from hadError. Runtime errors carry a
// `file:line:` prefix and a function traceback; parse errors keep their
// existing `... @ row,col` form (the parser has no module trace yet).
procedure PrintErr(const s: fun.str);
var
  t: fun.str;
begin
  try
    if not isLog then exit;
    WriteErr(ErrPos + s + sLineBreak);
    if _ENV <> nil then
    begin
      t := _ENV.traceBack;
      if t <> '' then WriteErr(t);
    end;
  except
  end;
end;

// Functions
procedure Println(const s: fun.str); stdcall;
begin
  try
    if isLog then Writeln(s);
  except
    on E: EBase do
      Writeln(E.Message);
  end;
end;

procedure Print(const s: fun.str);
begin
  try
    // WriteOut (not the RTL Write) keeps stdout byte-exact on Windows; see its
    // comment in utils.pas. The `?.`/echo output is a byte stream.
    if isLog then WriteOut(s);
  except
    on E: EBase do
      Writeln(E.Message);
  end;
end;

procedure PrintVer();
{$IfDef UNIX}
const exeName = 'fun';
{$Else}
const exeName = 'fun.exe';
{$EndIf}
begin
  Println('');
  Println('Fun ' + funRelease + ', Copyright (c) 2026, https://funlang.org');
  Println('Usage:');
  Println('  ' + exeName + ' [-fun:]<file.fun or .foo/.fxx> [-key:<key.ini>] [-log[:<log.txt>]] [-gui] [-v]');
  Println('  ' + exeName + ' pack <file.fun> [-o <out>] [-a <file-or-dir>]  bundle into one executable');
  Println('');
end;

// ---------------------------------------------------------------- bundled app
// A packaged single-file app is this executable with a zip payload (STORE
// entries only) and a 16-byte trailer ('FUNBUNDL' + uint64 payload size)
// appended by fun/lib/tools/fun-pack.fun. UnpackBundle extracts the payload to
// a temp directory and returns the entry script's path; '' means "no bundle".
const
  _BundleMagic = 'FUNBUNDL';

var
  _BundleDir: fun.str;

// little-endian value of n (<= 8) bytes at at; -1 on a short read
function _LE(fs: TFileStream; at: Int64; n: Integer): Int64;
var
  b: array[0..7] of Byte;
  i: Integer;
begin
  result := 0;
  if n > 8 then n := 8;
  fs.Position := at;
  if fs.Read(b, n) <> n then begin result := -1; exit; end;
  for i := n - 1 downto 0 do
    result := (result shl 8) or b[i];
end;

function _ReadStr(fs: TFileStream; at: Int64; n: Integer): fun.str;
var
  s: fun.str;
begin
  s := '';
  if n <= 0 then begin result := s; exit; end;
  SetLength(s, n);
  fs.Position := at;
  if fs.Read(s[1], n) <> n then s := '';
  result := s;
end;

function _TrimRel(s: fun.str): fun.str;
begin
  result := s;
  while (result <> '') and ((result[Length(result)] = #13) or
        (result[Length(result)] = #10) or (result[Length(result)] = ' ')) do
    SetLength(result, Length(result) - 1);
end;

procedure _DeleteTree(const dir: fun.str);
var
  sr: TSearchRec;
  p: fun.str;
begin
  p := IncludeTrailingPathDelimiter(dir);
  if FindFirst(p + '*', faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Name <> '.') and (sr.Name <> '..') then
      begin
        if (sr.Attr and faDirectory) <> 0 then
          _DeleteTree(p + sr.Name)
        else
          DeleteFile(p + sr.Name);
      end;
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  RemoveDir(dir);
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
  fs, fo: TFileStream;
  size, zipStart, zipLen, i, ents, cd, p, method, nl, xl, cl, loff,
  dataOff, csize, left, got, stopAt, cdOfs: Int64;
  tmp, name, rel, dest: fun.str;
  buf: array[0..65535] of Byte;
  marker, failed: fun.bool;
begin
  result := '';
  if not FileExists(exe) then exit;
  fs := TFileStream.Create(exe, fmOpenRead or fmShareDenyNone);
  fo := nil;
  try
    size := fs.Size;
    if size < 64 then exit;
    if _ReadStr(fs, size - 16, 8) <> _BundleMagic then exit;
    zipLen := _LE(fs, size - 8, 8);
    if (zipLen <= 0) or (zipLen > size - 16) then exit;
    zipStart := size - 16 - zipLen;
    cd := -1;
    i  := zipStart + zipLen - 22;
    stopAt := i - 65557;              // EOCD + max archive comment
    if stopAt < zipStart then stopAt := zipStart;
    while i >= stopAt do
    begin
      if _LE(fs, i, 4) = $06054B50 then begin cd := i; break; end;
      Dec(i);
    end;
    if cd < 0 then exit;
    ents  := _LE(fs, cd + 10, 2);
    cdOfs := _LE(fs, cd + 16, 4);
    if (ents < 0) or (cdOfs < 0) or (cdOfs >= zipLen) then exit;
    p     := zipStart + cdOfs;
    tmp  := IncludeTrailingPathDelimiter(GetTempDir) + 'fun-pack-' + IntToStr(GetTickCount);
    while DirectoryExists(tmp) do tmp := tmp + 'x';
    ForceDirectories(tmp);
    _BundleDir := tmp;
    marker := false;
    failed := false;
    for i := 0 to ents - 1 do
    begin
      if _LE(fs, p, 4) <> $02014B50 then begin failed := true; break; end;
      method := _LE(fs, p + 10, 2);
      csize  := _LE(fs, p + 20, 4);
      nl     := _LE(fs, p + 28, 2);
      xl     := _LE(fs, p + 30, 2);
      cl     := _LE(fs, p + 32, 2);
      loff   := _LE(fs, p + 42, 4);
      name   := _ReadStr(fs, p + 46, nl);
      if method <> 0 then begin failed := true; break; end;
      if (csize < 0) or (nl < 0) or (loff < 0) or (loff >= zipLen) then
      begin failed := true; break; end;
      dataOff := zipStart + loff + 30 + _LE(fs, zipStart + loff + 26, 2)
                                    + _LE(fs, zipStart + loff + 28, 2);
      if (dataOff < zipStart) or (dataOff + csize > zipStart + zipLen) then
      begin failed := true; break; end;
      if name = '.funpack/entry' then
      begin
        rel    := _TrimRel(_ReadStr(fs, dataOff, csize));
        marker := rel <> '';
      end
      else
      begin
        dest := _SafeRel(name);
        if dest <> '' then
        begin
          dest := tmp + PathDelim + dest;
          if ExtractFileDir(dest) <> '' then ForceDirectories(ExtractFileDir(dest));
          fo := TFileStream.Create(dest, fmCreate);
          fs.Position := dataOff;
          left := csize;
          while left > 0 do
          begin
            got := left; if got > SizeOf(buf) then got := SizeOf(buf);
            fs.Read(buf, got);
            fo.Write(buf, got);
            left := left - got;
          end;
          FreeAndNil(fo);
        end;
      end;
      p := p + 46 + nl + xl + cl;
    end;
    if fo <> nil then FreeAndNil(fo);
    if marker and not failed then
      result := tmp + PathDelim + _SafeRel(rel)
    else
    begin
      _DeleteTree(tmp);
      _BundleDir := '';
    end;
  finally
    fs.Free;
  end;
end;

// "funcmd pack": run the bundler tool that ships next to the runtime. A release
// tree keeps it in <exe>/lib/tools; a development build lives in src/prj/fun,
// three levels below the repository root.
function FindPackTool: fun.str;
const
  _rel = 'lib' + PathDelim + 'tools' + PathDelim + 'fun-pack.fun';
begin
  result := ExtractFilePath(ParamStr(0)) + _rel;
  if FileExists(result) then exit;
  result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + '..' + PathDelim +
            '..' + PathDelim + 'fun' + PathDelim + _rel;
  if FileExists(result) then exit;
  result := 'fun' + PathDelim + _rel;
  if FileExists(result) then exit;
  result := ExtractFilePath(ParamStr(0)) + _rel;   // reported when nothing was found
end;

// CFunParser
procedure CFunParser.DoError(const s: fun.str);
begin
  hadError := true;
  PrintErr(s);
end;

// CFunRunner
procedure CFunRunner.echo(const s: fun.str);
begin
  Print(s);
end;

function CFunRunner.clone: CEnv;
begin
  result := CFunRunner.create;
end;

// var
var
  r: CFunRunner;
  p: fun.ptr;
  f: fun.str;
{$IfDef FunStartupTiming}
  fs: fun.str;
{$EndIf}

{$IfDef FunDll}

function Run(arg: fun.int): fun.int; stdcall;
var
  v: CVar;
begin
  result := 1;
  if arg = -1 then
  begin // Free
    try
      del(p);
      del(r);
    except
      result := 0;
    end;
  end
  else if p = nil then
  begin // Compile
    if arg = 0 then // Fun script in dll
      f := GetModuleName(HInstance)
    else
    begin
      try
        f := fun.str(PChar(fun.ptr(arg)));
        if not FileExists(f) then f := OleStrToString(fun.ptr(arg));
      except
        f := OleStrToString(fun.ptr(arg));
      end;
    end;
    _ParserClass := CFunParser;
    try
      if FileExists(f) then
        p := CFunParser.ParseOrLoad(f)
      else
        p := CFunParser.Parse(f, CFunParser)
      ;
    except
      result := 0;
    end;
  end
  else
  begin // Run
    try
      v := CRuns(p).ID[_AT];
      if v = nil then v := CVar.new(CRuns(p), _AT);
      v.assign(arg);

      v := CRuns(p).ID[_AT + _AT];
      if v = nil then v := CVar.new(CRuns(p), _AT + _AT);
      v.assign(f);
    except
    end;
    if r = nil then
    begin
      r := CFunRunner.Create;
      _ENV := r;
    end;
    try
      CRun(p).run(r);
    except
      result := 0;
    end;
  end;
end;

exports Run;

{$Else}

  v, gui: fun.bool;
  log, fnGiven: fun.str;
  hlog: fun.int;

  {$IfDef _C_}
  key: fun.str;
  {$EndIf}

label
  _Run, _Exit, _Error;

{$EndIf}

{$IfDef CPUAARCH64}{$IfDef LINUX}
// glibc >= 2.34 removed __libc_csu_init / __libc_csu_fini, but FPC 3.2.2's
// aarch64-linux cprt0.o still references them (undefined reference at link
// time on e.g. ubuntu-24.04). Modern glibc runs .init_array itself, so empty
// definitions satisfy the linker without changing behaviour.
procedure __libc_csu_init(argc: longint; argv, envp: pointer); cdecl;
  public name '__libc_csu_init';
begin
end;

procedure __libc_csu_fini; cdecl;
  public name '__libc_csu_fini';
begin
end;
{$EndIf}{$EndIf}

begin
{$IfDef FunStartupTiming}{$IfNdef FunDll}
  TimeMark('main');
{$EndIf}{$EndIf}
{$IfNdef FunDll}
{$IfDef FPC}{$IfNDef UNIX}
  // FPC initialises its default datetime/number formats from the OS locale on
  // Windows, while on Unix it has no locale support and keeps the built-in
  // values (ShortDateFormat 'd/m/y', DateSeparator '-', DecimalSeparator '.').
  // Fun renders a date through that default (Variant -> AnsiString), so the
  // same line printed "7/18/2010 15:35:15" here and "18-7-10 15:35:15" on
  // Linux, and the shared snapshots could not match. Pin the Unix defaults so
  // date/number output (and the StrToDateTime-based FD parsing) is
  // host-independent. Delphi keeps the OS locale.
  DefaultFormatSettings.DateSeparator     := '-';
  DefaultFormatSettings.TimeSeparator     := ':';
  DefaultFormatSettings.ShortDateFormat   := 'd/m/y';
  DefaultFormatSettings.LongDateFormat    := 'dd" "mmmm" "yyyy';
  DefaultFormatSettings.ShortTimeFormat   := 'hh:nn';
  DefaultFormatSettings.LongTimeFormat    := 'hh:nn:ss';
  DefaultFormatSettings.DecimalSeparator  := '.';
  DefaultFormatSettings.ThousandSeparator := ',';
{$EndIf}{$EndIf}
  _ParserClass := CFunParser;

  gui   := FindParamAsBool('gui');
  v     := FindParamAsBool('v'  ) or FindParamAsBool('?');
  log   := FindParam(      'log');
  {$IfDef FunStartupTiming}
  TimeMark('params');
  {$EndIf}
  // A named script means a command-line run, even where no console is attached
  // (stdout redirected to a file, a CI runner, a scheduled task). FindCmdLine
  // only detects a parent console via AttachConsole, which is false in those
  // cases, so without this a redirected run was mistaken for a GUI launch and
  // printed nothing (isLog stayed false). Unix FindCmdLine is always true.
  if not gui then gui := (not FindCmdLine) and (FindParam('fun', 1) = '');
  {$IfDef FunStartupTiming}
  TimeMark('cmdline');
  {$EndIf}
  isLog := not gui or (log <> '');

  hlog := 0;
  if isLog and gui then
  begin
    if log = 'true' then log := ParamStr(0) + '.log';
    hlog := SetStdOut(log);
  end;

  if v then PrintVer();

  p   := nil;
  // a packaged app carries its script payload in this executable's tail; in
  // that mode every command-line argument belongs to the script
  f := UnpackBundle(ParamStr(0));
  if f <> '' then
  begin
    ArgScript := f;
    ArgShift  := -1;
    SetCurrentDir(_BundleDir); // relative imports/resources resolve inside the bundle
    goto _Run;
  end;
  // "funcmd pack <entry.fun> [-o <out>]": run the bundler tool. The subcommand
  // takes the script's argv slot, so the tool still sees 1.arg() = its own
  // path and 2.arg() = the first real argument.
  if ParamStr(1) = 'pack' then
  begin
    f := FindPackTool();
    fnGiven := f;
    if not FileExists(f) then goto _Error;
    ArgScript := f;
    goto _Run;
  end;

  f   := FindParam('fun', 1);
  fnGiven := f;
  // A named-but-missing script is a user error (non-zero exit).
  if (f <> '') and not FileExists(f) then goto _Error;
  if (f = '') or not FileExists(f) then
  begin
    // No script argument: a shipped app sits next to its own "<exe>.fun".
    if FileExists(ChangeFileExt(ParamStr(0), '.fun')) then
    begin
      f := ChangeFileExt(ParamStr(0), '.fun');
      goto _Run;
    end;

_Error:
    // A named-but-missing script file is an error (non-zero exit): say which
    // file was not found. No argument at all is a help request: print the usage
    // and exit 0. (Running with no file used to try the executable itself as a
    // script, which only produced a syntax error from its ELF/PE/Mach-O header.)
    if fnGiven <> '' then
    begin
      hadError := true;
      PrintErr('not found: ' + fnGiven);
    end
    else if not v then PrintVer();
    goto _Exit;
  end;

  {$IfDef _C_}
  key := FindParam('key');
  if key <> '' then ParseKeyAlias(key);
  {$EndIf}


_Run:
  {$IfDef FunStartupTiming}
  TimeMark('cli-ready');
  {$EndIf}
  r := CFunRunner.Create;
  _ENV := r;
  r.resetTrace;
  {$IfDef FunStartupTiming}
  TimeMark('env-ready');
  {$EndIf}

  try
    InitTick;
    if p = nil then
    begin
      {$IfDef FunStartupTiming}
      fs := CIO.Load(f);
      TimeMark('loaded');
      p := CFunParser.Parse(fs, CFunParser, f);
      {$Else}
      p := CFunParser.ParseOrLoad(f);
      {$EndIf}
    end;
    {$IfDef FunStartupTiming}
    TimeMark('parsed');
    {$EndIf}
    if v then
    begin
      Println('--------------------------------');
      Println('Compiled, time: ' + IntToStr(GetTick) + ' ms');
      Println('--------------------------------');
    end;
    CRun(p).run(r);
    {$IfDef FunStartupTiming}
    TimeMark('executed');
    {$EndIf}
    if v then
    begin
      Println('--------------------------------');
      Println('Finished, time: ' + IntToStr(GetTick) + ' ms');
      Println('--------------------------------');
    end;
  except
    on E: EBase do
      begin
        hadError := true;
        {$IfDef FunStartupTiming}
        TimeMark('error');
        DumpProfile;
        {$EndIf}
        PrintErr(E.Message);
      end;
  end;

  try
    del(p);
    {$IfDef FunStartupTiming}
    TimeMark('ast-freed');
    {$EndIf}
    del(r);
    {$IfDef FunStartupTiming}
    TimeMark('env-freed');
    {$EndIf}
  except
  end;

_Exit:
  if _BundleDir <> '' then _DeleteTree(_BundleDir);
  if hadError then ExitCode := 1;
  try
    if isLog then
    begin
      Flush(Output);
      {$IfDef FunStartupTiming}
      TimeMark('flushed');
      {$EndIf}
      // hlog is 0 when no -log file was opened. FileClose(0) would close
      // whatever the RTL has in slot 0 instead of doing nothing.
      if hlog <> 0 then CIO.Close(hlog);
    end;
    {$IfDef FunStartupTiming}
    // FreeCmdLine -> FreeConsole closes the stderr handle on Windows, so the
    // buffered profile must be written while the console is still attached.
    TimeMark('cleanup');
    {$EndIf}
    if not gui then FreeCmdLine;
  except
  end;

{$EndIf}
end.
