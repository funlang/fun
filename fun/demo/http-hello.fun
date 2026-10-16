// A minimal HTTP server on fun/lib/http-server: start it, then open
// http://127.0.0.1:8080/ in a browser or curl it.
//
// Blocks on the poll loop (as a server should), so it is run by hand, not by
// the regression suite:
//
//     src/prj/fun/funcmd fun/demo/http-hello.fun
//     curl http://127.0.0.1:8080/users/42
use 'fun/lib/http-server.fun';

fun hello(req, res)
  res.html('<h1>Hello from Fun!</h1>');
end fun;

fun user(req, res)
  res.json([id: req.param('id'), source: 'fun/lib/http-server']);
end fun;

fun notFound(req, res)
  res.status(404).text('nothing here');
end fun;

var s = HttpServer(8080);
s.Use(HttpLogger());
s.get('/', hello);
s.get('/users/:id', user);
s.get('/missing', notFound);
?. 'fun/lib/http-server demo listening on port ' & s.listen();
s.run();
