// lib-ado-odbc-unx on unixODBC: raw SQL, parameters, transactions, schema,
// and the lib-orm stack through an ODBC driver. The driver under test is the
// SQLite ODBC driver (no server needed); a couple of assertions use
// last_insert_rowid()/sqlite_master and are therefore SQLite-flavoured.
//
// The connection string comes from ODBC_TEST_CN so the test skips cleanly on
// hosts without unixODBC. run-ado-odbc.sh sets it when a driver is present.
use 'fun/lib/lib-ado-unx.fun';
use 'fun/lib/lib-orm-pro.fun';
use 'fun/lib/lib-utils.fun';
use 'fun/lib/lib-host.fun';

fun main(cn)
  if cn.lower().substr(0, 5) <> 'odbc:' then cn = 'odbc:' & cn; end if;
  var db = ADO(cn);
  db.dontPrintSQL = true;
  db.Open();
  ?. 'odbc=on';

  db.Execute('CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT, n INTEGER)');
  db.Execute("INSERT INTO t(name,n) VALUES('alice',42)");
  db.Execute("INSERT INTO t(name,n) VALUES('bob',7)");

  var rows = db.Execute('SELECT id,name,n FROM t ORDER BY id', false);
  ?. 'select count=' & rows.@count();
  for r in rows do
    ?. '  ' & r.id & ':' & r.name & ':' & r.n;
  end do;

  var p = db.Execute('SELECT name FROM t WHERE n > ?', false, ps: [[v: 10, dt: 1]]);
  ?. 'param=' & p.@count() & ':' & p[0].name;

  var a = db.Execute("INSERT INTO t(name,n) VALUES('carol',1); SELECT last_insert_rowid() AS autoId", true);
  ?. 'autoId=' & a[0].autoId;

  var u = db.Execute('UPDATE t SET n = 0 WHERE n > 0', false);
  ?. 'updated=' & u[0].rows;

  db.Begin();
  db.Execute("INSERT INTO t(name,n) VALUES('dave',9)");
  db.Rollback();
  ?. 'rollback=' & db.Execute('SELECT COUNT(*) AS c FROM t', false)[0].c;
  db.Begin();
  db.Execute("INSERT INTO t(name,n) VALUES('eve',9)");
  db.Commit();
  ?. 'commit=' & db.Execute('SELECT COUNT(*) AS c FROM t', false)[0].c;

  db.Execute('CREATE TABLE b(v BLOB)');
  db.Execute('INSERT INTO b VALUES(?)', false, ps: [[v: '\x00\x01\x02\xff'.escape(), dt: 11]]);
  ?. 'blob=' & str2hex(db.Execute('SELECT v FROM b', false)[0].v);

  db.Execute('INSERT INTO b VALUES(?)', false, ps: [[v: nil, dt: 9]]);
  var bn = db.Execute('SELECT v FROM b', false);
  ?. 'null=' & bn[1].v.eq(nil);

  // Int64 values above 2^53 must survive the SQL_C_SBIGINT round trip.
  db.Execute('CREATE TABLE big(v INTEGER)');
  db.Execute('INSERT INTO big VALUES(?)', false, ps: [[v: 9007199254740993, dt: 2]]);
  ?. 'int64=' & db.Execute('SELECT v FROM big', false)[0].v;

  db.Execute('CREATE TABLE flag(v INTEGER)');
  db.Execute('INSERT INTO flag VALUES(?)', false, ps: [[v: true, dt: 6]]);
  db.Execute('INSERT INTO flag VALUES(?)', false, ps: [[v: false, dt: 6]]);
  var fs = db.Execute('SELECT v FROM flag', false);
  ?. 'bool=' & fs[0].v & ',' & fs[1].v;

  // SQLGetData chunking: text and binary both cross the 4096-byte buffer.
  var bigblob = '';
  for i = 0 to 4999 do bigblob &= (i mod 256).toChar(); end do;
  var bigtext = '中'.x(2000);
  db.Execute('CREATE TABLE bigdata(t TEXT, b BLOB)');
  db.Execute('INSERT INTO bigdata VALUES(?,?)', false,
             ps: [[v: bigtext, dt: 10], [v: bigblob, dt: 12]]);
  var bd = db.Execute('SELECT t,b FROM bigdata', false)[0];
  ?. 'bigdata=' & bd.t.length() & ',' & bd.b.length()
     & ':' & (bd.t = bigtext) & ',' & (bd.b = bigblob);

  // An empty string must stay '' and not collapse into NULL.
  db.Execute('CREATE TABLE empty(v TEXT)');
  db.Execute('INSERT INTO empty VALUES(?)', false, ps: [[v: '', dt: 9]]);
  db.Execute('INSERT INTO empty VALUES(?)', false, ps: [[v: nil, dt: 9]]);
  var er = db.Execute('SELECT v FROM empty', false);
  ?. 'empty=' & er[0].v.length() & ',' & er[1].v.eq(nil);

  // NUMERIC keeps its decimal scale when bound as SQL_C_CHAR.
  db.Execute('CREATE TABLE num(v NUMERIC)');
  db.Execute('INSERT INTO num VALUES(?)', false, ps: [[v: -123.456, dt: 5]]);
  ?. 'numeric=' & db.Execute('SELECT v FROM num', false)[0].v;

  // Extra parameter markers are rejected before reaching the driver.
  var badp = false;
  try
    db.Execute('SELECT ? AS x', false, ps: [[v: 1, dt: 1], [v: 2, dt: 1]]);
  except
    badp = true;
  end try;
  ?. 'badparams=' & badp;

  var tabs = db.OpenSchema(adSchemaTables);
  ?. 'tables=' & tabs.@count() & ':' & tabs[0].TABLE_NAME;
  var cols = db.OpenSchema(adSchemaColumns);
  ?. 'columns=' & cols.@count() & ':' & cols[0].COLUMN_NAME & ':' & cols[0].DATA_TYPE;
  var pks = db.OpenSchema(adSchemaPrimaryKeys);
  ?. 'pkeys=' & pks.@count() & ':' & pks[0].COLUMN_NAME;

  // Composite PK/FK metadata comes back as one row per column.
  db.Execute('CREATE TABLE cp(a INTEGER, b INTEGER, PRIMARY KEY(a,b))');
  db.Execute('CREATE TABLE cf(x INTEGER, y INTEGER, FOREIGN KEY(x,y) REFERENCES cp(a,b))');
  var cpk = 0;
  for p in db.OpenSchema(adSchemaPrimaryKeys) do
    if p.TABLE_NAME = 'cp' then cpk += 1; end if;
  end do;
  var cfk = 0;
  for f in db.OpenSchema(adSchemaForeignKeys) do
    if f.FK_TABLE_NAME = 'cf' then cfk += 1; end if;
  end do;
  ?. 'composite=' & cpk & ',' & cfk;

  // ---- lib-orm through the same connection ----
  db.Execute('DROP TABLE t');
  db.Execute('DROP TABLE b');
  db.Execute('DROP TABLE big');
  db.Execute('DROP TABLE flag');
  db.Execute('DROP TABLE bigdata');
  db.Execute('DROP TABLE empty');
  db.Execute('DROP TABLE num');
  db.Execute('DROP TABLE cp');
  db.Execute('DROP TABLE cf');
  db.Execute('CREATE TABLE "User"(id INTEGER PRIMARY KEY, name TEXT UNIQUE, age INTEGER)');

  fun F(alias, name, dt, isP, isAuto)
    result = new [Alias: alias, Name: name, DataType: dt, IsPrimary: isP, IsAutoId: isAuto];
  end fun;

  db.schema = new [
    User: new [
      Alias: 'User', Name: 'User', Schema: '',
      @Fields: new [
        id:   F('id',   'id',   1, 1, 1),
        name: F('name', 'name', 9, 0, 0),
        age:  F('age',  'age',  1, 0, 0)
      ]
    ]
  ];

  var r1 = OrmSave(db, new [User: new [[name: 'alice', age: 30], [name: 'bob', age: 25]]]);
  ?. 'orm insert rows=' & r1.User.rows & ' autoId=' & r1.User.autoId;

  var g = OrmGet(db, new [User: new [name: 'alice']]);
  ?. 'orm get=' & g.User.@count() & ' age=' & g.User[0].age;

  var r2 = OrmUpdate(db, new [User: new [Set: new [age: 31], Where: new [name: 'alice']]]);
  ?. 'orm update rows=' & r2.User.rows;
  ?. 'orm age now=' & OrmGet(db, new [User: new [name: 'alice']]).User[0].age;

  var r3 = OrmDelete(db, new [User: new [name: 'bob']]);
  ?. 'orm delete rows=' & r3.User.rows;
  ?. 'orm remaining=' & db.Execute('SELECT COUNT(*) AS c FROM "User"', false)[0].c;

  // A failed multi-row save rolls the whole transaction back.
  var dup = false;
  try
    OrmSave(db, new [User: new [[name: 'dave'], [name: 'alice']]]);
  except
    dup = true;
  end try;
  ?. 'orm rollback=' & dup & ':' & db.Execute('SELECT COUNT(*) AS c FROM "User"', false)[0].c;

  var eac = db.ExecuteAndClose('SELECT 42 AS x', false);
  ?. 'eac=' & eac[0].x & ' closed=' & db.Closed();

  // lib-orm calls Begin() before its first Execute(); that must dispatch to
  // ODBC and open the connection, not fall through to the SQLite path.
  var lazy = ADO(cn);
  lazy.Begin();
  lazy.Execute('CREATE TABLE lazy(v INTEGER)');
  lazy.Commit();
  ?. 'lazy=' & lazy.Execute("SELECT COUNT(*) AS c FROM sqlite_master WHERE name='lazy'", false)[0].c;
  lazy.Execute('DROP TABLE lazy');
  lazy.Close();

  // Init() matches the Windows backend: it opens and installs the driver's
  // identifier literal, which ORM SQL generation depends on.
  var initdb = ADO(cn);
  initdb.Init();
  ?. 'init=' & (not initdb.Closed()) & ':' & initdb.quotes;
  initdb.Close();
end fun;

var cn = HostEnvGet('ODBC_TEST_CN');
if cn = nil or cn = '' then
  ?. 'odbc=skip';
else
  main(cn);
end if;
