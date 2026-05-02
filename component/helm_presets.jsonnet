local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();

// The hiera parameters for the component
local params = inv.parameters.loki;

// Prevent selecting a non-existent preset
assert std.member([ 'none', 'extra-small' ], params.preset) : 'params.preset must be one of: none, extra-small';

{
  none: {},
  // Extrasmall preset
  'extra-small': {
    backend: {
      replicas: 0,
    },
    read: {
      replicas: 0,
    },
    write: {
      replicas: 0,
    },
    singleBinary: {
      replicas: 0,
    },
    gateway: {
      replicas: 2,
    },
    querier: {
      replicas: 3,
      resources: {
        limits: {
          memory: '4Gi',
        },
        requests: {
          cpu: 1,
          memory: '2Gi',
        },
      },
    },
    queryFrontend: {
      replicas: 2,
      resources: {
        limits: {
          memory: '2Gi',
        },
        requests: {
          cpu: 1,
          memory: '1Gi',
        },
      },
    },
    queryScheduler: {
      replicas: 2,
    },
    distributor: {
      replicas: 3,
      resources: {
        limits: {
          memory: '4Gi',
        },
        requests: {
          cpu: '500m',
          memory: '2Gi',
        },
      },
    },
    ingester: {
      replicas: 3,
      resources: {
        limits: {
          memory: '16Gi',
        },
        requests: {
          cpu: 1,
          memory: '8Gi',
        },
      },
    },
    compactor: {
      replicas: 1,
      resources: {
        limits: {
          memory: '512Mi',
        },
        requests: {
          cpu: '250m',
          memory: '384Mi',
        },
      },
    },
    indexGateway: {
      replicas: 2,
      resources: {
        limits: {
          memory: '2.1Gi',
        },
        requests: {
          cpu: '500m',
          memory: '768Mi',
        },
      },
    },
    alertmanager: {
      replicas: 3,
      resources: {
        limits: {
          memory: '512Mi',
        },
        requests: {
          cpu: '250m',
          memory: '256Mi',
        },
      },
    },
    overridesExporter: {
      replicas: 1,
      resources: {
        limits: {
          memory: '128Mi',
        },
        requests: {
          cpu: '100m',
          memory: '128Mi',
        },
      },
    },
    ruler: {
      replicas: 2,
      resources: {
        limits: {
          memory: '768Mi',
        },
        requests: {
          cpu: '250m',
          memory: '512Mi',
        },
      },
    },
    patternIngester: {
    },
    chunksCache: {
      replicas: 2,
      resources: {
        limits: {
          memory: '4Gi',
        },
        requests: {
          cpu: '500m',
          memory: '4Gi',
        },
      },
    },
    resultsCache: {
      replicas: 2,
      resources: {
        limits: {
          memory: '614Mi',
        },
        requests: {
          cpu: '500m',
          memory: '614Mi',
        },
      },
    },
  },
}
