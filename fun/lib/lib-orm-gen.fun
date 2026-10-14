// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

fun GenCode(schema, name)
  var objectClasses = '';
  var schemaMethods = '';

  for k: v in schema do
    schemaMethods &= `
  var $k() = D$k(db, db.schema['$k']);`.eval();

    var relations = '';
    for n: r in v.@Parent do
      var a = r.Alias;
      relations &= `
  var Get$n(getKeys) = GetParent('$a', getKeys, D$a);`.eval();
    end do;
    for n: r in v.@Children do
      var a = r.Alias;
      relations &= `
  var Get%sSet(getKeys) = GetChildren('$a', getKeys, D$a);
  var New$n()           = NewChildren('$a', D$a);`.eval().format(n);
    end do;

    objectClasses &= `
class D$k = DObject()$relations
end class;
`.eval();
  end do;

  result = `use 'lib-orm.fun';
$objectClasses
class $name = NewSchema()
  // DObjects ...$schemaMethods
end class;
`.eval();
end fun;
