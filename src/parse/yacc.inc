//%%
{$I 'ycon.inc'}
{$I 'ytab.inc'}

type
  TParser = class
  private
    yystring: string;
    yyindex, yylineno, yycolno: integer;
    yytext: string;

    yystate:    integer;
    yyactchar:  char;
    yylastchar: char;
    yyrule:     integer;
    yyreject:   boolean;
    yydone:     boolean;
    yyretval:   integer;
    // Last token returned by the lexer, and whether the last shifted '.'
    // was member access (not the echo operator `?.`).
    yyPrevToken: integer;
    yyDotIsMember: boolean;
  private
    function yacc_parse(dontClear: fun.bool = false) : integer;
  public
    builder : CParser;
    function parse(const s: fun.str) : integer;
  end;

function TParser.parse(const s: fun.str) : integer;
begin
  yystring := s;
  result   := yacc_parse();
end;

{$IfNDef FPC}
var AX: array[1..max_act] of Pointer;
type _Act_ = procedure();
{$EndIf}

function TParser.yacc_parse(dontClear: fun.bool = false) : integer;

{$I 'lib\yacclib.pas'}
{$I 'lib\lexlib.pas'}
{$I 'lex.inc'}

var
  yystate, yysp, yyn : Integer;
  yys : array [1..yymaxdepth] of Integer;
  yyv : array [1..yymaxdepth] of YYSType;
  yyval : YYSType;
  yylval, yylast : YYSType;
  yylret, yylsp : integer;

procedure yyaction ( yyruleno : Integer );
{$IfNDef FPC}
{$I 'yact.inc'}
{$EndIf}
//%%
begin
{$IfDef FPC}
  case yyruleno of
//%%
{$I 'yact.inc.fpc'}
  end;
{$Else}
  if AX[1] = nil then AX_Init;
  asm
    push ebp
  end;
  _Act_(AX[yyruleno])();
  asm
    pop ecx
  end;
{$EndIf}
end;

//%%

const _error = 256;

function yyact(state, sym : Integer; var act : Integer) : Boolean;
var k : Integer;
begin
  k := yyal[state];
  while (k<=yyah[state]) and (yya[k].sym<>sym) do inc(k);
  if k>yyah[state] then
    yyact := false
  else
  begin
    act := yya[k].act;
    yyact := true;
  end;
end;

function yycan(state, sym : Integer) : Boolean;
var act : Integer;
begin
  result := yyact(state, sym, act);
end;

function yygoto(state, sym : Integer; var nstate : Integer) : Boolean;
var k : Integer;
begin
  k := yygl[state];
  while (k<=yygh[state]) and (yyg[k].sym<>sym) do inc(k);
  if k>yygh[state] then
    yygoto := false
  else
  begin
    nstate := yyg[k].act;
    yygoto := true;
  end;
end;

function yycharsym(i : Integer) : String;
begin
  if (i >= 1) and (i <= 255) then
  begin
    if i < 32 then
    begin
      if i = 9 then
        Result := #39'\t'#39
      else if i = 10 then
        Result := #39'\f'#39
      else if i = 13 then
        Result := #39'\n'#39
      else
        Result := #39'\0x' + IntToHex(i,2) + #39;
    end
    else
      Result := #39 + Char(i) + #39;
    Result := ' literal ' + Result;
  end
  else
  begin
    if i < -1 then
      Result := ' unknown'
    else if i = -1 then
      Result := ' token $accept'
    else if i = 0 then
      Result := ' token $eof'
    else if i = 256 then
      Result := ' token $error'
{$ifdef yyextradebug}
    else if i <= yymaxtoken then
      Result := ' token ' + yytokens[yychar].tokenname
    else
      Result := ' unknown token';
{$else}
    else
      Result := ' token';
{$endif}
  end;
  Result := Result + ' ' + IntToStr(yychar);
end;

label start, done, parse, next, error, errlab, shift, reduce, accept, abort;

begin

  yyclear();
  if not dontClear then yylineno := 1;
  yylret := 0;
  yylsp  := 0;

start:

  yystate := 0; yychar := -1; yyerrflag := 0; yysp := 0;
  yyPrevToken := -1;
  yyDotIsMember := false;

parse:

  inc(yysp);
  if yysp>yymaxdepth then
  begin
    builder.DoError('yyparse stack overflow');
    goto abort;
  end;
  yys[yysp] := yystate; yyv[yysp] := yyval;

next:

  if (yyd[yystate]=0) and (yychar=-1) then
  begin
    if yylret = 1 then
    begin
      yylret := 0;
      // Never re-feed the internal error token: shifting it as `error`
      // aborts again before the lexer can advance, which loops forever.
      // Lex the next token instead.
      if (yylsp = 1) or (yylval.val = _error) then goto next;
      yychar := yylval.val;
    end
    else
    begin
      yychar := lex();
      if yychar<0 then yychar := 0;

      if yyretval = 0 then goto done;

      yylval.val   := yychar;
      yylval.text  := yytext;
      yylval.node  := nil;
      {$IfNDef OnlyRuntime}
      yylval.index := yyindex;
      yylval.leng  := Length(yytext);
      yylval.row   := yylineno;
      yylval.col   := yycolno - yylval.leng + 1; // + 1 for IDE in SynEdit
      {$EndIf}
    end;
  end;

  {$IFDEF YYDEBUG}writeln('state ', yystate, yycharsym(yychar));{$ENDIF}

  yyn := yyd[yystate];
  if yyn<>0 then goto reduce;

  if not yyact(yystate, yychar, yyn) then goto error
  else if yyn>0 then                      goto shift
  else if yyn<0 then                      goto reduce
  else                                    goto accept;

error:

errlab:

  if yyerrflag<=2 then
  begin
    yyerrflag := 3;
    yylsp := yysp;
    while (yysp>0) and not ( yyact(yys[yysp], _error, yyn) and
                             (yyn>0) ) do
    begin
      {$IFDEF YYDEBUG}
        if yysp>1 then
          writeln('error recovery pops state ', yys[yysp], ', uncovers ',
                  yys[yysp-1])
        else
          writeln('error recovery fails ... abort');
      {$ENDIF}
      
      // Free the Error Nodes
      if yyv[yysp].node <> nil then TObject(yyv[yysp].node).Free;
      
      dec(yysp);
    end;
    if yysp=0 then goto abort;
    yystate := yyn;
    goto parse;
  end
  else
  begin
    {$IFDEF YYDEBUG}writeln('error recovery discards ' + yycharsym(yychar));{$ENDIF}
    if yychar=0 then goto abort;
    yychar := -1; goto next;
  end;

shift:

  if yychar = Ord('.') then
    yyDotIsMember := not yycan(yyn, Num);
  yystate := yyn; yychar := -1; yyval := yylval;
  if yyerrflag>0 then dec(yyerrflag);

  goto parse;

reduce:

  {$IFDEF YYDEBUG}writeln('reduce ' + IntToStr(-yyn) {$IFDEF YYEXTRADEBUG} + ' rule ' + yyr[-yyn].symname {$ENDIF});{$ENDIF}

  yyflag := yyfnone; yyaction(-yyn);
  dec(yysp, yyr[-yyn].len);
  if yygoto(yys[yysp], yyr[-yyn].sym, yyn) then yystate := yyn;

  case yyflag of
    yyfaccept : goto accept;
    yyfabort  : goto abort;
    yyferror  : goto errlab;
    yyfdone   : goto done;
  end;

  goto parse;

accept:

  yylret := 0; goto start;

abort:

  yylret := 1; goto start;

done:

  result := 0;

end;
