//[act-
  1:
                return(Num);
  2:
                return(Str);
  3:
                return(Time);
  4:
                return(Regex);

  5:
                ParseId(yytext);

  6:
                return(opConcat);
  7:
                return(opAddSub);
  8:
                return(opMulDiv);
  9:
                return(opPower);
  10:
                return(opBit);
  11:
                return(opCompare);
  12:
                return(_EQ);
  13:
                return(opAssign);
  14:
                return(opAny);
  15:
                return(opLambda);
  16:
                return(opPipe);
  17:
                returnc(yytext[1]);

  18:
                ;
  19:
                ;

//-act]