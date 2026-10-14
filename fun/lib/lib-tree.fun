// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

fun toList(tree, list)
  result = list;
  if result = nil then
    result = new [];
  end if;

  for n in tree.@nodes do
    result.@add(n);
    toList(n, result);
    n.@nodes  = nil;
    n.@parent = nil;
  end do;
end fun;

fun sortList(list, compare)
  compare = getCompare(compare);
  result = list;
  var n = list.@count();
  if n > 10000 then
    qsort(0, n-1);
  else
    shellSort(list, n-1);
  end if;

  # Quick Sort
  fun qsort(l, r)
    if l < r then
      var i = l;
      var j = r;
      var x = list[(l+r) div 2];
      while i < j loop
        while i < j and compare(list[i], x) < 0 do i += 1; end do;
        while i < j and compare(list[j], x) > 0 do j -= 1; end do;
        if i < j then
          var t   = list[i];
          list[i] = list[j];
          list[j] = t;
          i += 1;
          j -= 1;
        end if;
      end loop;
      if i = j then
        if i = r then
          j -= 1;
        elsif j = l then
          i += 1;
        end if;
      end if;
      qsort(l, j);
      qsort(i, r);
    end if;
  end fun;

  fun qs(l, r)
    if l < r then
      var i = l;
      var x = list[r];
      for j = l to r do
        if list[j] <= x then
          if i <> j then
            var t   = list[i];
            list[i] = list[j];
            list[j] = t;
          end if;
          i += 1;
        end if;
      end do;
      qs(l, i - 2);
      qs(i, r);
    end if;
  end fun;

  # Shell Sort, faster when n < 10000
  fun shellSort(a, n)
    for gap in [701, 301, 132, 57, 23, 10, 4, 1] do
      for i = gap to n loop
        var temp = a[i];
        var j = i - gap;
        while j >= 0 and compare(a[j], temp) > 0 do
          a[j + gap] = a[j];
          j -= gap;
        end do;
        a[j + gap] = temp;
      end loop;
    end do;
  end fun;
end fun;

fun getCompare(compare)
  result = compare;
  if result = nil then
    result = (k1, k2){
      if k1 > k2 then
        return 1;
      elsif k1 < k2 then
        return -1;
      else
        return 0;
      end if
    };
  end if;
end fun;

fun checkSort(list, compare)
  compare = getCompare(compare);
  result = true;
  for i = 1 to list.@count()-1 do
    if compare(list[i-1], list[i]) > 0 then
      return false;
    end if;
  end do;
end fun;
