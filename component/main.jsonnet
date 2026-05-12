// main template for loki
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local com = import 'lib/commodore.libjsonnet';

local prom = import 'lib/prom.libsonnet';

// The hiera parameters for the component
local params = inv.parameters.loki;


local secrets = com.generateResources(
  {
    // [if params.ingress.tls.enabled && params.ingress.tls.key != null && params.ingress.tls.cert != null then '%s-tls' % std.strReplace(params.ingress.url, '.', '-')]:
    //   {
    //     stringData: {
    //       'tls.key': params.ingress.tls.key,
    //       'tls.cert': params.ingress.tls.cert,
    //     },
    //   },
    // [if params.basicAuth.enabled && params.basicAuth.htpasswd != null then '%s-nginx-htpasswd' % inv.parameters._instance]:
    //   {
    //     stringData: {
    //       '.htpasswd': params.basicAuth.htpasswd,
    //     },
    //   },
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
}
