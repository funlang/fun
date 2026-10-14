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
unit io;

interface

uses fun, base;

type
  CFindEach = procedure (const f: fun.str; p: fun.ptr; size: fun.int = -1);

  CIO = class(CBase)
  public
    class procedure Append(const fn, ss: fun.str; cp: fun.word = 0);
    class procedure Check(err: fun.int; const msg: fun.str = '');
    class procedure Close(h: fun.int);
    class procedure Copy(f1, f2: fun.str; overwrite: fun.bool = true);
    class procedure Find(fn: fun.str; sub, size, rel: fun.bool; act: CFindEach; tag: fun.ptr);
    class function Load(const fn: fun.str; cp: fun.word = 0; mode: fun.int = -1): fun.str;
    class procedure Move(f1: fun.str; f2: fun.str = '');
    class function Norm(const fn: fun.str): fun.str;
    class function Open(fn: fun.str; forSave: fun.bool = false): fun.int;
    class procedure Save(const fn, ss: fun.str; cp: fun.word = 0; append: fun.bool = false);
    class function Time(fn: fun.str; flag: fun.byte = 0; dt: fun.time = 0): fun.time;
  end;
  

const
  CP_UTF8  = 65001;
  CP_UTF8P = 10056; // without BOM
  CP_UCS2  = 1200;
  CP_UCS2b = 1201;

{$IfDef Unicode}
var
  CP_Last: fun.word;
{$EndIf}

function LoadLib(const fn: fun.str): fun.uint;
procedure FreeLib(const h: fun.uint);
function GetProc(hlib: fun.uint; const name: fun.str): fun.ptr;

//{$IfDef Unicode}
function ToRawString(const s: WideString): AnsiString;
//{$EndIf}

{$IfDef MD5}
function MD5(const Buffer; Size: LongWord): string;
function SHA(const Buffer; Size: LongWord): string;
{$EndIf}

const
  Seek_Begin = 0;
  Seek_End   = 2;

implementation

uses {$IfNDef UNIX}Windows,{$Else}DateUtils,{$EndIf}
     {$IfDef MD5}{$IfDef UNIX}funhash,{$EndIf}{$EndIf}
     SysUtils;

{$IfDef WinCE}
type
  TBytes = array of fun.byte;
{$IfNDef Win64}
  PChar  = PWideChar;
{$EndIf}
{$EndIf}

{$IfDef Unicode}
const
  Pre_Utf8  = $00bfbbef;
  Pre_Ucsl  = $feff;
  Pre_Ucsb  = $fffe;

const
  PreS_Utf8 : AnsiString = #$ef#$bb#$bf;
  PreS_Ucsl : AnsiString = #$ff#$fe;
  PreS_Ucsb : AnsiString = #$fe#$ff;

type
  Pre_Code = record
    case fun.int of
      0: (bs: array[0..3]of fun.byte);
      1: (ws: array[0..1]of fun.word);
      2: (ds: fun.dword);
  end;
{$EndIf}

const
  _OpenFailed = 'Open "%s" failed: %s';
  _SaveFailed = 'Save "%s" failed: %s';

{$IfDef MD5}
{$I '..\lib\libmd5.inc'}
{$EndIf}

//==============================================================
class procedure CIO.Append(const fn, ss: fun.str; cp: fun.word = 0);
begin
  Save(fn, ss, cp, true);
end;

class procedure CIO.Check(err: fun.int; const msg: fun.str = '');
begin
  if err < 0 then
  begin
  {$IfNDef UNIX}
    raise EBase.Create(msg + SysErrorMessage(GetLastError));
  {$Else}
    raise EBase.Create(msg + SysErrorMessage(GetLastOSError));
  {$EndIf}
  end;
end;

class procedure CIO.Close(h: fun.int);
begin
  FileClose(h);
end;

class procedure CIO.Copy(f1, f2: fun.str; overwrite: fun.bool = true);
{$IfDef UNIX}
var
  fin, fout: fun.int;
  buf: array[0..65535] of byte;
  n: LongInt;
{$EndIf}
begin
  f1 := Norm(f1);
  f2 := Norm(f2);
  {$IfNDef UNIX}
  CopyFile(PChar(f1), PChar(f2), not overwrite);
  {$Else}
  if (not overwrite) and FileExists(f2) then
    CIO.Check(-1, 'Copy: target already exists: ' + f2);
  fin := FileOpen(f1, fmOpenRead or fmShareDenyNone);
  if fin < 0 then CIO.Check(fin, 'Copy: cannot open source: ');
  try
    fout := FileCreate(f2);
    if fout < 0 then CIO.Check(fout, 'Copy: cannot create target: ');
    try
      repeat
        n := FileRead(fin, buf, SizeOf(buf));
        if n > 0 then FileWrite(fout, buf, n);
      until n <= 0;
    finally
      FileClose(fout);
    end;
  finally
    FileClose(fin);
  end;
  {$EndIf}
end;

class procedure CIO.Find(fn: fun.str; sub, size, rel: fun.bool; act: CFindEach; tag: fun.ptr);
var
  ft: fun.int;
  fp: fun.str;
  
  procedure _find(const _fp: fun.str); overload; forward;
  
  procedure _find(const _fp, _fn: fun.str; _ft: fun.int; _act: CFindEach); overload;
  var
    sr: TSearchRec;
    sz: fun.int;
    f2: fun.str;
    // When a callback is given, matching entries are collected first and
    // emitted in a stable byte order. FindFirst/FindNext returns entries in
    // host order (ext4, APFS and NTFS all differ), so a script that lists a
    // directory would otherwise print differently on each machine.
    names: array of fun.str;
    sizes: array of fun.int;
    cnt, i, j: fun.int;
    kn: fun.str;
    kz: fun.int;

    function _cmp(const a, b: fun.str): fun.int;
    var
      n, k: fun.int;
    begin
      n := Length(a);
      if Length(b) < n then n := Length(b);
      for k := 1 to n do
      begin
        if a[k] < b[k] then begin result := -1; exit; end;
        if a[k] > b[k] then begin result := 1; exit; end;
      end;
      if Length(a) < Length(b) then result := -1
      else if Length(a) > Length(b) then result := 1
      else result := 0;
    end;

    procedure _collect(const _fp2, _fn2: fun.str; _ft2: fun.int);
    var
      sr2: TSearchRec;
    begin
      if FindFirst(_fp2 + _fn2, _ft2, sr2) = 0 then
      begin
        try
          repeat
            if (sr2.Name = '.') or (sr2.Name = '..') then continue;
            if ((_ft2 = faDirectory) and ((sr2.Attr and faDirectory) = faDirectory)) or
               ((sr2.Attr and _ft2) = (sr2.Attr and faAnyFile)) then
            begin
              if size then sz := sr2.Size else sz := -1;
              f2 := _fp2 + sr2.Name;
              if rel then Delete(f2, 1, Length(fp));
              SetLength(names, cnt + 1);
              SetLength(sizes, cnt + 1);
              names[cnt] := f2;
              sizes[cnt] := sz;
              cnt := cnt + 1;
            end;
          until FindNext(sr2) <> 0;
        finally
          FindClose(sr2);
        end;
      end;
    end;

  begin
    if assigned(_act) then
    begin
      cnt := 0;
      SetLength(names, 0);
      SetLength(sizes, 0);
      _collect(_fp, _fn, _ft);
      // stable insertion sort: byte order, identical on every host
      for i := 1 to cnt - 1 do
      begin
        kn := names[i];
        kz := sizes[i];
        j := i - 1;
        while (j >= 0) and (_cmp(names[j], kn) > 0) do
        begin
          names[j + 1] := names[j];
          sizes[j + 1] := sizes[j];
          j := j - 1;
        end;
        names[j + 1] := kn;
        sizes[j + 1] := kz;
      end;
      for i := 0 to cnt - 1 do
        _act(names[i], tag, sizes[i]);
    end
    else
    begin
      sz := -1;
      if FindFirst(_fp + _fn, _ft, sr) = 0 then
      begin
        try
          repeat
            if (sr.Name = '.') or (sr.Name = '..') then continue;
            if ((_ft = faDirectory) and ((sr.Attr and faDirectory) = faDirectory)) or
               ((sr.Attr and _ft) = (sr.Attr and faAnyFile)) then
              {$IfDef UNIX}
              _find(_fp + sr.Name + '/')
              {$Else}
              _find(_fp + sr.Name + '\')
              {$EndIf}
              ;
          until FindNext(sr) <> 0;
        finally
          FindClose(sr);
        end;
      end;
    end;
  end;
  
  procedure _find(const _fp: fun.str);
  begin
    _find(_fp, fn, ft, act);
    if sub then _find(_fp, '*.*', faDirectory, nil);
  end;
  
begin
  fn := Norm(fn);
  if (fn <> '') and (fn[Length(fn)] in ['\', '/']) then
  begin
    Delete(fn, Length(fn), 1);
    ft := faDirectory;
  end
  else
    ft := faAnyFile - faDirectory
  ;
  fp := ExtractFilePath(fn);
  fn := ExtractFileName(fn);
  _find(fp);
end;

class function CIO.Load(const fn: fun.str; cp: fun.word = 0; mode: fun.int = -1): fun.str;
var
  h: fun.int;
  L: fun.int64;
  
  {$IfDef Unicode}
  hd: Pre_Code;
  u8: Utf8String;
  bs: TBytes;
  i: fun.int;
  {$EndIf}
  s: AnsiString;
  
  procedure DoRead(p: fun.ptr);
  var
    sss, siz: fun.int;
    iii, ppp: fun.int64;
  begin
    if FileRead(h, p^, L) < 0 then
    begin
      ppp := fun.int(p);
      iii := L;
      sss := 32 * 1024 * 1024;
      while iii > 0 do
      begin
        siz := sss;
        if iii < siz then siz := iii;
        Check(FileRead(h, fun.ptr(ppp)^, siz));
        inc(ppp, sss);
        dec(iii, sss);
      end;
    end;
  end;
  
  
begin
  h := Open(fn);
  L := FileSeek(h, 0, Seek_End);
       FileSeek(h, 0, Seek_Begin);
  
  try
    {$IfDef Unicode}
    if mode < 0 then
    begin
      CP_Last := cp;
      if (cp = 0) and (L > 4) then
      begin
        FileRead(h, hd.bs, 4);
        if hd.ds and Pre_Utf8 = Pre_Utf8 then
        begin
          CP_Last := CP_UTF8;
          FileSeek(h, 3, Seek_Begin);
          Dec(L, 3);
        end
        else if hd.ws[0] = Pre_Ucsb then
        begin
          CP_Last := CP_UCS2b;
          FileSeek(h, 2, Seek_Begin);
          Dec(L, 2);
        end
        else if hd.ws[0] = Pre_Ucsl then
        begin
          CP_Last := CP_UCS2;
          FileSeek(h, 2, Seek_Begin);
          Dec(L, 2);
        end;
      end;
  
      if CP_Last = CP_UTF8 then
      begin
        SetLength(u8, L);
        DoRead(fun.ptr(u8));
        result := fun.str(u8);
        SetLength(u8, 0);
        exit;
      end
      else if (CP_Last = CP_UCS2b) or (CP_Last = CP_UCS2) then
      begin
        SetLength(bs, L);
        DoRead(fun.ptr(bs));
        L := L div 2;
        SetLength(result, L);
        if CP_Last = CP_UCS2b then
          for i := 1 to L do result[i] := fun.char(bs[i*2 -2] shl 8 + bs[i*2 -1])
        else
          for i := 1 to L do result[i] := fun.char(bs[i*2 -1] shl 8 + bs[i*2 -2])
        ;
        SetLength(bs, 0);
        exit;
      end;
    end;
    {$EndIf}
  
    FileSeek(h, 0, Seek_Begin);
    SetLength(s, L);
    DoRead(fun.ptr(s));
  
    {$IfDef Unicode}
      {$IfNDef WinCE}
        if (mode < 0) and (cp > 0) then
        begin
          if cp = $ffff then
          begin
            SetLength(result, L);
            for i := 1 to L do result[i] := fun.char(s[i]);
            exit;
          end
          else
            PWord(Integer(s) - 12)^ := cp;
        end;
      {$EndIf}
    {$EndIf}
  
    if mode < 0 then
      result := fun.str(s)
    else
    {$IfDef MD5}
      if mode = 0 then
        result := MD5(fun.ptr(s)^, L)
      else// if mode = 1 then
        result := SHA(fun.ptr(s)^, L)
    {$Else}
      result := ''
    {$EndIf}
    ;
  finally
    FileClose(h);
  end;
end;

class procedure CIO.Move(f1: fun.str; f2: fun.str = '');
begin
  f1 := Norm(f1);
  if f2 <> '' then f2 := Norm(f2);
  if f2 <> '' then
    RenameFile(f1, f2)
  else
  begin
    DeleteFile(f1);
  {$IfNDef UNIX}
    RemoveDirectory(PChar(f1));
  {$Else}
    // DeleteFile above handles plain files; RemoveDir drops an empty directory.
    RemoveDir(f1);
  {$EndIf}
  end;
end;

class function CIO.Norm(const fn: fun.str): fun.str;
begin
{$IfNDef UNIX}
  result := fn;
{$Else}
  result := StringReplace(fn, '\', '/', [rfReplaceAll]);
{$EndIf}
end;
class function CIO.Open(fn: fun.str; forSave: fun.bool = false): fun.int;
var
  fp, err: fun.str;
begin
  fn := Norm(fn);
  if not forSave then
  begin
    err    := _OpenFailed;
    result := FileOpen(fn, fmOpenRead or fmShareDenyNone);
  end
  else
  begin
    err    := _SaveFailed;
    if FileExists(fn) then
    begin
      result := FileOpen(fn, fmOpenReadWrite or fmShareDenyNone);
    end
    else
    begin
      fp := ExtractFilePath(fn);
      if (fp <> '') and not DirectoryExists(fp) then
      begin
        ForceDirectories(fp);
      end;
      result := FileCreate(fn);
    end;
  end;
  
  if result < 0 then
  begin
  {$IfNDef UNIX}
    raise EBase.Create(Format(err, [ExpandFileName(fn), SysErrorMessage(GetLastError)]));
  {$Else}
    raise EBase.Create(Format(err, [ExpandFileName(fn), SysErrorMessage(GetLastOSError)]));
  {$EndIf}
  end;
end;

class procedure CIO.Save(const fn, ss: fun.str; cp: fun.word = 0; append: fun.bool = false);
var
  h, iii, sss, siz: fun.int;
  ppp: fun.int64;
  
  {$IfDef Unicode}
  i: fun.int;
  bs: TBytes;
  p: PByte;
  {$EndIf}
  s: AnsiString;
  
begin
{$IfNDef UNIX}
  h := Open(StringReplace(fn, '/', '\', [rfReplaceAll]), true);
{$Else}
  h := Open(fn, true);
{$EndIf}
  
  try
    if append then
    begin
      FileSeek(h, 0, Seek_End);
    end
    else
    begin
      FileSeek(h, 0, Seek_Begin);
      {$IfNDef UNIX}
      SetEndOfFile(h);
      {$Else}
      FileTruncate(h, 0);
      {$EndIf}
  
      {$IfDef Unicode}
      case cp of
        CP_UTF8:
        begin
          FileWrite(h, fun.ptr(PreS_Utf8)^, 3);
        end;
  
        CP_UTF8P:
        begin
          cp := CP_UTF8;
        end;
  
        CP_UCS2:
        begin
          FileWrite(h, fun.ptr(PreS_Ucsl)^, 2);
        end;
  
        CP_UCS2b:
        begin
          FileWrite(h, fun.ptr(PreS_Ucsb)^, 2);
        end;
      end;
      {$EndIf}
    end;
  
    {$IfDef Unicode}
    if cp > 0 then
    begin
      case cp of
        CP_UCS2:
        begin
          FileWrite(h, fun.ptr(ss)^, Length(ss) * 2);
          exit;
        end;
  
        CP_UCS2b:
        begin
          p := fun.ptr(ss);
          SetLength(bs, Length(ss) * 2);
          for i := 0 to Length(ss)-1 do
          begin
            bs[i*2+1] := p^;
            bs[i*2]   := (p+1)^;
            Inc(p, 2);
          end;
          FileWrite(h, fun.ptr(bs)^, Length(bs));
          exit;
        end;
      end;
  
      if cp = $ffff then
      begin
        s := ToRawString(ss);
      end
      else
      begin
        {$IfNDef WinCE}
        // _LStrFromUStr(s, ss, cp);
        p := fun.ptr(ss);
        asm
          lea  eax, s
          mov  edx, p
          xor  ecx, ecx
          mov   cx, cp
          call System.@LStrFromUStr
        end;
        {$EndIf}
      end;
    end
    else
    {$EndIf}
      s := AnsiString(ss);
    if FileWrite(h, fun.ptr(s)^, Length(s)) < 0 then
    begin
      ppp := fun.int(fun.ptr(s));
      iii := Length(s);
      sss := 32 * 1024 * 1024;
      while iii > 0 do
      begin
        siz := sss;
        if iii < siz then siz := iii;
        Check(FileWrite(h, fun.ptr(ppp)^, siz));
        inc(ppp, sss);
        dec(iii, sss);
      end;
    end;
  finally
    FileClose(h);
  end;
end;

class function CIO.Time(fn: fun.str; flag: fun.byte = 0; dt: fun.time = 0): fun.time;
var
  Handle: THandle;
  {$IfNDef UNIX}
  FindData: TWin32FindData;
  SystemTime: TSystemTime;
  ft: TFileTime;
  {$Else}
  Age: LongInt;
  h: fun.int;
  {$EndIf}
  ret: ^fun.int64;
begin
  fn := Norm(fn);
  // flag:
  //  0 - CreationTime
  //  1 - LastWriteTime
  //  8 - Size
  result := 0.0;
  {$IfNDef UNIX}
  Handle := FindFirstFile(PChar(fn), FindData);
  if Handle <> INVALID_HANDLE_VALUE then
  begin
    Windows.FindClose(Handle);
    with FindData do if flag in [0, 1] then
    begin
      if flag = 0 then
        ft := ftCreationTime
      else
        ft := ftLastWriteTime
      ;
      FileTimeToSystemTime(ft, SystemTime);
      result := SystemTimeToDateTime(SystemTime);
  
      if dt <> 0 then
      begin
        Handle := CreateFile(PChar(fn),
          $100, // FILE_WRITE_ATTRIBUTES
          FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
          nil,
          OPEN_EXISTING,
          FILE_FLAG_BACKUP_SEMANTICS,
          0);
        if Handle <> INVALID_HANDLE_VALUE then
        begin
          DateTimeToSystemTime(dt, SystemTime);
          SystemTimeToFileTime(SystemTime, ft);
          if flag = 0 then
            SetFileTime(Handle, @ft, nil, nil)
          else
            SetFileTime(Handle, nil, nil, @ft)
          ;
          CloseHandle(Handle);
        end;
      end;
    end
    else// if flag = 8 then
    begin
      ret  := @result;
      ret^ := nFileSizeLow// + nFileSizeHigh shl 32;
    end;
  end;
  {$Else}
  // Linux has no portable creation/birth time, so both CreationTime (0) and
  // LastWriteTime (1) map to the modification time. Size (8) = byte length.
  if flag in [0, 1] then
  begin
    if dt = 0 then
    begin
      Age := FileAge(fn);
      if Age >= 0 then result := UnixToDateTime(Age, False);
    end
    else
      FileSetDate(fn, DateTimeToUnix(dt, False));
  end
  else // size
  begin
    h := FileOpen(fn, fmOpenRead or fmShareDenyNone);
    if h >= 0 then
    begin
      ret  := @result;
      ret^ := FileSeek(h, 0, Seek_End);
      FileClose(h);
    end;
  end;
  {$EndIf}
end;


//==============================================================
function LoadLib(const fn: fun.str): fun.uint;
begin
{$IfNDef UNIX}
  result := LoadLibrary(PChar(fn));
  if result = 0 then CIO.Check(-1, 'LoadLibrary(' + fn + '): ');
{$EndIf}
end;

procedure FreeLib(const h: fun.uint);
begin
{$IfNDef UNIX}
  FreeLibrary(h);
{$EndIf}
end;

function GetProc(hlib: fun.uint; const name: fun.str): fun.ptr;
begin
{$IfNDef UNIX}
  result := GetProcAddress(hlib, PChar(name));
  if result = nil then
  begin
    {$IfDef Unicode}
    result := GetProcAddress(hlib, PChar(name + 'W'));
    {$Else}
    result := GetProcAddress(hlib, PChar(name + 'A'));
    {$EndIf}
  end;
  if result = nil then
  begin
    FreeLib(hlib);
    CIO.Check(-1, 'GetProcAddress(' + name + '): ');
  end;
{$EndIf}
end;

//{$IfDef Unicode}
function ToRawString(const s: WideString): AnsiString;
var
  i, L: fun.int;
begin
  L := Length(s);
  SetLength(result, L);
  for i := 1 to L do result[i] := AnsiChar(s[i]);
end;
//{$EndIf}

end.
