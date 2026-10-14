// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

########################################
# lib-winole
########################################
#   built-in (2)
########################################
#     c.newobj(get = false)
########################################
#     f.@toEvent()
#     f.@toEvent(obj)
#     f.@toEvent(obj, Source, EventID, DispIDs)
########################################
# 1. c.newobj(get = false)
#      c:    class name or id
#      get:  get an existing COM object
# 2. Call method of ActiveX Object
#      obj.Method(), obj.Method(ps)
#      obj.Method(ps, psNamed), obj.Method(v0, n1: v1, n2: v2...)
# 3. Property get - @Property
#      x = obj.Property        # or
#      x = obj.@Property()     # or
#      x = obj.@Property(...)  # for Property with params
# 4. Property set - @@Property
#      obj.Property = x        # or
#      obj.@@Property(x)       # or
#      obj.@@Property(..., x)  # for Property with params
# 5. f.@toEvent()
#      f                       # fun (function)
#      obj                     # object
#      Source                  # Windows COM Object
#      EventID                 # IID
#      DispIDs                 # DispID(s)
########################################
