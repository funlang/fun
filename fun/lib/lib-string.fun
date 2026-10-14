// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

########################################
# lib-string
########################################
#   built-in (11)
########################################
#     a[n], a[n]=...
#       n - int, for char
#         float, for byte
#       L = N - 1
#         0 1 2 3 4 5 >> ++ >> L(ast)
#        -N << -- << -4 -3 -2 -1
#         0,.5  1,1.5  ...   L,L.5
#        -N            ...  -1,-.5
########################################
#     a.length   ()
#     a.lower    ()
#     a.upper    ()
#     a.subpos   (sub)
#     a.substr   (pos, len)         # Default pos=0, len=MAX, can be negative
#     a.move     (dest, len)        # dest: int, copy to dest
#     a.movs     (dest,len,pos,pod) # movSafe, dest: str, len,pos,pod can be negative
#     a.x        (n)                # Replicate n times, or reverse (n = -1)
#                                   #                       sort    (n = -2)
#     a.escape   ()                 # \ btnfr"'`/\ \x HH \u HHHH
#     a.format   (A1, A2, ... An)   # %s
#     a.eval     ()                 # $id
########################################
# 1. a.escape()
#      \b \t \n \f \r
#      \" \' \` \/ \\
#      \xHH \uHHHH
########################################
