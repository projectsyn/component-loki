local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.loki;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('loki', params.namespace);

{
  loki: app,
}
