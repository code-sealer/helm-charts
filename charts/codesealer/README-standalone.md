# Codesealer Standalone Helm Chart

This Helm chart installs [Codesealer](https://codesealer.com) as a standalone implementation on an
existing Kubernetes Cluster. Codesealer is configured through a management portal to protect applications
external to the Cluster.

## Prerequisites

To use this Helm chart you will need an access token for the Codesealer Docker registry.
In the following we assume that the access token is set in the following way:

```bash
export CODESEALER_TOKEN=<access token>
```

To use this Helm chart you will also need to set the following variables to match
your Ingress Controller's deployment on your Kubernetes Cluster:

```bash
export INGRESS_NAMESPACE=<ingress namespace>
export INGRESS_DEPLOYMENT=<ingress deployment>
export INGRESS_PORT=<ingress port>
export INGRESS_HELM_REPO=<ingress repo URL>
export INGRESS_HELM_CHART=<ingress chart>
```

To use this Helm chart you will also need to set the following variable to match
your Redis deployment on your Kubernetes Cluster:

```bash
export REDIS_NAMESPACE=redis
```

You will need the Redis generated password to install or upgrade Codesealer.  You can get that password with
the following command after Redis is installed:

```bash
export REDIS_PASSWORD=$(kubectl get secret --namespace ${REDIS_NAMESPACE} redis -o jsonpath="{.data.redis-password}" | base64 -d)
```

## Installing

To install the Codesealer Helm chart, please ensure the prerequisite parametes are defined
and run the following commands:

```bash
helm install codesealer codesealer/codesealer --create-namespace --namespace codesealer-system \
  --set codesealerToken="${CODESEALER_TOKEN}" \
  --set worker.ingress.namespace=${INGRESS_NAMESPACE} \
  --set worker.ingress.deployment=${INGRESS_DEPLOYMENT} \
  --set worker.ingress.port=${INGRESS_PORT} \
  --set worker.redis.namespace=${REDIS_NAMESPACE} \
  --set worker.config.bootloader.redisPassword="${REDIS_PASSWORD}" \
  --set worker.config.bootloader.fsEndpoints=false \
  --set manager.enabled=true \
  --set ingress.enabled=true \
  --wait --timeout=90s
```

## Upgrading

To upgrade an existing release, please ensure the prerequisite parametes are defined
and run the following commands:

```bash
helm repo update codesealer
helm upgrade codesealer codesealer/codesealer --namespace codesealer-system \
    --set codesealerToken="${CODESEALER_TOKEN}" \
    --set worker.ingress.namespace=${INGRESS_NAMESPACE} \
    --set worker.ingress.deployment=${INGRESS_DEPLOYMENT} \
    --set worker.ingress.port=${INGRESS_PORT} \
    --set worker.redis.namespace=${REDIS_NAMESPACE} \
    --set worker.config.bootloader.redisPassword="${REDIS_PASSWORD}" \
    --set worker.config.bootloader.fsEndpoints=false \
    --set manager.enabled=true \
    --set ingress.enabled=true \
    --wait --timeout=90s
```

Then restart the Codesealer deployment with the following command:

```bash
kubectl rollout restart deployments --namespace codesealer-system
kubectl rollout status deployments --namespace codesealer-system
```