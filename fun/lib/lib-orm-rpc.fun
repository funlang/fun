// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

use 'lib-jsonrpc.fun';
use 'lib-ado.fun';
use 'lib-orm-pro.fun' as orm;

#===================================================================================================
# var mf = OrmRpc('OrmRpc Demo', 800, 400, nil, JsonRpc.OnMessage.@toCallback(nil, 'iiii:i', true));
class OrmRpc = JsonRpc() #==========================================================================
  var cnString;
  var db = ADO();

  #===============================
  # args:
  #      connectionString
  #      schema
  #      selectAutoId
  fun OrmInit(args)
    cnString = args.connectionString;
    try
      if cnString !~ /\b(Provider|Driver|Dsn)\s*+=/i then
        cnString = 'Provider=sqloledb.1;' & cnString; // 默认支持 ADO.NET 连接串格式
      end if;

      if cnString <> nil and db <> nil then
        db.cn = cnString;
        if not db.Closed() then
          db.Close();
        end if;
      end if;
    except
      db = ADO(cnString, args);
    end try;

    db.schema = args.schema;
    db.Init();
    if args.selectAutoId <> '' then
      db.ps.selectAutoId = args.selectAutoId;
    end if;
  end fun;

  fun OrmCall(method, db, args, ret, sock)
    result = true;
    try
      var f = orm[method];
      ret.data = f(db, args);
      ret.result = 1;
    except
      ret.error = new [message: @, code: -32603];
      ret.result = 0;
    end try;
  end fun;

  #===============================
  fun Rpc_OrmInit(args, ret, sock)
    result = true;
    OrmInit(args);
    ret.result = 1;
  end fun;

  fun Rpc_OrmGet(args, ret, sock)
    result = OrmCall('OrmGet', db, args, ret, sock);
  end fun;

  fun Rpc_OrmSave(args, ret, sock)
    result = OrmCall('OrmSave', db, args, ret, sock);
  end fun;

  fun Rpc_OrmUpdate(args, ret, sock)
    result = OrmCall('OrmUpdate', db, args, ret, sock);
  end fun;

  fun Rpc_OrmDelete(args, ret, sock)
    result = OrmCall('OrmDelete', db, args, ret, sock);
  end fun;
end class;
