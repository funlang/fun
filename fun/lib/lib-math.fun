// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

########################################
# lib-math
########################################
#   built-in (6)
########################################
#     a.exp    () # e ^ a
#     a.log    () # LogE(a)
#     a.sin    ()
#     a.cos    ()
#     a.atan   ()
#     a.random () # 1.random(), 0.random(), a.random(), -1.random(seed = 0)
########################################

use 'lib-base.fun';

var pow(a, b) = a ^ b;
var sqrt(a)   = a ^ 0.5;

var exp(a)    = a.exp();
var log(a)    = a.log();
var log2(a)   = a.log() / 2.log();
var log10(a)  = a.log() / 10.log();

var sin(a)    = a.sin();
var cos(a)    = a.cos();
var tan(a)    = a.sin() / a.cos();
var atan(a)   = a.atan();
var asin(a)   = atan(a / sqrt(1 - a ^ 2));
var acos(a)   = atan(a / sqrt(1 - a ^ 2) * -1) + 2 * atan(1);

var pi()      = 1.atan() * 4;
var e()       = 1.exp();
var phi()     = (5^0.5+1)/2;

var max(a, b) = ifv(a > b, a, b);
var min(a, b) = ifv(a < b, a, b);
var abs(a)    = ifv(a < 0, a * -1, a);
var round(a, b) = a * 10^b div 1 / 10^b;
var floor(a)    = ifv(a div 1 > a, a div 1 - 1, a div 1);
var ceil(a)     = ifv(a div 1 < a, a div 1 + 1, a div 1);

var gcd(x, y) = y and gcd(y, x mod y) or x;
var lcm(x, y) = x * y / gcd(x, y);

var random()     = 1.random(); # return x in 0..1
var randomize()  = 0.random();
var randomint(a) = a.random(); # return x in 0..a
