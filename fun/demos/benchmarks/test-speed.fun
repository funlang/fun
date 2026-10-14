use 'lib-time.fun';

fun test(s, f)
  var t = tick(-2);
  f();
  ?. s & ' : ' & t.get();
end fun;

var ii = 100000000;
?. ii;
test('blank  ', {for i=1 to ii do                end do});
ii = 1000000;
?. ii;
test('1+2    ', {for i=1 to ii do var a=1+2    ; end do});
test('1.1+2  ', {for i=1 to ii do var a=1.1+2  ; end do});
test('1+2.1  ', {for i=1 to ii do var a=1+2.1  ; end do});
test('1.1+2.1', {for i=1 to ii do var a=1.1+2.1; end do});
test('1-2    ', {for i=1 to ii do var a=1-2    ; end do});
test('1.1-2  ', {for i=1 to ii do var a=1.1-2  ; end do});
test('1-2.1  ', {for i=1 to ii do var a=1-2.1  ; end do});
test('1.1-2.1', {for i=1 to ii do var a=1.1-2.1; end do});
test('1*2    ', {for i=1 to ii do var a=1*2    ; end do});
test('1.1*2  ', {for i=1 to ii do var a=1.1*2  ; end do});
test('1*2.1  ', {for i=1 to ii do var a=1*2.1  ; end do});
test('1.1*2.1', {for i=1 to ii do var a=1.1*2.1; end do});
test('1/2    ', {for i=1 to ii do var a=1/2    ; end do});
test('1.1/2  ', {for i=1 to ii do var a=1.1/2  ; end do});
test('1/2.1  ', {for i=1 to ii do var a=1/2.1  ; end do});
test('1.1/2.1', {for i=1 to ii do var a=1.1/2.1; end do});
var i1 = 1;
var i2 = 2;
var d1 = 1.1;
var d2 = 2.1;
test('i1+i2  ', {for i=1 to ii do var a=i1+i2  ; end do});
test('d1+i2  ', {for i=1 to ii do var a=d1+i2  ; end do});
test('i1+d2  ', {for i=1 to ii do var a=i1+d2  ; end do});
test('d1+d2  ', {for i=1 to ii do var a=d1+d2  ; end do});
test('i1-i2  ', {for i=1 to ii do var a=i1-i2  ; end do});
test('d1-i2  ', {for i=1 to ii do var a=d1-i2  ; end do});
test('i1-d2  ', {for i=1 to ii do var a=i1-d2  ; end do});
test('d1-d2  ', {for i=1 to ii do var a=d1-d2  ; end do});
test('i1*i2  ', {for i=1 to ii do var a=i1*i2  ; end do});
test('d1*i2  ', {for i=1 to ii do var a=d1*i2  ; end do});
test('i1*d2  ', {for i=1 to ii do var a=i1*d2  ; end do});
test('d1*d2  ', {for i=1 to ii do var a=d1*d2  ; end do});
test('i1/i2  ', {for i=1 to ii do var a=i1/i2  ; end do});
test('d1/i2  ', {for i=1 to ii do var a=d1/i2  ; end do});
test('i1/d2  ', {for i=1 to ii do var a=i1/d2  ; end do});
test('d1/d2  ', {for i=1 to ii do var a=d1/d2  ; end do});
test('d1/d2+3', {for i=1 to ii do var a=d1/d2+3; end do});
test('d1/2+3 ', {for i=1 to ii do var a=d1/2+3 ; end do});
test('i1/2+3 ', {for i=1 to ii do var a=i1/2+3 ; end do});
test('1/2+3  ', {for i=1 to ii do var a=1/2+3  ; end do});
test('1/2+3.1', {for i=1 to ii do var a=1/2+3.1; end do});
test('1      ', {for i=1 to ii do var a=1      ; end do});
test('"1"&"2"', {for i=1 to ii do var a="1"&"2"; end do});
test('1&2    ', {for i=1 to ii do var a=1&2    ; end do});
test('"1"+"2"', {for i=1 to ii do var a="1"+"2"; end do});
var f  = {};
var f1 = (a){};
var f2 = (a,b){};
var g  = {var a=1};
test('f()    ', {for i=1 to ii do f()          ; end do});
test('=f()   ', {for i=1 to ii do var a=f()    ; end do});
test('f1()   ', {for i=1 to ii do f1()         ; end do});
test('f2()   ', {for i=1 to ii do f2()         ; end do});
test('f1(1)  ', {for i=1 to ii do f1(1)        ; end do});
test('f2(1)  ', {for i=1 to ii do f2(1)        ; end do});
test('f2(1,2)', {for i=1 to ii do f2(1,2)      ; end do});
test('g()    ', {for i=1 to ii do g()          ; end do});
test('1>2    ', {for i=1 to ii do var a=1>2    ; end do});
test('if 1>2 ', {for i=1 to ii do if 1>2 then end if; end do});
class Number(me)
  this['+'] = fun (you) {
    //return me + you;
  };
  var f = {};
end class;
var n = Number(1);
test('n .+ 2 ', {for i=1 to ii do var a= n .+ 2; end do});
test('n.f()  ', {for i=1 to ii do n.f()        ; end do});
test('=n.f() ', {for i=1 to ii do var a=n.f()  ; end do});

#*
100000000
blank   : 642
1000000
1+2     : 78
1.1+2   : 94
1+2.1   : 78
1.1+2.1 : 94
1-2     : 94
1.1-2   : 78
1-2.1   : 94
1.1-2.1 : 94
1*2     : 78
1.1*2   : 94
1*2.1   : 94
1.1*2.1 : 79
1/2     : 94
1.1/2   : 78
1/2.1   : 94
1.1/2.1 : 94
i1+i2   : 141
d1+i2   : 141
i1+d2   : 141
d1+d2   : 140
i1-i2   : 141
d1-i2   : 141
i1-d2   : 141
d1-d2   : 141
i1*i2   : 156
d1*i2   : 141
i1*d2   : 141
d1*d2   : 141
i1/i2   : 157
d1/i2   : 141
i1/d2   : 141
d1/d2   : 156
d1/d2+3 : 172
d1/2+3  : 157
i1/2+3  : 141
1/2+3   : 125
1/2+3.1 : 125
1       : 47
"1"&"2" : 267
1&2     : 266
"1"+"2" : 329
f()     : 94
=f()    : 125
f1()    : 109
f2()    : 126
f1(1)   : 141
f2(1)   : 156
f2(1,2) : 157
g()     : 141
1>2     : 172
if 1>2  : 157
n .+ 2  : 375
n.f()   : 298
=n.f()  : 344
#
