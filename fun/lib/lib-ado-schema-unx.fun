// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-ado-schema-unx: the Unix backend of lib-ado-schema (SQLite via
// lib-ado-unx). Only the ADO import differs from the Windows file, which
// stays untouched; the schema column names OpenSchema returns are the same.

use 'lib-ado-unx.fun';
use 'lib-set.fun' as set;
use 'lib-stream.fun';


var adEmpty = 0x0;
var adTinyInt = 0x10;
var adSmallInt = 0x2;
var adInteger = 0x3;
var adBigInt = 0x14;
var adUnsignedTinyInt = 0x11;
var adUnsignedSmallInt = 0x12;
var adUnsignedInt = 0x13;
var adUnsignedBigInt = 0x15;
var adSingle = 0x4;
var adDouble = 0x5;
var adCurrency = 0x6;
var adDecimal = 0xE;
var adNumeric = 0x83;
var adBoolean = 0xB;
var adError = 0xA;
var adUserDefined = 0x84;
var adVariant = 0xC;
var adIDispatch = 0x9;
var adIUnknown = 0xD;
var adGUID = 0x48;
var adDate = 0x7;
var adDBDate = 0x85;
var adDBTime = 0x86;
var adDBTimeStamp = 0x87;
var adBSTR = 0x8;
var adChar = 0x81;
var adVarChar = 0xC8;
var adLongVarChar = 0xC9;
var adWChar = 0x82;
var adVarWChar = 0xCA;
var adLongVarWChar = 0xCB;
var adBinary = 0x80;
var adVarBinary = 0xCC;
var adLongVarBinary = 0xCD;
var adChapter = 0x88;
var adFileTime = 0x40;
var adDBFileTime = 0x89;
var adPropVariant = 0x8A;
var adVarNumeric = 0x8B;

class Schema(cnString, args)
  fun Get()
    var db = ADO(cnString, args);
    db.Open();
    result = new [];
    try
      result.Tables = db.OpenSchema(adSchemaTables);
      result.Fields = db.OpenSchema(adSchemaColumns);
      result.PKeys  = db.OpenSchema(adSchemaPrimaryKeys);
      result.FKeys  = db.OpenSchema(adSchemaForeignKeys);
    finally
      db.Close();
    end try;
  end fun;

  fun Filter(s, t)
    var ts = new [];
    s.Tables = set.filter(s.Tables, e -> e.TABLE_TYPE = 'TABLE');  //?. t.show('tables');
    s.Tables.@each((t){ts[t.TABLE_NAME] = t.TABLE_NAME});          //?. t.show('table each');
    s.Fields = set.filter(s.Fields, e -> ts[e.TABLE_NAME] <> nil); //?. t.show('fields');
    ts = new [];
    s.PKeys.@each((f){ts[f.TABLE_NAME&'.'&f.COLUMN_NAME]=1});      //?. t.show('pkey each');
    s.Fields.@each((f){
      f.IsPKey = ts[f.TABLE_NAME&'.'&f.COLUMN_NAME] and 1 or 0;
    });                                                            //?. t.show('isPKey');
    s.PKeys  = nil;
    s.FKeys  = set.filter(s.FKeys,  e->e.PK_TABLE_NAME in ts and e.FK_TABLE_NAME in ts);
  end fun;

  fun Format(s)
    s.DoTable = new [];
    s.Tables.@each((t){
      var n = new [];
      n.SchemaName = t.TABLE_SCHEMA;
      n.Name = t.TABLE_NAME;
      n.Id = n.SchemaName & '.' & n.Name;
      n.Alias = n.Name;
      n.Caption = n.Name;
      n.IsEnabled = 1;
      n.IsReadOnly = 0;
      n.CacheType = 0;
      s.DoTable.@add(n);
    }); s.Tables = nil;
    s.DoField = new [];
    s.Fields.@each((f){
      var n = new [];
      n.Table_Id = f.TABLE_SCHEMA & '.' & f.TABLE_NAME;
      n.Name = f.COLUMN_NAME;
      n.Id = n.Table_Id & '.' & n.Name;
      n.Alias = n.Name;
      n.Caption = n.Name;
      n.IsEnabled = 1;
      n.IsReadOnly = 0;
      n.IsLazyLoad = 0;
      n.IsAutoIncrement = (f.Column_Flags in [16, 90] and f.Data_Type = 3) / -1; //
      n.IsNullable = f.IS_NULLABLE div 1;
      n.IsPrimary = f.IsPKey;
      try
        n.Width = f.CHARACTER_MAXIMUM_LENGTH or 0;
      except
        n.Width = 0;
      end try;
      if n.Width >= 2^30 - 1 then
        n.Width = 0;
      end if;
      n.Scale = f.NUMBERIC_SCALE or 0;
      n.DataType = DataType(f.DATA_TYPE);
      s.DoField.@add(n);
    }); s.Fields = nil;
    s.DoRelation = new [];
    s.DoRelationField = new [];
    var list = new [];
    s.FKeys.@each((f){
      var n = new [];
      var r = new [];
      r.ChildName = f.FK_TABLE_NAME;
      r.ParentName = f.PK_TABLE_NAME;
      r.ChildTable_Id = f.FK_TABLE_SCHEMA & '.' & r.ChildName;
      r.ParentTable_Id = f.PK_TABLE_SCHEMA & '.' & r.ParentName;
      r.Name = f.FK_NAME;
      r.Id = f.FK_TABLE_SCHEMA & '.' & r.Name;
      r.IsEnabled = 1;

      n.ChildField_Id = r.ChildTable_Id & '.' & f.FK_COLUMN_NAME;
      n.ParentField_Id = r.ParentTable_Id & '.' & f.PK_COLUMN_NAME;
      n.Relation_Id = r.Id;
      n.Id = r.Id & '.' & f.FK_COLUMN_NAME;
      s.DoRelationField.@add(n);
      if list[r.Id] = nil then
        s.DoRelation.@add(r);
        list[r.Id] = 1;
      end if;
    }); s.FKeys = nil;

    fun DataType(dt)
      case dt is
        when [adTinyInt,adSmallInt,adUnsignedTinyInt,adUnsignedSmallInt] do result = 0;
        when [adError,adInteger,adUnsignedInt] do result = 1;
        when [adBigInt,adUnsignedBigInt] do result = 2;
        when  adSingle  do result = 3;
        when  adDouble  do result = 4;
        when [adDecimal,adNumeric,adVarNumeric,adCurrency] do result = 5;
        when  adBoolean  do result = 6;
        when  adGUID  do result = 7;
        when [adDate,adDBDate,adDBTime,adDBTimeStamp,adFileTime,adDBFileTime] do result = 8;
        when [adBSTR,adChar,adVarChar,adWChar,adVarWChar] do result = 9;
        when [adLongVarChar,adLongVarWChar] do result = 10;
        when [adBinary,adVarBinary] do result = 11;
        when  adLongVarBinary  do result = 12;
        else result = 9;
      end case;
    end fun;
  end fun;

  fun tObjectSet(s, k, str)
    str.Write('<ObjectSet Name="$k">\r\n'.escape().eval());
    s.@each((e){
      str.Write('<Object');
      e.@each((v, k){
        str.Write(' $k="$v"'.eval());
      });
      str.Write('/>\r\n'.escape());
    });
    str.Write('</ObjectSet>\r\n'.escape());
  end fun;

  fun GetxObject(fn) //use 'lib-time.fun'; var t = tick();
    var s = Get(); //?. t.show('get');
    Filter(s);     //?. t.show('filter');
    Format(s);     //?. t.show('format');
    var str = Stream(fn);
    str.Write('<ObjectSpace>');
    s.@each((v, k){
      if v then
        tObjectSet(v, k, str);
      end if;      //?. t.show(k);
    });            //?. t.show('save');
    str.Write('</ObjectSpace>');
    str.Save();
  end fun;
  // Linux direct route: build the lib-orm db.schema straight from the
  // formatted schema, bypassing GetxObject/LoadSchema. Those serialize through
  // lib-xml, which is MSXML/COM and cannot run on Linux.
  fun ToSchema()
    var s = this.Get();
    // Filter() ends with `s.FKeys = set.filter(..., e->e.PK_TABLE_NAME in ts ...)`
    // where ts is keyed by 'Table.Column', so it drops every FK on both hosts
    // (latent bug). Keep the raw FKeys so Format still builds DoRelation, which
    // the ORM uses for @Parent/@Children.
    var fkeys = s.FKeys;
    this.Filter(s);
    s.FKeys = fkeys;
    this.Format(s);
    result = _SchemaFrom(s);
  end fun;
end class;


// Mirror of lib-orm.fun's LoadSchema, but over the in-memory Do* sets instead
// of the XML the Windows path round-trips through lib-xml.
fun _fieldAlias(flds, id)
  result = nil;
  for f in flds do
    if f.Id = id then result = f.Alias; end if;
  end do;
end fun;

fun _SchemaFrom(s)
  var objs = s.DoTable;
  var flds = s.DoField;
  var rels = s.DoRelation;
  var rfds = s.DoRelationField;
  result = new [];
  for t in objs do
    var o = new [];
    if t.SchemaName <> '' then o.Schema = t.SchemaName; end if;
    o.Alias = t.Alias;
    o.Name  = t.Name;
    result[o.Alias] = o;

    var autoKey = nil;
    var keys = 0;
    o.@Fields = new [];
    for f in flds do
      next when f.Table_Id <> t.Id;
      var p = new [];
      p.Alias = f.Alias;
      p.Name  = f.Name;
      p.DataType  = f.DataType div 1;
      p.IsPrimary = f.IsPrimary;
      p.IsAutoId  = f.IsAutoIncrement;
      if p.IsPrimary then keys += 1; end if;
      if p.IsPrimary and p.IsAutoId then autoKey = p.Name; end if;
      o.@Fields[p.Alias] = p;
    end do;
    if keys = 1 and autoKey <> nil then o.@AutoKey = autoKey; end if;

    o.@Parent = new [];
    if rels then
      for r in rels do
        next when r.ChildTable_Id <> t.Id;
        var rf = new [];
        o.@Parent[r.ParentName] = rf;
        rf.Alias = _tableAlias(objs, r.ParentTable_Id);
        rf.@Keys = new [];
        for f in rfds do
          next when f.Relation_Id <> r.Id;
          var pa = _fieldAlias(flds, f.ParentField_Id);
          var ca = _fieldAlias(flds, f.ChildField_Id);
          if pa <> nil and ca <> nil then rf.@Keys[pa] = ca; end if;
        end do;
      end do;
    end if;

    o.@Children = new [];
    if rels then
      for r in rels do
        next when r.ParentTable_Id <> t.Id;
        var rf2 = new [];
        o.@Children[r.ChildName] = rf2;
        rf2.Alias = _tableAlias(objs, r.ChildTable_Id);
        rf2.@Keys = new [];
        for f in rfds do
          next when f.Relation_Id <> r.Id;
          var ca2 = _fieldAlias(flds, f.ChildField_Id);
          var pa2 = _fieldAlias(flds, f.ParentField_Id);
          if ca2 <> nil and pa2 <> nil then rf2.@Keys[ca2] = pa2; end if;
        end do;
      end do;
    end if;
  end do;
end fun;

fun _tableAlias(objs, id)
  result = nil;
  for t in objs do
    if t.Id = id then result = t.Alias; end if;
  end do;
end fun;
