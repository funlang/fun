
########################################
# set-named
########################################
#   [ name: value, name: value ... ]
########################################

var list = [red: 0x0000ff, green: 0x00ff00, blue: 0xff0000, 0xffff00, '黄色': 0xffff00, '显示': a -> a & '!', '101': 'key'];

for i in list do
  ?, i;
end do;
?. 'DONE';

?, 'red';
?, list[0];
?, list['red'];
?. list.red;

?, 'green';
?, list[1];
?, list['green'];
?. list.green;

?, 'blue';
?, list[2];
?, list['blue'];
?. list.blue;

list.yellow   = 0x00ffff;
list['white'] = 0xffffff;
list["black"] = 0x000000;

for i in list do
  ?, i;
end do;
?. 'DONE';

?. list.'黄色';
?. list.'显示'('多彩缤纷的世界你好');
?. list.[101]; // 强制表示键, 而非索引
