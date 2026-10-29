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
// libfdw FDWriter - FD 格式序列化实现
var
  indentStyle: fun.int;

  procedure WriteIndent(level: fun.int);
  var i: fun.int;
  begin
    if level <= 0 then Exit;
    case indentStyle of
      0: prefix(level * 2);
      1: for i := 1 to level do add('>');
      2: add(IntToStr(level) + '>');
    else
      prefix(level * 2);
    end;
  end;

  function ReplaceStr(const S, OldPattern, NewPattern: fun.str): fun.str;
  begin
    Result := NewStringReplace(S, OldPattern, NewPattern, [rfReplaceAll]);
  end;

  // FD numbers use the same RFC 8259 grammar as the reader (IsJsonNumber in
  // base.pas). A string that would parse as a number must be quoted.
  function IsNumericString(const s: fun.str): fun.bool;
  begin
    Result := IsJsonNumber(s);
  end;

  function IsPlainValue(const s: fun.str): fun.bool;
  begin
    Result := False;
    if s = '' then Exit;
    if (Pos(#10, s) > 0) or (Pos(#13, s) > 0) then Exit;
    if (s[1] in [' ', #9]) or (s[Length(s)] in [' ', #9]) then Exit;
    if IsNumericString(s) then Exit;
    if (s = 'true') or (s = 'false') or (s = 'null') then Exit;
    if (s = '[]') or (s = '{}') then Exit;
    if (Length(s) > 0) and (s[1] in ['"', '''', '`']) then Exit;
    Result := True;
  end;

  function IsPlainIdentifier(const s: fun.str): fun.bool;
  begin
    Result := False;
    if not IsPlainValue(s) then Exit;
    if kvd <> 32 then begin if (Pos(fun.char(kvd), s) > 0) then Exit; end
    else if (Pos(' ', s) > 0) or (Pos(#9, s) > 0) then Exit;
    if (Length(s) > 0) and (s[1] in ['>', '#', '-']) then Exit;
    if (Length(s) > 0) and (s[1] in ['0'..'9']) then Exit;
    Result := True;
  end;

  function IsBinaryData(const s: fun.str): fun.bool;
  var i: fun.int; ch: Char;
  begin
    Result := false;
    for i := 1 to Length(s) do
    begin
      ch := s[i];
      if (Ord(ch) < 32) and not (ch in [#9, #10, #13]) then
      begin
        Result := true;
        Exit;
      end;
    end;
  end;

  function GetFixedPrefix(len: fun.int64; var bs: fun.int): fun.str;
  begin
    if len <= $FFFF then begin
      Result := 'x'; bs := 2;
    end else if len <= $FFFFFF then begin
      Result := 'X'; bs := 3;
    end else if len <= $FFFFFFFF then begin
      Result := 'xx'; bs := 4;
    end else if len <= $FFFFFFFFFF then begin
      Result := 'xX'; bs := 5;
    end else begin
      Result := 'XX'; bs := 6;
    end;
  end;

  function EncodeFixedBinary(const data: fun.str): fun.str;
  var
    len: fun.int64;
    prefix: fun.str;
    hexLen: fun.str;
    hexDigits: fun.int;
  begin
    len := Length(data);
    prefix := GetFixedPrefix(len, hexDigits);
    hexLen := UpperCase(IntToHex(len, hexDigits * 2));
    Result := '``' + prefix + hexLen + data;
  end;

  function DoubleQuoteEscape(const s: fun.str): fun.str;
  begin
    Result := ReplaceStr(s, '"', '""');
  end;

  function QuoteFd(const s: fun.str; forKey: fun.bool): fun.str;
  var
    hasDQuote, hasSQuote, hasBQuote: Boolean;
    i: fun.int;
    ch: Char;
  begin
    if s = '' then
    begin
      Result := '""';
      Exit;
    end;

    if forKey then
    begin
      if IsPlainIdentifier(s) then
        Result := s
      else
        Result := '"' + DoubleQuoteEscape(s) + '"';
      Exit;
    end;

    if IsPlainValue(s) then
    begin
      Result := s;
      Exit;
    end;

    if IsBinaryData(s) then
    begin
      Result := EncodeFixedBinary(s);
      Exit;
    end;

    hasDQuote := false; hasSQuote := false; hasBQuote := false;
    for i := 1 to Length(s) do
    begin
      ch := s[i];
      case ch of
        '"':  hasDQuote := true;
        '''': hasSQuote := true;
        '`':  hasBQuote := true;
      end;
    end;

    if not hasDQuote then
      Result := '"' + s + '"'
    else if not hasSQuote then
      Result := '''' + s + ''''
    else if not hasBQuote then
      Result := '`' + s + '`'
    else
      Result := '"' + DoubleQuoteEscape(s) + '"';
  end;

  function SimpleValueToFd(e: CExp): fun.str;
  var
    val: PData;
    raw: fun.str;
  begin
    if e = nil then
    begin
      Result := 'null';
      Exit;
    end
    else if e.asObj <> nil then
    begin
      Result := '"(Object)"';
      Exit;
    end;
    val := PData(e.value);
    if (val = nil) or (val.VType <= varNull) then
    begin
      Result := 'null';
      Exit;
    end;
    raw := e.asStr;
    with val^ do
    begin
      if VType = varBoolean then
        Result := LowerCase(raw)
      else if isStr(VType) or (VType = 8209) then
        Result := QuoteFd(raw, false)
      else
        Result := raw;
    end;
  end;

  procedure WriteFdNode(node: CSet; level: fun.int);
  var
    i: fun.int;
    e: CExp;
    id: fun.str;
    childSet: CSet;
  begin
    id := SysUtils.Format('@%x', [fun.uint(fun.ptr(node.items))]);
    if hash.ItemById[id] <> nil then
    begin
      WriteIndent(level);
      add('"(Object)"');
      addLn();
      Exit;
    end;
    hash.ItemById[id] := node;

    for i := 0 to CExps.Count(node.items) - 1 do
    begin
      e := node.items.Item[i];

      WriteIndent(level);

      if (e <> nil) and (e.name <> '') then
        add(QuoteFd(e.name, true))
      else
        add('-');

      if (e <> nil) and (e.asObj <> nil) and (e.asObj is CSet) then
      begin
        childSet := CSet(e.asObj);
        if CExps.Count(childSet.items) = 0 then
        begin
          add(fun.char(kvd));
          if childSet is CNew2 then add('{}') else add('[]');
          addLn();
        end
        else
        begin
          addLn();
          WriteFdNode(childSet, level + 1);
        end;
      end
      else
      begin
        add(fun.char(kvd));
        add(SimpleValueToFd(e));
        addLn();
      end;
    end;
  end;

begin
  indentStyle := format;
  if indentStyle < 0 then indentStyle := 0;
  if indentStyle > 2 then indentStyle := 0;

  if kvd <> 32 then begin
    add('#!kvd:' + fun.char(kvd));
    addLn();
  end;
  WriteFdNode(cs, 0);
end;
