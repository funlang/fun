// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-orm-rpc-unx: the Unix backend of lib-orm-rpc -- the JSON-RPC ORM service
// on lib-jsonrpc-unx (poll(2), no UI) plus lib-ado-unx (SQLite). The Windows
// file keeps the COM/ODBC path (lib-jsonrpc + lib-ado + lib-orm-pro); this one
// swaps those two imports and builds the ORM schema straight from the database
// instead of expecting the client to ship it.
//
//     var rpc = OrmRpc();
//     rpc.port = 8278;
//     rpc.start();            // blocks, serving until stop()
//
//     rpc.listen();           // or bind only and drive runOnce() yourself
//     rpc.runOnce(200);
//
// Client protocol (unchanged from Windows):
//     {"jsonrpc":"2.0","id":1,"method":"OrmInit","params":{"connectionString":"/tmp/app.sqlite"}}
//     {"jsonrpc":"2.0","id":2,"method":"OrmGet","params":{"User":{"name":"alice"}}}
//
// OrmInit params: connectionString (a SQLite path / ':memory:' / 'Data
// Source=...'), optional schema (a lib-orm schema object, when the caller has
// one), optional selectAutoId. Without an explicit schema the tables/fields/
// keys are read from the database via lib-ado-schema-unx.
//
// SQL logging is off by default (a headless service should not write every
// statement to stdout); set `rpc.db.dontPrintSQL = false` after OrmInit to see it.

use 'lib-jsonrpc-unx.fun';
use 'lib-ado-unx.fun';
use 'lib-ado-schema-unx.fun';
use 'lib-orm-pro.fun' as orm;

#===================================================================================================
class OrmRpc = JsonRpc() #==========================================================================
  var cnString = nil;
  var db = nil;

  #===============================
  # args:
  #      connectionString
  #      schema           (optional; auto-built from the DB when absent)
  #      selectAutoId     (optional)
  fun OrmInit(args)
    cnString = args.connectionString;

    if db <> nil then
      try
        db.Close();
      except
      end try;
    end if;
    db = ADO(cnString, args);
    db.dontPrintSQL = true;   // headless service: keep the SQL off stdout

    if args.schema <> nil then
      db.schema = args.schema;
    else
      db.schema = Schema(cnString, args).ToSchema();
    end if;

    db.Init();
    if args.selectAutoId <> nil and args.selectAutoId <> '' then
      db.ps.selectAutoId = args.selectAutoId;
    end if;
    result = true;
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
