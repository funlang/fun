// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

use 'lib-os.fun';

fun escape(s)
  return s.replace(/^"|"$|(?=")"/g, '');
end fun;

fun GetCmdLineParams()
  result = new [];

  var s = 'kernel32'.getapi('GetCommandLine', ':s').call(); //?. s;
  var m = s.match(/("([^"]*+|"")++"|[^"\s]++)++/g); //?. m.@toJson();
  result.@exe = escape(m[0]);
  if result.@exe !~ /\.exe$/i then
    result.@exe &= '.exe';
  end if;
  //if result.@exe =~ /^\w:/ then
  //else
    //result.@exe = GetCurrPath() & '\' & result.@exe;
    result.@exe = GetFullPath(result.@exe);
  //end if;
  result.@path = result.@exe.replace(/[^\\]++$/, '');
  result.@fun = escape(m[1]);
  result.@ini = result.@exe.replace(/\.exe$/i, '.ini');
  result.args = m;
  result.options = ParseOptions(m);
end fun;
var CmdLineParams = GetCmdLineParams(); //?. CmdLineParams.@toJson(1);

fun ParseOptions(m)
  result = new [];
  var i = 1;
  var re = %^(-++|/)%;
  while i < m.@count() do
    if m[i] =~ re then
      var k = m[i].replace(re, '');
      if m[i+1] <> nil and m[i+1] !~ re then
        result[k] = m[i+1];
        i += 1;
      else
        result[k] = true;
      end if;
    end if;
    i += 1;
  end do;
end fun;

fun GetCmdLineArgs()
  #*
  启动文件 = result.argv[0] = 以fun源文件启动 ? .fun文件 : .exe文件
  result = {
    exe: 启动 exe 全名
    fun: 启动 fun 全名
    path: 启动文件所在路径
    base: 启动文件去除扩展名
    argc: 命令行参数个数
    argv: 命令行参数列表
  }
  *#
  result = new [];

  var s = 'kernel32'.getapi('GetCommandLine', ':s').call(); //?. s;
  var currPath = GetCurrPath() & '\';
  var m = s.match(/("([^"]*+|"")++"|[^"\s]++)++/g); //?. m.@toJson();
  var exe = escape(m[0]);
  if exe !~ /\.exe$/i then
    exe &= '.exe';
  end if;
  if exe !~ /^\w:/ then
    exe = currPath & exe;
  end if;
  result.exe = exe;

  result.argv = new [];
  var si = 1;
  var arg1 = escape(m[1]);
  var isFun = not not arg1 =~ /\.fun$/i;
  if isFun then
    if arg1 !~ /^\w:/ then
       arg1 = currPath & arg1;
    end if;
    si += 1;
    result.argv.@add(arg1);
    result['fun'] = arg1;
    result.path = arg1.replace(/[^\\]++$/, '');
    result.base = arg1.replace(/\.\w+$/i, '');
    result.isFUN = true;
  else
    result.argv.@add(exe);
    result.path = exe.replace(/[^\\]++$/, '');
    result.base = exe.replace(/\.\w+$/i, '');
    result.isFUN = false;
  end if;

  for i = si to m.@count() - 1 loop
    var a = escape(m[i]);
    if a != '-v' and a !~ '.\.fun$' then
      result.argv.@add(a);
    end if;
  end loop;
  result.argc = result.argv.@count();

end fun;
var cmdLineArgs = GetCmdLineArgs();
var __args = cmdLineArgs; // ?. __args;

class Config(file, obj, list)
  fun Load(defBlank)
    for k: v in list do
      if k = nil then
        k = v;
      end if;
      _load(v, k, defBlank);
    end do;
  end fun;

  fun Save()
    for k: v in list do
      if k = nil then
        k = v;
      end if;
      _save(v, k);
    end do;
  end fun;

  fun _load(name, tag, defBlank)
    try
      var s = '$file:$tag'.eval().load();
      if s <> nil then
        obj[name] = s;
      end if;
    except
      if defBlank then
        obj[name] = '';
      end if;
    end try;
  end fun;

  fun _save(name, tag)
    try
      '$file:$tag'.eval().save(obj[name]);
    except
      //?. @;
    end try;
  end fun;
end class;
