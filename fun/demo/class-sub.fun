
########################################
# class-subclass
########################################
#   class name = base ( parameters )
#     cmds
#   end class;
########################################

# define a class
class CA()
  ? 'CA-constructor-starting..';

  var name = 'CA';

  fun showName()
    ?. name;
  end fun;

  fun getName()
    return name;
  end fun;

  ?. 'DONE';
end class;

# define a sub-class
class CB = CA()
  ? 'CB-constructor-starting..';

  name = 'CB';

  ?. 'DONE';
end class;

class CC = CB()
  ? 'CC-constructor-starting..';

  name = 'CC';

  fun showName()
    ?. '--CC.showName() .. ' & name & ' .. DONE';
  end fun;

  ?. 'DONE';
end class;

fun test(o)
  ?. o.name;
  o.showName();
  ?. o.getName();
end fun;

?. '--CA--';
test( CA() );

?. '--CB--';
test( CB() );

?. '--CC--';
test( CC() );
