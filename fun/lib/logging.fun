// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// logging: default logger, named loggers, handlers and formatters.
//
//     use 'logging.fun';
//
//     logging.config([level: 'debug']);       // optional; defaults to stderr/info
//     var logger = logging.getLogger('http');
//     logger.info('request', [path: '/users']);
//
//     var reqLog = logger.with([requestId: id]);
//     reqLog.warning('slow', [ms: 1200]);
//
// Per-name levels: logging.config([levels: ['http': 'debug']]).
// Levels: logging.TRACE/DEBUG/INFO/WARNING/ERROR/CRITICAL/OFF.
// Without logging.config, output is stderr + info + text. The logging object is
// the only public entry; implementation files live under logging/.
use 'logging/core.fun';
use 'logging/handler.fun';
use 'logging/formatter.fun';
use 'logging/sink.fun';
use 'logging/defaults.fun';

class _LogApi()
  var manager = _LogManager();

  var TRACE    = _LOG_TRACE;
  var DEBUG    = _LOG_DEBUG;
  var INFO     = _LOG_INFO;
  var WARNING  = _LOG_WARNING;
  var ERROR    = _LOG_ERROR;
  var CRITICAL = _LOG_CRITICAL;
  var OFF      = _LOG_OFF;

  fun config(opts)
    result = manager.config(opts);
  end fun;

  fun getLogger(name)
    result = manager.getLogger(name);
  end fun;

  fun newLogger(opts)
    var cfg = _configWith(opts);
    var hs = cfg['handlers'];
    var fmt = cfg['formatter'];
    _prepareHandlers(hs, fmt);
    var nm = '';
    var flds = new [];
    if opts <> nil then
      if opts.@has('name') then nm = opts['name']; end if;
      if opts.@has('fields') then flds = _logCloneFields(opts['fields']); end if;
    end if;
    var l = _Logger(nil, nm, _levelValue(cfg['level']), _MultiHandler(hs), flds, '');
    l.filters = cfg['filters'];
    result = l;
  end fun;

  fun reset()
    manager.reset();
  end fun;

  fun ConsoleHandler(opts)
    var o = opts or new [];
    var so = new [];
    if o.@has('stream') then so['stream'] = o['stream']; end if;
    var h = new [];
    h['sink'] = _ConsoleSink(so);
    if o.@has('formatter') then h['formatter'] = o['formatter']; end if;
    if o.@has('level') then h['level'] = o['level']; end if;
    if o.@has('filters') then h['filters'] = o['filters']; end if;
    result = _StreamHandler(h);
  end fun;

  fun StreamHandler(opts)
    var o = opts or new [];
    var h = new [];
    if o.@has('sink') then h['sink'] = o['sink']; end if;
    if o.@has('formatter') then h['formatter'] = o['formatter']; end if;
    if o.@has('level') then h['level'] = o['level']; end if;
    if o.@has('filters') then h['filters'] = o['filters']; end if;
    result = _StreamHandler(h);
  end fun;

  fun FileHandler(opts)
    var o = opts or new [];
    var so = new [];
    if o.@has('path') then so['path'] = o['path']; end if;
    if o.@has('append') then so['append'] = o['append']; end if;
    var h = new [];
    h['sink'] = _FileSink(so);
    if o.@has('formatter') then h['formatter'] = o['formatter']; end if;
    if o.@has('level') then h['level'] = o['level']; end if;
    if o.@has('filters') then h['filters'] = o['filters']; end if;
    result = _StreamHandler(h);
  end fun;

  fun RotatingFileHandler(opts)
    var o = opts or new [];
    var so = new [];
    if o.@has('path') then so['path'] = o['path']; end if;
    if o.@has('maxSize') then so['maxSize'] = o['maxSize']; end if;
    if o.@has('backups') then so['backups'] = o['backups']; end if;
    if o.@has('append') then so['append'] = o['append']; end if;
    var h = new [];
    h['sink'] = _RotatingFileSink(so);
    if o.@has('formatter') then h['formatter'] = o['formatter']; end if;
    if o.@has('level') then h['level'] = o['level']; end if;
    if o.@has('filters') then h['filters'] = o['filters']; end if;
    result = _StreamHandler(h);
  end fun;

  fun MultiHandler(handlers)
    result = _MultiHandler(handlers);
  end fun;

  fun MemoryHandler(opts)
    result = _MemoryHandler(opts);
  end fun;

  fun NullHandler()
    result = _NullHandler();
  end fun;

  fun TextFormatter(opts)
    result = _TextFormatter(opts);
  end fun;

  fun JsonFormatter(opts)
    result = _JsonFormatter(opts);
  end fun;
end class;

var logging = _LogApi();
