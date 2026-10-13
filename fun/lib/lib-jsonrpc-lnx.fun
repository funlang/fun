// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-jsonrpc-lnx: the Linux name of lib-jsonrpc-unx.fun (kept so existing
// Linux scripts are unchanged). The real implementation lives in
// lib-jsonrpc-unx.fun; this file only re-exports it. macOS callers should
// `use 'lib-jsonrpc-unx.fun'`.

use 'lib-jsonrpc-unx.fun';
