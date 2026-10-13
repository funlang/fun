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

{$IfDef UNIX}
// Portable MD5/SHA1 from FPC's bundled hash units. The Windows branch below
// wraps advapi32.dll (MD5Init/A_SHAInit), which does not exist on Linux, so
// the shared library could not even be linked there. Linux-only: Windows keeps
// the original implementation unchanged.
function MD5(const Buffer; Size: LongWord): string;
begin
  result := FunMD5(Buffer, Size);
end;

function SHA(const Buffer; Size: LongWord): string;
begin
  result := FunSHA1(Buffer, Size);
end;

{$Else}

type
  TAdv32MD5 = object
  protected
    Unknown : array[1..24] of Byte;
    XBuff   : array[1..64] of Byte;
    Digest  : array[1..16] of Byte;
  public
    function  ToString: string;
    procedure Init;                                 stdcall;
    procedure Update(const Buffer; Size: LongWord); stdcall;
    procedure Final;                                stdcall;
  end;

  TAdv32SHA = object
  protected
    Unknown : array[1..52] of Byte;
    XBuff   : array[1..64] of Byte;
    Digest  : array[1..20] of Byte;
  public
    function  ToString: string;
    procedure Init;                                 stdcall;
    procedure Update(const Buffer; Size: LongWord); stdcall;
    procedure Final (const Digest);                 stdcall;
  end;

function MD5(const Buffer; Size: LongWord): string;
var
  tmp: ^TAdv32MD5;
begin
  New(tmp);
  with tmp^ do
  begin
    Init;
    Update(Buffer, Size);
    Final;
    Result := ToString;
  end;
  Dispose(tmp);
end;

function SHA(const Buffer; Size: LongWord): string;
var
  tmp: ^TAdv32SHA;
begin
  New(tmp);
  with tmp^ do
  begin
    Init;
    Update(Buffer, Size);
    Final(Digest);
    Result := ToString;
  end;
  Dispose(tmp);
end;

function GetString(const Buffer: Pointer; Size: LongWord): string;
const
  HexChars: array[0..15] of Char = '0123456789abcdef';
var
  i, b : LongWord;
  pSrc : PAnsiChar;
  pDst : PChar;
begin
  SetLength(Result, Size * 2);
  pDst := Pointer(Result);
  pSrc := PAnsiChar(Buffer);
  for i:= 0 to Size-1 do
  begin
    b  := Ord(pSrc[i]);
    pDst[i*2+0] := HexChars[b shr $4];
    pDst[i*2+1] := HexChars[b and $f];
  end;
end;

function TAdv32MD5.ToString: string;
begin
  Result := GetString(@Digest, 16);
end;

function TAdv32SHA.ToString: string;
begin
  Result := GetString(@Digest, 20);
end;

const AdvApi32 = 'advapi32.dll';
//const AdvApi32 = 'cryptdll.dll'; // No SHA
procedure TAdv32MD5.Init;                                 external AdvApi32 name 'MD5Init';
procedure TAdv32MD5.Update(const Buffer; Size: LongWord); external AdvApi32 name 'MD5Update';
procedure TAdv32MD5.Final;                                external AdvApi32 name 'MD5Final';
procedure TAdv32SHA.Init;                                 external AdvApi32 name 'A_SHAInit';
procedure TAdv32SHA.Update(const Buffer; Size: LongWord); external AdvApi32 name 'A_SHAUpdate';
procedure TAdv32SHA.Final (const Digest);                 external AdvApi32 name 'A_SHAFinal';

{$EndIf}
