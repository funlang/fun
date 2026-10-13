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
unit fun;

interface

type
  int32  = Integer;
  uint32 = Cardinal;
  int64  = System.Int64;
  uint64 = System.Int64;

  {$IfDef Win64}
  int    = int32; // NOT int64 !!!
  uint   = uint64;
  {$Else}
  int    = int32;
  uint   = uint32;
  {$EndIf}

  real   = Double;
  str    = String;
  bool   = Boolean;
  time   = TDateTime;

  char   = System.Char;
  byte   = System.Byte;
  word   = System.Word;
  dword  = System.LongWord;

  ptr    = Pointer;

  // Pointer-wide integers, signed and unsigned. Platform selection lives here,
  // next to the other aliases, so no other unit has to name a compiler-specific
  // pointer-sized type (PtrInt/PtrUInt/NativeInt/NativeUInt/...). Any 64-bit
  // target keeps full-width addresses; 32-bit targets are unchanged.
  // FPC marks 64-bit with CPU64, Delphi with Win64.
  {$IfDef Win64}
    {$Define FunPtrWide}
  {$EndIf}
  {$IfDef CPU64}
    {$Define FunPtrWide}
  {$EndIf}
  {$IfDef FunPtrWide}
  intptr  = int64;
  uintptr = QWord;
  {$Else}
  intptr  = int32;
  uintptr = uint32;
  {$EndIf}

const
  // Runtime version facts (funVersion, funRelease), kept in a separate include
  // so the numeric stamp can be regenerated without touching this unit:
  //   fun src/prj/fun/gen-version.fun
  // Both the `N.time()` probe and 'host'.arg() read these, so the two paths
  // cannot drift apart. See src/core/version.inc.
  {$I version.inc}

  {$IfDef FPC}
  VarObject = $201;//VarError;
  VarObjNew = $202;//VarError;
  VarObj010 = 2010;
  VarObj011 = 2011;
  {$Else}
  VarObject = 2010;
  VarObjNew = 2011;
  {$EndIf}


function StrToOleStr(const s: str): PWideChar;
var defaultCodePage: int = 0;

implementation

uses Variants, {$IfNDef UNIX}Windows,{$EndIf} Math,
     base{$IfNDef Alone}, core{$EndIf}
     {$IfDef Regex}, regex{$EndIf}
     ;


function StrToOleStr(const s: str): PWideChar;
{$IfDef UNIX}
begin
  result := PWideChar(s);
{$Else}
{$IfDef Unicode}
begin
  result := StringToOleStr(s);
{$Else}
  procedure DoStrToOleStr(var d: WideString);
  var
    i, j: int;
  begin
    d := '';
    if s <> '' then
    begin
      i := MultiByteToWideChar(defaultCodePage, 0, @s[1], Length(s), nil, 0);
      if i > 0 then
      begin
        SetLength(d, i);
        j := MultiByteToWideChar(defaultCodePage, 0, @s[1], Length(s), @d[1], i);
        if i <> j then SetLength(d, Min(i, j));
      end;
    end;
  end;
begin
  result := nil;
  if defaultCodePage = 0 then result := StringToOleStr(s)
  else DoStrToOleStr(WideString(ptr(result)));
{$EndIf}
{$EndIf}
end;

type
  CVarObject = class(TCustomVariantType)
  public
    procedure Clear(var V: CData); override;
    procedure Copy(var Dest: CData; const Source: CData; const Indirect: Boolean); override;
    procedure CastTo(var Dest: CData; const Source: CData; const AVarType: TVarType); override;
  end;

  CVarObjNew = class(CVarObject)
  public
    procedure Clear(var V: CData); override;
    procedure Copy(var Dest: CData; const Source: CData; const Indirect: Boolean); override;
  end;

//==============================================================
procedure CVarObject.Clear(var V: CData);
begin
  V.VType    := VarEmpty;
  V.VInt64   := 0;
end;

procedure CVarObject.Copy(var Dest: CData; const Source: CData; const Indirect: Boolean);
begin
  Dest.VType    := Source.VType;
  Dest.VInt64   := Source.VInt64;
end;

procedure CVarObject.CastTo(var Dest: CData; const Source: CData; const AVarType: TVarType);
begin
  //todo RaiseCastError;
  Dest.VType    := VarEmpty;
  Dest.VInt64   := 0;
  if AVarType = VarBoolean then
  begin
    Dest.VType  := VarBoolean;
    {$IfNDef Alone}
    with Source do
    begin
      if (CBase(VPointer) is CSet)
         {$IfDef Regex}or (CBase(VPointer) is CMatch){$EndIf}
         then
        Dest.VBoolean := CExp(VPointer).count > 0
      else if (CBase(VPointer) is CFun) then
        Dest.VBoolean := true
      ;
    end;
    {$EndIf}
  end;
end;

//==============================================================
procedure CVarObjNew.Clear(var V: CData);
begin
  del(asObj(@V));
  inherited;
end;

procedure CVarObjNew.Copy(var Dest: CData; const Source: CData; const Indirect: Boolean);
begin
  inherited;
  base.add(asObj(@Source));
end;

var
  _VarObject: CVarObject;
  _VarObjNew: CVarObjNew;

initialization
  _VarObject := CVarObject.Create(VarObject);
  _VarObjNew := CVarObjNew.Create(VarObjNew);

finalization
  try
    _VarObject.Free;
    _VarObjNew.Free;
  except
  end;

end.
