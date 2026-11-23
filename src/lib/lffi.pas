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
unit lffi;

// Unix FFI: load a native shared object and call an exported function by
// signature, backed by libffi (FPC's bundled `ffi` unit). This is the Unix
// counterpart of the Windows winapi unit. winapi.pas stays Windows-only and is
// isolated behind the WinAPI define; this unit is built only for Unix hosts
// (Linux with -dLinuxFFI, macOS with -dDarwinFFI), which the engine exposes as
// the single UnixFFI symbol.

interface

// libffi is linked explicitly: FPC does not always surface the library name
// recorded by the bundled ffi unit (its externals use a const, `external 'ffi'`),
// and the darwin cross link needs -lffi against the seeded libffi.tbd stub.
// Windows needs none of that: FPC writes the import table for 'ffi' (i.e.
// ffi.dll, which the build places next to funcmd.exe) itself, so a LINKLIB here
// would only ask for a libffi.a that does not exist.
{$IfNDef MSWINDOWS}{$LINKLIB ffi}{$EndIf}

uses fun, base, core, host,
     dynlibs,
     ffi;

type
  // FPC's bundled ffi unit declares ffi_cif without the target-specific tail
  // fields some libffi targets add (riscv64 appends riscv_nfixedargs and
  // riscv_unused, making the native struct 40 bytes instead of 32). libffi's
  // ffi_prep_cif writes the full native struct, so hand it a buffer with
  // headroom instead of trusting SizeOf(ffi_cif); otherwise the tail lands in
  // whatever follows the record and corrupts it.
  TCif = record
    cif: ffi_cif;
    extra: array[1..16] of Byte;
  end;

  // NUL-terminated UCS-4 buffer for the Unix wide-string ('w') FFI path; each
  // element is one wchar_t (4 bytes on Linux and macOS).
  TUCS4 = array of LongWord;

  // Handler added to env.libs: routes calls on a getapi() result object.
  CLffiApi = class(CLib)
  public
    function accept(exp: CExp): fun.bool; override;
    function call(env: CEnv; exp: CExp; const id: fun.str; exps: CExps; val: PValue; ct: fun.byte = CDoMethod): fun.bool; override;
  end;

  // A resolved native function; the value returned by f.getapi(...).
  CFFIFun = class(CExp)
  private
    flag: fun.str;     // type string, e.g. 'ss:i'
    nfix: Integer;     // variadic bindings: fixed-argument count (>0)
    hfun: fun.ptr;     // symbol address (dlsym result)
    hlib: TLibHandle;  // dlopen handle (released on destroy)
  public
    constructor Create(alib: TLibHandle; afun: fun.ptr; const atype: fun.str; anfix: Integer = 0);
    destructor Destroy; override;
    function call(env: CEnv; exps: CExps): PValue; override;
  end;

  // A Fun function wrapped as a native callable via a libffi closure. Returned
  // by f.@toCallback(type) and handed to C functions that take a function
  // pointer (matched in getapi() with a 'c' argument type).
  CFFICallback = class(CCallObj)
  private
    FClos: Pointer;         // libffi closure block (freed on destroy)
    FCode: Pointer;         // executable entry point returned to C
    FTypes: fun.str;        // '<argchars...>:<retchar>' from @toCallback
    FArgs: fun.str;         // argument type chars
    FRet: Char;             // return type char
    FCif: TCif;             // kept alive for the whole closure lifetime
    FAt: array of Pffi_type;// closure arg types (persisted for the cif)
    FStr: AnsiString;       // keeps the last string return alive
    FWide: TUCS4;             // keeps the last wchar_t* return alive
    function Build: Pointer;
    function GetProc: Pointer;
  protected
    function Parse(exp: CExp; exps: CExps; theEnv: CEnv): CFFICallback;
  public
    destructor Destroy; override;
    procedure Invoke(cif: Pffi_cif; resp: Pointer; args: PPointer);
    property Proc: Pointer read GetProc;
  end;

procedure _lgetapi(env: CEnv; exp: CExp; exps: CExps; val: PValue);
procedure _ltoCallback(env: CEnv; exp: CExp; exps: CExps; val: PValue);

implementation

uses SysUtils;

type PValue = base.PValue;

{$IfDef Linux}
// dlopen(NULL, ...) returns a handle for the main program, whose symbol scope
// includes libc and every dependency the executable already loaded. This is
// the portable fallback for a C-library name that has no shared object on the
// host: musl ships no libc.so.6 (only libc.musl-<cpu>.so.1), so the stdlib's
// `'libc.so.6'.getapi(...)` would otherwise fail on Alpine even though libc is
// linked in. FPC's dynlibs takes a file name ('' is not NULL), so call the
// loader directly; FPC's RTL already imports dlopen, so no extra -l is needed.
function c_dlopen(filename: PAnsiChar; flags: Integer): Pointer; cdecl; external name 'dlopen';
const
  C_RTLD_NOW = 2;
var
  _selflib: TLibHandle = NilHandle;
  _selflibTried: Boolean = False;

function ResolveGlobal(const name: string): fun.ptr;
begin
  result := nil;
  if name = '' then exit;
  if not _selflibTried then
  begin
    _selflibTried := True;
    _selflib := TLibHandle(c_dlopen(nil, C_RTLD_NOW));
  end;
  if _selflib <> NilHandle then
    result := fun.ptr(GetProcedureAddress(_selflib, name));
end;

// Only names whose symbols live in the process image may fall back to the
// global scope. An arbitrary missing library still reports the load error
// instead of silently using a same-named symbol from somewhere else.

// True for the tail that may follow a library stem: nothing, '.so' or
// '.so.<digits>'. A plain prefix test on 'libc.so' would also accept
// 'libc.something' and route an unrelated library into the process-image
// fallback.
function IsSoSuffix(const tail: string): Boolean;
var
  i: Integer;
begin
  if (tail = '') or (tail = '.so') then exit(True);
  if (Copy(tail, 1, 4) <> '.so.') or (Length(tail) = 4) then exit(False);
  for i := 5 to Length(tail) do
    if not (tail[i] in ['0'..'9']) then exit(False);
  result := True;
end;

function IsLibSoName(const name, stem: string): Boolean;
begin
  result := (Copy(name, 1, Length(stem)) = stem)
        and IsSoSuffix(Copy(name, Length(stem) + 1, MaxInt));
end;

// Drop a trailing '.so' / '.so.N' so LoadLibCandidates re-adds the versioned
// soname instead of trying names like libz.so.so.
function StripSoSuffix(const name: string): string;
var
  i: Integer;
begin
  result := name;
  for i := Length(name) - 2 downto 1 do
    if (name[i] = '.') and (name[i + 1] = 's') and (name[i + 2] = 'o')
       and IsSoSuffix(Copy(name, i, MaxInt)) then
      exit(Copy(name, 1, i - 1));
end;

// True for an explicit ABI version ('.so.<digits>'), as opposed to the
// unversioned '.so' linker name or a bare stem.
function HasSoVersion(const name: string): Boolean;
begin
  result := (Length(name) - Length(StripSoSuffix(name))) > Length('.so');
end;

function IsGlobalLibName(const name: string): Boolean;
begin
  result := (name = '')
         or IsLibSoName(name, 'libc')
         or (Copy(name, 1, 10) = 'libc.musl-') or (Copy(name, 1, 8) = 'ld-musl-')
         or IsLibSoName(name, 'libm')
         or IsLibSoName(name, 'libdl')
         or IsLibSoName(name, 'libpthread')
         or IsLibSoName(name, 'librt')
         or IsLibSoName(name, 'libutil');
end;
{$EndIf}

{$IfNDef MSWINDOWS}
// Extensions tried for a bare name (no path and no known extension). A runtime
// package usually carries only the versioned soname (libz.so.1; libz.so lives
// in the -dev package), so 'libz' must find libz.so.1 as well.
function LoadLibCandidates(const base: string): TLibHandle;
const
  {$IfDef Darwin}
  exts: array[0..5] of string = ('', '.dylib', '.1.dylib', '.2.dylib', '.3.dylib', '.4.dylib');
  {$Else}
  exts: array[0..9] of string = ('', '.so', '.so.1', '.so.0', '.so.2', '.so.3',
                                 '.so.4', '.so.5', '.so.6', '.so.8');
  {$EndIf}
var
  i: Integer;
  stem: string;
begin
  // 'libz.so'/'libz.so.1' are common spellings of a bare name; probing them
  // as-is would append another suffix and try libz.so.so.
  {$IfDef Linux}
  stem := StripSoSuffix(base);
  {$Else}
  stem := base;
  {$EndIf}
  // An explicit ABI version is a hard requirement. Only the exact soname the
  // caller named, or the plain stem and the unversioned '.so' link, may
  // satisfy it; probing the rest of exts would silently substitute another
  // major version.
  {$IfDef Linux}
  if HasSoVersion(base) then
  begin
    result := LoadLibrary(base);
    if result <> NilHandle then exit;
    result := LoadLibrary(stem);
    if result <> NilHandle then exit;
    result := LoadLibrary(stem + '.so');
    exit;
  end;
  {$EndIf}
  for i := Low(exts) to High(exts) do
  begin
    result := LoadLibrary(stem + exts[i]);
    if result <> NilHandle then exit;
  end;
  result := NilHandle;
end;
{$EndIf}

// Fun strings are UTF-8 bytes on every Unix host, while wchar_t is a 4-byte
// UCS-4 code unit on both Linux and macOS. The 'w' signature converts at the
// boundary, so wide C APIs (wcslen, wcscmp, ...) get a real wchar_t* instead
// of a char* reinterpreted as one. Win64's lffi keeps the old narrow
// behaviour: there wchar_t is 2-byte UTF-16, which needs a different encoder.
function Utf8ToUCS4(const s: AnsiString): TUCS4;
var
  i, j, n, k, need: Integer;
  c: LongWord;
  b: Byte;
  ok: Boolean;
begin
  n := Length(s);
  SetLength(result, n + 1);
  i := 1;
  j := 0;
  while i <= n do
  begin
    b := Byte(s[i]);
    if b < $80 then
    begin
      c := b; need := 0; inc(i);
    end
    else if (b and $E0) = $C0 then
    begin
      c := b and $1F; need := 1; inc(i);
    end
    else if (b and $F0) = $E0 then
    begin
      c := b and $0F; need := 2; inc(i);
    end
    else if (b and $F8) = $F0 then
    begin
      c := b and $07; need := 3; inc(i);
    end
    else
    begin
      c := $FFFD; need := 0; inc(i);
    end;
    ok := True;
    for k := 1 to need do
    begin
      if (i > n) or ((Byte(s[i]) and $C0) <> $80) then
      begin
        ok := False;
        break;
      end;
      c := (c shl 6) or (Byte(s[i]) and $3F);
      inc(i);
    end;
    if (not ok) or (c > $10FFFF) or ((c >= $D800) and (c <= $DFFF)) then
      c := $FFFD;
    result[j] := c;
    inc(j);
  end;
  result[j] := 0;
  SetLength(result, j + 1);
end;

function UCS4ToUtf8(p: PLongWord): AnsiString;
var
  c: LongWord;
  i: Integer;
  s: AnsiString;
begin
  s := '';
  if p <> nil then
  begin
    i := 0;
    while True do
    begin
      c := PLongWord(PByte(p) + i * SizeOf(LongWord))^;
      if c = 0 then break;
      inc(i);
      if (c > $10FFFF) or ((c >= $D800) and (c <= $DFFF)) then c := $FFFD;
      if c < $80 then
        s := s + AnsiChar(c)
      else if c < $800 then
        s := s + AnsiChar($C0 or (c shr 6)) + AnsiChar($80 or (c and $3F))
      else if c < $10000 then
        s := s + AnsiChar($E0 or (c shr 12)) + AnsiChar($80 or ((c shr 6) and $3F))
               + AnsiChar($80 or (c and $3F))
      else
        s := s + AnsiChar($F0 or (c shr 18)) + AnsiChar($80 or ((c shr 12) and $3F))
               + AnsiChar($80 or ((c shr 6) and $3F)) + AnsiChar($80 or (c and $3F));
    end;
  end;
  result := s;
end;

// FPC 3.2.2's bundled ffi unit hardcodes the pre-3.4 libffi enum, where
// x86_64-linux FFI_UNIX64 = 1. libffi >= 3.4 (Debian 12+, Ubuntu 22.04+,
// recent Fedora/RHEL) inserts FFI_SYSV before FFI_UNIX64, so the value the
// loaded libffi accepts there is 2; passing 1 returns FFI_BAD_ABI. Probe
// once at runtime and cache: new libffi first (2), old libffi second (1),
// the unit's own FFI_DEFAULT_ABI last. Keeps CentOS 7 (libffi 3.0.13) and
// modern distros on the same binary.
//
// Only x86_64 needs the probe. Elsewhere FPC's enum already matches libffi,
// and probing 2 can be wrong: riscv64 accepts 1..4 and treats 2 as
// FFI_UNUSED_1, so the probe would cache an unused ABI.
var
  _cif_abi: Integer = -1;

function cifABI: ffi_abi;
{$IfDef CPUX86_64}
var
  cif: TCif;
  at: array[0..0] of Pffi_type;
{$EndIf}
begin
{$IfDef CPUX86_64}
  if _cif_abi < 0 then
  begin
    at[0] := @ffi_type_pointer;
    if      ffi_prep_cif(@cif.cif, ffi_abi(2), 1, @ffi_type_pointer, @at) = FFI_OK then _cif_abi := 2
    else if ffi_prep_cif(@cif.cif, ffi_abi(1), 1, @ffi_type_pointer, @at) = FFI_OK then _cif_abi := 1
    else _cif_abi := Ord(FFI_DEFAULT_ABI);
  end;
{$Else}
  _cif_abi := Ord(FFI_DEFAULT_ABI);
{$EndIf}
  result := ffi_abi(_cif_abi);
end;

// f.getapi(name, type)
procedure _lgetapi(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  libname, name: fun.str;
  hlib: TLibHandle;
  hfun: fun.ptr;
  f: CFFIFun;
  e: CExp;
begin
  {$IfDef FunSafe}
  SafeDeny('getapi native call');
  {$EndIf}
  // exp is the shared object name (or '' when calling a raw address); the
  // optional named arg 'name' is the exported symbol to resolve.
  libname := exp.asStr;
  hlib := NilHandle;
  if libname <> '' then
  begin
    hlib := LoadLibrary(libname);
    // bare name, e.g. 'libc' on Unix or 'kernel32' on Windows: try the
    // platform's library suffix. On Linux a versioned spelling ('libz.so.1')
    // is normalized inside LoadLibCandidates, where an explicit version only
    // falls back to the plain stem and '.so', never to another major. Other
    // Unix hosts treat a '.so' spelling as exact.
    if (hlib = NilHandle) and (Pos('/', libname) = 0) and (Pos('\', libname) = 0)
       and (Pos('.dylib', libname) = 0) and (Pos('.dll', libname) = 0)
       {$IfNDef Linux} and (Pos('.so', libname) = 0) {$EndIf} then
      {$IfDef MSWINDOWS}
      hlib := LoadLibrary(libname + '.dll')
      {$Else}
      hlib := LoadLibCandidates(libname)
      {$EndIf};
  end;

  hfun := nil;
  name := '';
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
    if name = '' then
    begin
      if hlib = NilHandle then
        raise EBase.Create('getapi: cannot load library "' + libname + '"');
      raise EBase.Create('getapi: no symbol name for library "' + libname + '"');
    end;
    if hlib <> NilHandle then
    begin
      hfun := fun.ptr(GetProcedureAddress(hlib, name));
      {$IfDef MSWINDOWS}
      // Windows exports most of these with an A/W suffix (GetCommandLineA) while
      // the Fun-side names are unsuffixed (GetCommandLine), which is exactly what
      // io.GetProc handles for the Delphi path: retry with the suffix before
      // giving up. The narrow 's'/'i' convention means the ANSI entry point is
      // the one wanted, and an explicit 'nameW' still resolves directly.
      if hfun = nil then
        hfun := fun.ptr(GetProcedureAddress(hlib, name + 'A'));
      {$EndIf}
    end
    {$IfDef Linux}
    else if IsGlobalLibName(libname) then
      // No shared object with this name (musl has no libc.so.6): the symbol is
      // already in the process image, so resolve it from there.
      hfun := ResolveGlobal(name)
    {$EndIf};
    if hfun = nil then
    begin
      if hlib = NilHandle then
        raise EBase.Create('getapi: cannot load library "' + libname + '"')
      else
        raise EBase.Create('getapi: symbol "' + name + '" not found in "' + libname + '"');
    end;
  end;

  // 'variadic: <n>' marks a variadic symbol: n arguments are fixed, the rest
  // form the tail (idx 99 = no positional fallback, named only).
  f := CFFIFun.Create(hlib, hfun, CExps.FindAsVal(exps, 'type', 1, ''),
                      CExps.FindAsVal(exps, 'variadic', 99, 0));
  setObj(val, f, VarObjNew); del(f);
end;

//==============================================================
function CLffiApi.accept(exp: CExp): fun.bool;
begin
  result := exp.asObj is CFFIFun;
end;

function CLffiApi.call(env: CEnv; exp: CExp; const id: fun.str; exps: CExps; val: PValue; ct: fun.byte = CDoMethod): fun.bool;
begin
  // id = 'call'
  // x.call(...)
  // x(...)
  val^ := CFFIFun(exp.asObj).call(env, exps)^;
  result := true;
end;

//==============================================================
constructor CFFIFun.Create(alib: TLibHandle; afun: fun.ptr; const atype: fun.str; anfix: Integer = 0);
begin
  inherited new(nil);
  hlib := alib;
  hfun := afun;
  flag := atype;
  nfix := anfix;
end;

destructor CFFIFun.Destroy;
begin
  if hlib <> NilHandle then UnloadLibrary(hlib);
  inherited Destroy;
end;

type
  TFnProc = procedure; register; // generic callable address for libffi

function CFFIFun.call(env: CEnv; exps: CExps): PValue;
var
  e: CExp;
  n, i: Integer;
  cif: TCif;
  st: ffi_status;
  at: array of Pffi_type;
  av: array of Pointer;
  slots: array of QWord;
  refs: array of QWord;
  byref: array of Boolean;
  strs: array of AnsiString;
  wstrs: array of TUCS4;
  ch, rt: Char;
  ret: QWord;
  rtype: Pffi_type;
begin
  if CExps.count(exps) = 1 then
  begin
    e := exps.Item[0];
    if e.asObj is CSet then exps := CSet(e.asObj).items;
  end;

  n := CExps.count(exps);
  SetLength(at, n); SetLength(av, n); SetLength(slots, n);
  SetLength(refs, n); SetLength(byref, n);
  SetLength(strs, n);
  SetLength(wstrs, n);

  // Build one 8-byte slot per argument; libffi reads from it. Integer/pointer
  // and the string forms pass as GPR values (ffi_type_pointer), doubles route
  // through the SSE register file (ffi_type_double). Each slot is 8 bytes and
  // 8-aligned, so both kinds fit in the same QWord array.
  for i := 0 to n - 1 do
  begin
    at[i] := @ffi_type_pointer;
    slots[i] := 0;
    av[i] := @slots[i];
    e := CExp(exps.Item[i]);
    ch := flag[i + 1];
    // A bare `var x` with a pointer type is an OUT/INOUT parameter. win32's
    // winapi.pas passes the address of the value for 'p'; do the same through
    // a pointer-width scratch cell and copy the result back after the call.
    // Without this, lffi sent x's value (often 0 = NULL) and the callee
    // reported STATUS_INVALID_PARAMETER (e.g. BCryptOpenAlgorithmProvider).
    byref[i] := (e is CRef) and (ch = 'p')
                and not isStr(e.value) and (e.asObj = nil);
    if byref[i] then
    begin
      if isNum(e.value) then refs[i] := QWord(e.value^) else refs[i] := 0;
      slots[i] := QWord(fun.uintptr(@refs[i]));
      Continue;
    end;
    case ch of
      's', 'a', 'r':
        begin
          strs[i] := AnsiString(e.asStr);
          if strs[i] <> '' then slots[i] := QWord(fun.uintptr(@strs[i][1]));
        end;
      'w':
        // Win64's lffi keeps passing the string bytes (wchar_t is UTF-16
        // there); on Unix wchar_t is 4-byte UCS-4, so convert explicitly.
        {$IfDef MSWINDOWS}
        begin
          strs[i] := AnsiString(e.asStr);
          if strs[i] <> '' then slots[i] := QWord(fun.uintptr(@strs[i][1]));
        end;
        {$Else}
        begin
          wstrs[i] := Utf8ToUCS4(AnsiString(e.asStr));
          slots[i] := QWord(fun.uintptr(@wstrs[i][0]));
        end;
        {$EndIf}
      'c': // callback: pass a Fun callback's native entry point
        begin
          if e.asObj is CFFICallback then slots[i] := QWord(fun.uintptr(CFFICallback(e.asObj).Proc))
          else if isNum(e.value, true) then slots[i] := QWord(e.value^)
          else if e.asObj <> nil then slots[i] := QWord(fun.uintptr(e.asObj));
        end;
      'f': // single (float32) argument (SSE)
        begin
          at[i] := @ffi_type_float;
          if isNum(e.value, true) then PSingle(@slots[i])^ := Double(e.value^)
          else PSingle(@slots[i])^ := 0;
        end;
      'd': // double argument (SSE)
        begin
          at[i] := @ffi_type_double;
          if isNum(e.value, true) then PDouble(@slots[i])^ := Double(e.value^)
          else PDouble(@slots[i])^ := 0;
        end;
      'n', 'i', 'l':
        begin
          if isNum(e.value) then slots[i] := QWord(e.value^)
          else if e.asObj <> nil then slots[i] := QWord(fun.uintptr(e.asObj));
        end;
      'p':
        begin
          if isStr(e.value) then
            slots[i] := QWord(fun.uintptr(Pointer(AnsiString(e.asStr))))
          else if isNum(e.value) then
            slots[i] := QWord(e.value^)
          else if e.asObj <> nil then
            slots[i] := QWord(fun.uintptr(e.asObj));
        end;
      else // 'v', 'c' -> 0
        slots[i] := 0;
    end;
  end;

  // select the libffi return type from the last type char
  rt := flag[Length(flag)];
  case rt of
    'f': rtype := @ffi_type_float;
    'd': rtype := @ffi_type_double;
    'v': rtype := @ffi_type_void;
  else rtype := @ffi_type_pointer; // incl. 'w' (degrades to narrow char*)
  end;
  if (nfix >= 1) and (nfix < n) then
  begin
    // Variadic binding: tell libffi which leading arguments are fixed. On
    // Darwin arm64 the tail goes on the stack (Apple's AAPCS64), on the
    // SysV-family targets both forms behave alike. Fall back to the fixed
    // preparation if the loaded libffi refuses the variadic one.
    st := ffi_prep_cif_var(@cif.cif, cifABI, nfix, n, rtype, @at[0]);
    if st <> FFI_OK then st := ffi_prep_cif(@cif.cif, cifABI, n, rtype, @at[0]);
  end
  else
    st := ffi_prep_cif(@cif.cif, cifABI, n, rtype, @at[0]);
  if st <> FFI_OK then raise EBase.Create('getapi: ffi_prep_cif failed');

  ret := 0;
  if rt = 'v' then ffi_call(@cif.cif, TFnProc(hfun), nil, @av[0])
  else ffi_call(@cif.cif, TFnProc(hfun), @ret, @av[0]); // 8-byte resp buffer holds f/d too

  // Write pointer-sized OUT/INOUT values back into their `var` targets.
  for i := 0 to n - 1 do
    if byref[i] then
      CRef(CExp(exps.Item[i])).value^ := Int64(refs[i]);

  case rt of
    'f': p_val^ := PSingle(@ret)^;
    'd': p_val^ := PDouble(@ret)^;
    's', 'a', 'r': p_val^ := fun.str(PAnsiChar(fun.uintptr(ret)));
    {$IfDef MSWINDOWS}
    'w': p_val^ := fun.str(PAnsiChar(fun.uintptr(ret)));
    {$Else}
    'w': p_val^ := fun.str(UCS4ToUtf8(PLongWord(fun.uintptr(ret))));
    {$EndIf}
    'i'     : p_val^ := fun.int(LongInt(ret));      // C int (low 32 bits / eax)
    'l', 'n': p_val^ := Int64(ret);                 // C long / 64-bit number
    'v'     : p_val^ := NullValue;
  // 'p': Int64, not fun.uintptr. On non-Unicode builds isNum() does not accept
  // varUInt64, so an unsigned-64 result could not be fed back into another FFI
  // call (it silently passed 0). Int64 keeps the full 64-bit value and is
  // the same convention used for @toCallback(ptr: true) addresses.
  else     p_val^ := Int64(ret);                   // 'p' / default
  end;
  result := p_val;
end;

//==============================================================
// f.fn.@toCallback(obj, type, ptr)
//   type -> '<argchars...>:<retchar>', e.g. ':i', 'ii:i', 'd:d'
//   arg chars: i(nt32) l(ong64)/n(umber64) f(loat32) d(ouble) s/a/r(char*)
//              w(ide char*, converted to wchar_t on Unix) p/c(pointer)
//   ret chars: same plus v(void). Fun strings are UTF-8 on Unix, so a 'w'
//   argument is converted to a NUL-terminated UCS-4 buffer (wchar_t is 4 bytes
//   on Linux and macOS) and a 'w' return is converted back to UTF-8.
//   'C' is the Win32 cdecl convention marker; the SysV ABI is always cdecl, so
//   here it is accepted as an alias for 'i' (callbacks written for the Windows
//   lffi, such as lib-tcc's tcc_set_error_func, keep their int return).
//   cdecl (SysV) is always used.
procedure _ltoCallback(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  c: CFFICallback;
  e: CExp;
begin
  {$IfDef FunSafe}
  SafeDeny('native callback');
  {$EndIf}
  c := CFFICallback.Create.Parse(exp, exps, env);
  e := CExps.Find(exps, 'ptr', 2);
  if (e <> nil) and e.asBool then
    val^ := Int64(fun.uintptr(c.Proc)) // raw address escape hatch; object stays alive
  else
  begin
    setObj(val, c, VarObjNew); del(c);
  end;
end;

// libffi closure entry: native code calls FCode -> libffi trampoline -> this.
procedure CFFITrampoline(cif: Pffi_cif; resp: Pointer; args: PPointer; user: Pointer); cdecl;
begin
  if user <> nil then CFFICallback(user).Invoke(cif, resp, args);
end;

function CFFICallback.Parse(exp: CExp; exps: CExps; theEnv: CEnv): CFFICallback;
begin
  inherited parse(exp, exps, theEnv);
  FTypes := CExps.FindAsVal(exps, 'type', 1, '');
  result := self;
end;

destructor CFFICallback.Destroy;
begin
  if FClos <> nil then ffi_closure_free(FClos);
  FClos := nil;
  inherited Destroy;
end;

function CFFICallback.Build: Pointer;
var
  p, i: Integer;
  rtype: Pffi_type;
  st: ffi_status;
begin
  if FCode <> nil then exit(FCode);

  p := Pos(':', FTypes);
  if p = 0 then
  begin
    FArgs := '';
    FRet  := 'v';
  end
  else
  begin
    FArgs := Copy(FTypes, 1, p - 1);
    if p < Length(FTypes) then FRet := FTypes[p + 1] else FRet := 'v';
  end;

  SetLength(FAt, Length(FArgs));
  for i := 1 to Length(FArgs) do
    case FArgs[i] of
      'i': FAt[i - 1] := @ffi_type_sint32;
      'l', 'n': FAt[i - 1] := @ffi_type_sint64;
      'f': FAt[i - 1] := @ffi_type_float;
      'd': FAt[i - 1] := @ffi_type_double;
    else FAt[i - 1] := @ffi_type_pointer; // p/c/s/a/r/w
    end;

  case FRet of
    // 'C': Win32 cdecl convention marker. SysV is always cdecl, so on Linux it
    // is the same as 'i' (mirrors Win32, which reads the result from eax).
    'i', 'C': rtype := @ffi_type_sint32;
    'l', 'n': rtype := @ffi_type_sint64;
    'f': rtype := @ffi_type_float;
    'd': rtype := @ffi_type_double;
    'c', 'p', 's', 'a', 'r', 'w': rtype := @ffi_type_pointer;
  else rtype := @ffi_type_void; // 'v'
  end;

  if Length(FArgs) > 0 then
    st := ffi_prep_cif(@FCif.cif, cifABI, Length(FArgs), rtype, @FAt[0])
  else
    st := ffi_prep_cif(@FCif.cif, cifABI, 0, rtype, nil);
  if st <> FFI_OK then raise EBase.Create('toCallback: ffi_prep_cif failed');

  FClos := ffi_closure_alloc(SizeOf(ffi_closure), @FCode);
  if FClos = nil then raise EBase.Create('toCallback: ffi_closure_alloc failed');

  st := ffi_prep_closure_loc(FClos, @FCif.cif, @CFFITrampoline, Pointer(self), FCode);
  if st <> FFI_OK then raise EBase.Create('toCallback: ffi_prep_closure_loc failed');
  result := FCode;
end;

function CFFICallback.GetProc: Pointer;
begin
  result := Build;
end;

procedure CFFICallback.Invoke(cif: Pffi_cif; resp: Pointer; args: PPointer);
var
  es: CExps;
  e: CExp;
  i, na: Integer;
  ch: Char;
  rv: PValue;
begin
  es := CExps.Create();
  try
    na := Length(FArgs);
    for i := 0 to na - 1 do
    begin
      e := CExp.new(nil);
      es.Add(e);
      ch := FArgs[i + 1];
      case ch of
        'i': e.assign(PLongInt(args[i])^);
        'l', 'n': e.assign(PInt64(args[i])^);
        'f': e.assign(PSingle(args[i])^);
        'd': e.assign(PDouble(args[i])^);
        's', 'a', 'r': e.assign(fun.str(PAnsiChar(PPointer(args[i])^)));
        {$IfDef MSWINDOWS}
        'w': e.assign(fun.str(PAnsiChar(PPointer(args[i])^)));
        {$Else}
        'w': e.assign(fun.str(UCS4ToUtf8(PLongWord(PPointer(args[i])^))));
        {$EndIf}
        'c', 'p': e.assign(Int64(fun.uintptr(PPointer(args[i])^)));
      else e.assign(0);
      end;
    end;

    rv := call(self.env, es); // evaluate the wrapped Fun function
    if (resp = nil) or (rv = nil) then exit;

    case FRet of
      'v': ; // void
      'i', 'C': // 'C' = Win32 cdecl marker; return as the 32-bit int Win32 does
        if isFloat(rv) then PLongInt(resp)^ := Trunc(Double(rv^))
        else if isNum(rv) then PLongInt(resp)^ := LongInt(rv^)
        else PLongInt(resp)^ := 0;
      'l', 'n':
        if isFloat(rv) then PInt64(resp)^ := Trunc(Double(rv^))
        else if isNum(rv) then PInt64(resp)^ := Int64(rv^)
        else PInt64(resp)^ := 0;
      'f': PSingle(resp)^ := Double(rv^); // auto-converts to Single
      'd': PDouble(resp)^ := Double(rv^);
      'p', 'c': PPointer(resp)^ := Pointer(fun.uintptr(Double(rv^)));
      's', 'a':
        begin
          FStr := fun.str(rv^); // keep the returned string alive
          if FStr <> '' then PPointer(resp)^ := PAnsiChar(@FStr[1])
          else PPointer(resp)^ := nil;
        end;
      {$IfNDef MSWINDOWS}
      'w':
        begin
          FWide := Utf8ToUCS4(AnsiString(fun.str(rv^))); // keep it alive
          PPointer(resp)^ := @FWide[0];
        end;
      {$EndIf}
    end;
  finally
    del(es);
  end;
end;

end.
