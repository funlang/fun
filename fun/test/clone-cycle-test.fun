// Cycle safety for the collection clone path.
//
// `a.self = a` stores a reference without copying, so it is safe by itself.
// `new [input: a]` and `a.@clone()` deep-copy the collection and must not
// recurse forever on a self-reference or a nested cycle. The clone keeps the
// cycle inside the copy: mutating the copy must not affect the source, and the
// copied cycle must point at the copy.
//
// The file prints stable booleans and is snapshotted by the regression runner.

var s = new [x: 1];
s.self = s;
var sc = new [input: s];
?. 'self isolated: ' & (sc.input.x = 1);
sc.input.x = 9;
?. 'self source intact: ' & (s.x = 1);
?. 'self cycle points at copy: ' & (sc.input.self.x = 9);
?. 'self json marks cycle: ' & (sc.input.@toJson(0, json: true).subpos('"(Object)"') > 0);

var inner = new [v: 1];
inner.self = inner;
var outer = new [inner: inner];
var copy = new [outer: outer];
?. 'nested value: ' & (copy.outer.inner.v = 1);
copy.outer.inner.v = 7;
?. 'nested source intact: ' & (inner.v = 1);
?. 'nested cycle points at copy: ' & (copy.outer.inner.self.v = 7);

var l = new [];
l.@add(l);
var m = new [l: l];
?. 'list cycle copied: ' & (m.l[0].@count() = 1);
l.@add(99);
?. 'list copy isolated: ' & (m.l.@count() = 1);
?. 'list cycle points at copy: ' & (m.l[0].@count() = 1);

class CNode()
  var nxt = nil;
  var v = 0;
end class;

var o = CNode();
o.v = 1;
o.nxt = o;
var w = new [o: o];
?. 'object value: ' & (w.o.v = 1);
w.o.v = 9;
?. 'object source intact: ' & (o.v = 1);
?. 'object cycle points at copy: ' & (w.o.nxt.v = 9);

var x = new [v: 1];
var y = new [a: x, b: x];
y.a.v = 9;
?. 'shared acyclic copied twice: ' & (y.b.v = 1);

var mc = s.@clone();
mc.x = 5;
?. 'method clone isolated: ' & (s.x = 1);
?. 'method cycle points at clone: ' & (mc.self.x = 5);

?. 'done';
