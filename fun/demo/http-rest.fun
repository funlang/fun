// A small JSON REST server: routes with a path parameter, a route group with
// an auth middleware, and access logging. Start it, then call it (curl, or
// fun/demo/http-client.fun pointed at 127.0.0.1:8080):
//
//     src/prj/fun/funcmd fun/demo/http-rest.fun
//     curl http://127.0.0.1:8080/users/42
//     curl -H 'token: secret' http://127.0.0.1:8080/api/orders
//
// Blocks on the poll loop (as a server should), so it is run by hand, not by
// the regression suite.
use 'fun/lib/http-server.fun';

fun roots(req, res)
  res.json([service: 'fun-rest', endpoints: ['/users/:id', '/api/orders']]);
end fun;

fun user(req, res)
  res.json([id: req.param('id'), name: 'user ' & req.param('id')]);
end fun;

fun trace(req, res, nx)
  ?. req.method & ' ' & req.path;
  nx();
end fun;

fun auth(req, res, nx)
  if req.header('token') <> 'secret' then
    res.status(401).json([error: 'unauthorized (send header: token: secret)']);
  else
    nx();
  end if;
end fun;

fun orders(req, res)
  res.json([orders: [[id: 1, total: 13], [id: 2, total: 42]]]);
end fun;

var s = HttpServer(8080);
s.Use(HttpLogger());
s.Use(trace);
s.get('/', roots);
s.get('/users/:id', user);
var api = s.group('/api');     // route group: shared prefix
api.Use(auth);                 // group middleware: no nx() call = short cut
api.get('/orders', orders);

?. 'listening on http://127.0.0.1:' & s.listen();
s.run();
