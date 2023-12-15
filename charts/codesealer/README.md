# Codesealer Ingress Sidecar Helm Chart

This Helm chart installs [Codesealer](https://codesealer.com) as a sidecar to an
existing ingress deployment. This enabled automatic protection of the application behind
the ingress.

## Prerequisites

To use this Helm chart you will need an access token for the Codesealer Docker registry.
In the following we assume that the access token is set in the following way:

```bash
export CODESEALER_TOKEN=<access token>
```

Additionally you will need an ingress and an application to protect. Below are steps to
get started with a demo application and an Nginx Ingress. For guides on how to use this
Helm chart with specific Kubernetes implementations, see the ["Kubernetes Implementation
Specifics"](#kubernetes-implementation-specifics) section.

### Ingress

This Helm chart will install Codesealer as a sidecar to an existing ingress deployment.
If you don't have an ingress already, you can install an [Nginx Ingress
Controller](https://docs.nginx.com/nginx-ingress-controller/) using the following
command:

```bash
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace
```

> NOTE: If using Kind, install the Ingress using the following variation
>
> ```bash
> helm upgrade --install ingress-nginx ingress-nginx \
>   --repo https://kubernetes.github.io/ingress-nginx \
>   --namespace ingress-nginx --create-namespace \
>   --set controller.hostPort.enabled=true \
>   --set controller.updateStrategy.rollingUpdate.maxUnavailable=1
> ```
>
> See also the notes on Kind in the ["Kubernetes Implementation
> Specifics"](#kubernetes-implementation-specifics) section.

### Target Application

Codesealer will add protection to any existing web application. If you don't already
have an application, you can install [OWASP's Juice
Shop](https://owasp.org/www-project-juice-shop/) demo application using the following
command:

```bash
helm repo add securecodebox https://charts.securecodebox.io/
helm install juice-shop securecodebox/juice-shop --namespace juice-shop --create-namespace \
  --set ingress.enabled=true \
  --set "ingress.hosts[0].host=localhost,ingress.hosts[0].paths[0].path=/" \
  --set "ingress.tls[0].hosts[0]=localhost,ingress.tls[0].secretName=" \
  --set ingress.pathType=Prefix
```

## Installing

To install this Helm chart, set the `INGRESS_NAMESPACE` variable to match your target
ingress deployment and run the following commands:

```bash
helm repo add codesealer https://code-sealer.github.io/helm-charts
helm install codesealer codesealer/codesealer --create-namespace --namespace codesealer-system \
  --set codesealerToken=${CODESEALER_TOKEN} \
  --set worker.ingress.namespace=${INGRESS_NAMESPACE} \
  --set image.pullPolicy=Always
```

Wait for the Codesealer deployement to start. You can do this by using the following
command:

```bash
kubectl wait --namespace codesealer-system \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=codesealer-mutating-webhook \
  --timeout=90s
```

To enabled Codesealer on your ingress, set the `INGRESS_NAMESPACE` and
`INGRESS_DEPLOYMENT` variables to match your target ingress and run the following
commands:

```bash
kubectl label ns $INGRESS_NAMESPACE codesealer.com/webhook=enabled
kubectl patch deployment $INGRESS_DEPLOYMENT -n $INGRESS_NAMESPACE -p '{"spec": {"template":{"metadata":{"annotations":{"codesealer.com/injection":"enabled"}}}} }'
```

Your ingress pods should now restart and have Codesealer sidecars running with them.
Codesealer will now automatically protect your application.

## Upgrading

To upgrade an existing release, set the `INGRESS_NAMESPACE` variable to match your
target ingress deployment and run the following commands:

```bash
helm repo update codesealer
helm upgrade codesealer codesealer/codesealer --namespace codesealer-system \
  --set codesealerToken=${CODESEALER_TOKEN} \
  --set worker.ingress.namespace=${INGRESS_NAMESPACE} \
  --set image.pullPolicy=Always
```

Then restart the Codesealer deployment with the following command:

```bash
kubectl rollout restart deployments --namespace codesealer-system
kubectl rollout status deployments --namespace codesealer-system
```

Finally, set the `INGRESS_NAMESPACE` and `INGRESS_DEPLOYMENT` variables to match your
target ingress and restart your ingress deployment:

```bash
kubectl rollout restart deployment $INGRESS_DEPLOYMENT --namespace $INGRESS_NAMESPACE
kubectl rollout status deployment $INGRESS_DEPLOYMENT --namespace $INGRESS_NAMESPACE
```

## Uninstalling

To uninstall a release,  run the following commands:

```bash
helm uninstall codesealer --namespace codesealer-system
helm repo remove codesealer
```

## Kubernetes Implementation Specifics

### Kind

For this chart to work with [Kind](https://kind.sigs.k8s.io/) use the following Kind
configuration:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
```
