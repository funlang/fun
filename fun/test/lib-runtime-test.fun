// runtime: source/stack/lastError and short paths. Booleans only.
use 'fun/lib/runtime.fun';
use 'fun/lib/lib-host.fun';

fun raises(fn)
  var bad = false;
  try
    fn();
  except
    bad = true;
  end try;
  result = bad;
end fun;

fun hasSuffix(s, suffix)
  result = s <> nil and ('' & s).subpos(suffix) >= 0;
end fun;

fun sourceGap()
  var a = runtime.source();
  var b = runtime.source();
  result = b['line'] - a['line'];
end fun;

class C()
  fun mark()
    var s = runtime.source();
    ?. s['function'] = 'mark';
    ?. s['className'] = 'C';
  end fun;
end class;

var c = C();
c.mark();

var lam = () {
  var s = runtime.source();
  ?. s <> nil;
  ?. s['line'] > 0;
};
lam();

fun inner()
  var s = runtime.source();
  ?. s <> nil;
  ?. s['function'] = 'inner';
  ?. hasSuffix(s['file'], 'lib-runtime-test.fun');
  ?. hasSuffix(s['path'], 'lib-runtime-test.fun');
  ?. s['line'] > 0;
  ?. sourceGap() = 1;

  var st = runtime.stack();
  ?. st.@count() >= 1;
  ?. st[0]['callee'] = 'inner';
  ?. hasSuffix(st[0]['file'], 'lib-runtime-test.fun');
  ?. runtime.stack(0).@count() = 0;
end fun;

inner();

?. runtime.lastError() = nil;
?. runtime.source(99) = nil;
?. raises(((){ runtime.source(-1); }));
?. raises(((){ runtime.stack(-1); }));

fun boom()
  var x = 1 / 0;
end fun;

fun caller()
  boom();
end fun;

try
  caller();
except
  var e = runtime.lastError();
  ?. e <> nil;
  ?. e['message'].subpos('division') >= 0;
  ?. hasSuffix(e['file'], 'lib-runtime-test.fun');
  ?. e['function'] = 'boom';
  ?. e['line'] > 0;
  ?. e['stack'].@count() >= 1;
  ?. hasSuffix(e['stack'][0]['file'], 'lib-runtime-test.fun');
end try;

var oldRoot = runtime.root();
?. oldRoot <> nil;
var newRoot = runtime.root(HostFullPath('.'));
?. newRoot <> nil;
?. hasSuffix(runtime.source()['path'], 'lib-runtime-test.fun');
runtime.root('');
?. hasSuffix(runtime.source()['path'], 'lib-runtime-test.fun');
