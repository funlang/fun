// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

use 'lib-asm-pro.fun';
use 'lib-tcc.fun';

fun NewJit(code, args, names, name)
  if code =~ /^#!c\b/i then
    result = ccompile(code, flag: args, name: name);
  else
    result = Assembly(code: code, args: args, names: names).Load();
  end if;
end fun;
