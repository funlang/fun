// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// logging/defaults: the single source of the built-in logging configuration.
use 'formatter.fun';
use 'sink.fun';
use 'handler.fun';

fun _defaultFormatter(opts)
  result = _TextFormatter(opts);
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
    // sourcePath applies to the built-in formatter; a user formatter owns its
    // own options.
    if opts.@has('sourcePath') and opts['sourcePath'] <> nil and not opts.@has('formatter') then
      cfg['formatter'] = _defaultFormatter([sourcePath: opts['sourcePath']]);
    end if;
  end if;
  if cfg['level'] = nil then cfg['level'] = 'info'; end if;
  if cfg['formatter'] = nil then
    var fmtOpts = nil;
    if cfg['sourcePath'] <> nil then fmtOpts = [sourcePath: cfg['sourcePath']]; end if;
    cfg['formatter'] = _defaultFormatter(fmtOpts);
  end if;
  if cfg['handlers'] = nil then cfg['handlers'] = _defaultHandlers(); end if;
  result = cfg;
end fun;
