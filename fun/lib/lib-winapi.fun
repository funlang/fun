// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

########################################
# lib-winapi
########################################
#   built-in (2)
########################################
#     f.getapi(name, type)
########################################
#     f.@toCallback(nil, type, ptr)
#     f.@toCallback(obj, type, ptr)
########################################
# 1. f.getapi(name, type)
#      f:    file name (.dll)
#      name: proc name or address
#      type: xxx...:x
#            n(umber)   i(nt)      l(ong)     f(loat)
#            s(tring)   w(idestr)  a(nsistr)  r(awstr)
#            p(ointer)  c(allback) v(oid)
# 2. how to call?
#      method.call() or method()
#
#    e.g.:
#
#      # get API
#      var msgbox = 'user32'.getapi('MessageBox', 'issi:i');
#
#      # call via method.call()
#      msgbox.call(0, 'Hello, world!', 'Welcome...', 1);
#
#      # or call via method()
#      msgbox(0, 'Hello, world!', 'Welcome...', 1);
# 3. f.@toCallback(obj, type, ptr)
#      f                       # fun (function)
#      obj                     # object
#      type: xxx...:x          # W - BSTR (OleString)
#                   C          # cdecl
#      ptr: true or false      # default false
########################################
