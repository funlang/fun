// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// fun-jsbox: one-shot, JSON-only JavaScript sandbox worker.
//
// Protocol (stdin -> stdout):
//
//   {"protocol":1,"op":"eval","code":"...","input":<json>,
//    "limits":{"timeout_ms":200,"memory_bytes":4194304,"output_bytes":262144},
//    "seed":1,"now_ms":0}
//
// The worker evaluates `code` as the body of
//
//   (function(input){"use strict"; ... })
//
// and writes exactly one JSON object to stdout. Diagnostics never go to
// stdout. A non-eval request is rejected. The parent (Fun) is expected to
// enforce its own timeout and to treat the worker as untrusted.
//
// This file intentionally does not link quickjs-libc: no console, no module
// loader, no file/process APIs. The only host capability is `input`, and the
// only result channel is `return`.

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <ctype.h>
#include <errno.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifndef _WIN32
#include <sys/resource.h>
#include <sys/time.h>
#include <unistd.h>
#endif

#include "quickjs.h"

#define JSBOX_PROTOCOL 1

#define JSBOX_STR2(x) #x
#define JSBOX_STR(x) JSBOX_STR2(x)
#define JSBOX_ENGINE_VERSION \
    JSBOX_STR(QJS_VERSION_MAJOR) "." JSBOX_STR(QJS_VERSION_MINOR) "." JSBOX_STR(QJS_VERSION_PATCH)

#define DEFAULT_TIMEOUT_MS 200
#define DEFAULT_MEMORY_BYTES ((int64_t)4 * 1024 * 1024)
#define DEFAULT_OUTPUT_BYTES ((int64_t)256 * 1024)

#define HARD_INPUT_BYTES ((int64_t)16 * 1024 * 1024)
#define HARD_TIMEOUT_MS ((int64_t)10000)
#define HARD_MEMORY_BYTES ((int64_t)64 * 1024 * 1024)
#define HARD_OUTPUT_BYTES ((int64_t)4 * 1024 * 1024)

#define HOST_MEMORY_BYTES ((size_t)64 * 1024 * 1024)
#define HOST_STACK_BYTES ((size_t)2 * 1024 * 1024)

typedef struct {
    char *data;
    size_t len;
    size_t cap;
} Buf;

typedef struct {
    char kind[24];
    char name[64];
    char *message;
    char *stack;
    int line;
    int column;
    int retryable;
} Err;

typedef struct {
    int64_t deadline_ms;
    int timed_out;
} Deadline;

typedef struct {
    char *code;
    size_t code_len;
    char *input;
    size_t input_len;
    int64_t timeout_ms;
    int64_t memory_bytes;
    int64_t output_bytes;
    uint32_t seed;
    int64_t now_ms;
} Request;

static int64_t now_ms(void)
{
#ifdef _WIN32
    return (int64_t)clock() * 1000 / CLOCKS_PER_SEC;
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
#endif
}

static void *xmalloc(size_t n)
{
    void *p = malloc(n ? n : 1);
    if (!p) {
        fputs("fun-jsbox: out of memory\n", stderr);
        exit(2);
    }
    return p;
}

static void *xrealloc(void *p, size_t n)
{
    void *q = realloc(p, n ? n : 1);
    if (!q) {
        fputs("fun-jsbox: out of memory\n", stderr);
        exit(2);
    }
    return q;
}

static char *xstrndup(const char *s, size_t n)
{
    char *p = xmalloc(n + 1);
    memcpy(p, s, n);
    p[n] = '\0';
    return p;
}

static void buf_reserve(Buf *b, size_t extra)
{
    size_t need = b->len + extra + 1;
    if (need <= b->cap)
        return;
    size_t cap = b->cap ? b->cap : 256;
    while (cap < need)
        cap *= 2;
    b->data = xrealloc(b->data, cap);
    b->cap = cap;
}

static void buf_append(Buf *b, const char *s, size_t n)
{
    buf_reserve(b, n);
    memcpy(b->data + b->len, s, n);
    b->len += n;
    b->data[b->len] = '\0';
}

static void buf_puts(Buf *b, const char *s)
{
    buf_append(b, s, strlen(s));
}

static void buf_putc(Buf *b, char c)
{
    buf_reserve(b, 1);
    b->data[b->len++] = c;
    b->data[b->len] = '\0';
}

static void buf_printf(Buf *b, const char *fmt, ...)
{
    char tmp[512];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(tmp, sizeof(tmp), fmt, ap);
    va_end(ap);
    if (n < 0)
        return;
    if ((size_t)n >= sizeof(tmp))
        n = (int)sizeof(tmp) - 1;
    buf_append(b, tmp, (size_t)n);
}

static void buf_json_string(Buf *b, const char *s, size_t n)
{
    static const char hex[] = "0123456789abcdef";
    buf_putc(b, '"');
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)s[i];
        switch (c) {
        case '"':  buf_puts(b, "\\\""); break;
        case '\\': buf_puts(b, "\\\\"); break;
        case '\b': buf_puts(b, "\\b"); break;
        case '\f': buf_puts(b, "\\f"); break;
        case '\n': buf_puts(b, "\\n"); break;
        case '\r': buf_puts(b, "\\r"); break;
        case '\t': buf_puts(b, "\\t"); break;
        default:
            if (c < 0x20) {
                char esc[7] = {'\\', 'u', '0', '0', hex[c >> 4], hex[c & 15], 0};
                buf_puts(b, esc);
            } else {
                buf_putc(b, (char)c);
            }
            break;
        }
    }
    buf_putc(b, '"');
}

static void buf_free(Buf *b)
{
    free(b->data);
    b->data = NULL;
    b->len = b->cap = 0;
}

static void cap_utf8(char **ps, size_t cap)
{
    char *s = *ps;
    size_t n = strlen(s);
    if (n <= cap)
        return;
    size_t k = cap;
    while (k > 0 && ((unsigned char)s[k] & 0xc0) == 0x80)
        k--;
    char *t = xmalloc(k + 4);
    memcpy(t, s, k);
    memcpy(t + k, "...", 3);
    t[k + 3] = '\0';
    free(s);
    *ps = t;
}

static char *shift_stack_lines(const char *s)
{
    if (!s)
        return NULL;
    const char *m = strstr(s, "<jsbox>:");
    if (!m)
        return xstrndup(s, strlen(s));

    Buf b = {0};
    const char *p = s;
    while ((m = strstr(p, "<jsbox>:")) != NULL) {
        size_t prefix = (size_t)(m - p) + strlen("<jsbox>:");
        buf_append(&b, p, prefix);
        p += prefix;
        if (isdigit((unsigned char)*p)) {
            char *end = NULL;
            long l = strtol(p, &end, 10);
            if (l > 1)
                l--;
            buf_printf(&b, "%ld", l);
            p = end;
        }
    }
    buf_puts(&b, p);
    return b.data;
}

static void err_free(Err *e)
{
    free(e->message);
    free(e->stack);
    memset(e, 0, sizeof(*e));
}

static void err_set(Err *e, const char *kind, const char *name,
                    const char *message, int retryable)
{
    snprintf(e->kind, sizeof(e->kind), "%s", kind ? kind : "internal");
    snprintf(e->name, sizeof(e->name), "%s", name ? name : "Error");
    free(e->message);
    e->message = xstrndup(message ? message : "", strlen(message ? message : ""));
    e->retryable = retryable;
}

static char *js_to_cstring(JSContext *ctx, JSValue v, size_t *out_len)
{
    size_t n = 0;
    const char *s = JS_ToCStringLen(ctx, &n, v);
    if (!s)
        return NULL;
    char *p = xstrndup(s, n);
    JS_FreeCString(ctx, s);
    if (out_len)
        *out_len = n;
    return p;
}

static void parse_pos(const char *stack, int *line, int *column)
{
    *line = 0;
    *column = 0;
    if (!stack)
        return;
    const char *mark = strstr(stack, "<jsbox>:");
    if (mark) {
        const char *p = mark + strlen("<jsbox>:");
        if (isdigit((unsigned char)*p)) {
            char *end = NULL;
            long l = strtol(p, &end, 10);
            if (*end == ':' && isdigit((unsigned char)end[1])) {
                char *end2 = NULL;
                long c = strtol(end + 1, &end2, 10);
                *line = (int)l;
                *column = (int)c;
                return;
            }
        }
    }
    const char *p = stack;
    for (; *p; p++) {
        if (*p != ':' || !isdigit((unsigned char)p[1]))
            continue;
        char *end = NULL;
        long l = strtol(p + 1, &end, 10);
        if (*end != ':' || !isdigit((unsigned char)end[1]))
            continue;
        char *end2 = NULL;
        long c = strtol(end + 1, &end2, 10);
        if (l > 0) {
            *line = (int)l;
            *column = (int)c;
            return;
        }
    }
}

static void capture_exception(JSContext *ctx, int phase, Deadline *dl, Err *e)
{
    JSValue exc = JS_GetException(ctx);
    char name[64] = "Error";
    char *message = NULL;
    char *stack = NULL;

    JSValue jname = JS_GetPropertyStr(ctx, exc, "name");
    if (JS_IsException(jname)) {
        JS_FreeValue(ctx, JS_GetException(ctx));
    } else if (JS_IsString(jname)) {
        size_t n = 0;
        const char *s = JS_ToCStringLen(ctx, &n, jname);
        if (s) {
            size_t k = n < sizeof(name) - 1 ? n : sizeof(name) - 1;
            memcpy(name, s, k);
            name[k] = '\0';
            JS_FreeCString(ctx, s);
        }
    }
    JS_FreeValue(ctx, jname);

    JSValue jmsg = JS_GetPropertyStr(ctx, exc, "message");
    if (JS_IsException(jmsg)) {
        JS_FreeValue(ctx, JS_GetException(ctx));
    } else if (JS_IsString(jmsg)) {
        message = js_to_cstring(ctx, jmsg, NULL);
    }
    JS_FreeValue(ctx, jmsg);
    if (!message)
        message = js_to_cstring(ctx, exc, NULL);
    if (!message)
        message = xstrndup("", 0);
    cap_utf8(&message, 4096);

    JSValue jstack = JS_GetPropertyStr(ctx, exc, "stack");
    if (JS_IsException(jstack)) {
        JS_FreeValue(ctx, JS_GetException(ctx));
    } else if (JS_IsString(jstack)) {
        stack = js_to_cstring(ctx, jstack, NULL);
    }
    JS_FreeValue(ctx, jstack);
    if (stack) {
        cap_utf8(&stack, 8192);
        char *shifted = shift_stack_lines(stack);
        free(stack);
        stack = shifted;
    }

    const char *kind = "runtime";
    int retryable = 1;
    if (dl && dl->timed_out) {
        kind = "timeout";
    } else if (strstr(message, "out of memory") || strstr(message, "Out of memory")) {
        kind = "oom";
    } else if (phase == 1) {
        kind = "syntax";
    }

    snprintf(e->kind, sizeof(e->kind), "%s", kind);
    snprintf(e->name, sizeof(e->name), "%s", name);
    e->message = message;
    e->stack = stack;
    e->retryable = retryable;
    parse_pos(stack, &e->line, &e->column);

    JS_FreeValue(ctx, exc);
}

static int64_t clamp_i64(int64_t v, int64_t lo, int64_t hi)
{
    if (v < lo)
        return lo;
    if (v > hi)
        return hi;
    return v;
}

static int64_t get_int_prop(JSContext *ctx, JSValue obj, const char *name, int64_t def)
{
    if (JS_IsException(obj)) {
        JS_FreeValue(ctx, JS_GetException(ctx));
        return def;
    }
    JSValue v = JS_GetPropertyStr(ctx, obj, name);
    int64_t out = def;
    if (JS_IsException(v)) {
        JS_FreeValue(ctx, JS_GetException(ctx));
        return def;
    }
    if (!JS_IsUndefined(v) && !JS_IsNull(v)) {
        if (JS_ToInt64Ext(ctx, &out, v) != 0) {
            JS_FreeValue(ctx, JS_GetException(ctx));
            out = def;
        }
    }
    JS_FreeValue(ctx, v);
    return out;
}

static char *read_stdin(size_t *out_len, int *too_large)
{
    size_t cap = 65536;
    size_t len = 0;
    char *p = xmalloc(cap + 1);

    for (;;) {
        if (len == cap) {
            if ((int64_t)cap >= HARD_INPUT_BYTES) {
                *too_large = 1;
                char tmp[65536];
                while (fread(tmp, 1, sizeof(tmp), stdin) > 0) {
                }
                free(p);
                return NULL;
            }
            size_t ncap = cap * 2;
            if ((int64_t)ncap > HARD_INPUT_BYTES + 1)
                ncap = (size_t)HARD_INPUT_BYTES + 1;
            p = xrealloc(p, ncap + 1);
            cap = ncap;
        }
        size_t n = fread(p + len, 1, cap - len, stdin);
        if (n == 0)
            break;
        len += n;
    }
    p[len] = '\0';
    *out_len = len;
    return p;
}

static int parse_request(const char *json, size_t len, Request *r, Err *e)
{
    JSRuntime *rt = JS_NewRuntime();
    if (!rt) {
        err_set(e, "internal", "InternalError", "cannot create QuickJS runtime", 0);
        return 0;
    }
    JS_SetMemoryLimit(rt, HOST_MEMORY_BYTES);
    JS_SetMaxStackSize(rt, HOST_STACK_BYTES);
    JSContext *ctx = JS_NewContext(rt);
    if (!ctx) {
        JS_FreeRuntime(rt);
        err_set(e, "internal", "InternalError", "cannot create QuickJS context", 0);
        return 0;
    }

    int ok = 0;
    JSValue req = JS_UNDEFINED;
    JSValue jproto = JS_UNDEFINED;
    JSValue jop = JS_UNDEFINED;
    JSValue jcode = JS_UNDEFINED;
    JSValue jinput = JS_UNDEFINED;
    JSValue jstr = JS_UNDEFINED;
    JSValue jlim = JS_UNDEFINED;

    req = JS_ParseJSON(ctx, json, len, "<request>");
    if (JS_IsException(req)) {
        capture_exception(ctx, 0, NULL, e);
        snprintf(e->kind, sizeof(e->kind), "protocol");
        e->retryable = 0;
        goto done;
    }

    jproto = JS_GetPropertyStr(ctx, req, "protocol");
    if (JS_IsException(jproto)) {
        JS_FreeValue(ctx, JS_GetException(ctx));
        err_set(e, "protocol", "ProtocolError", "cannot read protocol", 0);
        goto done;
    }
    if (!JS_IsUndefined(jproto) && !JS_IsNull(jproto)) {
        int64_t proto = -1;
        int conv = JS_ToInt64Ext(ctx, &proto, jproto);
        if (conv != 0)
            JS_FreeValue(ctx, JS_GetException(ctx));
        if (conv != 0 || proto != JSBOX_PROTOCOL) {
            err_set(e, "protocol", "ProtocolError", "unsupported protocol version", 0);
            goto done;
        }
    }

    jop = JS_GetPropertyStr(ctx, req, "op");
    if (JS_IsException(jop)) {
        JS_FreeValue(ctx, JS_GetException(ctx));
        err_set(e, "protocol", "ProtocolError", "cannot read op", 0);
        goto done;
    }
    if (!JS_IsUndefined(jop) && !JS_IsNull(jop)) {
        char *op = js_to_cstring(ctx, jop, NULL);
        int is_eval = op && strcmp(op, "eval") == 0;
        free(op);
        if (!is_eval) {
            if (JS_HasException(ctx))
                JS_FreeValue(ctx, JS_GetException(ctx));
            err_set(e, "protocol", "ProtocolError", "unsupported op", 0);
            goto done;
        }
    }

    jcode = JS_GetPropertyStr(ctx, req, "code");
    if (JS_IsException(jcode)) {
        JS_FreeValue(ctx, JS_GetException(ctx));
        err_set(e, "protocol", "ProtocolError", "cannot read code", 0);
        goto done;
    }
    if (!JS_IsString(jcode)) {
        err_set(e, "protocol", "ProtocolError", "missing string field: code", 0);
        goto done;
    }
    r->code = js_to_cstring(ctx, jcode, &r->code_len);
    if (!r->code) {
        if (JS_HasException(ctx))
            JS_FreeValue(ctx, JS_GetException(ctx));
        err_set(e, "protocol", "ProtocolError", "code is not valid UTF-8", 0);
        goto done;
    }

    jinput = JS_GetPropertyStr(ctx, req, "input");
    if (JS_IsException(jinput)) {
        JS_FreeValue(ctx, JS_GetException(ctx));
        err_set(e, "protocol", "ProtocolError", "cannot read input", 0);
        goto done;
    }
    if (JS_IsUndefined(jinput) || JS_IsNull(jinput)) {
        r->input = xstrndup("null", 4);
        r->input_len = 4;
    } else {
        jstr = JS_JSONStringify(ctx, jinput, JS_UNDEFINED, JS_UNDEFINED);
        if (JS_IsException(jstr) || JS_IsUndefined(jstr)) {
            if (JS_IsException(jstr))
                JS_FreeValue(ctx, JS_GetException(ctx));
            err_set(e, "protocol", "ProtocolError", "input is not JSON-serializable", 0);
            goto done;
        }
        r->input = js_to_cstring(ctx, jstr, &r->input_len);
        if (!r->input) {
            if (JS_HasException(ctx))
                JS_FreeValue(ctx, JS_GetException(ctx));
            err_set(e, "protocol", "ProtocolError", "input is not valid UTF-8", 0);
            goto done;
        }
    }

    jlim = JS_GetPropertyStr(ctx, req, "limits");
    if (JS_IsException(jlim)) {
        JS_FreeValue(ctx, JS_GetException(ctx));
        jlim = JS_UNDEFINED;
    }
    r->timeout_ms = clamp_i64(get_int_prop(ctx, jlim, "timeout_ms", DEFAULT_TIMEOUT_MS),
                              1, HARD_TIMEOUT_MS);
    r->memory_bytes = clamp_i64(get_int_prop(ctx, jlim, "memory_bytes", DEFAULT_MEMORY_BYTES),
                                256 * 1024, HARD_MEMORY_BYTES);
    r->output_bytes = clamp_i64(get_int_prop(ctx, jlim, "output_bytes", DEFAULT_OUTPUT_BYTES),
                                1024, HARD_OUTPUT_BYTES);

    r->seed = (uint32_t)get_int_prop(ctx, req, "seed", 1);
    r->now_ms = get_int_prop(ctx, req, "now_ms", 0);

    ok = 1;

done:
    JS_FreeValue(ctx, jlim);
    JS_FreeValue(ctx, jstr);
    JS_FreeValue(ctx, jinput);
    JS_FreeValue(ctx, jcode);
    JS_FreeValue(ctx, jop);
    JS_FreeValue(ctx, jproto);
    JS_FreeValue(ctx, req);
    if (!ok) {
        free(r->code);
        r->code = NULL;
        r->code_len = 0;
        free(r->input);
        r->input = NULL;
        r->input_len = 0;
    }
    JS_FreeContext(ctx);
    JS_FreeRuntime(rt);
    return ok;
}

static void apply_rlimits(int64_t memory_bytes, int64_t timeout_ms, int64_t output_bytes)
{
#ifndef _WIN32
    struct rlimit rl;
    rl.rlim_cur = rl.rlim_max = (rlim_t)(memory_bytes + (int64_t)128 * 1024 * 1024);
    setrlimit(RLIMIT_AS, &rl);
    rl.rlim_cur = rl.rlim_max = (rlim_t)((timeout_ms + 999) / 1000 + 2);
    setrlimit(RLIMIT_CPU, &rl);
    rl.rlim_cur = rl.rlim_max = (rlim_t)(output_bytes + (int64_t)1024 * 1024);
    setrlimit(RLIMIT_FSIZE, &rl);
    rl.rlim_cur = rl.rlim_max = 0;
    setrlimit(RLIMIT_CORE, &rl);
    rl.rlim_cur = rl.rlim_max = 16;
    setrlimit(RLIMIT_NOFILE, &rl);
#ifdef RLIMIT_NPROC
    rl.rlim_cur = rl.rlim_max = 0;
    setrlimit(RLIMIT_NPROC, &rl);
#endif
#else
    (void)memory_bytes;
    (void)timeout_ms;
    (void)output_bytes;
#endif
}

static int on_interrupt(JSContext *ctx, void *opaque)
{
    (void)ctx;
    Deadline *dl = (Deadline *)opaque;
    if (now_ms() >= dl->deadline_ms) {
        dl->timed_out = 1;
        return 1;
    }
    return 0;
}

static void emit_response(const char *value, size_t value_len, const Err *e,
                          int64_t wall_ms, const Request *r)
{
    Buf b = {0};
    buf_puts(&b, "{\"protocol\":");
    buf_printf(&b, "%d", JSBOX_PROTOCOL);
    buf_puts(&b, ",\"engine\":\"quickjs-ng\",\"engine_version\":\"");
    buf_puts(&b, JSBOX_ENGINE_VERSION);
    buf_puts(&b, "\"");
    buf_puts(&b, ",\"ok\":");
    buf_puts(&b, e ? "false" : "true");
    buf_puts(&b, ",\"value\":");
    if (e)
        buf_puts(&b, "null");
    else if (value)
        buf_append(&b, value, value_len);
    else
        buf_puts(&b, "null");
    buf_puts(&b, ",\"error\":");
    if (!e) {
        buf_puts(&b, "null");
    } else {
        buf_puts(&b, "{\"kind\":");
        buf_json_string(&b, e->kind, strlen(e->kind));
        buf_puts(&b, ",\"name\":");
        buf_json_string(&b, e->name, strlen(e->name));
        buf_puts(&b, ",\"message\":");
        buf_json_string(&b, e->message ? e->message : "", e->message ? strlen(e->message) : 0);
        buf_puts(&b, ",\"line\":");
        buf_printf(&b, "%d", e->line);
        buf_puts(&b, ",\"column\":");
        buf_printf(&b, "%d", e->column);
        buf_puts(&b, ",\"stack\":");
        buf_json_string(&b, e->stack ? e->stack : "", e->stack ? strlen(e->stack) : 0);
        buf_puts(&b, ",\"retryable\":");
        buf_puts(&b, e->retryable ? "true" : "false");
        buf_putc(&b, '}');
    }
    buf_puts(&b, ",\"usage\":{\"wall_ms\":");
    buf_printf(&b, "%lld", (long long)wall_ms);
    buf_puts(&b, ",\"timeout_ms\":");
    buf_printf(&b, "%lld", (long long)(r ? r->timeout_ms : 0));
    buf_puts(&b, ",\"memory_bytes\":");
    buf_printf(&b, "%lld", (long long)(r ? r->memory_bytes : 0));
    buf_puts(&b, ",\"output_bytes\":");
    buf_printf(&b, "%lld", (long long)(r ? r->output_bytes : 0));
    buf_puts(&b, "}}\n");

    fwrite(b.data, 1, b.len, stdout);
    fflush(stdout);
    buf_free(&b);
}

static void emit_early_error(const char *kind, const char *message, int retryable,
                             int64_t start_ms)
{
    Err e;
    memset(&e, 0, sizeof(e));
    err_set(&e, kind, "ProtocolError", message, retryable);
    emit_response(NULL, 0, &e, now_ms() - start_ms, NULL);
    err_free(&e);
}

int main(void)
{
    int64_t start_ms = now_ms();
    size_t input_len = 0;
    int too_large = 0;
    char *input = read_stdin(&input_len, &too_large);

    if (!input) {
        if (too_large)
            emit_early_error("input_limit", "request is too large", 1, start_ms);
        else
            emit_early_error("input_limit", "cannot read request", 1, start_ms);
        return 0;
    }
    if (input_len == 0) {
        free(input);
        emit_early_error("protocol", "empty request", 0, start_ms);
        return 0;
    }

    Request req;
    memset(&req, 0, sizeof(req));
    Err e;
    memset(&e, 0, sizeof(e));
    if (!parse_request(input, input_len, &req, &e)) {
        free(input);
        emit_response(NULL, 0, &e, now_ms() - start_ms, NULL);
        err_free(&e);
        return 0;
    }
    free(input);

    apply_rlimits(req.memory_bytes, req.timeout_ms, req.output_bytes);

    JSRuntime *rt = JS_NewRuntime();
    if (!rt) {
        err_set(&e, "internal", "InternalError", "cannot create sandbox runtime", 0);
        goto done;
    }
    JS_SetMemoryLimit(rt, (size_t)req.memory_bytes);
    JS_SetMaxStackSize(rt, (size_t)clamp_i64(req.memory_bytes / 2, 256 * 1024, 2 * 1024 * 1024));

    JSContext *ctx = JS_NewContext(rt);
    if (!ctx) {
        JS_FreeRuntime(rt);
        err_set(&e, "internal", "InternalError", "cannot create sandbox context", 0);
        goto done;
    }

    Deadline dl = {now_ms() + req.timeout_ms, 0};
    JS_SetInterruptHandler(rt, on_interrupt, &dl);

    Buf src = {0};
    buf_puts(&src, "(function(input){\"use strict\";");
    buf_printf(&src,
               "var __jsbox_seed=%u>>>0;"
               "try{Math.random=function(){__jsbox_seed=(__jsbox_seed+0x6D2B79F5)>>>0;"
               "var t=__jsbox_seed;t=Math.imul(t^(t>>>15),t|1);"
               "t^=t+Math.imul(t^(t>>>7),t|61);"
               "return ((t^(t>>>14))>>>0)/4294967296;};}catch(e){}"
               "try{Date.now=function(){return %lld;};}catch(e){}",
               (unsigned)req.seed, (long long)req.now_ms);
    buf_puts(&src, "\n");
    buf_append(&src, req.code, req.code_len);
    buf_puts(&src, "\n})");

    JSValue fn = JS_Eval(ctx, src.data, src.len, "<jsbox>", JS_EVAL_TYPE_GLOBAL);
    buf_free(&src);
    if (JS_IsException(fn)) {
        capture_exception(ctx, 1, &dl, &e);
        JS_FreeContext(ctx);
        JS_FreeRuntime(rt);
        goto done;
    }

    JSValue jinput = JS_ParseJSON(ctx, req.input, req.input_len, "<input>");
    if (JS_IsException(jinput)) {
        capture_exception(ctx, 0, &dl, &e);
        JS_FreeValue(ctx, fn);
        JS_FreeContext(ctx);
        JS_FreeRuntime(rt);
        goto done;
    }

    JSValue ret = JS_Call(ctx, fn, JS_UNDEFINED, 1, &jinput);
    JS_FreeValue(ctx, jinput);
    JS_FreeValue(ctx, fn);

    if (JS_IsException(ret)) {
        capture_exception(ctx, 0, &dl, &e);
        JS_FreeContext(ctx);
        JS_FreeRuntime(rt);
        goto done;
    }

    if (JS_IsPromise(ret)) {
        err_set(&e, "runtime", "TypeError",
                "return a plain JSON value, not a Promise", 1);
        JS_FreeValue(ctx, ret);
        JS_FreeContext(ctx);
        JS_FreeRuntime(rt);
        goto done;
    }

    JSValue json = JS_UNDEFINED;
    if (!JS_IsUndefined(ret)) {
        json = JS_JSONStringify(ctx, ret, JS_UNDEFINED, JS_UNDEFINED);
    }
    if (JS_IsException(json)) {
        capture_exception(ctx, 0, &dl, &e);
        JS_FreeValue(ctx, ret);
        JS_FreeContext(ctx);
        JS_FreeRuntime(rt);
        goto done;
    }
    if (JS_IsUndefined(json)) {
        err_set(&e, "runtime", "TypeError",
                "return value is not JSON-serializable (undefined, function, or symbol)",
                1);
        JS_FreeValue(ctx, ret);
        JS_FreeContext(ctx);
        JS_FreeRuntime(rt);
        goto done;
    }

    size_t value_len = 0;
    const char *value = JS_ToCStringLen(ctx, &value_len, json);
    if (!value) {
        capture_exception(ctx, 0, &dl, &e);
        JS_FreeValue(ctx, json);
        JS_FreeValue(ctx, ret);
        JS_FreeContext(ctx);
        JS_FreeRuntime(rt);
        goto done;
    }

    if ((int64_t)value_len > req.output_bytes) {
        err_set(&e, "output_limit", "RangeError", "result exceeds output limit", 1);
        JS_FreeCString(ctx, value);
        JS_FreeValue(ctx, json);
        JS_FreeValue(ctx, ret);
        JS_FreeContext(ctx);
        JS_FreeRuntime(rt);
        goto done;
    }

    emit_response(value, value_len, NULL, now_ms() - start_ms, &req);
    JS_FreeCString(ctx, value);
    JS_FreeValue(ctx, json);
    JS_FreeValue(ctx, ret);
    JS_FreeContext(ctx);
    JS_FreeRuntime(rt);
    free(req.code);
    free(req.input);
    return 0;

done:
    emit_response(NULL, 0, &e, now_ms() - start_ms, &req);
    err_free(&e);
    free(req.code);
    free(req.input);
    return 0;
}
