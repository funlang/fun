// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// env: process environment variables.
//
//     use 'env.fun';
//
//     env.get('HOME');              // nil when unset
//     env.get('PORT', '8080');      // default when unset
//     env.has('PORT');              // true even for an empty value
//     env.set('APP_MODE', 'dev');
//     env.unset('APP_MODE');
//
// Names are case-sensitive on POSIX and case-insensitive on Windows. Changes
// affect this process and its children. The core primitives live in lib-host;
// env only provides the public namespace and the default-value rule.
use 'lib-host.fun';

class _EnvApi()
  fun get(name, default)
    if HostEnvHas(name) then result = HostEnvGet(name); else result = default; end if;
  end fun;

  fun has(name)
    result = HostEnvHas(name);
  end fun;

  fun set(name, value)
    result = HostEnvSet(name, value);
  end fun;

  fun unset(name)
    result = HostEnvUnset(name);
  end fun;
end class;

var env = _EnvApi();
