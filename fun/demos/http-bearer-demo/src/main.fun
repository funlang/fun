use '../../../lib/http-server.fun';
use '../../../lib/http-bearer.fun';

fun verifyDemo(req, c)
  if c['token'] = 'demo-token' then
    var p = new [];
    p['sub'] = 'demo-user';
    p['roles'] = new [];
    p['roles']['reader'] = true;
    result = p;
  else
    result = false;
  end if;
end fun;

fun meH(req, res)
  res.json([sub: req.auth['sub'], scheme: req.auth['scheme']]);
end fun;

fun publicH(req, res)
  res.json([ok: true, from: 'public']);
end fun;

var s = HttpServer(8080);
s.Use(HttpLogger());
s.get('/api/public', publicH);
var api = s.group('/api');
api.Use(HttpBearerAuth(verifyDemo, [realm: 'demo']));
api.get('/me', meH);
s.static('/', 'web');
s.run();
