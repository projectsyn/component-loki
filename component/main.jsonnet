// main template for loki
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local com = import 'lib/commodore.libjsonnet';

// `prom.libsonnet` (with `generateRules`) is provided by
// component-openshift4-monitoring via a library alias. On non-OpenShift
// clusters fall back to component-prometheus, which exports
// `prometheus.libsonnet`, and reimplement the small `generateRules` helper.
// Keep behaviour identical to the OpenShift `prom.libsonnet`: `generateRules`
// only shapes the rules, the syn labels are stamped later by `patch-alerts`.
local prom =
  if std.member(inv.applications, 'openshift4-monitoring') then
    import 'lib/prom.libsonnet'
  else if std.member(inv.applications, 'prometheus') then
    local p = import 'lib/prometheus.libsonnet';
    {
      generateRules(name, rules): p.PrometheusRule(name) {
        spec: {
          groups: std.filter(
            function(g) std.length(g.rules) > 0,
            [
              {
                name: group_name,
                rules: [
                  local rnamekey = std.splitLimit(rname, ':', 1);
                  rules[group_name][rname] {
                    // transform source key into "alert: alertname" or
                    // "record: recordname"
                    [rnamekey[0]]: rnamekey[1],
                  }
                  for rname in std.objectFields(rules[group_name])
                  if rules[group_name][rname] != null
                ],
              }
              for group_name in std.objectFields(rules)
              if rules[group_name] != null
            ]
          ),
        },
      },
    }
  else
    error 'component requires one of component-openshift4-monitoring or component-prometheus to be present';

// The hiera parameters for the component
local params = inv.parameters.loki;

// Prevent using non-instantiated configuration of this component
assert inv.parameters._instance != 'loki' : "configuring non-instantiated component isn't allowed";

local secrets = com.generateResources(
  {
    [if params.ingress.tls.enabled && params.ingress.tls.key != null && params.ingress.tls.cert != null then '%s-tls' % std.strReplace(params.ingress.url, '.', '-')]:
      {
        stringData: {
          'tls.key': params.ingress.tls.key,
          'tls.cert': params.ingress.tls.cert,
        },
      },
    [if params.basicAuth.enabled && params.basicAuth.htpasswd != null then '%s-nginx-htpasswd' % inv.parameters._instance]:
      {
        stringData: {
          '.htpasswd': params.basicAuth.htpasswd,
        },
      },
    ['%s-bucket-secret' % inv.parameters._instance]: {
      stringData: {
        S3_ACCESS_KEY_ID: params.s3.auth.accessKeyId,
        S3_SECRET_ACCESS_KEY: params.s3.auth.secretAccessKey,
      },
    },
  } + com.makeMergeable(params.secrets),
  function(name) kube.Secret(name) {
    metadata+: {
      labels+: {
        'app.kubernetes.io/managed-by': 'commodore',
        'app.kubernetes.io/name': name,
      },
      namespace: params.namespace.name,
    },
  }
);

local netpols =
  local exposedComponents = com.renderArray(params.networkPolicy.exposedComponents);
  local allowedNamespaces = com.renderArray(params.networkPolicy.allowedNamespaces);
  if
    params.networkPolicy.enabled
    && std.length(exposedComponents) > 0
    && std.length(allowedNamespaces) > 0
  then kube.NetworkPolicy('allow-from-other-namespaces') {
    metadata+: {
      labels+: {
        'app.kubernetes.io/managed-by': 'commodore',
        'app.kubernetes.io/name': 'allow-from-other-namespaces',
      },
      namespace: params.namespace.name,
    },
    spec: {
      policyTypes: [ 'Ingress' ],
      podSelector: {
        matchExpressions: [ {
          key: 'app.kubernetes.io/component',
          operator: 'In',
          values: exposedComponents,
        } ],
      },
      ingress: [ {
        from: [ {
          namespaceSelector: {
            matchExpressions: [ {
              key: 'kubernetes.io/metadata.name',
              operator: 'In',
              values: allowedNamespaces,
            } ],
          },
        } ],
      } ],
    },
  } else {};

// Define outputs below
{
  [if params.namespace.create then '00_namespace']: kube.Namespace(params.namespace.name) {
    metadata+: com.makeMergeable(params.namespace.metadata),
  },
  '01_secrets': secrets,
  // Empty file to make sure the directory is created. Later used in patching alerts.
  '10_helm_loki/loki/templates/monitoring/.keep': {},

  '20_prometheus_rule': prom.generateRules('loki-custom', { 'loki-custom.rules': params.alerts.additionalRules }) {
    metadata+: {
      namespace: params.namespace.name,
    },
  },
  [if std.length(netpols) > 0 then '30_network_policies']: netpols,
}
