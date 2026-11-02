// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

use 'lib-ado.fun';
use 'lib-ado-base.fun';
use 'lib-set.fun' as set;
use 'lib-stream.fun';

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
    var tt = new []; // surviving table names
    var ts = new [];
    s.Tables = set.filter(s.Tables, e -> e.TABLE_TYPE = 'TABLE');  //?. t.show('tables');
    s.Tables.@each((t){tt[t.TABLE_NAME] = 1});                     //?. t.show('table each');
    s.Fields = set.filter(s.Fields, e -> tt[e.TABLE_NAME] <> nil);//?. t.show('fields');
    ts = new [];
    s.PKeys.@each((f){ts[f.TABLE_NAME&'.'&f.COLUMN_NAME]=1});      //?. t.show('pkey each');
    s.Fields.@each((f){
      f.IsPKey = ts[f.TABLE_NAME&'.'&f.COLUMN_NAME] and 1 or 0;
    });                                                            //?. t.show('isPKey');
    s.PKeys  = nil;
    s.FKeys  = set.filter(s.FKeys,  e->tt[e.PK_TABLE_NAME] and tt[e.FK_TABLE_NAME]);
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
end class;
