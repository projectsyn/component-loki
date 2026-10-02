// main template for loki
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local prom = import 'lib/prom.libsonnet';
local inv = kap.inventory();
local com = import 'lib/commodore.libjsonnet';

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

local prometheusRules = prom.generateRules('loki-custom', { 'loki-custom.rules': params.alerts.additionalRules }) {
  metadata+: {
    namespace: params.namespace.name,
  },
};

local has_monitoring = std.member(inv.applications, 'prometheus') || std.member(inv.applications, 'openshift4-monitoring');
local has_alerts = std.length(params.alerts.additionalRules) > 0;

// Define outputs below
{
  [if params.namespace.create then '00_namespace']: kube.Namespace(params.namespace.name) {
    metadata+: com.makeMergeable(params.namespace.metadata),
  },
  '01_secrets': secrets,
  // Empty file to make sure the directory is created. Later used in patching alerts.
  '10_helm_loki/loki/templates/monitoring/.keep': {},

  [if has_monitoring && has_alerts then '20_prometheus_rule']: prometheusRules,
  [if std.length(netpols) > 0 then '30_network_policies']: netpols,
}
