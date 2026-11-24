// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// stdlib: build a machine-readable index of the pure-Fun standard library.
//
//   use 'stdlib.fun';
//   var idx = stdlibIndex('fun/lib', '9.5.7');
//   idx.@toJson(json: true);
//
// The index is intentionally shallow: module name, file, platform suffix,
// size, a first-line summary and the public top-level functions and classes.
// It is enough for an agent to discover that a module exists and what it
// exports, without duplicating the manual.

use 'fs.fun';
use 'lib-path.fun';

fun stdlibBase(name)
  result = name.replace(/\.fun$/, '');
end fun;

fun stdlibPlatform(name)
  if name =~ /-lnx\.fun$/ then result = 'linux'; return; end if;
  if name =~ /-unx\.fun$/ then result = 'unix'; return; end if;
  if name =~ /-win\.fun$/ then result = 'windows'; return; end if;
  if name =~ /-a64\.fun$/ then result = 'arm64'; return; end if;
  if name =~ /-x64\.fun$/ then result = 'x86_64'; return; end if;
  if name =~ /-loongarch64\.fun$/ then result = 'loongarch64'; return; end if;
  if name =~ /-riscv64\.fun$/ then result = 'riscv64'; return; end if;
  result = 'any';
end fun;

fun stdlibBoilerplate(t)
  var s = t.lower();
  result = s.subpos('copyright') >= 0 or s.subpos('spdx') >= 0 or
    s.subpos('permission') >= 0 or s.subpos('the software') >= 0 or
    s.subpos('without warranty') >= 0 or s.subpos('merchantability') >= 0 or
    s.subpos('liability') >= 0 or s.subpos('authors') >= 0 or
    s.subpos('fitness for a particular purpose') >= 0;
end fun;

fun stdlibRuler(t)
  if t = '' then result = false; return; end if;
  for i = 0 to t.length() - 1 do
    var c = t.substr(i, 1);
    if c <> '#' and c <> '*' and c <> '=' and c <> '-' then
      result = false;
      return;
    end if;
  end do;
  result = true;
end fun;

fun stdlibSummary(content, name)
  var lines = content.match(/^.*$/gm);
  if lines = nil then result = name; return; end if;
  for l in lines do
    var t = l.replace(/^\s+/, '').replace(/\s+$/, '');
    if t = '' then next; end if;
    if stdlibRuler(t) then next; end if;
    if stdlibBoilerplate(t) then next; end if;
    if t.substr(0, 2) = '//' then t = t.substr(2); end if;
    if t.substr(0, 1) = '#' then t = t.substr(1); end if;
    if t.substr(0, 1) = '*' then t = t.substr(1); end if;
    t = t.replace(/^\s+/, '').replace(/\s+$/, '');
    if t.length() < 4 then next; end if;
    if t = name then next; end if;
    if t.substr(0, 3) = 'use' or t.substr(0, 3) = 'var' or
       t.substr(0, 3) = 'fun' or t.substr(0, 5) = 'class' then next; end if;
    if t.length() > 160 then t = t.substr(0, 157) & '...'; end if;
    result = t;
    return;
  end do;
  result = name;
end fun;

fun stdlibExports(content, moduleName)
  var out = new [];
  var seen = new [];
  var owners = new [];
  var lines = content.match(/^.*$/gm);
  if lines = nil then result = out; return; end if;
  // Pass 1: a module singleton, e.g. `var fs = _FsApi()`.
  for line in lines do
    var m = line.match(/^var\s+([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\s*\(/);
    if m <> nil and m.@(1) = moduleName then owners[m.@(2)] = m.@(1); end if;
  end do;
  // Pass 2: top-level functions, classes and their methods.
  var cls = '';
  for line in lines do
    var t = line.replace(/\s+$/, '');
    var mc = t.match(/^class\s+([A-Za-z_]\w*)/);
    if mc <> nil and mc.@(1) <> nil then
      cls = mc.@(1);
      if cls.substr(0, 1) <> '_' and seen[cls] = nil then
        seen[cls] = true;
        out.@add(new [kind: 'class', name: cls, signature: t.replace(/\s+/g, ' ')]);
      end if;
      next;
    end if;
    if t =~ /^end\s+class/ then cls = ''; next; end if;
    var mf = t.match(/^fun\s+([A-Za-z_]\w*)\s*(\([^)]*\))/);
    if mf <> nil and mf.@(1) <> nil then
      var nm = mf.@(1);
      if nm.substr(0, 1) <> '_' and seen[nm] = nil then
        seen[nm] = true;
        out.@add(new [kind: 'fun', name: nm, signature: 'fun ' & nm & mf.@(2)]);
      end if;
      next;
    end if;
    var mm = t.match(/^\s+fun\s+([A-Za-z_]\w*)\s*(\([^)]*\))/);
    if mm <> nil and mm.@(1) <> nil and cls <> '' then
      var nm = mm.@(1);
      var owner = cls;
      if owners[cls] <> nil then owner = owners[cls]; end if;
      if nm.substr(0, 1) <> '_' and (cls.substr(0, 1) <> '_' or owners[cls] <> nil) then
        var key = owner & '.' & nm;
        if seen[key] = nil then
          seen[key] = true;
          out.@add(new [kind: 'method', name: key, owner: owner, signature: 'fun ' & nm & mm.@(2)]);
        end if;
      end if;
      next;
    end if;
    var vf1 = t.match(/^var\s+([A-Za-z_]\w*)\s*(\([^)]*\))\s*=/);
    if vf1 <> nil and vf1.@(1) <> nil then
      var nm = vf1.@(1);
      if nm.substr(0, 1) <> '_' and seen[nm] = nil then
        seen[nm] = true;
        out.@add(new [kind: 'fun', name: nm, signature: 'fun ' & nm & vf1.@(2)]);
      end if;
      next;
    end if;
    var vf2 = t.match(/^var\s+([A-Za-z_]\w*)\s*=\s*(\([^)]*\))/);
    if vf2 <> nil and vf2.@(1) <> nil then
      var nm = vf2.@(1);
      if nm.substr(0, 1) <> '_' and seen[nm] = nil then
        seen[nm] = true;
        out.@add(new [kind: 'fun', name: nm, signature: 'fun ' & nm & vf2.@(2)]);
      end if;
      next;
    end if;
    var mv = t.match(/^var\s+([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\s*\(/);
    if mv <> nil and mv.@(1) = moduleName then
      var nm2 = mv.@(1);
      if seen[nm2] = nil then
        seen[nm2] = true;
        out.@add(new [kind: 'value', name: nm2, signature: 'var ' & nm2 & ' = ' & mv.@(2) & '()']);
      end if;
      next;
    end if;
  end do;
  result = out;
end fun;

fun stdlibLines(content)
  var n = content.match(/\n/g);
  result = 1;
  if n <> nil then result = n.@count() + 1; end if;
end fun;

fun stdlibIndex(libDir, funVersion)
  var mods = new [];
  var names = fs.list(libDir);
  if names <> nil then
    for n in names do
      if n =~ /\.fun$/ then
        try
          var file = PathJoin([libDir, n]);
          var c = file.load();
          var name = stdlibBase(n);
          mods.@add(new [
            name: name,
            file: file,
            platform: stdlibPlatform(n),
            bytes: c.length(),
            lines: stdlibLines(c),
            summary: stdlibSummary(c, name),
            exports: stdlibExports(c, name)
          ]);
        except
        end try;
      end if;
    end do;
  end if;
  result = new [
    generatedFrom: libDir,
    funVersion: funVersion or '',
    moduleCount: mods.@count(),
    modules: mods
  ];
end fun;
