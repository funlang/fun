// An HTTP client call: fetch Beijing's current weather from the free
// open-meteo API (no key needed) and pick fields out of the JSON reply. No
// server required; to talk to fun/demo/http-rest.fun instead, point `url` at
// http://127.0.0.1:8080/... (start that demo first).
//
//     src/prj/fun/funcmd fun/demo/http-client.fun
use 'fun/lib/http-client.fun';
use 'fun/lib/lib-json.fun';

var r = HttpClient([
  url: 'https://api.open-meteo.com/v1/forecast?latitude=39.9&longitude=116.4&current_weather=true',
  method: 'GET'
]);
if r.code = 200 then
  var w = r.body.getJson();
  ?. 'Beijing temperature: ' & w.current_weather.temperature & ' °C';
  ?. 'wind speed: ' & w.current_weather.windspeed;
else
  ?. 'request failed: rc=' & r.rc & ' ' & r.message;
end if;
