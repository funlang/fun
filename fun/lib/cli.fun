// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// cli: a small command-line framework. A root command owns global flags and
// subcommands; every subcommand is also a cli.command. Help, version, aliases,
// env fallback, required flags, hooks and exit codes are built in.
//
//     use 'cli.fun';
//
//     fun hello(ctx)
//       ?. 'hello ' & ctx.string('name');
//     end fun;
//
//     var root = cli.command('demo', [version: '1.0']);
//     root.flag(cli.string('name', [aliases: ['n'], value: 'world']));
//     root.action(hello);
//     var code = root.run();
//
// The framework never calls exit(); run() returns a code. Call cli.quit(code)
// only after the command has finished, if the process should exit.

use 'lib-host.fun';
use 'env.fun';

var _CLI_NL = 10.toChar();
if IsWindows() then _CLI_NL = 13.toChar() & 10.toChar(); end if;
var _CLI_DASH = '-';

// Console writers. Help/errors go to fd 1/2 unless the caller passes an
// object with write(s), such as io.buffer.
var _cliWrite;
var _cliStdHandle;
var _cliWriteFile;
var _cliExit;
var _cliExitProcess;
if IsWindows() then
  _cliStdHandle = 'kernel32'.getapi('GetStdHandle', 'i:p');
  _cliWriteFile = 'kernel32'.getapi('WriteFile', 'ppipp:i');
  _cliExitProcess = 'kernel32'.getapi('ExitProcess', 'i:');
else
  _cliWrite = LibC().getapi('write', 'ipi:i');
  _cliExit = LibC().getapi('exit', 'i:');
end if;

class _CliConsole(fd)
  var h = fd;

  fun write(s)
    if s = '' then result = true; return; end if;
    try
      if IsWindows() then
        var id = -12;
        if this.h = 1 then id = -11; end if;
        var sh = _cliStdHandle(id);
        if sh <> nil then
          var got = 0.toChar().x(4);
          _cliWriteFile(sh, s.toNum(-1), s.length(), got.toNum(-1), nil);
        end if;
      else
        _cliWrite(this.h, s.toNum(-1), s.length());
      end if;
    except
    end try;
    result = true;
  end fun;
end class;

fun _cliList(v)
  result = new [];
  if v = nil then return; end if;
  var t = v.type();
  if t = 8 then result.@add(v); return; end if;
  try
    if v.@toJson(json: true).substr(0, 1) = '[' then
      for i = 0 to v.@count() - 1 do result.@add(v[i]); end do;
      return;
    end if;
  except
  end try;
  raise 'cli: expected a list';
end fun;

fun _cliJoin(xs, sep)
  var s = '';
  for i = 0 to xs.@count() - 1 do
    if i > 0 then s &= sep; end if;
    s &= '' & xs[i];
  end do;
  result = s;
end fun;

fun _cliPad(s, w)
  if s.length() >= w then result = s; return; end if;
  result = s & ' '.x(w - s.length());
end fun;

fun _cliOpt(opts, k)
  if opts = nil then result = nil; return; end if;
  if opts.@has(k) then result = opts[k]; else result = nil; end if;
end fun;

fun _cliBoolOpt(opts, k, d)
  var v = _cliOpt(opts, k);
  var t = v.type();
  if v = nil and t = 0 then result = d; return; end if;
  if t <> 11 then raise 'cli: ' & k & ' must be a boolean'; end if;
  result = v;
end fun;

fun _cliStringOpt(opts, k, d)
  var v = _cliOpt(opts, k);
  if v = nil and v.type() = 0 then result = d; return; end if;
  result = '' & v;
end fun;

fun _cliToBool(s)
  var t = ('' & s).lower();
  if t = 'true' or t = '1' or t = 'yes' or t = 'on' then result = true; return; end if;
  if t = 'false' or t = '0' or t = 'no' or t = 'off' then result = false; return; end if;
  raise 'invalid boolean ' & s;
end fun;

fun _cliIsDigit(c)
  if c = '' then result = false; return; end if;
  var b = c.toByte(0);
  result = b >= 48 and b <= 57;
end fun;

fun _cliIsIntText(s)
  var l = s.length();
  if l = 0 then result = false; return; end if;
  var i = 0;
  var c = s.substr(0, 1);
  if c = '+' or c = '-' then i = 1; end if;
  if i >= l then result = false; return; end if;
  while i < l do
    if not _cliIsDigit(s.substr(i, 1)) then result = false; return; end if;
    i += 1;
  end do;
  result = true;
end fun;

fun _cliIsFloatText(s)
  var l = s.length();
  if l = 0 then result = false; return; end if;
  var i = 0;
  var c = s.substr(0, 1);
  if c = '+' or c = '-' then i = 1; end if;
  var digits = 0;
  while i < l and _cliIsDigit(s.substr(i, 1)) do i += 1; digits += 1; end do;
  if i < l and s.substr(i, 1) = '.' then
    i += 1;
    while i < l and _cliIsDigit(s.substr(i, 1)) do i += 1; digits += 1; end do;
  end if;
  if digits = 0 then result = false; return; end if;
  if i < l and (s.substr(i, 1) = 'e' or s.substr(i, 1) = 'E') then
    i += 1;
    c = s.substr(i, 1);
    if c = '+' or c = '-' then i += 1; end if;
    var ed = 0;
    while i < l and _cliIsDigit(s.substr(i, 1)) do i += 1; ed += 1; end do;
    if ed = 0 then result = false; return; end if;
  end if;
  result = i = l;
end fun;

fun _cliNextValueOk(f, s)
  if s.length() < 2 then result = true; return; end if;
  if s.substr(0, 1) <> '-' then result = true; return; end if;
  if f.kind = 'int' then result = _cliIsIntText(s); return; end if;
  if f.kind = 'float' then result = _cliIsFloatText(s); return; end if;
  result = false;
end fun;

fun _cliIsFunScript(s)
  var l = s.length();
  if l < 4 then result = false; return; end if;
  var ext = s.substr(l - 4);
  result = ext = '.fun' or ext = '.foo' or ext = '.fxx';
end fun;

fun _cliToInt(s)
  var t = '' & s;
  if not _cliIsIntText(t) then raise 'invalid integer ' & s; end if;
  try
    var v = t.toNum();
    if v.type() <> 3 then raise 'invalid integer ' & s; end if;
    result = v;
  except
    raise 'invalid integer ' & s;
  end try;
end fun;

fun _cliToFloat(s)
  var t = '' & s;
  if not _cliIsFloatText(t) then raise 'invalid number ' & s; end if;
  try
    var v = t.toNum();
    if v.type() = 3 then result = 1.0 * v; return; end if;
    if v.type() <> 5 then raise 'invalid number ' & s; end if;
    result = v;
  except
    raise 'invalid number ' & s;
  end try;
end fun;

fun _cliFlagConvert(f, raw, envName)
  var label = 'flag --' & f.name;
  if envName <> '' then label &= ' from env ' & envName; end if;
  try
    if f.kind = 'bool' then result = _cliToBool(raw);
    elsif f.kind = 'int' then result = _cliToInt(raw);
    elsif f.kind = 'float' then result = _cliToFloat(raw);
    else result = raw;
    end if;
  except
    raise label & ': ' & ('' & @);
  end try;
end fun;

fun _cliFlagValue(kind, v)
  if kind = 'string' then
    if v.type() = 0 then result = ''; else result = '' & v; end if;
    return;
  end if;
  if kind = 'bool' then
    if v.type() = 0 then result = false; elsif v.type() = 11 then result = v; else result = _cliToBool(v); end if;
    return;
  end if;
  if kind = 'int' then
    if v.type() = 0 then result = 0; else result = _cliToInt(v); end if;
    return;
  end if;
  if kind = 'float' then
    if v.type() = 0 then result = 0.0; else result = _cliToFloat(v); end if;
    return;
  end if;
  if kind = 'strings' then
    if v = nil then result = new []; else result = _cliList(v); end if;
    return;
  end if;
  raise 'cli: unknown flag kind ' & kind;
end fun;

fun _cliCopyValue(v)
  if v = nil then result = nil; return; end if;
  try
    if v.@toJson(json: true).substr(0, 1) = '[' then
      result = new [];
      for i = 0 to v.@count() - 1 do result.@add(v[i]); end do;
      return;
    end if;
  except
  end try;
  result = v;
end fun;

fun _cliArgv()
  var raw = new [];
  var i = 1;
  while i.arg() <> '' do
    raw.@add(i.arg());
    i += 1;
  end do;
  var skip = raw.@count() > 0 and _cliIsFunScript(raw[0]);
  result = new [];
  for j = 0 to raw.@count() - 1 do
    if not (skip and j = 0) then result.@add(raw[j]); end if;
  end do;
end fun;

fun _cliNameBad(s)
  var t = '' & s;
  if t = '' then result = true; return; end if;
  if t.substr(0, 1) = '-' then result = true; return; end if;
  result = t.subpos('=') >= 0;
end fun;

fun _cliCommandMatches(c, s)
  if c.name.eq(s) then result = true; return; end if;
  for i = 0 to c.aliases.@count() - 1 do
    if c.aliases[i].eq(s) then result = true; return; end if;
  end do;
  result = false;
end fun;

fun _cliAddFlag(flags, f)
  for i = 0 to flags.@count() - 1 do
    var g = flags[i];
    if g.matches(f.name) then raise 'cli: duplicate flag --' & f.name; end if;
    for j = 0 to f.aliases.@count() - 1 do
      if g.matches(f.aliases[j]) then
        raise 'cli: duplicate flag alias -' & f.aliases[j];
      end if;
    end do;
  end do;
  for j = 0 to f.aliases.@count() - 1 do
    if f.aliases[j].eq(f.name) then raise 'cli: duplicate flag alias -' & f.aliases[j]; end if;
    for k = j + 1 to f.aliases.@count() - 1 do
      if f.aliases[j].eq(f.aliases[k]) then
        raise 'cli: duplicate flag alias -' & f.aliases[j];
      end if;
    end do;
  end do;
  flags.@add(f);
end fun;

fun _cliAddCommandFlag(flags, f, version)
  if f.matches('help') or f.matches('h') then
    raise 'cli: flag ' & f.name & ' is reserved for --help';
  end if;
  if version <> '' and (f.matches('version') or f.matches('v')) then
    raise 'cli: flag ' & f.name & ' is reserved for --version';
  end if;
  _cliAddFlag(flags, f);
end fun;

fun _cliAddCommand(commands, c)
  if c.name.eq('help') then raise 'cli: command help is reserved'; end if;
  for j = 0 to c.aliases.@count() - 1 do
    if c.aliases[j].eq('help') then raise 'cli: command alias help is reserved'; end if;
  end do;
  for i = 0 to commands.@count() - 1 do
    var g = commands[i];
    if _cliCommandMatches(g, c.name) then raise 'cli: duplicate command ' & c.name; end if;
    for j = 0 to c.aliases.@count() - 1 do
      if _cliCommandMatches(g, c.aliases[j]) then
        raise 'cli: duplicate command alias ' & c.aliases[j];
      end if;
    end do;
  end do;
  for j = 0 to c.aliases.@count() - 1 do
    if c.aliases[j].eq(c.name) then raise 'cli: duplicate command alias ' & c.aliases[j]; end if;
    for k = j + 1 to c.aliases.@count() - 1 do
      if c.aliases[j].eq(c.aliases[k]) then
        raise 'cli: duplicate command alias ' & c.aliases[j];
      end if;
    end do;
  end do;
  commands.@add(c);
end fun;

class _CliFlag(name, kind, opts)
  var name = name;
  var kind = kind;
  var aliases = new [];
  var def = nil;
  var hasDef = false;
  var usage = '';
  var envs = new [];
  var required = false;
  var hidden = false;
  var placeholder = '';

  if name = nil or name = '' then raise 'cli: flag name required'; end if;
  if _cliNameBad(name) then raise 'cli: invalid flag name --' & name; end if;
  var av = _cliOpt(opts, 'aliases');
  if av <> nil then aliases = _cliList(av); end if;
  for i = 0 to aliases.@count() - 1 do
    if _cliNameBad(aliases[i]) then raise 'cli: invalid flag alias -' & aliases[i]; end if;
  end do;
  var ev = _cliOpt(opts, 'env');
  if ev <> nil then envs = _cliList(ev); end if;
  if opts <> nil and opts.@has('value') then
    def = opts['value'];
    hasDef = true;
  end if;
  def = _cliFlagValue(kind, def);
  usage = _cliStringOpt(opts, 'usage', '');
  required = _cliBoolOpt(opts, 'required', false);
  hidden = _cliBoolOpt(opts, 'hidden', false);
  placeholder = _cliStringOpt(opts, 'placeholder', '');
  if placeholder = '' and kind <> 'bool' then placeholder = 'value'; end if;

  fun fresh()
    result = _cliCopyValue(this.def);
    if result = nil then result = _cliFlagValue(this.kind, nil); end if;
  end fun;

  fun matches(s)
    if s.eq(this.name) then result = true; return; end if;
    for i = 0 to this.aliases.@count() - 1 do
      if this.aliases[i].eq(s) then result = true; return; end if;
    end do;
    result = false;
  end fun;
end class;

class _CliContext(values, given, argv, name, kinds, o, e)
  var vals = values;
  var set = given;
  var list = argv;
  var cmdName = name;
  var kinds = kinds;
  var o = o;
  var e = e;

  fun _kind(name)
    if not this.kinds.@has(name) then raise "unknown flag '" & name & "'"; end if;
    result = this.kinds[name];
  end fun;

  fun _need(name, kind)
    var k = this._kind(name);
    if k <> kind then
      raise "flag '" & name & "' is " & k & ', not ' & kind;
    end if;
  end fun;

  fun string(name)
    this._need(name, 'string');
    result = '' & this.vals[name];
  end fun;

  fun bool(name)
    this._need(name, 'bool');
    result = this.vals[name];
  end fun;

  fun int(name)
    this._need(name, 'int');
    result = this.vals[name];
  end fun;

  fun float(name)
    this._need(name, 'float');
    result = this.vals[name];
  end fun;

  fun strings(name)
    this._need(name, 'strings');
    result = this.vals[name];
  end fun;

  fun has(name)
    this._kind(name);
    result = this.set.@has(name);
  end fun;

  fun out()
    result = this.o;
  end fun;

  fun err()
    result = this.e;
  end fun;

  fun args()
    result = this.list;
  end fun;

  fun arg(n)
    if n >= 0 and n < this.list.@count() then result = this.list[n]; else result = nil; end if;
  end fun;

  fun narg()
    result = this.list.@count();
  end fun;

  fun command()
    result = this.cmdName;
  end fun;
end class;

class _CliCommand(name, opts)
  var name = name;
  var aliases = new [];
  var usage = '';
  var usageText = '';
  var argsUsage = '';
  var version = '';
  var description = '';
  var flags = new [];
  var commands = new [];
  var act = nil;
  var beforeFn = nil;
  var afterFn = nil;
  var hidden = false;
  var out = nil;
  var err = nil;

  if name = nil or name = '' then raise 'cli: command name required'; end if;
  if _cliNameBad(name) then raise 'cli: invalid command name ' & name; end if;
  var av = _cliOpt(opts, 'aliases');
  if av <> nil then aliases = _cliList(av); end if;
  for i = 0 to aliases.@count() - 1 do
    if _cliNameBad(aliases[i]) then raise 'cli: invalid command alias ' & aliases[i]; end if;
  end do;
  usage = _cliStringOpt(opts, 'usage', '');
  usageText = _cliStringOpt(opts, 'usageText', '');
  argsUsage = _cliStringOpt(opts, 'argsUsage', '');
  version = _cliStringOpt(opts, 'version', '');
  description = _cliStringOpt(opts, 'description', '');
  hidden = _cliBoolOpt(opts, 'hidden', false);
  out = _cliOpt(opts, 'out');
  err = _cliOpt(opts, 'err');
  act = _cliOpt(opts, 'action');
  beforeFn = _cliOpt(opts, 'before');
  afterFn = _cliOpt(opts, 'after');
  var fs = _cliOpt(opts, 'flags');
  if fs <> nil then
    for i = 0 to fs.@count() - 1 do _cliAddCommandFlag(flags, fs[i], version); end do;
  end if;
  var cs = _cliOpt(opts, 'commands');
  if cs <> nil then
    for i = 0 to cs.@count() - 1 do _cliAddCommand(commands, cs[i]); end do;
  end if;

  fun flag(f)
    _cliAddCommandFlag(this.flags, f, this.version);
    result = this;
  end fun;

  fun command(c)
    _cliAddCommand(this.commands, c);
    result = this;
  end fun;

  fun action(fn)
    this.act = fn;
    result = this;
  end fun;

  fun before(fn)
    this.beforeFn = fn;
    result = this;
  end fun;

  fun after(fn)
    this.afterFn = fn;
    result = this;
  end fun;

  fun _findFlag(s)
    for i = 0 to this.flags.@count() - 1 do
      if this.flags[i].matches(s) then result = this.flags[i]; return; end if;
    end do;
    result = nil;
  end fun;

  fun _findCommand(s)
    for i = 0 to this.commands.@count() - 1 do
      if _cliCommandMatches(this.commands[i], s) then result = this.commands[i]; return; end if;
    end do;
    result = nil;
  end fun;

  fun _put(f, val, vals, given)
    if f.kind = 'strings' then
      if not given.@has(f.name) then vals[f.name] = new []; end if;
      vals[f.name].@add(val);
    else
      vals[f.name] = val;
    end if;
    given[f.name] = true;
  end fun;

  fun _applyEnv(vals, given)
    for i = 0 to this.flags.@count() - 1 do
      var f = this.flags[i];
      if not given.@has(f.name) then
        for j = 0 to f.envs.@count() - 1 do
          var n = f.envs[j];
          if env.has(n) then
            var raw = env.get(n);
            if f.kind = 'strings' then
              var xs = new [];
              if raw <> '' then
                var start = 0;
                for k = 0 to raw.length() - 1 do
                  if raw.substr(k, 1) = ',' then
                    xs.@add(raw.substr(start, k - start));
                    start = k + 1;
                  end if;
                end do;
                xs.@add(raw.substr(start));
              end if;
              vals[f.name] = xs;
              given[f.name] = true;
            else
              _put(f, _cliFlagConvert(f, raw, n), vals, given);
            end if;
            exit;
          end if;
        end do;
      end if;
    end do;
  end fun;

  fun _checkRequired(given)
    for i = 0 to this.flags.@count() - 1 do
      var f = this.flags[i];
      if f.required and not given.@has(f.name) then
        raise 'required flag --' & f.name;
      end if;
    end do;
  end fun;

  fun _helpText()
    var lines = new [];
    var head = this.name;
    if this.version <> '' then head &= ' ' & this.version; end if;
    lines.@add(head);
    if this.description <> '' then
      lines.@add(this.description);
    elsif this.usage <> '' then
      lines.@add(this.usage);
    end if;
    if this.usageText <> '' then
      lines.@add(this.usageText);
    else
      var u = 'usage: ' & this.name;
      if this.flags.@count() > 0 then u &= ' [options]'; end if;
      if this.commands.@count() > 0 then u &= ' [command]'; end if;
      if this.argsUsage <> '' then u &= ' ' & this.argsUsage; end if;
      lines.@add(u);
    end if;
    if this.commands.@count() > 0 then
      lines.@add('');
      lines.@add('commands:');
      var cw = 'help'.length();
      for i = 0 to this.commands.@count() - 1 do
        var c = this.commands[i];
        if not c.hidden then
          var spec = c.name;
          if c.aliases.@count() > 0 then spec &= ' (' & _cliJoin(c.aliases, ', ') & ')'; end if;
          if spec.length() > cw then cw = spec.length(); end if;
        end if;
      end do;
      for i = 0 to this.commands.@count() - 1 do
        var c = this.commands[i];
        if not c.hidden then
          var spec = c.name;
          if c.aliases.@count() > 0 then spec &= ' (' & _cliJoin(c.aliases, ', ') & ')'; end if;
          var line = '  ' & _cliPad(spec, cw);
          if c.usage <> '' then line &= '  ' & c.usage; end if;
          lines.@add(line);
        end if;
      end do;
      lines.@add('  ' & _cliPad('help', cw) & '  show help');
    end if;
    lines.@add('');
    lines.@add('options:');
    var fw = '-h, --help'.length();
    if this.version <> '' and '-v, --version'.length() > fw then fw = '-v, --version'.length(); end if;
    for i = 0 to this.flags.@count() - 1 do
      if not this.flags[i].hidden then
        var spec = this._flagSpec(this.flags[i]);
        if spec.length() > fw then fw = spec.length(); end if;
      end if;
    end do;
    for i = 0 to this.flags.@count() - 1 do
      var f = this.flags[i];
      if not f.hidden then
        var line = '  ' & _cliPad(this._flagSpec(f), fw);
        var desc = this._flagDesc(f);
        if desc <> '' then line &= '  ' & desc; end if;
        lines.@add(line);
      end if;
    end do;
    lines.@add('  ' & _cliPad('-h, --help', fw) & '  show help');
    if this.version <> '' then lines.@add('  ' & _cliPad('-v, --version', fw) & '  show version'); end if;
    var body = '';
    for i = 0 to lines.@count() - 1 do
      if i > 0 then body &= _CLI_NL; end if;
      body &= lines[i];
    end do;
    result = body & _CLI_NL;
  end fun;

  fun _flagSpec(f)
    var s = '';
    for i = 0 to f.aliases.@count() - 1 do
      s &= '-' & f.aliases[i] & ', ';
    end do;
    s &= '--' & f.name;
    if f.kind <> 'bool' then s &= ' <' & f.placeholder & '>'; end if;
    result = s;
  end fun;

  fun _flagDefault(f)
    if f.kind = 'strings' then result = f.def.@toJson(); return; end if;
    if f.kind = 'string' then result = '"' & f.def & '"'; return; end if;
    if f.kind = 'bool' then
      if f.def then result = 'true'; else result = 'false'; end if;
      return;
    end if;
    result = '' & f.def;
  end fun;

  fun _flagDesc(f)
    var s = f.usage;
    if f.hasDef then
      if s <> '' then s &= ' '; end if;
      s &= '(default: ' & _flagDefault(f) & ')';
    end if;
    if f.required then
      if s <> '' then s &= ' '; end if;
      s &= '(required)';
    end if;
    if f.envs.@count() > 0 then
      if s <> '' then s &= ' '; end if;
      s &= '(env: ' & _cliJoin(f.envs, ', ') & ')';
    end if;
    result = s;
  end fun;

  fun _out(s, o)
    if o <> nil then o.write(s); end if;
  end fun;

  fun _err(s, e)
    if e <> nil then e.write(s); end if;
  end fun;

  fun _usageError(s, e)
    this._err('error: ' & s & _CLI_NL & "Run '" & this.name & " --help' for usage." & _CLI_NL, e);
  end fun;

  fun help()
    result = this._helpText();
  end fun;

  fun _runHelp(tokens, o, e)
    var c = this;
    var i = 0;
    while i < tokens.@count() do
      if tokens[i].eq('help') then
        if i = tokens.@count() - 1 then
          this._out(c._helpText(), o);
          result = 0;
          return;
        end if;
        c._usageError('unknown command ' & tokens[i], e);
        result = 2;
        return;
      end if;
      var nx = c._findCommand(tokens[i]);
      if nx = nil then
        c._usageError('unknown command ' & tokens[i], e);
        result = 2;
        return;
      end if;
      c = nx;
      i += 1;
    end do;
    this._out(c._helpText(), o);
    result = 0;
  end fun;

  fun _code(v)
    var t = v.type();
    if v = nil and t = 0 then result = 0; return; end if;
    if t = 3 then result = v; return; end if;
    if t = 11 then
      if v then result = 0; else result = 1; end if;
      return;
    end if;
    raise 'action must return nil, an integer or a boolean';
  end fun;

  fun _hookBefore(fn, ctx, e)
    try
      var bc = fn(ctx);
      var bt = bc.type();
      if bc = nil and bt = 0 then result = 0; return; end if;
      if bt = 11 then
        if bc then result = 0; else
          this._err('error: before hook failed' & _CLI_NL, e);
          result = 1;
        end if;
        return;
      end if;
      if bt = 3 then
        if bc <> 0 then result = bc; end if;
        return;
      end if;
      raise 'before hook must return nil, an integer or a boolean';
    except
      this._err('error: ' & ('' & @) & _CLI_NL, e);
      result = 1;
    end try;
  end fun;

  fun _hookAfter(fn, ctx, e)
    try
      fn(ctx);
      result = 0;
    except
      this._err('error: ' & ('' & @) & _CLI_NL, e);
      result = 1;
    end try;
  end fun;

  fun _runParentsBefore(parents, vals, given, e, ctxs)
    for i = 0 to parents.@count() - 1 do
      var p = parents[i];
      p._applyEnv(vals, given);
      p._checkRequired(given);
      if p.beforeFn <> nil then
        var bc = p._hookBefore(p.beforeFn, ctxs[i], ctxs[i].err());
        if bc <> 0 then result = bc; return; end if;
      end if;
    end do;
    result = 0;
  end fun;

  fun _runParentsAfter(parents, e, ctxs)
    var i = parents.@count() - 1;
    while i >= 0 do
      var p = parents[i];
      if p.afterFn <> nil then
        var ac = p._hookAfter(p.afterFn, ctxs[i], ctxs[i].err());
        if ac <> 0 then result = ac; return; end if;
      end if;
      i -= 1;
    end do;
    result = 0;
  end fun;

  fun _runInner(tokens, inherited, given, root, o, e, parents)
    var vals = new [];
    inherited.@each((v, k){ vals[k] = _cliCopyValue(v); });
    var gv = new [];
    given.@each((v, k){ gv[k] = v; });
    for i = 0 to this.flags.@count() - 1 do
      var f = this.flags[i];
      if not given.@has(f.name) then vals[f.name] = f.fresh(); end if;
    end do;

    var pos = new [];
    var i = 0;
    var showHelp = false;
    var showVersion = false;
    while i < tokens.@count() do
      var a = tokens[i];
      if a.eq('--') then
        i += 1;
        while i < tokens.@count() do pos.@add(tokens[i]); i += 1; end do;
        exit;
      end if;
      if a.eq('-h') or a.eq('--help') then showHelp = true; exit; end if;
      if a.eq('-v') and this.version <> '' then showVersion = true; exit; end if;
      if a.eq('--version') and this.version <> '' then showVersion = true; exit; end if;

      if a.eq('help') and pos.@count() = 0 and (parents.@count() = 0 or this.commands.@count() > 0) then
        var rest = new [];
        for j = i + 1 to tokens.@count() - 1 do rest.@add(tokens[j]); end do;
        result = this._runHelp(rest, o, e);
        return;
      end if;

      if a.substr(0, 2) = '--' and a.length() > 2 then
        var body = a.substr(2);
        var eq = body.subpos('=');
        var nm = body;
        var hasVal = false;
        var raw = '';
        if eq >= 0 then
          nm = body.substr(0, eq);
          raw = body.substr(eq + 1);
          hasVal = true;
        end if;
        var f = this._findFlag(nm);
        if f = nil then raise 'unknown flag --' & nm; end if;
        if f.kind = 'bool' then
          if hasVal then _put(f, _cliFlagConvert(f, raw, ''), vals, gv); else _put(f, true, vals, gv); end if;
          i += 1;
        else
          if not hasVal then
            if i + 1 >= tokens.@count() or not _cliNextValueOk(f, tokens[i + 1]) then
              raise 'flag --' & nm & ' needs a value';
            end if;
            i += 1;
            raw = tokens[i];
          end if;
          _put(f, _cliFlagConvert(f, raw, ''), vals, gv);
          i += 1;
        end if;
      elsif a.substr(0, 1) = _CLI_DASH and a.length() > 1 then
        var body = a.substr(1);
        var eq = body.subpos('=');
        var f = nil;
        if eq >= 0 then
          var nm = body.substr(0, eq);
          f = _findFlag(nm);
          if f = nil then raise 'unknown flag -' & nm; end if;
          var raw = body.substr(eq + 1);
          _put(f, _cliFlagConvert(f, raw, ''), vals, gv);
          i += 1;
        else
          f = _findFlag(body);
          if f <> nil then
            if f.kind = 'bool' then
              _put(f, true, vals, gv);
              i += 1;
            else
              if i + 1 >= tokens.@count() or not _cliNextValueOk(f, tokens[i + 1]) then
                raise 'flag -' & body & ' needs a value';
              end if;
              i += 1;
              var raw = tokens[i];
              _put(f, _cliFlagConvert(f, raw, ''), vals, gv);
              i += 1;
            end if;
          else
            var j = 0;
            var used = false;
            while j < body.length() do
              var ch = body.substr(j, 1);
              var cf = _findFlag(ch);
              if cf = nil then raise 'unknown flag -' & ch; end if;
              if cf.kind = 'bool' then
                _put(cf, true, vals, gv);
                j += 1;
              else
                var rem = body.substr(j + 1);
                var raw = '';
                if rem <> '' then
                  raw = rem;
                  i += 1;
                else
                  if i + 1 >= tokens.@count() or not _cliNextValueOk(cf, tokens[i + 1]) then
                    raise 'flag -' & ch & ' needs a value';
                  end if;
                  i += 1;
                  raw = tokens[i];
                  i += 1;
                end if;
                _put(cf, _cliFlagConvert(cf, raw, ''), vals, gv);
                used = true;
                exit;
              end if;
            end do;
            if not used then i += 1; end if;
          end if;
        end if;
      else
        if this.commands.@count() > 0 and pos.@count() = 0 then
          var c = this._findCommand(a);
          if c = nil then raise 'unknown command ' & a; end if;
          var ps = new [];
          for k = 0 to parents.@count() - 1 do ps.@add(parents[k]); end do;
          ps.@add(this);
          var rest = new [];
          for j = i + 1 to tokens.@count() - 1 do rest.@add(tokens[j]); end do;
          var co = c.out;
          if co = nil then co = o; end if;
          var ce = c.err;
          if ce = nil then ce = e; end if;
          result = c._run(rest, vals, gv, root, co, ce, ps);
          return;
        end if;
        pos.@add(a);
        i += 1;
      end if;
    end do;

    if showHelp then
      this._out(this._helpText(), o);
      result = 0;
      return;
    end if;
    if showVersion then
      this._out(this.name & ' ' & this.version & _CLI_NL, o);
      result = 0;
      return;
    end if;

    if this.act = nil then
      this._out(this._helpText(), o);
      result = 0;
      return;
    end if;

    var kinds = new [];
    for pi = 0 to parents.@count() - 1 do
      var pf = parents[pi].flags;
      for j = 0 to pf.@count() - 1 do kinds[pf[j].name] = pf[j].kind; end do;
    end do;
    for i = 0 to this.flags.@count() - 1 do
      kinds[this.flags[i].name] = this.flags[i].kind;
    end do;
    var pctxs = new [];
    for pi = 0 to parents.@count() - 1 do
      var po = parents[pi].out;
      if po = nil then po = o; end if;
      var pe = parents[pi].err;
      if pe = nil then pe = e; end if;
      pctxs.@add(_CliContext(vals, gv, new [], parents[pi].name, kinds, po, pe));
    end do;
    var ctx = _CliContext(vals, gv, pos, this.name, kinds, o, e);

    var pbc = this._runParentsBefore(parents, vals, gv, e, pctxs);
    if pbc <> 0 then result = pbc; return; end if;

    this._applyEnv(vals, gv);
    this._checkRequired(gv);

    if this.beforeFn <> nil then
      var bc = this._hookBefore(this.beforeFn, ctx, e);
      if bc <> 0 then result = bc; return; end if;
    end if;

    var code = 0;
    try
      code = _code(this.act(ctx));
    except
      this._err('error: ' & ('' & @) & _CLI_NL, e);
      code = 1;
    end try;

    if this.afterFn <> nil then
      var ac = this._hookAfter(this.afterFn, ctx, e);
      if ac <> 0 then code = ac; end if;
    end if;

    var pac = this._runParentsAfter(parents, e, pctxs);
    if pac <> 0 then result = pac; return; end if;
    result = code;
  end fun;

  fun _run(tokens, inherited, given, root, o, e, parents)
    try
      result = this._runInner(tokens, inherited, given, root, o, e, parents);
    except
      this._usageError('' & @, e);
      result = 2;
    end try;
  end fun;

  fun run(args)
    var toks = args;
    if toks = nil then toks = _cliArgv(); end if;
    var o = this.out;
    var e = this.err;
    if o = nil then o = _CliConsole(1); end if;
    if e = nil then e = _CliConsole(2); end if;
    result = this._run(toks, new [], new [], this, o, e, new []);
  end fun;
end class;

class _CliApi()
  fun command(name, opts)
    result = _CliCommand(name, opts);
  end fun;

  fun string(name, opts)
    result = _CliFlag(name, 'string', opts);
  end fun;

  fun bool(name, opts)
    result = _CliFlag(name, 'bool', opts);
  end fun;

  fun int(name, opts)
    result = _CliFlag(name, 'int', opts);
  end fun;

  fun float(name, opts)
    result = _CliFlag(name, 'float', opts);
  end fun;

  fun strings(name, opts)
    result = _CliFlag(name, 'strings', opts);
  end fun;

  fun quit(code)
    var t = code.type();
    if t = 0 then code = 0;
    elsif t <> 3 then raise 'cli: exit code must be an integer'; end if;
    if IsWindows() then _cliExitProcess(code); else _cliExit(code); end if;
    result = true;
  end fun;
end class;

var cli = _CliApi();
