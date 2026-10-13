// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-unicode-lnx: the Linux name of lib-unicode-unx.fun (kept so existing
// Linux scripts are unchanged). The real implementation lives in
// lib-unicode-unx.fun; this file only re-exports it. macOS callers should
// `use 'lib-unicode-unx.fun'` directly.

use 'lib-unicode-unx.fun';
