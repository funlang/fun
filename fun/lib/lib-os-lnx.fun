// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-os-lnx: the Linux name of lib-os-unx.fun (kept so existing Linux scripts
// are unchanged). The real implementation lives in lib-os-unx.fun; this file
// only re-exports it. macOS callers should `use 'lib-os-unx.fun'` directly.

use 'lib-os-unx.fun';
