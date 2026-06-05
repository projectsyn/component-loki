local com = import 'lib/commodore.libjsonnet';
local inv = com.inventory();
local params = inv.parameters.loki;

local dir = std.extVar('output_path');

// `lib/alert-patching.libsonnet` is only provided by
// component-openshift4-monitoring. On non-OpenShift clusters provide a minimal
// fallback that stamps the syn alert labels, prefixes alert names with `SYN_`,
// filters ignored alerts and preserves recording rules. The OpenShift-only
// bits (syn_team lookup, customAnnotations) are intentionally omitted.
local ap =
  if std.member(inv.applications, 'openshift4-monitoring') then
    import 'lib/alert-patching.libsonnet'
  else
    local patchRule(rule, patches={}, patchName=true) =
      if !std.objectHas(rule, 'alert') then
        rule
      else
        rule {
          alert:
            if patchName && !std.startsWith(super.alert, 'SYN_') then
              'SYN_' + super.alert
            else
              super.alert,
          labels+: {
            syn: 'true',
            syn_component: inv.parameters._instance,
          },
        } + com.makeMergeable(std.get(patches, rule.alert, {}));
    {
      patchRule: patchRule,
      filterPatchRules(group, ignoreNames=[], patches={}, preserveRecordingRules=false, patchNames=true):
        local ignore = std.set(ignoreNames);
        group {
          rules: [
            patchRule(rule, patches, patchNames)
            for rule in super.rules
            if (
              if std.objectHas(rule, 'alert')
              then !std.member(ignore, rule.alert)
              else preserveRecordingRules
            )
          ],
        },
    };

local pt = params.alerts.patchRules;

local patch = function(o)
  if o.kind == 'PrometheusRule' then
    o {
      spec+: {
        groups: std.map(
          function(g)
            ap.filterPatchRules(g, pt.ignoreNames, pt.patches, preserveRecordingRules=true)
          , o.spec.groups
        ),
      },
    }
  else
    o;

com.fixupDir(dir, patch)
