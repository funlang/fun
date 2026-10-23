// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// logging/handler: route a LogRecord to one or more sinks.
use 'levels.fun';
use 'formatter.fun';

fun _handlerPass(filters, rec)
  result = true;
  if filters = nil then return; end if;
  for i = 0 to filters.@count() - 1 do
    var f = filters[i];
    if f <> nil then
      var ok = false;
      try
        ok = f(rec);
      except
        ok = false;
      end try;
      if not ok then result = false; return; end if;
    end if;
  end do;
end fun;

fun _handlerFormat(formatter, rec)
  if formatter = nil then
    result = _TextFormatter([]).format(rec);
    return;
  end if;
  result = nil;
  try
    result = formatter.format(rec);   // formatter object
  except
  end try;
  if result = nil then
    try
      result = formatter(rec);        // formatter function
    except
      try
        result = _TextFormatter([]).format(rec);
      except
        result = '';
      end try;
    end try;
  end if;
end fun;

class _StreamHandler(opts)
  var sink = nil;
  var formatter = nil;
  var level = nil;
  var filters = nil;

  if opts <> nil then
    if opts.@has('sink') then sink = opts['sink']; end if;
    if opts.@has('formatter') then formatter = opts['formatter']; end if;
    if opts.@has('level') and opts['level'] <> nil then
      level = _levelValue(opts['level']);
    end if;
    if opts.@has('filters') then filters = opts['filters']; end if;
  end if;

  fun enabled(lv)
    if lv >= _LOG_OFF then result = false; return; end if;
    if level <> nil and lv < level then result = false; return; end if;
    result = true;
  end fun;

  fun handle(rec)
    if not this.enabled(rec.level) then return; end if;
    if not _handlerPass(filters, rec) then return; end if;
    if sink = nil then return; end if;
    try
      sink.write(_handlerFormat(formatter, rec));
    except
    end try;
  end fun;

  fun flush()
    try
      if sink <> nil then sink.flush(); end if;
    except
    end try;
  end fun;

  fun close()
    try
      if sink <> nil then sink.close(); end if;
    except
    end try;
  end fun;
end class;

class _MultiHandler(handlers)
  var handlers = handlers;
  if handlers = nil then handlers = new []; end if;

  fun enabled(lv)
    result = false;
    for i = 0 to handlers.@count() - 1 do
      if handlers[i].enabled(lv) then result = true; return; end if;
    end do;
  end fun;

  fun handle(rec)
    for i = 0 to handlers.@count() - 1 do
      var h = handlers[i];
      if h.enabled(rec.level) then
        try
          h.handle(rec);
        except
        end try;
      end if;
    end do;
  end fun;

  fun flush()
    for i = 0 to handlers.@count() - 1 do
      try
        handlers[i].flush();
      except
      end try;
    end do;
  end fun;

  fun close()
    for i = 0 to handlers.@count() - 1 do
      try
        handlers[i].close();
      except
      end try;
    end do;
  end fun;
end class;

class _MemoryHandler(opts)
  var records = new [];
  var filters = nil;
  if opts <> nil and opts.@has('filters') then filters = opts['filters']; end if;

  fun enabled(lv)
    result = true;
  end fun;

  fun handle(rec)
    if _handlerPass(filters, rec) then records.@add(rec); end if;
  end fun;

  fun clear()
    records = new [];
  end fun;

  fun flush()
  end fun;

  fun close()
  end fun;
end class;

class _NullHandler()
  fun enabled(lv)
    result = false;
  end fun;

  fun handle(rec)
  end fun;

  fun flush()
  end fun;

  fun close()
  end fun;
end class;

fun _prepareHandler(h, formatter)
  if h = nil then return; end if;
  if h.handlers <> nil then
    for i = 0 to h.handlers.@count() - 1 do
      _prepareHandler(h.handlers[i], formatter);
    end do;
  end if;
  if h.sink <> nil and h.formatter = nil then
    h.formatter = formatter;
  end if;
end fun;

fun _prepareHandlers(handlers, formatter)
  if handlers = nil then return; end if;
  for i = 0 to handlers.@count() - 1 do
    _prepareHandler(handlers[i], formatter);
  end do;
end fun;
