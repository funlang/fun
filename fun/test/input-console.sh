#!/bin/sh
# Console input builtins ('line'/'char'/'all'.input()) with a scripted session.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FUNCMD="$ROOT/fun/funcmd"
[ -x "$FUNCMD" ] || FUNCMD="$ROOT/src/prj/fun/funcmd"
[ -x "$FUNCMD" ] || FUNCMD="$ROOT/fun/fun"
[ -x "$FUNCMD" ] || { echo "funcmd not built"; exit 2; }

echo "== demo: Chinese Q&A (structural A不A/A没A, arrow-lambda swap) =="
printf '你会聊天吗?\n你会不会唱歌吗?\n你能不能帮我?\n可不可以加你微信?\n你有没有钱?\n你去没去过北京?\n您会唱歌吗?\n今天天气好不好？\n普通一句\n\n' | "$FUNCMD" "$ROOT/fun/demo/input.fun"

echo "== char: one key at a time =="
printf 'ab\n' | "$FUNCMD" "$ROOT/fun/test/input-char.fun"

echo "== all: remainder of the stream =="
printf 'x\ny' | "$FUNCMD" "$ROOT/fun/test/input-all.fun"
