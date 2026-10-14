
del *.obj /q
del *.dcu /q

make.exe

del pcre_default_tables.c /q

set dcc=D:\Borland\Delphi7\bin\dcc32
%dcc% pcre -B -Q %*
