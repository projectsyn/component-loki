local com = import 'lib/commodore.libjsonnet';
local inv = com.inventory();
local params = inv.parameters.loki;
local ap = import 'lib/alert-patching.libsonnet';

local dir = std.extVar('output_path');


local pt = params.alerts.patchRules;

local patch = function(o)
  if o.kind == 'PrometheusRule' then
    o {
      spec+: {
        groups: std.map(
          function(g)
            ap.filterPatchRules(g, com.renderArray(pt.ignoreNames), pt.patches, preserveRecordingRules=true)
          , o.spec.groups
        ),
      },
    }
  else
    o;

com.fixupDir(dir, patch)
