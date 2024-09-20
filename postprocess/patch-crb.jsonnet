local com = import 'lib/commodore.libjsonnet';
local inv = com.inventory();

local dir = std.extVar('output_path');

local patch = function(o)
  if o.kind == 'ClusterRoleBinding' then
    o {
      kind: 'RoleBinding',
    }
  else
    o;

com.fixupDir(dir, patch)
