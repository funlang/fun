// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

use 'lib-param.fun';

var arrows = ['', '->', '<-'];

//==============================================================
// Bind
//==============================================================
class Bind(form, keys)
  form.Events.beforeShow  = Init;
  form.Events.beforeClick = Save;
  form.Events.afterClick  = Load;
  form.Events.@data       = new [];

  fun DoHotKey(e)
    e = form.GetEvent(e);
    var k = e.keyCode;    //?. k;
    if k in [37, 39] then              // <- ->
      k = arrows[k - 38];
    elsif k >= 0x70 and k <= 0x7b then // F1 to F12
      k = 'F' & k - 0x6f; //?. k;
      if e.ctrlKey then                // Ctrl-Fn
        k = 'Ctrl-' & k;
      end if;
    elsif e.ctrlKey then               // Ctrl-
      k = 'Ctrl-' & k.toChar();
    elsif e.altKey then                // Alt &
      k = '&' & k.toChar();
    elsif k >= 65 and k <= 90 then     // A to Z
      k = k.toChar();
    else
      k = nil;
    end if;
    if k <> nil then
      try
        var f = keys[k];
        if f <> nil then
          //?. f;
          f = form[f];
          if f <> nil then
            Save(e);
            try
              f(e);
            finally
              Load(e);
            end try;
          end if;
        end if;
      except
        ?. 'fun:key: ' & @;
      end try;
    end if;
  end fun;

  fun Init()
    if keys <> nil then
      form.doc.onkeyup = DoHotKey.@toEvent(form);
    end if;

    for i = 0 to form.doc.all.length() - 1 do
      var e = form.doc.all.item(i);
      var f = nil;
      try
        f = e.getAttribute('fun:data', 2);
      except
      end try;
      if f <> nil then
        var prop = ParseJsonLite(f);
        var name = nil;
        for k:v in prop do
          name = k;
          if v.lower() = 'true' then
            prop[k] = 'value';
          end if;
          exit;
        end do;
        if name <> nil then
          prop.@e = e;
          form.Events.@data[name] = prop;
        end if;
      end if;

      if keys <> nil then
        try
          f = e.getAttribute('fun:key', 2);
          if f <> nil then
            var clk = e.getAttribute('fun:click', 2);
            if f =~ /.,./ then
              f.match(/[^,\x20]++/g, (m){ //?. m.@@();
                keys[m.@@().replace(/\bAlt-/, '&')] = clk;
              });
            else
              keys[f.replace(/\bAlt-/, '&')] = clk;
            end if;
          end if;
        except
        end try;
      end if;
    end do;

    Load();
  end fun;

  fun Load(e)
    for k:v in form.Events.@data do
      try
        exit when e <> nil and e.srcElement.getAttribute('fun:lite', 2) <> nil;
        if not v.w then // Write only
          if v.load <> nil then
            v.load(k, v); // load(name, props)
          else
            //var value = form[k]; // k may be name1.name2 such as res.Title
            var f2 = form; var k2 = k; UnCascade(var f2, var k2);
            var value = f2[k2];
            if v.@e.getAttribute(v[k], 0) <> value then
              v.@e.setAttribute(v[k], value, 0);
            end if;
          end if;
        end if;
      except
        ?. 'Load e: $@ @ $@@()'.eval();
      end try;
    end do;
  end fun;

  fun Save(e)
    for k:v in form.Events.@data do
      exit when e <> nil and e.srcElement.getAttribute('fun:lite', 2) <> nil;
      if not v.r then // Read only
        if v.save <> nil then
          v.save(k, v); // save(name, props)
        else
          //form[k] = v.@e.getAttribute(v[k], 0);
          // k is name1.name2 not only supports Load(), but also Save()
          var f2 = form; var k2 = k; UnCascade(var f2, var k2);
          f2[k2] = v.@e.getAttribute(v[k], 0);
        end if;
      end if;
    end do;
  end fun;
end class;
