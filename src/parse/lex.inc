//%%
{$I 'ltab.inc'}

function lex() : integer;

{$I 'id.inc'}

procedure yyaction ( yyruleno : Integer );
//%%
begin
  case yyruleno of
//%%
{$I 'lact.inc'}
  end;
end;

//%%

var yyn : Integer;

label start, scan, action;

begin

start:

  yynew;

scan:

  for yyn := yykl[yystate] to     yykh[yystate] do yymark(yyk[yyn]);
  for yyn := yymh[yystate] downto yyml[yystate] do yymatch(yym[yyn]);

  if yytl[yystate]>yyth[yystate] then goto action;

  yyscan;

  yyn := yytl[yystate];
  // modify 2010-04-14: b -> Integer, + Unicode IDs and Keywords
  //while (yyn<=yyth[yystate]) and not (yyactchar in yyt[yyn].cc{$IfDef _B_}=yyt[yyn].b{$EndIf}) do inc(yyn);
  {$IfDef _B_}
  while (yyn<=yyth[yystate]) and not (
                                       (yyactchar in yyt[yyn].cc = (yyt[yyn].b <> 0)) or
                                       ((Ord(yyactchar) > $ff) and (yyt[yyn].b = 2))
                                     ) do inc(yyn);
  {$Else}
  while (yyn<=yyth[yystate]) and not (yyactchar in yyt[yyn].cc) do inc(yyn);
  {$EndIf}
  // end of modify
  if yyn>yyth[yystate] then goto action;

  yystate := yyt[yyn].s;

  goto scan;

action:

  if yyfind(yyrule) then
    begin
      yyaction(yyrule);
      if yyreject then goto action;
    end
  else if not yydefault and yywrap then
    begin
      yyclear;
      return(0);
    end;

  if not yydone then goto start;

  Result := yyretval;

end;

