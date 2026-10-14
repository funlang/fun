// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

use 'lib-stack.fun';

//==============================================================
// Yaml
//==============================================================
class Yaml(fn)
  var kv;
  Load();

  fun Load(f)
    kv = new [];
    if f <> nil then
      fn = f;
    end if;
    if fn <> nil and fn.find() then
      ParseYaml(fn.load(), kv);
    end if;
  end fun;

  fun Save(test)
    var s = nil;
    for k:v in kv do
      if k <> nil then
        s &= '$k:\r\n'.escape().eval();
        for vk: vv in v do
          s &= ' $vk: $vv\r\n'.escape().eval();
        end do;
      end if;
    end do;
    if test then
      result = s;
    else
      fn.save(s);
    end if;
  end fun;

  fun Parse(s, set, keepNotes)
    if set = nil then
      set = new [];
    end if;
    result =  set;

    var tabs = s.match(/^#!tabs:\s*+(\d)/).@(1);
    if tabs = nil then
      tabs = 1;
    end if;

    var stk = Stack();
    var lvl = 0;
    var tmp = new []; tmp.n = set;
    stk.push(tmp);
    var cmt = '';
    var cmts = 0;
    s.match(`(?:^|(?<=\n))(?:
      (?P<cmt>[\x20\t]*+#.*+|)
      |
      (?P<sp>[\x20\t]*+) (?:
                            (?P<eq2>-) [\x20\t]*+ (?P<val2>(?:"[^\r\n]*"|[^#\r\n]*?)) |
                            (?P<key>(?:[^:=\r\n]++|::|==)*+)
                            (?: [\x20\t]*+ (?P<eq>[:=]) [\x20\t]*+ (?P<val>(?:"[^\r\n]*"|[^#\r\n]*?)) )?
                         )
                         (?P<isp>[\x20\t]*+)
                         (?P<icmt>#[^\r\n]*+)?
    )(?:\r?\n|$)`.replace(/\s++/g, '').toRegex('g'), (m){
      var mcmt = m.@('cmt');
      var sp   = m.@('sp');
      var key  = m.@('key').replace(/\s++$/, '');
      var eq   = m.@('eq')  & m.@('eq2');
      var val  = m.@('val') & m.@('val2');
      var isp  = m.@('isp');
      var icmt = m.@('icmt');
      if keepNotes and mcmt <> nil then
        if cmt <> nil then
          cmt &= '\n'.escape();
        end if;
        cmt &= mcmt;
        //?. cmt;
      end if;
      //?. 'SETTING: $sp $key $eq $val $icmt'.eval();
      if key & eq & val <> '' then
        //?. 'SETTING: $sp $key $eq $val $icmt'.eval(); # *
        if eq = '-' and val <> '' and val =~ /^([^:=\r\n]++|::|==)++\s*+[:=]\s*+/ then
          var v = val;
          val = ''; // ?. lvl;
          case sp.length() div tabs is
          when lvl do
            hit();
          else //?, lvl; ?. key;
            while @ < lvl do
              stk.pop();
              lvl -= 1;
            end do; //var p = stk.peek(); ?. p.@toJson();
            hit();  //?, v; ?, lvl; ?. sp.length() div tabs; ?. p.@toJson(); ?. stk.peek().@toJson();
          end case;
          key = v.match(/^([^:=\r\n]++|::|==)++/).@@();
          val = v.substr(key.length()).replace(/^\s*+[:=]\s*+|\s*+$/g, '');
          key = key.replace(/\s*+$/, '');
          sp &= ' '.x(tabs);
        end if;

        case sp.length() div tabs is
        when lvl do
          hit();
        else
          while @ < lvl do
            stk.pop();
            lvl -= 1;
          end do;
          hit();
        end case;
        fun hit()
          var tops = stk.peek();
          if tops.p <> nil and tops.k <> nil and tops.n = nil then
            tops.n = new [];
            tops.p[tops.k] = tops.n;
          end if;
          var top  = tops.n;
          if keepNotes and cmt & icmt <> nil then
            top['#!' & cmts] = new [cmt: cmt, isp: isp, icmt: icmt];
            cmts += 1;
          end if;
          if val <> nil then
            val = val.replace(/^NULL$|^\s++|\s++$|^"(.*)"$/g, '$1').replace('\r\n', '\r\n'.escape());
            if key <> nil then
              if top = set and key =~ /^\.(\.[^.]++)++$/ then // ..a.b.c: d
                var n = set;
                key.match(/([^.]++)\./g, (m){
                  var k = m.@(1);
                  if n[k] = nil then
                    n[k] = new [];
                  end if;
                  n = n[k];
                });
                n[key.match(/[^.]++$/).@@()] = val;
              else
                top[key] = val;
              end if;
            else
              top.@add(val);
            end if;
          else
            var node = new [];
            if key <> nil then
              node = nil;
              top[key] = node;
            else
              top.@add(node);
            end if;
            var tmp = new []; tmp.p = top; tmp.k = key; tmp.n = node;
            stk.push(tmp);
            lvl += 1;
          end if;
        end fun;
        cmt = '';
      end if; //?. set.@toJson();
    });
  end fun;

  fun Stringify(json, level, fn, tabs)
    tabs = tabs or 1;
    var lastCmt = nil;
    result = '#!tabs:$tabs\n\n'.escape().eval() & toString(json, level, fn);
    fun toString(json, level, fn)
      json = json or kv;
      result = '';
      for k: v in json do //next when k =~ /sql$/;
        if k =~ /^#!\d++$/ then
          if v.cmt <> nil then
            result &= v.cmt & '\n'.escape();
          end if;
          lastCmt = v;
          next;
        end if;
        var kk = ' '.x(level * tabs);
        //if k <> nil then
          kk &= k & ':';
        //end if;
        if isSet(v) then
          if k = nil then
            //kk &= ':';
          end if;
          result &= kk;
          if lastCmt <> nil then
            result &= lastCmt.isp & lastCmt.icmt;
            lastCmt = nil;
          end if;
          result &= '\n'.escape() & toString(v, level + 1, fn);
        else
          if k <> nil then
            kk &= ' ';
          end if;
          result &= kk & align(v, kk.length()+1, fn);
          if lastCmt <> nil then
            result &= lastCmt.isp & lastCmt.icmt;
            lastCmt = nil;
          end if;
          result &= '\n'.escape();
        end if;
      end do;

      fun isSet(v)
        try
          result = v.@count() > 0;
        except
          result = false;
        end try;
      end fun;

      fun align(v, l)
        //result = v.replace(/(\r?\n)(.)/g, '$1' & ' '.x(l) & '$2');
        result = v.replace(/\r?\n/g, '\r\n');
        if fn <> nil then
          result = fn(result);
        end if;
        if result = nil then
          result = 'NULL';
        elsif result =~ /#/ then
          result = '"' & result & '"';
        end if;
      end fun;
    end fun;
  end fun;
end class;

fun ParseYaml(yaml, json)
  result = json;
  if result = nil then
    result = new [];
  end if;
  json = result;
  yaml = yaml.replace(/\s*+#[^\r\n]*+/gm, ''); // remove comments #...
  yaml.match(/(?:^|(?<=\n))(?P<key>\S[^\r\n]*?)[\x20\t]*+[=:]?\r?\n(?P<val>(?:\x20[^\r\n]*+(?:\r?\n|$))++)/gs, (m){
    var v = new [];
    json[m.@('key')] = v; //?. m.@('key'); ?. m.@('val');
    m.@('val').match(/^\x20(?P<key>\S(?:[^\r\n=:]++|==|::)*+)\s*+[=:]\s*+(?P<val>[^\r\n]++)/gm, (n){ //?. n.@('key');
      v[n.@('key').replace(/==/g, '=').replace(/::/g, ':')] = n.@('val').replace('\r\n', '\r\n'.escape());
    });
  });
end fun;
