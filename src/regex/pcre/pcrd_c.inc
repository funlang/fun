{$IfNDef Win64}
// PCRE's C side needs the symbol "malloc"/"free". On i386 a Pascal function
// declared cdecl gets the _-prefixed C name, which is what the bcc32 objects
// ask for. On win64 there is no prefix and these bodies would carry FPC's
// mangled names, so pcrd.pas imports msvcrt's malloc/free there instead (and
// gets the plain symbols the MinGW-built objects look up).
function malloc(Size: Integer): Pointer; cdecl;
begin
  GetMem(Result, Size);
end;

procedure free(P: Pointer); cdecl;
begin
  FreeMem(P);
end;
{$EndIf}

function _memcpy(Dest, Src: Pointer; N: Integer): Pointer; cdecl;
begin
  Move(Src^, Dest^, N);
  Result := Dest;
end;

function _memmove(Dest, Src: Pointer; N: Integer): Pointer; cdecl;
begin
  Move(Src^, Dest^, N);
  Result := Dest;
end;

function _memset(P: Pointer; B: Byte; N: Integer): Pointer; cdecl;
begin
  FillChar(P^, N, B);
  Result := P;
end;

function _memcmp(S1, S2: PByteArray; N: Integer): Integer; cdecl;
var
  I: Integer;
begin
  I := 0;
  while (I < N) and (S1[I] = S2[I]) do Inc(I);
  if I >= N then Result := 0
            else if S1[I] < S2[I] then Result := -1
                                  else Result := 1;
end;

function _strncmp (const S1, S2: PAnsiChar; N: Cardinal): Integer; cdecl;
begin
  Result := StrLComp(S1, S2, N);
end;

function _strlen(S: PAnsiChar): Integer; cdecl;
begin
  Result := StrLen(S);
end;

function _isdigit(C: Integer): Integer; cdecl;
begin
  Result := Integer(Char(C) in [#0..#9]);
end;
