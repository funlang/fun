// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// logging/core: LogRecord, Logger and the global named-logger manager.
use 'levels.fun';
use 'defaults.fun';
use 'handler.fun';
use 'formatter.fun';

fun _logNow()
  result = 1.time();
end fun;

fun _logCloneFields(src)
  result = new [];
  if src <> nil then
    for k: v in src do result[k] = v; end do;
  end if;
end fun;

fun _logMergeFields(dst, src, prefix)
  if src = nil then return; end if;
  var p = prefix or '';
  for k: v in src do dst[p & k] = v; end do;
end fun;

class _LogRecord(tm, lv, nm, msg, flds)
  var time = tm;
  var level = lv;
  var levelName = _levelName(lv);
  var name = nm or '';
  var message = msg or '';
  var fields = flds;
  var source = nil;   // reserved for the runtime call site (v2)
  if fields = nil then fields = new []; end if;
end class;

class _Logger(mgr, nm, lvl, hdl, flds, grp)
  var manager = mgr;
  var name = nm or '';
  var level = lvl;
  var handler = hdl;
  var fields = flds;
  var group = grp or '';
  var filters = nil;
  if fields = nil then fields = new []; end if;

  fun enabled(lv)
    var n = _levelValue(lv);
    if n >= _LOG_OFF then result = false; return; end if;
    if manager <> nil then
      result = n >= manager.effectiveLevel(name);
    else
      var own = level;
      if own = nil then own = _LOG_INFO; end if;
      result = n >= own;
    end if;
  end fun;

  fun log(lv, msg, flds)
    var n = _levelValue(lv);
    if not this.enabled(n) then return; end if;
    var all = _logCloneFields(fields);
    _logMergeFields(all, flds, group);
    var rec = _LogRecord(_logNow(), n, name, '' & (msg or ''), all);
    if not _handlerPass(filters, rec) then return; end if;
    if manager <> nil then
      manager.emit(rec);
    elsif handler <> nil then
      try
        handler.handle(rec);
      except
      end try;
    end if;
  end fun;

  fun trace(msg, flds)
    this.log(_LOG_TRACE, msg, flds);
  end fun;

  fun debug(msg, flds)
    this.log(_LOG_DEBUG, msg, flds);
  end fun;

  fun info(msg, flds)
    this.log(_LOG_INFO, msg, flds);
  end fun;

  fun warning(msg, flds)
    this.log(_LOG_WARNING, msg, flds);
  end fun;

  fun warn(msg, flds)
    this.log(_LOG_WARNING, msg, flds);
  end fun;

  fun error(msg, flds)
    this.log(_LOG_ERROR, msg, flds);
  end fun;

  fun critical(msg, flds)
    this.log(_LOG_CRITICAL, msg, flds);
  end fun;

  fun fatal(msg, flds)
    this.log(_LOG_CRITICAL, msg, flds);
  end fun;

  fun with(flds)
    var f = _logCloneFields(fields);
    _logMergeFields(f, flds, group);
    var child = _Logger(manager, name, level, handler, f, group);
    child.filters = filters;
    result = child;
  end fun;

  fun withGroup(g)
    var prefix = group & g & '.';
    var child = _Logger(manager, name, level, handler, fields, prefix);
    child.filters = filters;
    result = child;
  end fun;
end class;

class _LogManager()
  var rootLevel = _LOG_INFO;
  var defaultFormatter = nil;
  var rootHandler = nil;
  var levels = new [];
  var filters = nil;
  var loggers = new [];
  var ready = false;

  fun apply(cfg)
    rootLevel = _levelValue(cfg['level']);
    defaultFormatter = cfg['formatter'];
    var hs = cfg['handlers'];
    if hs = nil then hs = new []; end if;
    _prepareHandlers(hs, defaultFormatter);
    rootHandler = _MultiHandler(hs);
    levels = cfg['levels'];
    if levels = nil then levels = new []; end if;
    filters = cfg['filters'];
    ready = true;
  end fun;

  fun init()
    if ready then return; end if;
    this.apply(_configWith(nil));
  end fun;

  fun config(opts)
    this.apply(_configWith(opts));
    result = this.getLogger('');
  end fun;

  fun getLogger(name)
    this.init();
    var key = name or '';
    var l = loggers[key];
    if l = nil then
      l = _Logger(this, key, nil, nil, new [], '');
      loggers[key] = l;
    end if;
    result = l;
  end fun;

  fun effectiveLevel(name)
    this.init();
    if name <> '' and levels.@has(name) then
      result = _levelValue(levels[name]);
    else
      result = rootLevel;
    end if;
  end fun;

  fun emit(rec)
    this.init();
    if not _handlerPass(filters, rec) then return; end if;
    if rootHandler <> nil then
      try
        rootHandler.handle(rec);
      except
      end try;
    end if;
  end fun;

  fun reset()
    rootLevel = _LOG_INFO;
    defaultFormatter = nil;
    rootHandler = nil;
    levels = new [];
    filters = nil;
    loggers = new [];
    ready = false;
  end fun;
end class;
