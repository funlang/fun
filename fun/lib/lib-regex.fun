// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

########################################
# lib-regex
########################################
#   built-in (3)
########################################
#   match:
#     str.match(str)           # match only in string form
#
#     str.match(reg)           # match in regex pattern
#     reg.match(str)           # match in regex pattern
#     str.match(reg, action)   # match in regex pattern
#     reg.match(str, action)   # match in regex pattern
#
#   replace:
#     str.replace(str, newstr) # replace all in string form
#
#     str.replace(reg, newone) # replace in regex pattern
#     reg.replace(str, newone) # replace in regex pattern
#
#   toRegex:
#     str.toRegex(options)     # options: g, i, m, s, u, x
########################################
# 1. str: string
#    reg: regex
# 2. if 'g' in regex option, match() return a list of matched string
#      if action exists, the action will be performed with a match
#         object argument for every match, and return string concated
#         from the return value of the action
#    or, match() return a match object with all matched groups
#                           (matched string is 0 of the groups)
#      if action exists, the action will be performed with the match
#         object one time, and return string from the return value of
#         the action
# 3. if newone is string, replace with the string one time or all
#       (according to 'g')
#    or if newone is action (function), replace with the return value
#       of the action
# 4. options:
#    g - global, match or replace all
#    i - ignore case, case insensitive
#    m - multiple lines, ^ and $ match start or end of any line
#    s - single line, dot(.) match any character, even newline(\n)
#    u - UTF8
#    x - extended, allow regex to contain extra whitespace and comments
#    e.g.: '\d+'.toRegex('g')
########################################

# return left string, the right argument must be var right, e.g.:
#   var right = '';
#   var left  = splitonce(/\./, 'a.b', var right);
#   // Now, left = a, right = b
var splitonce(re, str, right) = re.match(str, (m){
    @ = m.missed();
    right = m.rest();
  });

# return a list
var split = (re, str){
      result = new [];
      var m  = re.match(str);
      while m.@@() <> nil loop
        result.@add(m.missed());
        m.match();
      end loop;
      result.@add(m.missed());
    };
var sp_and = fun split(/&/);
var sp_eq  = fun split(/=/);
