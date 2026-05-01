local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();

// The hiera parameters for the component
local params = inv.parameters.loki;
local isOpenshift = std.member([ 'openshift4', 'oke' ], inv.parameters.facts.distribution);
local hasRolloutOperator = std.member(inv.applications, 'rollout-operator');

local s3endpoint =
  if params.s3.endpoint != null then
    params.s3.endpoint
  else if std.get(inv.parameters.facts, 'cloud') == 'cloudscale' then
    'objects.%s.cloudscale.ch' % std.stripChars(std.get(inv.parameters.facts, 'region', 'lpg'), '0123456789')
  else if std.get(inv.parameters.facts, 'cloud') == 'exoscale' then
    'sos-%s.exo.io' % std.get(inv.parameters.facts, 'region', 'ch-gva-2')
  else
    '${S3_ENDPOINT}';

// Global Params and Zone Aware Replication
local globalConfig = params.global + com.makeMergeable({
  nodeSelector: std.get(params, 'globalNodeSelector', params.global.nodeSelector),
  zoneAwareReplication: if hasRolloutOperator then params.global.zoneAwareReplication else std.trace('rollout-operator must be installed', {}),
});

local components = com.makeMergeable({
  // Read Path
  querier: {
    nodeSelector: std.get(params.components.querier, 'nodeSelector', globalConfig.nodeSelector),
  } + com.makeMergeable(params.components.querier),
  queryFrontend: {
    nodeSelector: std.get(params.components.queryFrontend, 'nodeSelector', globalConfig.nodeSelector),
  } + com.makeMergeable(params.components.queryFrontend),
  queryScheduler: {
    nodeSelector: std.get(params.components.queryScheduler, 'nodeSelector', globalConfig.nodeSelector),
  } + com.makeMergeable(params.components.queryScheduler),
  // Write Path
  distributor: {
    nodeSelector: std.get(params.components.distributor, 'nodeSelector', globalConfig.nodeSelector),
  } + com.makeMergeable(params.components.distributor),
  ingester: {
    nodeSelector: std.get(params.components.ingester, 'nodeSelector', globalConfig.nodeSelector),
    zoneAwareReplication: globalConfig.zoneAwareReplication,
  } + com.makeMergeable(params.components.ingester),
  // Backend
  compactor: {
    nodeSelector: std.get(params.components.compactor, 'nodeSelector', globalConfig.nodeSelector),
  } + com.makeMergeable(params.components.compactor),
  indexGateway: {
    nodeSelector: std.get(params.components.indexGateway, 'nodeSelector', globalConfig.nodeSelector),
  } + com.makeMergeable(params.components.indexGateway),
  // Ingress Configuration
  gateway: {
    [if params.components.gateway.enabled then 'enabledNonEnterprise']: params.components.gateway.enabled,
    nodeSelector: std.get(params.components.gateway, 'nodeSelector', globalConfig.nodeSelector),
  } + com.makeMergeable(params.components.gateway),
  // "Optional" components
  alertmanager: {
    nodeSelector: std.get(params.components.alertmanager, 'nodeSelector', globalConfig.nodeSelector),
  } + com.makeMergeable(params.components.alertmanager),
  overridesExporter: {
    nodeSelector: std.get(params.components.overridesExporter, 'nodeSelector', globalConfig.nodeSelector),
  } + com.makeMergeable(params.components.overridesExporter),
  patternIngester: {
    nodeSelector: std.get(params.components.patternIngester, 'nodeSelector', globalConfig.nodeSelector),
  } + com.makeMergeable(params.components.patternIngester),
  ruler: {
    nodeSelector: std.get(params.components.ruler, 'nodeSelector', globalConfig.nodeSelector),
  } + com.makeMergeable(params.components.ruler),
});

// Caches
local caches = com.makeMergeable({
  chunksCache: {
    nodeSelector: std.get(params.caches.chunks, 'nodeSelector', globalConfig.nodeSelector),
  } + com.makeMergeable(params.caches.chunks),
  resultsCache: {
    nodeSelector: std.get(params.caches.results, 'nodeSelector', globalConfig.nodeSelector),
  } + com.makeMergeable(params.caches.results),
});

// Experimental
local caches = com.makeMergeable({
  bloomPlanner: {
    nodeSelector: std.get(params.experimental.bloomPlanner, 'nodeSelector', globalConfig.nodeSelector),
  } + com.makeMergeable(params.experimental.bloomPlanner),
  bloomBuilder: {
    nodeSelector: std.get(params.experimental.bloomBuilder, 'nodeSelector', globalConfig.nodeSelector),
  } + com.makeMergeable(params.experimental.bloomBuilder),
  bloomGateway: {
    nodeSelector: std.get(params.experimental.bloomGateway, 'nodeSelector', globalConfig.nodeSelector),
  } + com.makeMergeable(params.experimental.bloomGateway),
});

// Global Config
local openshift = if isOpenshift then com.makeMergeable({
  //   global: {
  //     dnsService: 'dns-default',
  //     dnsNamespace: 'openshift-dns',
  //   },
  //   rbac: {
  //     type: 'scc',
  //     podSecurityContext: {
  //       fsGroup: null,
  //       runAsGroup: null,
  //       runAsUser: null,
  //     },
  //   },
  //   rollout_operator: {
  //     podSecurityContext: {
  //       fsGroup: null,
  //       runAsGroup: null,
  //       runAsUser: null,
  //     },
  //   },
}) else {};

local images = com.makeMergeable({
  image: {
    repository: '%(registry)s/%(repository)s' % params.images.loki,
    [if std.objectHas(params.images.loki, 'tag') then 'tag']: params.images.loki.tag,
  },
  memcached: {
    image: {
      repository: '%(registry)s/%(repository)s' % params.images.memcached,
      [if std.objectHas(params.images.memcached, 'tag') then 'tag']: params.images.memcached.tag,
    },
  },
  memcachedExporter: {
    image: {
      repository: '%(registry)s/%(repository)s' % params.images.memcachedExporter,
      [if std.objectHas(params.images.memcachedExporter, 'tag') then 'tag']: params.images.memcachedExporter.tag,
    },
  },
  gateway: {
    nginx: {
      image: {
        registry: params.images.nginx.registry,
        repository: params.images.nginx.repository,
        [if std.objectHas(params.images.nginx, 'tag') then 'tag']: params.images.nginx.tag,
      },
    },
  },
});

local global = com.makeMergeable({
  //   global: {
  //     extraEnvFrom: [ {
  //       secretRef: {
  //         name: '%s-bucket-secret' % inv.parameters._instance,
  //       },
  //     } ],
  //     podAnnotations: {
  //       bucketSecretVersion: '%s' % params.s3.auth.secretVersion,
  //     },
  //   },
  //   [if params.monitoring then 'metaMonitoring']: {
  //     serviceMonitor: {
  //       enabled: params.monitoring,
  //     },
  //     prometheusRule: {
  //       enabled: params.monitoring,
  //       lokiAlerts: true,
  //       lokiRules: true,
  //     },
  //   },
});

// loki Config
local loki = com.makeMergeable({
  loki: {
    schemaConfig: {
      configs: [ {
        from: '2024-04-01',
        store: 'tsdb',
        object_store: 's3',
        schema: 'v13',
        index: {
          prefix: 'loki_index_',
          period: '24h',
        },
      } ],
    },
    storage: {
      type: 's3',
      bucketNames: {
        chunks: '%s-chunks' % inv.parameters._instance,
        ruler: '%s-ruler' % inv.parameters._instance,
        admin: '%s-loki-admin' % inv.parameters._instance,
      },
    },
    ingester: {
      chunk_encoding: 'snappy',
    },
    tracing: {
      enabled: true,
    },
    querier: {
      // Default is 4, if you have enough memory and CPU you can increase, reduce if OOMing
      max_concurrent: 4,
    },
    //     structuredConfig: {
    //       alertmanager_storage: {
    //         backend: 's3',
    //         s3: {
    //           bucket_name: '%s-alertmanager-bucket' % params.s3.bucketPrefix,
    //           endpoint: s3endpoint,
    //           [if params.s3.region != null then 'region']: params.s3.region,
    //           [if params.s3.insecure then 'insecure']: true,
    //           access_key_id: '${S3_ACCESS_KEY_ID}',
    //           secret_access_key: '${S3_SECRET_ACCESS_KEY}',
    //         },
    //       },
    //       blocks_storage: {
    //         backend: 's3',
    //         s3: {
    //           bucket_name: '%s-blocks-bucket' % params.s3.bucketPrefix,
    //           endpoint: s3endpoint,
    //           [if params.s3.region != null then 'region']: params.s3.region,
    //           [if params.s3.insecure then 'insecure']: true,
    //           access_key_id: '${S3_ACCESS_KEY_ID}',
    //           secret_access_key: '${S3_SECRET_ACCESS_KEY}',
    //         },
    //       },
    //       ruler_storage: {
    //         backend: 's3',
    //         s3: {
    //           bucket_name: '%s-ruler-bucket' % params.s3.bucketPrefix,
    //           endpoint: s3endpoint,
    //           [if params.s3.region != null then 'region']: params.s3.region,
    //           [if params.s3.insecure then 'insecure']: true,
    //           access_key_id: '${S3_ACCESS_KEY_ID}',
    //           secret_access_key: '${S3_SECRET_ACCESS_KEY}',
    //         },
    //       },
    //       [if params.config.tenantFederation then 'tenant_federation']: {
    //         enabled: params.config.tenantFederation,
    //       },
    //       [if params.config.tenantFederation then 'ruler']: {
    //         tenant_federation: {
    //           enabled: params.config.tenantFederation,
    //         },
    //       },
    //       [if params.config.haTracker then 'limits']: {
    //         accept_ha_samples: true,
    //         ha_cluster_label: params.config.haLabels.cluster,
    //         ha_replica_label: params.config.haLabels.replica,
    //       },
    //       [if params.config.haTracker then 'distributor']: {
    //         ha_tracker: {
    //           enable_ha_tracker: true,
    //           ha_tracker_failover_timeout: '60s',
    //           kvstore: {
    //             // prefix: '%s/' % inv.parameters._instance,  // 👈 TODO: think about that
    //             store: params.config.haStore.type,
    //             [params.config.haStore.type]: {
    //               [obj]: params.config.haStore[obj]
    //               for obj in std.objectFields(params.config.haStore)
    //               if obj != 'type'
    //             },
    //           },
    //         },
    //       },
    //       // use clasic ingest architecture if kafka is disabled
    //       ingest_storage: {
    //         enabled: if params.components.kafka.enabled then true else false,
    //       },
    //       ingester: {
    //         push_grpc_method_enabled: if params.components.kafka.enabled then false else true,
    //       },
    //     },
  },
});

// Loki Config
local ingress = com.makeMergeable({
  //   [if params.components.gateway.enabled then 'gateway']: {
  //     ingress: {
  //       enabled: params.ingress.enabled,
  //       [if params.ingress.tls.enabled && params.ingress.tls.clusterIssuer != null then 'annotations']: {
  //         'cert-manager.io/cluster-issuer': params.ingress.tls.clusterIssuer,
  //       } + if std.objectHas(params.ingress, 'annotations') then com.makeMergeable(params.ingress.annotations) else {},
  //       [if std.objectHas(params.ingress, 'labels') then 'labels']: params.ingress.labels,
  //       hosts: [ {
  //         host: params.ingress.url,
  //         paths: [
  //           {
  //             path: '/',
  //             pathType: 'Prefix',
  //           },
  //         ],
  //       } ],
  //       [if params.ingress.tls.enabled then 'tls']: [ {
  //         hosts: [ params.ingress.url ],
  //         secretName: '%s-tls' % std.strReplace(params.ingress.url, '.', '-'),
  //       } ],
  //     },
  //     nginx: {
  //       basicAuth: {
  //         enabled: params.basicAuth.enabled,
  //         [if params.basicAuth.htpasswd != null && !std.objectHas(params.basicAuth, 'existingSecret') then 'existingSecret']: '%s-nginx-htpasswd' % inv.parameters._instance,
  //         [if std.objectHas(params.basicAuth, 'existingSecret') then 'existingSecret']: params.basicAuth.existingSecret,
  //       },
  //     },
  //   },
});

// hardcoded removal of rollout-operator
local hardNope = com.makeMergeable({
  minio: {
    enabled: false,
  },
  rollout_operator: {
    enabled: false,
  },
  [if params.preset != 'none' then 'deploymentMode']: 'Distributed',
  //   store_gateway: {
  //     zoneAwareReplication: {
  //       enabled: if hasRolloutOperator && params.global.zoneAwareReplication.enabled then true else false,
  //     },
  //   },
  //   ingester: {
  //     zoneAwareReplication: {
  //       enabled: if hasRolloutOperator && params.global.zoneAwareReplication.enabled then true else false,
  //     },
  //   },
});

{
  ['%s-components' % inv.parameters._instance]: components + caches,
  ['%s-configs' % inv.parameters._instance]: openshift + images + global + loki + ingress,
  ['%s-overrides' % inv.parameters._instance]: params.helm_values + hardNope,
}
