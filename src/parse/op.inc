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

function ParseOp(const s: fun.str; bit: fun.bool = false): fun.char;
var
  i: fun.int;
begin
  result := s[1];
  i := Length(s);
  if i = 2 then
  begin
    if s[1] = s[2] then
    begin
      case s[1] of
        '<':  result := 'l'; // <<
        '>':  result := 'r'; // >>
      end;
    end
    else
    begin
      case s[2] of
        '=':  case s[1] of
                '<': result := 'l'; // <=
                '>': result := 'g'; // >=
              end;
        '~':  case s[1] of
                '=': result := '~'; // =~
                '!': result := '$'; // !~
              end;
        else  begin
                if s = '<>' then result := '!';
              end;
      end;
    end;
  end;
  if bit then result := fun.char( Ord(result) - ( Ord('a')-Ord('A') ) );
end;
