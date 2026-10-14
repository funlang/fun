
########################################
# test for lib-winole.fun
########################################

use '..\lib\lib-winole.fun';
use '..\lib\lib-base.fun';

test();

fun test()
  var f1 = 'c:\temp\admin\1.tmp';
  var f2 = 'c:\temp\admin\2.tmp';
  var fn = 'c:\temp\admin\?.tmp';

  # Create ActiveX Object
  var sh = 'Wscript.Shell'.newobj();

  f1.save('Windows COM');

  # Call Method of COM Object
  sh.Run('cmd.exe /Ccopy %s %s'.format(f1, f2), 0, true);

  ?. f2.load();

  foreach(fn.find(), (f){?.f; f.move()});

  var regex = 'VBScript.RegExp'.newobj();
  regex.Pattern = '^\d+$';  # Property set, or:
                            # regex.@@Pattern('^\d+$');
  ?. regex.Pattern;         # Property get, or:
                            # ?. regex.@Pattern();
  ?. regex.Test('123');     # Call method
  ?. regex.Test('abc');
end fun;
