// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

use 'lib-set.fun';
use 'lib-ado-base.fun';

class ADO(cnString, args)
  var db = 'ADODB.Connection'.newobj();
  var cn = cnString;
  var ps = args or [];

  fun Open()
    if ps.mode <> 0 then
      db.Mode = ps.mode; //?. db.Mode;
    end if;
    try
      db.Open(cn);
    except
      raise @ & ' - ' & cn;
    end try;
  end fun;

  fun Close()
    try
      db.Close();
    except
    end try;
  end fun;

  var Closed  () = db = nil or db.State = 0;
  var Begin   () = db.BeginTrans();
  var Commit  () = db.CommitTrans();
  var Rollback() = db.RollbackTrans();

  fun Init()
    var rs = OpenSchema(adSchemaDBInfoLiterals);
    literal('QUOTE', 'quotes');
    literal('SCHEMA_SEPARATOR', 'dot');
    if this.quotes <> nil then
      this.quotes = this.quotes & '%s' & this.quotes;
    end if;

    fun literal(name, prop)
      var s = find(rs, e -> e.LiteralName = name);
      if s <> nil then
        this[prop] = s.LiteralValue;
      end if;
    end fun;
  end fun;

  fun OpenSchema(schema)
    if Closed() then
      Open();
    end if;

    var rs = db.OpenSchema(schema);
    result = rs2json(rs);
  end fun;

  // Execute(sql, rsNext, ps, ...): run a statement.
  //   ps = [] or nil  -> plain Connection.Execute.
  //   ps = [{v, dt}, ...] in '?' order -> parameterized via ADODB.Command,
  //       where dt is the ORM internal DataType (0..12). Values are passed raw
  //       and typed by column so ADO converts them (avoids bigint precision loss).
  fun Execute(sql, rsNext, stream, from, top, tick, ps)
    if Closed() then
      Open();
    end if;

    var i = 0;  // affected records
    var rs;
    if ps?.@count?() > 0 then
      var nq = sql.replace(/[^?]/g, '').length();
      if nq <> ps.@count() then
        raise 'Execute: ? count (%s) != params (%s).\nSQL:\n%s'.format(nq, ps.@count(), sql);
      end if;

      var cmd = 'ADODB.Command'.newobj();
      cmd.ActiveConnection = db;
      cmd.CommandType = 1; // adCmdText
      cmd.CommandText = sql;
      if this.ps.debugParams <> nil then
        ?. 'params: ' & ps.@toJson();
      end if;
      var pn = 0;
      for p in ps do
        pn += 1;
        var prm = cmd.CreateParameter('p' & pn, this.AdoType(p.dt), 1, this.AdoLen(p.dt, p.v), p.v);
        cmd.Parameters.Append(prm);
      end do;
      rs = cmd.Execute(var i);
    else
      rs = db.Execute(sql, var i);
    end if;

    if tick <> nil then
      ?. tick.show('exec sql');
    end if;
    if rsNext then
      rs = rs.NextRecordset();
    end if;
    if rs.Fields.Count > 0 then
      result = rs2json(rs, rsNext, stream, from, top, tick);
      if rsNext and result.@count() = 1 then
        result[0].rows = i;
      end if;
    else
      result = new [[rows: i]];
    end if;
  end fun;

  // Map ORM internal DataType (0..12) -> ADO DataTypeEnum.
  // Bind by column type; pass the raw value so ADO converts it
  // (numbers for numeric columns; bigint as string so ADO turns it into Int64).
  fun AdoType(dt)
    case dt div 1 is
      when 0  do result = 2;    // adSmallInt
      when 1  do result = 3;    // adInteger
      when 2  do result = 20;   // adBigInt
      when 3  do result = 4;    // adSingle
      when 4  do result = 5;    // adDouble
      when 5  do result = 131;  // adNumeric (decimal/numeric/currency)
      when 6  do result = 11;   // adBoolean
      when 7  do result = 72;   // adGUID
      when 8  do result = 135;  // adDBTimeStamp
      when 9  do result = 200;  // adVarChar
      when 10 do result = 201;  // adLongVarChar
      when 11 do result = 204;  // adVarBinary
      when 12 do result = 205;  // adLongVarBinary
      else result = 12;         // adVariant
    end case;
  end fun;

  fun AdoLen(dt, v)
    var s = '' & v;
    case dt div 1 is
      when [7, 9, 10, 11, 12] do result = s.length();
      else result = 0;
    end case;
    if result <= 0 then result = 1; end if;
  end fun;

  fun ExecuteAndClose(sql, rsNext, ps)
    try
      if sql =~ /^-?\d++$/ then
        result = OpenSchema(sql div 1);
      else
        try
          result = Execute(sql, rsNext, ps: ps);
        except
          raise '$@ at $@@()'.eval();
        end try;
      end if;
    finally
      this.Close();
    end try;
  end fun;

  fun rs2json(rs, rsNext, stream, from, top, tick)
    var fs = rs.Fields;
    result = new [];

    if fs.Count > 0 then
    //try
      if not rs.BOF and not rsNext then
        rs.MoveFirst(); // Execute again when SELECT ...; ...
      end if;
      if from > 0 then
        rs.Move(from);
        if tick <> nil then
          ?. tick.show('move to ' & from);
        end if;
      end if;
      var rsCount = 0;
      if stream <> nil then
        while not rs.EOF do
          for i = 0 to fs.Count-1 do
            if i > 0 then
              stream.Write('\t'.escape());
            end if;
            var v = fs.@Item(i).Value;
            try
              stream.Write(v);
            except
              //?. '$@ at $@@()'.eval();
            end try;
          end do;
          stream.Write('\n'.escape());
          rsCount += 1;
          exit when top > 0 and rsCount >= top;
          rs.MoveNext();
        end do;
      else
        while not rs.EOF do
          var obj = new [];
          result.@add(obj);
          for i = 0 to fs.Count-1 do
            try
              obj[fs.@Item(i).Name] = fs.@Item(i).Value;
            except
              ?. '$@ at $@@()'.eval();
              try
                ?, i; ?, fs.@Item(i).Name; ?. fs.@Item(i).Value;
              except
                raise @ & '[DataType error or VarChar too long]';
              end try;
            end try;
          end do;
          rsCount += 1;
          exit when top > 0 and rsCount >= top;
          rs.MoveNext();
        end do;
      end if;
    //except
    //end try;
    end if;
  end fun;
end class;
