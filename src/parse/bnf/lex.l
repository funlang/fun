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

l               [$_@-Za-z]
d               [0-9]
ds              {d}+
x               [0-9A-Fa-f]
xs              {x}+

num             {ds}(\.{ds})?([Ee][-+]?{ds})?|\.{ds}|0[Xx]{xs}|0[Bb][01]+
st1             \'([^\']*|\'\')*\'|\"([^\"]*|\"\")*\"|\`([^\`]*|\`\`)*\`
str               {st1}|\`[^\`]*\`{id}\`[^\`]*\`
time            @({st1})
regex           \/[^\/\000- ]+\/[a-z]*|\%[^\%\000- ]+\%[a-z]*|\$({st1})[a-z]*

id              {l}({l}|{d})*

opConcat        "&"
opAddSub        "+"|"-"
opMulDiv        "*"|"/"
opPower         "^"
opBit           "<<"|">>"
opCompare       "<"|">"|"!="|"<>"|"<="|">="|"=~"|"!~"
opEQ            "="
opAssign        [\+\-\*\&]\=
opAny           \.[\~\!\#\%\^\&\*\-\+\=\\\|\<\>\/\?]+
opLambda        "->"
opPipe          "|"
opOther         [\?\;\:\,\.\(\)\[\]\{\}]

blank           [\001- ]+
comment         #([^*][^\n]*\n?|\*[^#]*#)|"//"[^\n]*\n?

%start

%%

{num}           return(Num);
{str}           return(Str);
{time}          return(Time);
{regex}         return(Regex);

{id}            ParseId(yytext);

{opConcat}      return(opConcat);
{opAddSub}      return(opAddSub);
{opMulDiv}      return(opMulDiv);
{opPower}       return(opPower);
{opBit}         return(opBit);
{opCompare}     return(opCompare);
{opEQ}          return(_EQ);
{opAssign}      return(opAssign);
{opAny}         return(opAny);
{opLambda}      return(opLambda);
{opPipe}        return(opPipe);
{opOther}       returnc(yytext[1]);

{comment}       ;
{blank}         ;

%%
