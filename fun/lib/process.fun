// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// process: run a child process and capture its stdio.
//
//     use 'process.fun';
//
//     var r = process.run('git', ['status', '--short'], [timeout: 5000]);
//     r.ok; r.exitCode; r.stdout; r.stderr;
//
// The command is executed directly (no shell). Use 'sh' / 'cmd' explicitly
// when shell syntax is needed. Input and output are raw bytes.

var _P_CHUNK = 65536;
var _P_POLL_MS = 50;
var _P_POLLIN = 1;

var _pState = new [
  hostKnown: false,
  bound: false,
  isWindows: false,
  isMac: false,
  isLinux: false,
  isUnicode: false,
  ptrBytes: 4,
  pipe: nil,
  fork: nil,
  dup2: nil,
  closeFd: nil,
  execvp: nil,
  waitpid: nil,
  kill: nil,
  exitNow: nil,
  fcntl: nil,
  poll: nil,
  chdir: nil,
  signal: nil,
  read: nil,
  write: nil,
  errno: nil,
  strerror: nil,
  memcpy: nil,
  getTime: nil,
  createPipe: nil,
  setHandleInfo: nil,
  createProcess: nil,
  peek: nil,
  readFile: nil,
  writeFile: nil,
  waitSingle: nil,
  getExitCode: nil,
  terminate: nil,
  closeHandle: nil,
  getLastError: nil,
  getTick: nil,
  getTempPath: nil,
  getTempName: nil,
  createFile: nil,
  setFilePointer: nil,
  deleteFile: nil
];

fun _pHost()
  if _pState.hostKnown then result = true; return; end if;
  var host = 'host'.arg().getJson(fd: true);
  _pState.isWindows = host.os = 'windows';
  _pState.isMac = host.os = 'macos';
  _pState.isLinux = host.os = 'linux';
  _pState.isUnicode = 0x1234.toChar().toByte() > 0xff;
  _pState.ptrBytes = host.bits div 8;
  if not _pState.isWindows and not _pState.isMac and not _pState.isLinux then
    raise 'process: unsupported host ' & host.os;
  end if;
  _pState.hostKnown = true;
  result = true;
end fun;

fun _pBind()
  if _pState.bound then result = true; return; end if;
  _pHost();
  try
    if _pState.isWindows then
      _pState.createPipe = 'kernel32'.getapi('CreatePipe', 'iiii:i');
      _pState.setHandleInfo = 'kernel32'.getapi('SetHandleInformation', 'iii:i');
      _pState.createProcess = 'kernel32'.getapi('CreateProcessA', 'iaiiiiiiii:i');
      _pState.peek = 'kernel32'.getapi('PeekNamedPipe', 'iiiiii:i');
      _pState.readFile = 'kernel32'.getapi('ReadFile', 'iiiiv:i');
      _pState.writeFile = 'kernel32'.getapi('WriteFile', 'iiiiv:i');
      _pState.waitSingle = 'kernel32'.getapi('WaitForSingleObject', 'ii:i');
      _pState.getExitCode = 'kernel32'.getapi('GetExitCodeProcess', 'iii:i');
      _pState.terminate = 'kernel32'.getapi('TerminateProcess', 'ii:i');
      _pState.closeHandle = 'kernel32'.getapi('CloseHandle', 'i:i');
      _pState.getLastError = 'kernel32'.getapi('GetLastError', ':i');
      _pState.getTick = 'kernel32'.getapi('GetTickCount', ':i');
      _pState.getTempPath = 'kernel32'.getapi('GetTempPathA', 'ii:i');
      _pState.getTempName = 'kernel32'.getapi('GetTempFileNameA', 'iiii:i');
      _pState.createFile = 'kernel32'.getapi('CreateFileA', 'iiiiiii:p');
      _pState.setFilePointer = 'kernel32'.getapi('SetFilePointer', 'iiii:i');
      _pState.deleteFile = 'kernel32'.getapi('DeleteFileA', 'i:i');
    else
      var lib = 'libc.so.6';
      if _pState.isMac then lib = 'libSystem.B.dylib'; end if;
      _pState.pipe = lib.getapi('pipe', 'p:i');
      _pState.fork = lib.getapi('fork', ':i');
      _pState.dup2 = lib.getapi('dup2', 'ii:i');
      _pState.closeFd = lib.getapi('close', 'i:i');
      _pState.execvp = lib.getapi('execvp', 'pp:i');
      _pState.waitpid = lib.getapi('waitpid', 'ipi:i');
      _pState.kill = lib.getapi('kill', 'ii:i');
      _pState.exitNow = lib.getapi('_exit', 'i:');
      _pState.fcntl = lib.getapi('fcntl', 'iii:i', variadic: 2);
      _pState.poll = lib.getapi('poll', 'iii:i');
      _pState.chdir = lib.getapi('chdir', 's:i');
      _pState.signal = lib.getapi('signal', 'ii:i');
      _pState.read = lib.getapi('read', 'ipi:i');
      _pState.write = lib.getapi('write', 'ipi:i');
      _pState.memcpy = lib.getapi('memcpy', 'ppn:p');
      _pState.getTime = lib.getapi('gettimeofday', 'ipi:i');
      if _pState.isMac then
        _pState.errno = lib.getapi('__error', ':p');
      else
        _pState.errno = lib.getapi('__errno_location', ':p');
      end if;
      try
        _pState.strerror = lib.getapi('strerror', 'i:s');
      except
        _pState.strerror = nil;
      end try;
    end if;
    _pState.bound = true;
    result = true;
  except
    var why = '' & @;
    if why.subpos('safe mode') >= 0 then
      raise 'process.run: native process execution is disabled in safe mode (' & why & ')';
    end if;
    raise 'process.run: an FFI-enabled build is required (' & why & ')';
  end try;
end fun;

fun _pByteAt(s, i)
  result = s[i * 0.5 + 0.1];
end fun;

fun _pBytesToString(buf, k)
  if k = 0 then result = ''; return; end if;
  if _pState.isUnicode then
    result = '';
    for i = 0 to k - 1 do result &= _pByteAt(buf, i).toChar(); end do;
  else
    result = buf.substr(0, k);
  end if;
end fun;

fun _pByteData(s)
  if not _pState.isUnicode then result = s; return; end if;
  var n = s.length();
  var b = 0.toChar().x(n);
  for i = 0 to n - 1 do b.fromByte(i, s.toByte(i)); end do;
  result = b;
end fun;

fun _pDwordAt(s, at)
  if _pState.isUnicode then
    result = (_pByteAt(s, at + 3) << 24) + (_pByteAt(s, at + 2) << 16) +
             (_pByteAt(s, at + 1) << 8) + _pByteAt(s, at);
  else
    result = (s.toByte(at + 3) << 24) + (s.toByte(at + 2) << 16) +
             (s.toByte(at + 1) << 8) + s.toByte(at);
  end if;
end fun;

fun _pDword(s)
  result = _pDwordAt(s, 0);
end fun;

fun _pPtrAt(s, at)
  result = 0;
  var m = 1;
  for i = 0 to _pState.ptrBytes - 1 do
    if _pState.isUnicode then
      result += _pByteAt(s, at + i) * m;
    else
      result += s.toByte(at + i) * m;
    end if;
    if i < _pState.ptrBytes - 1 then m *= 256; end if;
  end do;
end fun;

fun _pWrite32(buf, at, v)
  buf.fromByte(at, v bit and 0xff);
  buf.fromByte(at + 1, (v >> 8) bit and 0xff);
  buf.fromByte(at + 2, (v >> 16) bit and 0xff);
  buf.fromByte(at + 3, (v >> 24) bit and 0xff);
end fun;

fun _pWritePtr(buf, at, v)
  var lo = v mod 4294967296;
  var hi = (v div 4294967296) mod 4294967296;
  _pWrite32(buf, at, lo);
  if _pState.ptrBytes = 8 then _pWrite32(buf, at + 4, hi); end if;
end fun;

fun _pErrnoValue()
  var errno = _pState.errno;
  var memcpy = _pState.memcpy;
  if errno = nil or memcpy = nil then result = -1; return; end if;
  var p = errno();
  if p = nil then result = -1; return; end if;
  var buf = 0.toChar().x(4);
  memcpy(buf.toNum(-1), p, 4);
  result = _pDword(buf);
end fun;

fun _pErrnoText(e)
  if e < 0 then result = ''; return; end if;
  var strerror = _pState.strerror;
  var s = '';
  if strerror <> nil then s = strerror(e); end if;
  if s = nil or s = '' then result = 'errno ' & e;
  else result = s & ' (' & e & ')'; end if;
end fun;

fun _pIsAgain(e)
  result = e = 4 or e = 11 or e = 35;
end fun;

fun _pStr(v, what)
  if v.type() = 0 then raise 'process: ' & what & ' is required'; end if;
  if v.type() <> 8 then raise 'process: ' & what & ' must be a string'; end if;
  if v.subpos(0.toChar()) >= 0 then raise 'process: ' & what & ' must not contain NUL'; end if;
  result = v;
end fun;

fun _pArgs(args)
  result = new [];
  if args = nil then return; end if;
  var n = 0;
  try
    n = args.@count();
  except
    raise 'process: args must be a list of strings';
  end try;
  for i = 0 to n - 1 do
    result.@add(_pStr(args[i], 'args[' & i & ']'));
  end do;
end fun;

fun _pOpt(opts, name)
  result = nil;
  if opts = nil then return; end if;
  try
    if opts.@has(name) then result = opts[name]; end if;
  except
    raise 'process: opts must be a set';
  end try;
end fun;

fun _pCheckOpts(opts)
  if opts = nil then return; end if;
  var bad = '';
  var listish = false;
  try
    opts.@each((v, k){
      if k = nil or k = '' then
        listish = true;
      elsif k <> 'stdin' and k <> 'cwd' and k <> 'timeout' and k <> 'output' then
        bad = k;
      end if;
    });
  except
    raise 'process: opts must be a set';
  end try;
  if listish then raise 'process: opts must be a set'; end if;
  if bad <> '' then raise 'process: unknown option: ' & bad; end if;
  result = true;
end fun;

fun _pUnixPipe()
  var buf = 0.toChar().x(8);
  if _pState.pipe(buf.toNum(-1)) <> 0 then
    var e = _pErrnoValue();
    raise 'process: create pipe failed (' & _pErrnoText(e) & ')';
  end if;
  var fds = new [];
  fds.@add(_pDwordAt(buf, 0));
  fds.@add(_pDwordAt(buf, 4));
  result = fds;
end fun;

fun _pUnixClose(fd)
  if fd <> nil and fd >= 0 then _pState.closeFd(fd); end if;
  result = true;
end fun;

fun _pUnixCloseAll(fds)
  for fd in fds do _pUnixClose(fd); end do;
  result = true;
end fun;

fun _pUnixClosePair(pair)
  if pair <> nil then _pUnixClose(pair[0]); _pUnixClose(pair[1]); end if;
  result = true;
end fun;

fun _pUnixPipes()
  var a = new [];
  try
    a.@add(_pUnixPipe());
    a.@add(_pUnixPipe());
    a.@add(_pUnixPipe());
    a.@add(_pUnixPipe());
  except
    for p in a do _pUnixClosePair(p); end do;
    raise @;
  end try;
  result = a;
end fun;

fun _pUnixCloexec(fd)
  _pState.fcntl(fd, 2, 1);
  result = true;
end fun;

fun _pUnixNonblock(fd)
  var flags = 2048;
  if _pState.isMac then flags = 4; end if;
  _pState.fcntl(fd, 4, flags);
  result = true;
end fun;

fun _pUnixWriteErr(fd, e)
  var b = 0.toChar().x(4);
  _pWrite32(b, 0, e);
  _pState.write(fd, b.toNum(-1), 4);
  result = true;
end fun;

fun _pUnixArgv(name, args)
  var n = args.@count() + 1;
  var buf = 0.toChar().x((n + 1) * _pState.ptrBytes);
  _pWritePtr(buf, 0, name.toNum(-1));
  for i = 0 to args.@count() - 1 do
    _pWritePtr(buf, (i + 1) * _pState.ptrBytes, args[i].toNum(-1));
  end do;
  _pWritePtr(buf, n * _pState.ptrBytes, 0);
  result = buf;
end fun;

fun _pUnixStatus(status)
  result = new [exitCode: 0, signal: nil];
  if (status bit and 0x7f) = 0 then
    result.exitCode = ((status >> 8) bit and 0xff);
  else
    var sig = (status bit and 0x7f);
    result.exitCode = 0 - sig;
    result.signal = sig;
  end if;
end fun;

class _PUnix()
  var pid = 0;
  var inFd = -1;
  var outFd = -1;
  var errFd = -1;
  var inData = '';
  var inPos = 0;
  var outText = '';
  var errText = '';
  var outOpen = true;
  var errOpen = true;
  var exited = false;
  var status = 0;
  var timedOut = false;
  var waitErr = -1;
  var startMs = 0;
  var maxOut = 0;
  var outBytes = 0;
  var outputExceeded = false;

  fun appendCapped(s, isErr)
    if this.maxOut <= 0 then
      if isErr then this.errText &= s; else this.outText &= s; end if;
      return;
    end if;
    var n = _pByteData(s).length();
    if this.outBytes + n > this.maxOut then
      this.outputExceeded = true;
      return;
    end if;
    if isErr then this.errText &= s; else this.outText &= s; end if;
    this.outBytes += n;
  end fun;

  fun close()
    if this.inFd >= 0 then _pUnixClose(this.inFd); this.inFd = -1; end if;
    if this.outFd >= 0 then _pUnixClose(this.outFd); this.outFd = -1; end if;
    if this.errFd >= 0 then _pUnixClose(this.errFd); this.errFd = -1; end if;
    this.outOpen = false;
    this.errOpen = false;
  end fun;

  fun readChunk(fd)
    var read = _pState.read;
    var buf = 0.toChar().x(_P_CHUNK);
    loop
      var n = read(fd, buf.toNum(-1), _P_CHUNK);
      if n.type() = 0 then raise 'process: read failed'; end if;
      if n < 0 then
        var e = _pErrnoValue();
        if _pIsAgain(e) then return ''; end if;
        raise 'process: read failed (' & _pErrnoText(e) & ')';
      end if;
      if n = 0 then return nil; end if;
      result = _pBytesToString(buf, n);
      return;
    end loop;
  end fun;

  fun writeStdin()
    if this.inFd < 0 then return; end if;
    var write = _pState.write;
    while this.inPos < this.inData.length() do
      var part = _pByteData(this.inData.substr(this.inPos));
      var n = write(this.inFd, part.toNum(-1), part.length());
      if n.type() = 0 then raise 'process: write failed'; end if;
      if n < 0 then
        var e = _pErrnoValue();
        if _pIsAgain(e) then return; end if;
        if e = 32 then _pUnixClose(this.inFd); this.inFd = -1; return; end if;
        raise 'process: write failed (' & _pErrnoText(e) & ')';
      end if;
      if n = 0 then raise 'process: write failed'; end if;
      this.inPos += n;
    end do;
    _pUnixClose(this.inFd);
    this.inFd = -1;
  end fun;

  fun pollFds()
    var buf = 0.toChar().x(24);
    for i = 0 to 2 do _pWrite32(buf, i * 8, -1); _pWrite32(buf, i * 8 + 4, 0); end do;
    if this.outOpen and this.outFd >= 0 then
      _pWrite32(buf, 0, this.outFd);
      _pWrite32(buf, 4, _P_POLLIN);
    end if;
    if this.errOpen and this.errFd >= 0 then
      _pWrite32(buf, 8, this.errFd);
      _pWrite32(buf, 12, _P_POLLIN);
    end if;
    result = buf;
  end fun;

  fun revents(buf, i)
    result = (_pDwordAt(buf, i * 8 + 4) >> 16) bit and 0xffff;
  end fun;

  fun pump(timeout)
    this.startMs = _pUnixNow();
    var idle = 0;
    try
      loop
        this.writeStdin();

        var left = _P_POLL_MS;
        if timeout <> nil and timeout > 0 then
          var used = _pUnixNow() - this.startMs;
          left = timeout - used;
          if left < 0 then left = 0; end if;
          if left > _P_POLL_MS then left = _P_POLL_MS; end if;
        end if;

        var fds = this.pollFds();
        var n = _pState.poll(fds.toNum(-1), 3, left);
        if n < 0 then
          var pe = _pErrnoValue();
          if pe <> 4 then raise 'process: poll failed (' & _pErrnoText(pe) & ')'; end if;
        elsif n > 0 then
          if this.revents(fds, 0) <> 0 and this.outOpen then
            var s = this.readChunk(this.outFd);
            if s.type() = 0 then
              _pUnixClose(this.outFd); this.outFd = -1; this.outOpen = false;
            else
              this.appendCapped(s, false);
            end if;
          end if;
          if this.revents(fds, 1) <> 0 and this.errOpen then
            var s = this.readChunk(this.errFd);
            if s.type() = 0 then
              _pUnixClose(this.errFd); this.errFd = -1; this.errOpen = false;
            else
              this.appendCapped(s, true);
            end if;
          end if;
        end if;

        if this.outputExceeded and not this.exited then
          // The cap is a hard stop, not just a buffer limit: kill the child so
          // it cannot keep producing output while we drain.
          _pState.kill(this.pid, 9);
        end if;

        if not this.exited then
          var st = 0.toChar().x(4);
          var w = _pState.waitpid(this.pid, st.toNum(-1), 1);
          if w = this.pid then
            this.exited = true;
            this.status = _pDword(st);
          elsif w < 0 then
            var e = _pErrnoValue();
            if e <> 4 then this.waitErr = e; exit; end if;
          end if;
        end if;

        if timeout <> nil and timeout > 0 and not this.exited then
          if _pUnixNow() - this.startMs >= timeout then
            _pState.kill(this.pid, 9);
            this.timedOut = true;
            exit;
          end if;
        end if;

        if this.exited and not this.outOpen and not this.errOpen then exit; end if;
        if this.exited then
          idle += 1;
          if idle > 3 and n <= 0 then exit; end if;
        else
          idle = 0;
        end if;
      end loop;

      if this.waitErr >= 0 then
        raise 'process: wait failed (' & _pErrnoText(this.waitErr) & ')';
      end if;

      if this.timedOut then
        var st = 0.toChar().x(4);
        loop
          var w = _pState.waitpid(this.pid, st.toNum(-1), 0);
          if w = this.pid then this.status = _pDword(st); this.exited = true; exit; end if;
          var e = _pErrnoValue();
          if e <> 4 then this.waitErr = e; exit; end if;
        end loop;
        if this.waitErr >= 0 then
          raise 'process: wait failed (' & _pErrnoText(this.waitErr) & ')';
        end if;
        var grace = 0;
        while grace < 100 and (this.outOpen or this.errOpen) do
          if this.outOpen then
            var so = this.readChunk(this.outFd);
            if so.type() = 0 then _pUnixClose(this.outFd); this.outFd = -1; this.outOpen = false;
            else this.appendCapped(so, false); end if;
          end if;
          if this.errOpen then
            var se = this.readChunk(this.errFd);
            if se.type() = 0 then _pUnixClose(this.errFd); this.errFd = -1; this.errOpen = false;
            else this.appendCapped(se, true); end if;
          end if;
          grace += 1;
        end do;
      end if;
    finally
      if not this.exited and this.waitErr < 0 then
        _pState.kill(this.pid, 9);
        var st = 0.toChar().x(4);
        loop
          var w = _pState.waitpid(this.pid, st.toNum(-1), 0);
          if w = this.pid then exit; end if;
          var e = _pErrnoValue();
          if e <> 4 then exit; end if;
        end loop;
      end if;
      this.close();
    end try;
  end fun;

  fun result()
    var r = _pUnixStatus(this.status);
    result = new [
      ok: r.exitCode = 0 and not this.timedOut and not this.outputExceeded,
      exitCode: r.exitCode,
      signal: r.signal,
      timedOut: this.timedOut,
      outputExceeded: this.outputExceeded,
      stdout: this.outText,
      stderr: this.errText
    ];
  end fun;
end class;

fun _pUnixNow()
  var tv = 0.toChar().x(_pState.ptrBytes * 2);
  _pState.getTime(tv.toNum(-1), 0);
  result = _pPtrAt(tv, 0) * 1000 + _pPtrAt(tv, _pState.ptrBytes) div 1000;
end fun;

fun _pRunUnix(name, args, opts)
  var input = _pOpt(opts, 'stdin');
  if input = nil then input = ''; elsif input.type() <> 8 then raise 'process: stdin must be a string'; end if;
  var cwd = _pOpt(opts, 'cwd');
  if cwd <> nil and cwd.type() <> 8 then raise 'process: cwd must be a string'; end if;
  if cwd <> nil and cwd <> '' and cwd.subpos(0.toChar()) >= 0 then raise 'process: cwd must not contain NUL'; end if;
  var timeout = _pOpt(opts, 'timeout');
  if timeout = nil then timeout = 0; elsif timeout.type() <> 3 or timeout < 0 then raise 'process: timeout must be a non-negative integer'; end if;
  var output = _pOpt(opts, 'output');
  if output = nil then output = 0; elsif output.type() <> 3 or output < 0 then raise 'process: output must be a non-negative integer'; end if;

  var ps = _pUnixPipes();
  var pin = ps[0];
  var pout = ps[1];
  var perr = ps[2];
  var perr2 = ps[3];
  // Child ends must stay inheritable and may legitimately be fd 0/1/2;
  // only the parent ends and the exec-error pipe need CLOEXEC.
  _pUnixCloexec(pin[1]); _pUnixCloexec(pout[0]); _pUnixCloexec(perr[0]);
  _pUnixCloexec(perr2[0]); _pUnixCloexec(perr2[1]);
  var argv = _pUnixArgv(name, args);
  var pid = _pState.fork();
  if pid < 0 then
    var e = _pErrnoValue();
    _pUnixCloseAll([pin[0], pin[1], pout[0], pout[1], perr[0], perr[1], perr2[0], perr2[1]]);
    raise 'process: fork failed (' & _pErrnoText(e) & ')';
  end if;

  if pid = 0 then
    _pUnixClose(pin[1]); _pUnixClose(pout[0]); _pUnixClose(perr[0]); _pUnixClose(perr2[0]);
    var e = 0;
    if _pState.dup2(pin[0], 0) < 0 then e = _pErrnoValue(); _pUnixWriteErr(perr2[1], e); _pState.exitNow(127); end if;
    if _pState.dup2(pout[1], 1) < 0 then e = _pErrnoValue(); _pUnixWriteErr(perr2[1], e); _pState.exitNow(127); end if;
    if _pState.dup2(perr[1], 2) < 0 then e = _pErrnoValue(); _pUnixWriteErr(perr2[1], e); _pState.exitNow(127); end if;
    // Keep fds 0/1/2: a source fd may have been reused as a dup2 target.
    if pin[0] > 2 then _pUnixClose(pin[0]); end if;
    if pout[1] > 2 then _pUnixClose(pout[1]); end if;
    if perr[1] > 2 then _pUnixClose(perr[1]); end if;
    if cwd <> nil and cwd <> '' then
      if _pState.chdir(cwd) <> 0 then
        e = _pErrnoValue(); _pUnixWriteErr(perr2[1], e); _pState.exitNow(127);
      end if;
    end if;
    _pState.execvp(name, argv.toNum(-1));
    e = _pErrnoValue();
    _pUnixWriteErr(perr2[1], e);
    _pState.exitNow(127);
  end if;

  _pUnixClose(pin[0]); _pUnixClose(pout[1]); _pUnixClose(perr[1]); _pUnixClose(perr2[1]);
  var ebuf = 0.toChar().x(4);
  var en = -1;
  var start0 = _pUnixNow();
  var pfd = 0.toChar().x(8);
  _pWrite32(pfd, 0, perr2[0]);
  _pWrite32(pfd, 4, _P_POLLIN);
  loop
    var pt = -1;
    if timeout <> nil and timeout > 0 then
      pt = timeout - (_pUnixNow() - start0);
      if pt < 0 then pt = 0; end if;
    end if;
    var pr = _pState.poll(pfd.toNum(-1), 1, pt);
    if pr < 0 then
      var pe = _pErrnoValue();
      if pe = 4 then next; end if;
      _pState.kill(pid, 9);
      _pUnixClose(perr2[0]); _pUnixClose(pin[1]); _pUnixClose(pout[0]); _pUnixClose(perr[0]);
      var st0 = 0.toChar().x(4);
      _pState.waitpid(pid, st0.toNum(-1), 0);
      raise 'process: start failed (' & name & '): ' & _pErrnoText(pe);
    elsif pr = 0 then
      _pState.kill(pid, 9);
      var st1 = 0.toChar().x(4);
      _pState.waitpid(pid, st1.toNum(-1), 0);
      _pUnixClose(perr2[0]); _pUnixClose(pin[1]); _pUnixClose(pout[0]); _pUnixClose(perr[0]);
      raise 'process: start failed (' & name & '): timeout';
    end if;
    en = _pState.read(perr2[0], ebuf.toNum(-1), 4);
    if en >= 0 then exit; end if;
    var re = _pErrnoValue();
    if re = 4 or re = 11 or re = 35 then next; end if;
    _pState.kill(pid, 9);
    _pUnixClose(perr2[0]); _pUnixClose(pin[1]); _pUnixClose(pout[0]); _pUnixClose(perr[0]);
    var st2 = 0.toChar().x(4);
    _pState.waitpid(pid, st2.toNum(-1), 0);
    raise 'process: start failed (' & name & '): ' & _pErrnoText(re);
  end loop;
  _pUnixClose(perr2[0]);
  if en > 0 then
    var e = _pDword(ebuf);
    _pUnixClose(pin[1]); _pUnixClose(pout[0]); _pUnixClose(perr[0]);
    var st = 0.toChar().x(4);
    _pState.waitpid(pid, st.toNum(-1), 0);
    raise 'process: start failed (' & name & '): ' & _pErrnoText(e);
  end if;

  var oldSig = _pState.signal(13, 1);
  _pUnixNonblock(pin[1]); _pUnixNonblock(pout[0]); _pUnixNonblock(perr[0]);
  var p = _PUnix();
  p.pid = pid;
  p.inFd = pin[1];
  p.outFd = pout[0];
  p.errFd = perr[0];
  p.inData = input;
  p.maxOut = output;
  try
    p.pump(timeout);
    result = p.result();
  finally
    if oldSig >= 0 then _pState.signal(13, oldSig); end if;
  end try;
end fun;

fun _pWinErrText(e)
  result = 'error ' & e;
end fun;

fun _pWinSA()
  var n = 12;
  if _pState.ptrBytes = 8 then n = 24; end if;
  var b = 0.toChar().x(n);
  _pWrite32(b, 0, n);
  if _pState.ptrBytes = 8 then
    _pWrite32(b, 16, 1);
  else
    _pWrite32(b, 8, 1);
  end if;
  result = b;
end fun;

fun _pWinPipe()
  var sa = _pWinSA();
  var rb = 0.toChar().x(_pState.ptrBytes);
  var wb = 0.toChar().x(_pState.ptrBytes);
  var ok = _pState.createPipe(rb.toNum(-1), wb.toNum(-1), sa.toNum(-1), 0);
  if ok = 0 then
    raise 'process: create pipe failed (' & _pWinErrText(_pState.getLastError()) & ')';
  end if;
  var a = new [];
  a.@add(_pPtrAt(rb, 0));
  a.@add(_pPtrAt(wb, 0));
  result = a;
end fun;

fun _pWinClose(h)
  if h <> 0 and h <> -1 then _pState.closeHandle(h); end if;
  result = true;
end fun;

fun _pWinClosePair(pair)
  if pair <> nil then _pWinClose(pair[0]); _pWinClose(pair[1]); end if;
  result = true;
end fun;

fun _pWinPipes()
  var a = new [];
  try
    a.@add(_pWinPipe());
    a.@add(_pWinPipe());
  except
    for p in a do _pWinClosePair(p); end do;
    raise @;
  end try;
  result = a;
end fun;

fun _pWinNoInherit(h)
  if _pState.setHandleInfo(h, 1, 0) = 0 then
    raise 'process: set handle failed (' & _pWinErrText(_pState.getLastError()) & ')';
  end if;
  result = true;
end fun;

fun _pWinStartup(inH, outH, errH)
  var n = 68;
  if _pState.ptrBytes = 8 then n = 104; end if;
  var si = 0.toChar().x(n);
  _pWrite32(si, 0, n);
  var flagsAt = 44;
  var inAt = 56;
  var outAt = 60;
  var errAt = 64;
  if _pState.ptrBytes = 8 then
    flagsAt = 60;
    inAt = 80;
    outAt = 88;
    errAt = 96;
  end if;
  _pWrite32(si, flagsAt, 0x100);
  _pWritePtr(si, inAt, inH);
  _pWritePtr(si, outAt, outH);
  _pWritePtr(si, errAt, errH);
  result = si;
end fun;

fun _pWinProcInfo()
  var n = 16;
  if _pState.ptrBytes = 8 then n = 24; end if;
  result = 0.toChar().x(n);
end fun;

fun _pWinQuote(s)
  var need = false;
  if s = '' then need = true; end if;
  for i = 0 to s.length() - 1 do
    var c = s.substr(i, 1);
    if c = ' ' or c = 9.toChar() or c = '"' then need = true; end if;
  end do;
  if not need then result = s; return; end if;
  var out = '"';
  var bs = 0;
  for i = 0 to s.length() - 1 do
    var c = s.substr(i, 1);
    if c = 92.toChar() then
      bs += 1;
    elsif c = '"' then
      out &= 92.toChar().x(bs * 2 + 1) & c;
      bs = 0;
    else
      out &= 92.toChar().x(bs) & c;
      bs = 0;
    end if;
  end do;
  out &= 92.toChar().x(bs * 2) & '"';
  result = out;
end fun;

fun _pWinCmd(name, args)
  var c = _pWinQuote(name);
  for a in args do c &= ' ' & _pWinQuote(a); end do;
  result = c;
end fun;

// Windows anonymous pipes have no non-blocking write. Use a temporary file
// for stdin so large input cannot block the single-threaded pump.
fun _pWinStdinFile(input)
  var tp = 0.toChar().x(260);
  var n = _pState.getTempPath(260, tp.toNum(-1));
  if n = 0 or n >= 260 then
    raise 'process: temp path failed (' & _pWinErrText(_pState.getLastError()) & ')';
  end if;
  var fn = 0.toChar().x(260);
  var pfx = _pByteData('fun') & 0.toChar();
  if _pState.getTempName(tp.toNum(-1), pfx.toNum(-1), 0, fn.toNum(-1)) = 0 then
    raise 'process: temp file failed (' & _pWinErrText(_pState.getLastError()) & ')';
  end if;
  var sa = _pWinSA();
  var h = _pState.createFile(fn.toNum(-1), 0xC0010000, 7, sa.toNum(-1), 3, 0x04000100, 0);
  if h = nil or h < 0 or h = 0xffffffff then
    var ce = _pState.getLastError();
    _pState.deleteFile(fn.toNum(-1));
    raise 'process: create temp file failed (' & _pWinErrText(ce) & ')';
  end if;
  var writeFile = _pState.writeFile;
  var pos = 0;
  while pos < input.length() do
    var part = _pByteData(input.substr(pos));
    var got = 0.toChar().x(4);
    var ok = writeFile(h, part.toNum(-1), part.length(), got.toNum(-1), nil);
    if ok = 0 then
      _pWinClose(h);
      raise 'process: write stdin failed (' & _pWinErrText(_pState.getLastError()) & ')';
    end if;
    var k = _pDword(got);
    if k = 0 then _pWinClose(h); raise 'process: write stdin failed'; end if;
    pos += k;
  end do;
  var sp = _pState.setFilePointer(h, 0, 0, 0);
  if sp = -1 or sp = 0xffffffff then
    _pWinClose(h);
    raise 'process: seek stdin failed (' & _pWinErrText(_pState.getLastError()) & ')';
  end if;
  result = h;
end fun;

class _PWin()
  var hProcess = 0;
  var hThread = 0;
  var outH = 0;
  var errH = 0;
  var outText = '';
  var errText = '';
  var outOpen = true;
  var errOpen = true;
  var exited = false;
  var exitCode = 0;
  var timedOut = false;
  var startMs = 0;
  var maxOut = 0;
  var outBytes = 0;
  var outputExceeded = false;

  fun appendCapped(s, isErr)
    if this.maxOut <= 0 then
      if isErr then this.errText &= s; else this.outText &= s; end if;
      return;
    end if;
    var n = _pByteData(s).length();
    if this.outBytes + n > this.maxOut then
      this.outputExceeded = true;
      return;
    end if;
    if isErr then this.errText &= s; else this.outText &= s; end if;
    this.outBytes += n;
  end fun;

  fun close()
    if this.outH <> 0 then _pWinClose(this.outH); this.outH = 0; end if;
    if this.errH <> 0 then _pWinClose(this.errH); this.errH = 0; end if;
    if this.hProcess <> 0 then _pWinClose(this.hProcess); this.hProcess = 0; end if;
    this.outOpen = false;
    this.errOpen = false;
  end fun;

  fun readChunk(h)
    var avail = 0.toChar().x(4);
    var ok = _pState.peek(h, 0, 0, 0, avail.toNum(-1), 0);
    if ok = 0 then
      var e = _pState.getLastError();
      if e = 109 or e = 38 or e = 232 then return nil; end if;
      raise 'process: read failed (' & _pWinErrText(e) & ')';
    end if;
    var n = _pDword(avail);
    if n = 0 then return ''; end if;
    if n > _P_CHUNK then n = _P_CHUNK; end if;
    var buf = 0.toChar().x(n);
    var got = 0.toChar().x(4);
    var readFile = _pState.readFile;
    var ok2 = readFile(h, buf.toNum(-1), n, got.toNum(-1), nil);
    if ok2 = 0 then
      var e = _pState.getLastError();
      if e = 109 or e = 38 or e = 232 then return nil; end if;
      raise 'process: read failed (' & _pWinErrText(e) & ')';
    end if;
    var k = _pDword(got);
    if k = 0 then return nil; end if;
    result = _pBytesToString(buf, k);
  end fun;

  fun pump(timeout)
    this.startMs = _pState.getTick();
    var idle = 0;
    try
      loop
        var progress = false;
        if this.outOpen then
          var so = this.readChunk(this.outH);
          if so.type() = 0 then
            _pWinClose(this.outH); this.outH = 0; this.outOpen = false;
          elsif so <> '' then
            this.appendCapped(so, false);
            progress = true;
          end if;
        end if;
        if this.errOpen then
          var se = this.readChunk(this.errH);
          if se.type() = 0 then
            _pWinClose(this.errH); this.errH = 0; this.errOpen = false;
          elsif se <> '' then
            this.appendCapped(se, true);
            progress = true;
          end if;
        end if;

        if this.outputExceeded and not this.exited then
          _pState.terminate(this.hProcess, 1);
        end if;

        var w = _pState.waitSingle(this.hProcess, 0);
        if w = 0 then
          if not this.exited then
            var cb = 0.toChar().x(4);
            if _pState.getExitCode(this.hProcess, cb.toNum(-1)) = 0 then
              raise 'process: wait failed (' & _pWinErrText(_pState.getLastError()) & ')';
            end if;
            this.exitCode = _pDword(cb);
            this.exited = true;
          end if;
        elsif w <> 258 then
          raise 'process: wait failed (' & _pWinErrText(_pState.getLastError()) & ')';
        end if;

        if timeout <> nil and timeout > 0 and not this.exited then
          var elapsed = (_pState.getTick() - this.startMs) bit and 0xffffffff;
          if elapsed >= timeout then
            _pState.terminate(this.hProcess, 1);
            this.timedOut = true;
            exit;
          end if;
        end if;

        if this.exited and not this.outOpen and not this.errOpen then exit; end if;
        if this.exited then
          if progress then
            idle = 0;
          else
            idle += 1;
            if idle > 3 then exit; end if;
          end if;
        else
          idle = 0;
          if not progress then
            w = _pState.waitSingle(this.hProcess, 10);
            if w = 0 then
              var cb2 = 0.toChar().x(4);
              if _pState.getExitCode(this.hProcess, cb2.toNum(-1)) = 0 then
                raise 'process: wait failed (' & _pWinErrText(_pState.getLastError()) & ')';
              end if;
              this.exitCode = _pDword(cb2);
              this.exited = true;
            elsif w <> 258 then
              raise 'process: wait failed (' & _pWinErrText(_pState.getLastError()) & ')';
            end if;
          end if;
        end if;
      end loop;

      if this.timedOut then
        _pState.waitSingle(this.hProcess, 5000);
        var cb = 0.toChar().x(4);
        if _pState.getExitCode(this.hProcess, cb.toNum(-1)) = 0 then
          raise 'process: wait failed (' & _pWinErrText(_pState.getLastError()) & ')';
        end if;
        this.exitCode = _pDword(cb);
        this.exited = true;
        var grace = 0;
        while grace < 100 and (this.outOpen or this.errOpen) do
          if this.outOpen then
            var so = this.readChunk(this.outH);
            if so.type() = 0 then _pWinClose(this.outH); this.outH = 0; this.outOpen = false;
            else this.appendCapped(so, false); end if;
          end if;
          if this.errOpen then
            var se = this.readChunk(this.errH);
            if se.type() = 0 then _pWinClose(this.errH); this.errH = 0; this.errOpen = false;
            else this.appendCapped(se, true); end if;
          end if;
          grace += 1;
        end do;
      end if;
    finally
      if not this.exited then
        _pState.terminate(this.hProcess, 1);
        _pState.waitSingle(this.hProcess, 5000);
      end if;
      this.close();
    end try;
  end fun;

  fun result()
    result = new [
      ok: this.exitCode = 0 and not this.timedOut and not this.outputExceeded,
      exitCode: this.exitCode,
      signal: nil,
      timedOut: this.timedOut,
      outputExceeded: this.outputExceeded,
      stdout: this.outText,
      stderr: this.errText
    ];
  end fun;
end class;

fun _pRunWin(name, args, opts)
  var input = _pOpt(opts, 'stdin');
  if input = nil then input = ''; elsif input.type() <> 8 then raise 'process: stdin must be a string'; end if;
  var cwd = _pOpt(opts, 'cwd');
  if cwd <> nil and cwd.type() <> 8 then raise 'process: cwd must be a string'; end if;
  if cwd <> nil and cwd <> '' and cwd.subpos(0.toChar()) >= 0 then raise 'process: cwd must not contain NUL'; end if;
  var timeout = _pOpt(opts, 'timeout');
  if timeout = nil then timeout = 0; elsif timeout.type() <> 3 or timeout < 0 then raise 'process: timeout must be a non-negative integer'; end if;
  var output = _pOpt(opts, 'output');
  if output = nil then output = 0; elsif output.type() <> 3 or output < 0 then raise 'process: output must be a non-negative integer'; end if;

  var fin = _pWinStdinFile(input);
  var ps = nil;
  try
    ps = _pWinPipes();
  except
    _pWinClose(fin);
    raise @;
  end try;
  var pout = ps[0];
  var perr = ps[1];
  try
    _pWinNoInherit(pout[0]);
    _pWinNoInherit(perr[0]);
  except
    _pWinClose(fin);
    _pWinClosePair(pout);
    _pWinClosePair(perr);
    raise @;
  end try;

  var si = _pWinStartup(fin, pout[1], perr[1]);
  var pi = _pWinProcInfo();
  var cmd = _pWinCmd(name, args);
  var cd = 0;
  var cdbuf = '';
  if cwd <> nil and cwd <> '' then
    cdbuf = _pByteData(cwd) & 0.toChar();
    cd = cdbuf.toNum(-1);
  end if;
  var ok = _pState.createProcess(0, cmd, 0, 0, 1, 0, 0, cd, si.toNum(-1), pi.toNum(-1));
  if ok = 0 then
    var e = _pState.getLastError();
    _pWinClose(fin);
    _pWinClose(pout[0]); _pWinClose(pout[1]);
    _pWinClose(perr[0]); _pWinClose(perr[1]);
    raise 'process: start failed (' & name & '): ' & _pWinErrText(e);
  end if;

  var p = _PWin();
  p.hProcess = _pPtrAt(pi, 0);
  p.hThread = _pPtrAt(pi, _pState.ptrBytes);
  _pWinClose(p.hThread);
  p.hThread = 0;
  p.outH = pout[0];
  p.errH = perr[0];
  p.maxOut = output;
  _pWinClose(fin); _pWinClose(pout[1]); _pWinClose(perr[1]);
  p.pump(timeout);
  result = p.result();
end fun;

class _ProcessApi()
  fun run(name, args, opts)
    name = _pStr(name, 'name');
    if name = '' then raise 'process: name is required'; end if;
    args = _pArgs(args);
    _pCheckOpts(opts);
    _pBind();
    if _pState.isWindows then
      result = _pRunWin(name, args, opts);
    else
      result = _pRunUnix(name, args, opts);
    end if;
  end fun;
end class;

var process = _ProcessApi();
