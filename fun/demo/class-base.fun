
########################################
# class-base
########################################
#   class name = base ( parameters )
#     cmds
#   end class;
########################################
#   this.field or this.method()
#   base.field or base.method()
########################################

// base class
class CBas()
  var field = 'field';

  fun method()
    ?. field;
  end fun;

  fun test()
    ?. field;
    ?. this.field;
    method();      // call the method in this class
    this.method(); // call the override method
  end fun;
end class;

// sub class
class CSub = CBas()
  fun method()
    ? 'CSub.method()..';
    base.method(); // call the method in base classes
  end fun;
end class;

// test ...
var bas = CBas();
var sub = CSub();
?. '--test--bas--'; ?. bas.field; bas.test();
?. '--test--sub--'; ?. sub.field; sub.test();
// test ...
bas.field = 'bas';
sub.field = 'sub';
?. '--test--bas--'; ?. bas.field; bas.test();
?. '--test--sub--'; ?. sub.field; sub.test();
