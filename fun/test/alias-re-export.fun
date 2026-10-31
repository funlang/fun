// `use ... as F` must expose names imported by a forwarding module, not only
// the wrapper's own definitions.
use 'alias-forward.fun' as F;
?. F.AliasValue();
