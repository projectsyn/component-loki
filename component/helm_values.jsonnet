local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();

// The hiera parameters for the component
local params = inv.parameters.loki;
local isOpenshift = std.member([ 'openshift4', 'oke' ], inv.parameters.facts.distribution);
local hasRolloutOperator = std.member(inv.applications, 'rollout-operator');

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
    extraEnvFrom: [ { secretRef: { name: '%s-bucket-secret' % inv.parameters._instance } } ],
    extraArgs: [ '-config.expand-env=true' ],
    nodeSelector: std.get(params.components.gateway, 'nodeSelector', globalConfig.nodeSelector),
  } + com.makeMergeable(params.components.gateway),
  // "Optional" components
  alertmanager: {
    nodeSelector: std.get(params.components.alertmanager, 'nodeSelector', globalConfig.nodeSelector),
  } + com.makeMergeable(params.components.alertmanager),
  overridesExporter: {
    nodeSelector: std.get(params.components.overridesExporter, 'nodeSelector', globalConfig.nodeSelector),
  } + com.makeMergeable(params.components.overridesExporter),
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
local experimental = com.makeMergeable({
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
  global: {
    dnsService: 'dns-default',
    dnsNamespace: 'openshift-dns',
  },
}) else {};

local images = com.makeMergeable({
  loki: {
    image: {
      repository: '%(registry)s/%(repository)s' % params.images.loki,
      [if std.objectHas(params.images.loki, 'tag') then 'tag']: params.images.loki.tag,
    },
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
    metrics: {
      image: {
        registry: params.images.accessLogExporter.registry,
        repository: params.images.accessLogExporter.repository,
        [if std.objectHas(params.images.accessLogExporter, 'tag') then 'tag']: params.images.accessLogExporter.tag,
      },
    },
  },
});

local global = com.makeMergeable({
  global: {
    extraEnvFrom: [ { secretRef: { name: '%s-bucket-secret' % inv.parameters._instance } } ],
    podAnnotations: {
      bucketSecretVersion: '%s' % params.s3.auth.secretVersion,
    },
  },
  lokiCanary: {
    enabled: false,
  },
  test: {
    enabled: false,
  },
});

// loki Config
local loki = com.makeMergeable({
  loki: {
    limits_config: {
      retention_period: params.global.retention,
    },
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
        chunks: '%s-chunks' % params.s3.bucketPrefix,
        ruler: '%s-ruler' % params.s3.bucketPrefix,
        admin: '%s-loki-admin' % params.s3.bucketPrefix,
      },
      s3: {
        endpoint: params.s3.endpoint,
        [if params.s3.region != null then 'region']: params.s3.region,
        [if params.s3.insecure then 'insecure']: true,
        accessKeyId: '${S3_ACCESS_KEY_ID}',
        secretAccessKey: '${S3_SECRET_ACCESS_KEY}',
        s3ForcePathStyle: params.s3.forcePathStyle,
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
  },
});

// Loki Config
local ingress = com.makeMergeable({
});

// hardcoded removal of rollout-operator
local hardRestrictions = com.makeMergeable({
  minio: {
    enabled: false,
  },
  rollout_operator: {
    enabled: false,
  },
  [if !std.member([ 'none', 'legacy' ], params.preset) then 'deploymentMode']: 'Distributed',
});

{
  ['%s-configs' % inv.parameters._instance]: openshift + images + global + loki + ingress,
  ['%s-overrides' % inv.parameters._instance]: params.helm_values + hardRestrictions,
}
