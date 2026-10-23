use '../../../lib/http-server.fun';
use '../../../lib/http-session.fun';

fun meH(req, res)
  if req.session['user'] = nil then
    res.json([user: nil]);
  else
    res.json([user: req.session['user']]);
  end if;
end fun;

fun loginH(req, res)
  var body = req.json();
  var user = body['user'];
  if user = nil or user = '' then
    res.status(400).json([error: 'user required']);
    return;
  end if;
  req.session['user'] = user;
  SessionRegenerate(req);
  res.json([user: user]);
end fun;

fun countH(req, res)
  req.session['count'] = (req.session['count'] or 0) + 1;
  res.json([count: req.session['count']]);
end fun;

fun logoutH(req, res)
  req.session = nil;
  res.json([ok: true]);
end fun;

var s = HttpServer(8080);
s.Use(HttpLogger());
s.Use(HttpSession([name: 'sid', ttl: 86400, maxAge: 0, sameSite: 'Lax']));
s.get('/api/me', meH);
s.post('/api/login', loginH);
s.get('/api/count', countH);
s.post('/api/logout', logoutH);
s.static('/', 'web');
s.run();
