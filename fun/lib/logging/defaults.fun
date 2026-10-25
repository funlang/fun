// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// logging/defaults: the single source of the built-in logging configuration.
use 'formatter.fun';
use 'sink.fun';
use 'handler.fun';

fun _defaultFormatter()
  result = _TextFormatter([]);
end fun;

fun _defaultHandlers()
  result = new [];
  result.@add(_StreamHandler([
    sink: _ConsoleSink([stream: 'stderr'])
  ]));
end fun;

fun _defaultLogConfig()
  result = new [];
  result['level'] = 'info';
  result['formatter'] = _defaultFormatter();
  result['handlers'] = _defaultHandlers();
end fun;

fun _configWith(opts)
  var cfg = _defaultLogConfig();
  if opts <> nil then
    for k: v in opts do cfg[k] = v; end do;
  end if;
  if cfg['level'] = nil then cfg['level'] = 'info'; end if;
  if cfg['formatter'] = nil then cfg['formatter'] = _defaultFormatter(); end if;
  if cfg['handlers'] = nil then cfg['handlers'] = _defaultHandlers(); end if;
  result = cfg;
end fun;
