#!/bin/sh
# Run lib-ado-odbc-test.fun when unixODBC plus a SQLite ODBC driver are
# available; otherwise report SKIP and exit 0.
#
# This keeps the shared regression list portable: the ODBC backend is optional
# at runtime (lib-ado-unx stays on embedded SQLite when no driver is present).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FUNCMD="${FUNCMD:-$ROOT/src/prj/fun/funcmd}"
[ -x "$FUNCMD" ] || FUNCMD="$ROOT/fun/fun"

driver=""
cn="${ODBC_TEST_CN:-}"

# A source-built local prefix (used by the maintainer host) takes precedence.
P="${ODBC_PREFIX:-$HOME/.local/odbc}"
if [ -z "$cn" ] && [ -f "$P/lib/libodbc.so.2" ] && [ -f "$P/lib/libsqlite3odbc.so" ]; then
    LD_LIBRARY_PATH="$P/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    ODBCSYSINI="$P/etc"
    export LD_LIBRARY_PATH ODBCSYSINI
    if [ -f "$P/etc/odbcinst.ini" ] && grep -q '^\[SQLite3\]' "$P/etc/odbcinst.ini"; then
        driver="SQLite3"
    elif [ -f "$P/etc/odbcinst.ini" ] && grep -q '^\[SQLite\]' "$P/etc/odbcinst.ini"; then
        driver="SQLite"
    fi
fi

# System unixODBC (CI: unixodbc + libsqliteodbc), driver names registered by
# the distribution package.
if [ -z "$cn" ] && [ -z "$driver" ] && command -v odbcinst >/dev/null 2>&1; then
    if odbcinst -q -d 2>/dev/null | grep -q '^\[SQLite3\]'; then
        driver="SQLite3"
    elif odbcinst -q -d 2>/dev/null | grep -q '^\[SQLite\]'; then
        driver="SQLite"
    fi
fi

if [ -z "$cn" ] && [ -z "$driver" ]; then
    if [ "${ODBC_TEST_VERBOSE:-0}" = "1" ]; then
        echo "SKIP: unixODBC or a SQLite ODBC driver is not available"
    fi
    echo "odbc=checked"
    exit 0
fi

if [ -z "$cn" ]; then
    dbfile="${TMPDIR:-/tmp}/fun-ado-odbc-$$.db"
    trap 'rm -f "$dbfile"' EXIT HUP INT TERM
    cn="DRIVER=$driver;DATABASE=$dbfile"
fi

ODBC_TEST_CN="$cn"
export ODBC_TEST_CN

# The regression runner compares shell-test output byte for byte. Keep the
# normal line stable whether ODBC is present or not; set ODBC_TEST_VERBOSE=1
# to see the full SQL/ORM trace.
out="$("$FUNCMD" fun/test/lib-ado-odbc-test.fun 2>&1)"
rc=$?
if [ "$rc" -ne 0 ]; then
    printf '%s\n' "$out"
    exit "$rc"
fi
if [ "${ODBC_TEST_VERBOSE:-0}" = "1" ]; then printf '%s\n' "$out"; fi
echo "odbc=checked"
