
########################################
# test for lib-winapi.fun
########################################

use '..\lib\lib-winapi.fun';

test();

fun test()
  # constants
  var WM_SETTEXT = 12;
  var user32     = 'user32';

  # get APIs
  var findwin = user32.getapi('FindWindow',    'ss:i');
  var sendmsg = user32.getapi('SendMessage',   'iiip:i');
  var gettext = user32.getapi('GetWindowText', 'ipi:i');

  # settxt call sendmsg() - WM_SETTEXT
  var settxt(h, t) = sendmsg(h, WM_SETTEXT, 0, t);

  # gettxt call gettext()
  var gettxt  = (h){
    result    = ' '.x(256);
    var len   = gettext(h, var result, 255);
    result    = result.substr(len: len);
  };

  # call findwin via findwin.call()
  var handle  = findwin.call('Shell_TrayWnd', '');

  # call settxt
  settxt(handle, 'New text.');

  # call gettxt
  ?. '[' & gettxt(handle) & ']';

  # call settxt
  settxt(handle, '');

  # call gettxt
  ?. '[' & gettxt(handle) & ']';
end fun;
