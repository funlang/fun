use '../../../lib/http-server.fun';
use '../../../lib/http-cors.fun';

fun publicH(req, res)
  res.header('X-Request-Id', 'demo-1').json([ok: true, from: 'api']);
end fun;

fun echoH(req, res)
  res.json([got: req.json()]);
end fun;

var s = HttpServer(8080);
s.Use(HttpLogger());
s.Use(HttpCors([
  origins: ['http://127.0.0.1:5173'],
  methods: ['GET', 'POST'],
  headers: ['Content-Type', 'Authorization'],
  exposeHeaders: ['X-Request-Id'],
  credentials: true,
  maxAge: 600
]));
s.get('/api/public', publicH);
s.post('/api/echo', echoH);
s.run();
