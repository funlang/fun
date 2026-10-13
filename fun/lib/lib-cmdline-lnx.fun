// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-cmdline-lnx: the Linux name of lib-cmdline-unx.fun (kept so existing
// Linux scripts are unchanged). The real implementation lives in
// lib-cmdline-unx.fun; this file only re-exports it. macOS callers should
// `use 'lib-cmdline-unx.fun'` directly.

use 'lib-cmdline-unx.fun';
