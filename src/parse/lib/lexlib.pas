const
  nl = #10;

function get_char: char;
begin
  if yyindex < Length(yystring) then
  begin
    Result := yystring[yyindex + 1];
    if Result = nl then
    begin
      Inc(yylineno);
      yycolno := 0;
    end;
    Inc(yyindex);
    Inc(yycolno);
  end
  else if yyindex = Length(yystring) then // 2012-09-15, fix bug for last line is .../...;
  begin
    Result := #0;
    Inc(yyindex);
  end
  else
  begin
    Result := #0;
    yydone := true;
  end;
end;

procedure unget_char(c: char);
begin
  Dec(yyindex);
  Dec(yycolno);
  // get_char() counts a newline when it reads it. A lexer rule that peeks
  // past the end of a line and then pushes it back must undo that count, or
  // the first token on the next line is reported one row too far. Debugger
  // breakpoints depend on CRune.row, so keep rows honest here.
  if c = nl then Dec(yylineno);
  if c = #0 then
  begin
    yyretval := 0;
  end;
end;

const

  max_matches = 1024;
  max_rules   = 256;

var

  yystext:   string;
  yysemi:    boolean;
  yysstate, yylstate: integer;
  yymatches: integer;
  yystack:   array [1..max_matches] of integer;
  yypos:     array [1..max_rules] of integer;
  yysleng:   byte;

procedure yymore;
begin
  yystext := yytext;
end;

procedure yyless(n: integer);
var
  i: integer;
begin
  for i := length(yytext) downto n + 1 do
    unget_char(yytext[i]);
  setlength(yytext, n);
end;

procedure reject;
var
  i: integer;
begin
  yyreject := True;
  for i := length(yytext) + 1 to yysleng do
    yytext := yytext + get_char;
  Dec(yymatches);
end;

procedure return(n: integer);
begin
  yyretval := n;
  yydone   := True;
end;

procedure returnc(c: char);
begin
  yyretval := Ord(c);
  yydone   := True;
end;

procedure _start(state: integer);
begin
  yysstate := state;
end;

function yywrap: boolean;
begin
  Result := True;
end;

procedure yynew;
begin
  if yylastchar <> #0 then
    if yylastchar = nl then
      yylstate := 1
    else
      yylstate := 0;
  yystate := yysstate + yylstate;
  yytext    := yystext;
  yystext   := '';
  yymatches := 0;
  yydone    := False;
end;

procedure yyscan;
begin
  yyactchar := get_char;
  yytext    := yytext + yyactchar;
end;

procedure yymark(n: integer);
begin
  yypos[n] := length(yytext);
end;

procedure yymatch(n: integer);
begin
  Inc(yymatches);
  yystack[yymatches] := n;
end;

function yyfind(var n: integer): boolean;
begin
  yyreject := False;
  while (yymatches > 0) and (yypos[yystack[yymatches]] = 0) do
    Dec(yymatches);
  if yymatches > 0 then
  begin
    yysleng := length(yytext);
    n := yystack[yymatches];
    yyless(yypos[n]);
    yypos[n] := 0;
    if length(yytext) > 0 then
      yylastchar := yytext[length(yytext)]
    else
      yylastchar := #0;
    Result := True;
  end
  else begin
    yyless(0);
    yylastchar := #0;
    Result     := False;
  end
end;

function yydefault: boolean;
begin
  yyreject  := False;
  yyactchar := get_char;
  if yyactchar <> #0 then
  begin
    //put_char(yyactchar);
    Result := True;
  end
  else if not yysemi then
  begin
    // End of input: hand the parser one implicit ';' so a final statement
    // written without its terminating semicolon is still reduced and run.
    // Only the end of input is affected; a missing ';' between statements
    // stays a syntax error (see CHANGELOG).
    yysemi   := True;
    yylstate := 1;
    yyretval := Ord(';');
    yydone   := True;
    Result   := True;
  end
  else begin
    yylstate := 1;
    Result   := False;
  end;
  yylastchar := yyactchar;
end;

procedure yyclear;
begin
  yysemi     := False;
  yysstate   := 0;
  yylstate   := 1;
  yylastchar := #0;
  yytext     := '';
  yystext    := '';
end;

