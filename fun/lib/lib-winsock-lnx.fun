// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-winsock-lnx: the Linux name of lib-winsock-unx.fun (kept so existing
// Linux scripts are unchanged). The real implementation lives in
// lib-winsock-unx.fun; this file only re-exports it. macOS callers should
// `use 'lib-winsock-unx.fun'`.

use 'lib-winsock-unx.fun';
