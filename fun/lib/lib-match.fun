// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

########################################
# lib-match (match object)
########################################
#   built-in (6)
########################################
#     m.match()       # perform next match, return success or not
#
#     m.missed()      # return string missed (Left string of matched)
#     m.value()       # return string matched
#     m.value(substi) # return string substitute
#        m.@@()       # return string matched
#        m.@@(substi) # return string substitute
#             *       # return offsets
#     m.rest()        # return string rest (All right string)
#
#     m.gcount()      # return group count
#
#     m.groups(num)   # return group by index
#     m.groups(str)   # return group by name
#          m.@(num)   # group by index
#                 ,1) # pos += num, return pos
#                 ,2) # pos += num, return str
#          m.@(str)   # group by name
#                 ,1) # name -> index
########################################
