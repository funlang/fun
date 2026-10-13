// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-cmdline-unx: the Unix (Linux/macOS) backend of lib-cmdline.
//
// The Windows lib-cmdline.fun reads kernel32.GetCommandLine and assumes
// '.exe'/'.ini' suffixes and '\\' separators. None of that exists on Unix, so
// this backend keeps the plain module name on Windows and provides the same API
// here: GetCmdLineParams()/CmdLineParams, GetCmdLineArgs()/cmdLineArgs, and Config.
//
// Unix data source and the choices made for it (previously the [DECIDE] points):
//   * argv from N.arg(): 0 = the executable (absolute), 1 = the script,
//     2.. = user arguments. There is no argc builtin, so the scan stops at the
//     first empty argument.
//   * @exe is 0.arg() as the executable path (no readlink('/proc/self/exe')
//     symlink resolution; argv[0] is already absolute here).
//   * '.exe' completion and '.ini' derivation are Windows concepts and are
//     dropped. There is no `path`/`base` derivation beyond stripping the
//     script's extension.
//   * tokens and paths use '/' (HostSep()), never '\\'.
//   * options accept '-x' and '--x' plus POSIX '--key=value'; the Windows '/x'
//     prefix is gone because on Unix '/x' is an absolute path.
//
// `args` keeps the Windows shape: [exe, script, user args...] so code that
// indexes args the same way on both hosts keeps working.

use 'lib-host.fun';

fun DirName(p)
  result = p.replace(%[^/]*$%, '');   // keeps the trailing separator, like lib-os
end fun;

// argv without the executable: [script, user args...].
fun Argv()
  result = new [];
  var i = 1;
  while i.arg() <> '' do
    result.@add(i.arg());
    i += 1;
  end do;
end fun;

fun ParseOptions(m)
  result = new [];
  var i = 1;
  while i < m.@count() do
    var a = m[i];
    if a =~ %^--?% then
      var body = a.replace(%^--?%, '');
      var eq = body.subpos('=');
      if eq >= 0 then
        result[body.substr(0, eq)] = body.substr(eq + 1);
      elsif i + 1 < m.@count() and m[i+1] !~ %^--?% then
        result[body] = m[i+1];
        i += 1;
      else
        result[body] = true;
      end if;
    end if;
    i += 1;
  end do;
end fun;

fun GetCmdLineParams()
  // Do not name this local 'argv': Fun identifiers are case-insensitive and it
  // would collide with the Argv() function in the UID chain.
  var argvs = Argv();
  var toks  = new [0.arg()];
  for a in argvs do toks.@add(a); end do;
  result = new [];
  result.@exe  = 0.arg();
  result.@path = DirName(result.@exe);
  result.@fun  = argvs.@count() > 0 and argvs[0] or '';
  result.args  = toks;
  result.options = ParseOptions(toks);
end fun;

var CmdLineParams = GetCmdLineParams();

fun GetCmdLineArgs()
  #*
  result = {
    exe:  启动 exe 全名
    fun:  启动 fun 脚本全名（脚本启动时）
    path: 启动文件所在路径
    base: 启动文件去除扩展名
    argc: 命令行参数个数
    argv: 参数列表（脚本 + 用户参数）
  }
  *#
  result = new [];
  var exe = 0.arg();
  result.exe = exe;
  result.argv = new [];
  var arg1 = 1.arg();
  var isFun = arg1 <> '' and arg1 =~ /\.fun$/i;
  var si = 1;
  if isFun then
    var full = HostFullPath(arg1);
    si = 2;
    result.argv.@add(full);
    result['fun'] = full;
    result.path = DirName(full);
    result.base = full.replace(/\.\w+$/i, '');
    result.isFUN = true;
  else
    result.argv.@add(exe);
    result.path = DirName(exe);
    result.base = exe.replace(/\.\w+$/i, '');
    result.isFUN = false;
  end if;
  var i = si;
  while i.arg() <> '' do
    var a = i.arg();
    if a <> '-v' and a !~ /\.fun$/ then result.argv.@add(a); end if;
    i += 1;
  end do;
  result.argc = result.argv.@count();
end fun;

var cmdLineArgs = GetCmdLineArgs();
var __args = cmdLineArgs;

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
