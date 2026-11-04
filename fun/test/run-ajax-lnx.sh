#!/bin/sh
# Live HTTP test for lib-ajax-lnx: starts a local python3 fixture server, runs
# fun/test/lib-ajax-lnx-http.fun against it, tears the server down.
#
# Needs python3 (the fixture server) and the interpreter built at
# src/prj/fun/funcmd. If python3 is missing this exits 2 so the regression
# runner reports a clear FAIL rather than a confusing diff.
cd "$(dirname "$0")/../.." || exit 2
PORT=18731
MARKER=fun/test/.ajax-lnx-ready
FUNCMD="${FUNCMD:-src/prj/fun/funcmd}"
[ -x "$FUNCMD" ] || FUNCMD="fun/fun"

if ! command -v python3 >/dev/null 2>&1; then
    echo "run-ajax-lnx.sh: python3 not found (needed for the HTTP fixture)" >&2
    exit 2
fi
if [ ! -x "$FUNCMD" ]; then
    echo "run-ajax-lnx.sh: $FUNCMD not built" >&2
    exit 2
fi

rm -f "$MARKER"
python3 fun/test/ajax-lnx-server.py "$PORT" "$MARKER" >/dev/null 2>&1 &
SRV=$!
trap 'kill "$SRV" 2>/dev/null; rm -f "$MARKER"' EXIT INT TERM

i=0
while [ ! -f "$MARKER" ] && [ "$i" -lt 100 ]; do
    sleep 0.1
    i=$((i + 1))
done
if [ ! -f "$MARKER" ]; then
    echo "run-ajax-lnx.sh: fixture server did not start on port $PORT" >&2
    exit 2
fi

"$FUNCMD" fun/test/lib-ajax-lnx-http.fun 2>&1
