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

procedure ParseFD(const s: fun.str);
type
  TParseState = (stLineStart, stKey);
  TCharSet = set of AnsiChar;
const
  Whitespace: TCharSet = [' ', #9];
  LineBreak: TCharSet = [#10, #13];
  Digit: TCharSet = ['0'..'9'];
var
  pos, pold: fun.int;
  curDepth, newDepth: fun.int;
  pendingKey: fun.str;
  state: TParseState;
  key: fun.str;
  val: CData;
  parseError: fun.bool;
  parseErrMsg: fun.str;
  parseErrPos: fun.int;
  kvd: TCharSet;

  procedure SyntaxError(const msg: fun.str);
  begin
    parseError := True;
    if parseErrMsg = '' then
    begin
      parseErrMsg := msg;
      parseErrPos := pos;
    end;
  end;

  procedure SkipWhile(const chSet: TCharSet);
  begin
    while (pos <= Length(s)) and (s[pos] in chSet) do Inc(pos);
  end;

  procedure SkipUntil(const chSet: TCharSet);
  begin
    while (pos <= Length(s)) and not (s[pos] in chSet) do Inc(pos);
  end;

  function ExtractUntil(const chSet: TCharSet): fun.str;
  var
    start: fun.int;
  begin
    start := pos;
    SkipUntil(chSet);
    Result := Copy(s, start, pos - start);
  end;

  function ExtractWhile(const chSet: TCharSet): fun.str;
  var
    start: fun.int;
  begin
    start := pos;
    SkipWhile(chSet);
    Result := Copy(s, start, pos - start);
  end;

  function ParseQuoted(delim: fun.char; needEscape: fun.bool): fun.str;
  begin
    Result := '';
    Inc(pos);
    while True do
    begin
      Result := Result + ExtractUntil([delim]);
      if (pos + 1 <= Length(s)) and (s[pos + 1] = delim) then
      begin
        Result := Result + delim;
        Inc(pos, 2);
      end
      else
      begin
        Inc(pos);
        Break;
      end;
    end;
    if needEscape then
      Result := esc(Result);
  end;

  function ParseFixedLength: fun.str;
  var
    prefix: fun.str;
    i: fun.int;
    hexLen: fun.int;
    lenStr: fun.str;
    dataLen: fun.int;
  begin
    Result := '';
    prefix := ExtractWhile(['x', 'X']);
    if prefix = '' then Exit;
    if Length(prefix) > 2 then SetLength(prefix, 2);
    hexLen := 0;
    for i := 1 to Length(prefix) do
      if prefix[i] = 'x' then
        hexLen := hexLen + 4
      else
        hexLen := hexLen + 6;
    if pos + hexLen - 1 > Length(s) then
    begin
      SyntaxError('Incomplete fixed-length length specifier');
      Exit;
    end;
    lenStr := Copy(s, pos, hexLen);
    Inc(pos, hexLen);
    dataLen := StrToInt('$' + lenStr);
    if pos + dataLen - 1 > Length(s) then
    begin
      SyntaxError('Truncated fixed-length data');
      Exit;
    end;
    Result := Copy(s, pos, dataLen);
    Inc(pos, dataLen);
  end;

  function ParseRawToken(const stopSet: TCharSet; out isQuoted: fun.bool): fun.str;
  var
    c: fun.char;
    needEscape: fun.bool;
    token: fun.str;
  begin
    token := '';
    isQuoted := False;
    if parseError then Exit;
    SkipWhile(Whitespace);
    if pos > Length(s) then Exit;

    needEscape := False;
    if (s[pos] = '\') and (pos+1 <= Length(s)) and (s[pos+1] in ['"', '''', '`']) then
    begin
      needEscape := True;
      Inc(pos);
    end;

    c := s[pos];
    if c in ['"', '''', '`'] then
    begin
      isQuoted := True;
      if (c = '`') and (pos+1 <= Length(s)) and (s[pos+1] = '`') then
      begin
        Inc(pos, 2);
        token := ParseFixedLength;
      end
      else
      begin
        token := ParseQuoted(c, needEscape);
      end;
    end
    else
    begin
      token := ExtractUntil(stopSet);
    end;
    Result := token;
  end;

  function ParseKey: fun.str;
  var
    isQuoted: fun.bool;
  begin
    Result := ParseRawToken(kvd + LineBreak, isQuoted);
  end;

  function ParseValue: CData;
  var
    token: fun.str;
    isQuoted: fun.bool;
  begin
    Result.VType := VarEmpty;
    token := ParseRawToken(LineBreak, isQuoted);
    if parseError then Exit;
    if isQuoted then
      CValue(Result) := token
    else
    begin
      token := Trim(token);
      if token = '[]' then
        setObj(PValue(@Result), CNew.new(nil).parse(CExps.create), VarObjNew)
      else if token = '{}' then
        setObj(PValue(@Result), CNew2.new(nil).parse(CExps.create), VarObjNew)
      else if token = 'true' then
        CValue(Result) := True
      else if token = 'false' then
        CValue(Result) := False
      else if token = 'null' then
        CValue(Result) := NullValue
      else if token = '' then
        CValue(Result) := ''
      else if (token[1] >= '0') and (token[1] <= '9') or (token[1] = '-') then
      try
        CValue(Result) := CParser.StrToNum(token);
      except
        CValue(Result) := token;
      end
      else
        CValue(Result) := token;
    end;
  end;

  function ParseDepth: fun.int;
  var
    blanks: fun.str;
    gts, nums: fun.str;
  begin
    blanks := ExtractWhile(Whitespace);
    gts := ExtractWhile(['>']);
    if gts <> '' then
    begin
      SkipWhile(Whitespace);
      Result := Length(gts);
      Exit;
    end;
    nums := ExtractWhile(Digit);
    if (nums <> '') and (pos <= Length(s)) and (s[pos] = '>') then
    begin
      Inc(pos);
      SkipWhile(Whitespace);
      Result := StrToInt(nums);
      Exit;
    end;
    blanks := NewStringReplace(blanks, #9, '  ', [rfReplaceAll]);
    Result := Length(blanks) div 2;
  end;

begin
  Root := nil;
  Level := 0;
  SetLength(Stack, 0);
  Push('');
  pos := 1;
  curDepth := 0;
  pendingKey := '';
  state := stLineStart;
  parseError := False;
  kvd := Whitespace;

  while (pos <= Length(s)) and not parseError do
  begin
    case state of
      stLineStart:
      begin
        newDepth := ParseDepth;
        if pos > Length(s) then Break;
        if s[pos] in LineBreak then
        begin
          SkipWhile(LineBreak);
          Continue;
        end;
        if s[pos] = '#' then
        begin
          pold := pos;
          SkipUntil(LineBreak);
          if ((pos - pold) > 6) and (Copy(s, pold, 6) = '#!kvd:') then kvd := [s[pold+6]];
          SkipWhile(LineBreak);
          Continue;
        end;
        while curDepth > newDepth do
        begin
          Pop;
          Dec(curDepth);
        end;
        if newDepth > curDepth then
        begin
          if pendingKey = '' then
            SyntaxError('Unexpected indentation increase')
          else
          begin
            if pendingKey = '-' then
              Push('')
            else
              Push(pendingKey);
            pendingKey := '';
            curDepth := newDepth;
          end;
        end;
        if parseError then Break;
        state := stKey;
      end;

      stKey:
      begin
        key := ParseKey;
        if parseError then Break;
        SkipWhile(kvd);
        if (pos > Length(s)) or (s[pos] in LineBreak) then
        begin
          pendingKey := key;
          state := stLineStart;
          SkipWhile(LineBreak);
          Continue;
        end;
        val := ParseValue;
        if parseError then Break;
        SkipWhile(LineBreak);
        if key = '-' then
          GetVal('', @val)
        else
          GetVal(key, @val);
        state := stLineStart;
      end;
    end;
  end;

  if parseError then
  begin
    StrictFail(parseErrMsg, parseErrPos);
    ReleaseTree;
  end;
  while Level > 1 do Pop;
end;