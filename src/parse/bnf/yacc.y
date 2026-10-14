/* Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
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
//*************************************************************/

/*--start symbol definition*/
%start              Goal

/*--terminal definitions*/
%token              Id
%token              Num Str Time Regex

/*--keywords*/
%token              _if _case _loop _try _fun _class
%token              _elsif _when _else _except _finally
%token              _end _exit _next _raise _return
%token              _then _is _do _while _for _to _step _in
%token              _var _use
%token              _as _new _atom
%token              _true _false _null
%token              _div _mod _not _and _or _xor _bit

/*--operators*/
%token              opConcat
%token              opAddSub opMulDiv opPower
%token              opBit opBitNot
%token              opCompare
%token              opNot opAnd opOr

%token              opLambda

%token              opAssign
%token              opAny

/*--precedence definitions*/
%left               opPipe
%right              opLambda
%left               opOr
%left               opAnd
%right              opNot
%nonassoc           opCompare _in _EQ
%left               opConcat
%left               opAddSub
%left               opBit
%right              opBitNot
%left               opMulDiv
%left               opPower
%right              UMINUS

/*--type definitions*/

%%

/*--goal*/
Goal        : Run                       { yyaccept; }
            | error                     { builder.BuildError($1); yyabort; }
            ;

/*--statement*/
Run         : _if    Exp _then          { builder.BuildIf($1, $3, $2); }
            | _elsif Exp _then          { builder.BuildIf($1, $3, $2, true); }
            | _else                     { builder.BuildElse($1); }
            
            | _case Exp _is             { builder.BuildCase($1, $3, $2); }
            | _when Exp _do             { builder.BuildWhen($1, $3, $2); }
            
            |                                   _loop       { builder.BuildLoop($1); }
            | _while      Exp                    Loop       { builder.BuildLoop($1, $3, $2); }
            | _for        Id        _in Exp      Loop       { builder.BuildForIn($1, $5, $2, $4); }
            | _for Id ":" Id        _in Exp      Loop       { builder.BuildForIn($1, $7, $4, $6, $2.text); }
            | _for        Id "," Id _in Exp      Loop       { builder.BuildForIn($1, $7, $2, $6, '', $4.text); }
            | _for Id ":" Id "," Id _in Exp      Loop       { builder.BuildForIn($1, $9, $4, $8, $2.text, $6.text); }
            | _for Id _EQ Exp _to Exp            Loop       { builder.BuildFor($1, $7, $2, $4, $6); }
            | _for Id _EQ Exp _to Exp _step Exp  Loop       { builder.BuildFor($1, $9, $2, $4, $6, $8.node); }
            
            | _try                      { builder.BuildTry($1); }
            | _except                   { builder.BuildExcept($1); }
            | _finally                  { builder.BuildFinally($1); }
            
            | _fun   Id            FunA { builder.BuildFun($1, $3, $2, $3); }
            | _class Id            FunA { builder.BuildClass($1, $3, $2, $3); }
            | _class Id _EQ VarExp FunA { builder.BuildClass($1, $5, $2, $5, $4.node); }
            
            | Cmd ";"                   { }
            |     ";"                   { }
            |     "}"                   { if builder.BuildEnd($1).val = -1 then yy_done; }
            | Cmd "}"                   { if builder.BuildEnd($2).val = -1 then yy_done; }
            ;

Loop        : _loop                     { }
            | _do                       { }
            ;

Bloc        : _if                       { }
            | _case                     { }
            | _loop                     { }
            | _do                       { }
            | _try                      { }
            | _fun                      { }
            | _class                    { }
            ;

Cmd         : _end Bloc                 { builder.BuildEnd($1, $2, $2); }
            
            | _exit                     { builder.BuildExit($1); }
            | _exit _when Exp           { builder.BuildExit($1, $3, $3); }
            | _next                     { builder.BuildNext($1); }
            | _next _when Exp           { builder.BuildNext($1, $3, $3); }
            | _return                   { builder.BuildReturn($1); }
            | _return     Exp           { builder.BuildReturn($1, $2, $2); }
            | _raise      Exp           { builder.BuildRaise($1, $2, $2); }
            
            | _use Str                  { builder.BuildUse($1, $2, $2); }
            | _use Str _as Id           { builder.BuildUse($1, $4, $2, $4.text); }
            
            | _var Id                   { builder.BuildVar($1, $2, $2); }
            | _var Id _EQ Exp           { builder.BuildVar($1, $4, $2, $4.node); }

            | _var Id FunA _EQ          { builder.BuildVar($1, $4, $2, builder.BuildFunDef($1, $4, $3.node, true, $2.text).node, true); }
                               Exp      { builder.BuildReturn($$, $$, $$); builder.BuildEnd($$, true); }
            
            | Left _EQ      Exp         { builder.BuildSet($1, $3, $1, $3); }
            | Left opAssign Exp         { builder.BuildSet($1, $3, $1, $3, $2.text); }
            
            | FunCall                   { builder.BuildCall($1); }
            | "?"     Exp               { builder.BuildEcho($1, $2, $2); }
            | "?" "." Exp               { builder.BuildEcho($1, $3, $3, #13#10); }
            | "?" "," Exp               { builder.BuildEcho($1, $3, $3, ' '); }
            | "?" ":" Exp               { builder.BuildEcho($1, $3, $3, #9); }
            ;

/*--expression*/
Exp2        : Exp opOr      Exp         { $$ := builder.CreateExp($1, $3, $1, $2, $3); }
            | Exp opAnd     Exp         { $$ := builder.CreateExp($1, $3, $1, $2, $3); }
            |     opNot     Exp         { $$ := builder.CreateExp($1, $2, $1, $2); }
            | Exp opCompare Exp         { $$ := builder.CreateExp($1, $3, $1, $2, $3); }
            | Exp  _EQ      Exp         { $$ := builder.CreateExp($1, $3, $1, $2, $3); }
            | Exp  _in      Exp         { $$ := builder.CreateExp($1, $3, $1, $2, $3); }
            | Exp opConcat  Exp         { $$ := builder.CreateExp($1, $3, $1, $2, $3); }
            | Exp opAddSub  Exp         { $$ := builder.CreateExp($1, $3, $1, $2, $3); }
            | Exp opBit     Exp         { $$ := builder.CreateExp($1, $3, $1, $2, $3, true); }
            |     opBitNot  Exp         { $$ := builder.CreateExp($1, $2, $1, $2, true); }
            | Exp opMulDiv  Exp         { $$ := builder.CreateExp($1, $3, $1, $2, $3); }
            | Exp opPower   Exp         { $$ := builder.CreateExp($1, $3, $1, $2, $3); }

            | _fun FunA "{"             { $$ := builder.BuildFunDef($1, $3, $2.node); }
            |      FunA "{"             { $$ := builder.BuildFunDef($1, $2, $1.node); }
            |           "{"             { $$ := builder.BuildFunDef($1, $1, nil); }
            | FunA opLambda             { $$ := builder.BuildFunDef($1, $2, $1.node, true); yylast := $$; }
                            Exp         { builder.BuildReturn($$, $$, $$); builder.BuildEnd($$, true); $$ := yylast; }
            | Id   opLambda             { $$ := builder.BuildFunDef($1, $2, builder.CreateNames($1).node, true); yylast := $$; }
                            Exp         { builder.BuildReturn($$, $$, $$); builder.BuildEnd($$, true); $$ := yylast; }
            |      opLambda             { $$ := builder.BuildFunDef($1, $1, nil, true); yylast := $$; }
                            Exp         { builder.BuildReturn($$, $$, $$); builder.BuildEnd($$, true); $$ := yylast; }

            | _fun FunCall              { $$ := builder.CreateFunFun($1, $2, $2); }
            | _new SetConst             { $$ := builder.CreateSetNew($1, $2, $2); }
            | _var Id                   { $$ := builder.CreateRef($1, $2, $2); }

            | VarExp opAny BasExp       { $$ := builder.CreateDotAny($1, $3, $1, $2, $3); }
            | Exp opPipe VarExp         { $$ := builder.CreateFunExp($1, $3, $3, builder.CreateValues($1)); }
            | Exp opPipe FunCall        { $$ := builder.CreateFunExp($1, $3, builder.CreateFunFun($3, $3, $3), builder.CreateValues($1)); }
            ;

Exp         : Exp2                      { }
            | BasExp                    { }
            ;

BasExp      : Const                     { }
            | Left                      { }
            | FunCall                   { }
            | "(" Exp2 ")"              { $$ := builder.CreateExp($1, $3, $2); }
            ;

Left        : VarExp                    { }
            | SetIndex                  { }
            ;

VarExp      : Id                        { $$ := builder.CreateId($1); }
            | Id "?"                    { $$ := builder.CreateId($1, true); }
            | BasExp "." Id             { $$ := builder.CreateVarExp($1, $3, $1, $3); }
            | BasExp "." Id "?"         { $$ := builder.CreateVarExp($1, $4, $1, $3, false, true); }
            | BasExp "." Str            { $$ := builder.CreateVarExp($1, $3, $1, $3, true); }
            ;

Const       : Num                       { $$ := builder.CreateNum($1); }
            | opAddSub Num %prec UMINUS { $$ := builder.CreateNum($2, $1.text); }
            | Str                       { $$ := builder.CreateStr($1); }
            | Time                      { $$ := builder.CreateTime($1); }
            | _true                     { $$ := builder.CreateConst($1, true); }
            | _false                    { $$ := builder.CreateConst($1, false); }
            | _null                     { $$ := builder.CreateConst($1, NullValue); }
            | Regex                     { $$ := builder.CreateRegex($1); }
            | SetConst                  { }
            ;

/*--fun and set*/
FunA        : "(" Names ")"             { $$ := builder.CreateNames($1, $3, $2); }
            ;

FunCall     : BasExp "(" Values ")"     { $$ := builder.CreateFunExp($1, $4, $1, $3); }
            ;

SetConst    : "[" Values "]"            { $$ := builder.CreateSetConst($1, $3, $2); }
            | "[" Values "," "]"        { $$ := builder.CreateSetConst($1, $4, $2); }
            ;

SetIndex    : BasExp "[" Exp "]"        { $$ := builder.CreateSetIndex($1, $4, $1, $3); }
            | BasExp "." "[" Exp "]"    { $$ := builder.CreateSetIndex($1, $5, $1, $4, '.'); }
            ;

Names       :                           { $$ := EmptyResult; }
            |           Id              { $$ := builder.CreateNames($1); }
            | Names "," Id              { $$ := builder.CreateNames($1, $3, $1, $3); }
            ;

Values      :                           { $$ := EmptyResult; }
            |            Value          { $$ := builder.CreateValues($1); }
            | Values "," Value          { $$ := builder.CreateValues($1, $3, $1, $3); }
            ;

Value       :         Exp               { }
            | Id  ":" Exp               { $$ := builder.CreateValue($1, $3, $1, $3); }
            | Str ":" Exp               { $$ := builder.CreateValue($1, $3, $1, $3, true); }
            ;

%%
