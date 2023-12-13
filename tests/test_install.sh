#!/bin/bash

set -ueo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "Usage: ./test_install.sh [install | uninstall | upgrade]"
    exit 1
fi

clear

export CODESEALER_HELM_REPO=https://raw.githubusercontent.com/code-sealer/helm-charts/gh-pages
export CODESEALER_HELM_CHART=codesealer/codesealer

export INGRESS_NAMESPACE=ingress-nginx
export INGRESS_DEPLOYMENT=ingress-nginx-controller

if [[ "$1" == "install" ]]; then

  echo "########################################################################################"
  echo "#  Do you wish to install NGINX Ingress Controller to access the OWASP Juice Shop Application?"
  echo "########################################################################################"
  read -r -p 'Install NGINX Ingress Controller [y/n]: '

  if [[ ${REPLY} == 'y' ]]; then
    helm upgrade --install ingress-nginx ingress-nginx \
    --repo https://kubernetes.github.io/ingress-nginx \
    --namespace ${INGRESS_NAMESPACE} --create-namespace \
    --set controller.hostPort.enabled=true \
    --set controller.service.type=LoadBalancer \
    --set controller.publishService.enabled=false \
    --set controller.extraArgs.publish-status-address=localhost

    echo "########################################################################################"
    echo "#  Waiting for NGINX Ingress Controller to start"
    echo "########################################################################################"

    kubectl wait --namespace ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=90s
  fi

  echo "########################################################################################"
  echo "#  Do you wish to install the OWASP Juice Shop Application?"
  echo "########################################################################################"
  read -r -p 'Install OWASP Juice Shop [y/n]: '

  if [[ ${REPLY} == 'y' ]]; then
    helm repo add securecodebox https://charts.securecodebox.io/
    helm install juice-shop securecodebox/juice-shop --namespace juice-shop --create-namespace \
      --set ingress.enabled=true \
      --set "ingress.hosts[0].host=localhost,ingress.hosts[0].paths[0].path=/" \
      --set "ingress.tls[0].hosts[0]=localhost,ingress.tls[0].secretName=" \
      --set ingress.pathType=Prefix

    echo "########################################################################################"
    echo "#  Waiting for Juice Shop to start"
    echo "########################################################################################"

    kubectl wait --namespace juice-shop \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=juice-shop \
    --timeout=90s
  fi

  echo "########################################################################################"
  echo "#  Install Codesealer"
  echo "########################################################################################"
  read -r -s -p 'Press any key to continue.'

  # Install Codesealer helm repo
  helm repo add codesealer ${CODESEALER_HELM_REPO}

  # Install Codsealer
  helm install codesealer ${CODESEALER_HELM_CHART} --create-namespace --namespace codesealer-system \
    --set codesealerToken="${CODESEALER_TOKEN}" \
    --set worker.ingress.namespace=${INGRESS_NAMESPACE} \
    --set image.pullPolicy=Always \
    --set worker.config.endpoint.wafMonitorMode=false \
    --set worker.config.endpoint.enableWaf=true \
    --set worker.config.endpoint.wafFullTransaction=true \
    --set worker.config.endpoint.paranoiaLevel=1

  echo "########################################################################################"
  echo "#  Waiting for Codesealer to start"
  echo "########################################################################################"

  kubectl wait --namespace codesealer-system \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=codesealer-mutating-webhook \
  --timeout=90s

  echo "########################################################################################"
  echo "#  Activate Codesealer by applying labels and annotations"
  echo "########################################################################################"
  read -r -s -p 'Press any key to continue.'

  # Enable Codesealer
  echo "########################################################################################"
  echo "  $ kubectl label ns ${INGRESS_NAMESPACE} codesealer.com/webhook=enabled"
  echo "  $ kubectl patch deployment ${INGRESS_DEPLOYMENT} -n ${INGRESS_NAMESPACE} -p '{"spec": {"template":{"metadata":{"annotations":{"codesealer.com/injection":"enabled"}}}} }'"
  echo "########################################################################################"

  kubectl label ns ${INGRESS_NAMESPACE} codesealer.com/webhook=enabled
  kubectl patch deployment ${INGRESS_DEPLOYMENT} -n ${INGRESS_NAMESPACE} -p '{"spec": {"template":{"metadata":{"annotations":{"codesealer.com/injection":"enabled"}}}} }'

  echo "########################################################################################"
  echo "#  Restart NGINX Ingress Controller"
  echo "########################################################################################"
  read -r -s -p 'Press any key to continue.'

  kubectl scale deployment ${INGRESS_DEPLOYMENT}  --namespace ${INGRESS_NAMESPACE} --replicas=0
  sleep 20   
  kubectl scale deployment ${INGRESS_DEPLOYMENT}  --namespace ${INGRESS_NAMESPACE} --replicas=1

  echo "########################################################################################"
  echo "#  Waiting for NGINX Ingress Controller to restart"
  echo "########################################################################################"

  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=90s

elif [[ "$1" == "uninstall" ]]; then

  echo "########################################################################################"
  echo "#  Uninstall Codesealer"
  echo "########################################################################################"

  helm uninstall codesealer --namespace codesealer-system
  helm repo remove codesealer

  echo "########################################################################################"
  echo "#  Do you wish to uninstall OWASP Juice Shop Application"
  echo "########################################################################################"
  read -r -p 'Uninstall OWASP Juice Shop [y/n]: '

  if [[ ${REPLY} == 'y' ]]; then
    helm uninstall juice-shop --namespace juice-shop
    helm repo remove securecodebox
  fi

  echo "########################################################################################"
  echo "#  Do you wish to uninstall NGINX Ingress Controller?"
  echo "########################################################################################"
  read -r -p 'Uninstall NGINX Ingress Controller [y/n]: '

  if [[ ${REPLY} == 'y' ]]; then
    helm uninstall ingress-nginx --namespace ${INGRESS_NAMESPACE}
  fi

elif [[ "$1" == "upgrade" ]]; then

  echo "########################################################################################"
  echo "#  Upgrade Codesealer Release"
  echo "########################################################################################"

  helm repo update codesealer
  helm upgrade codesealer ${CODESEALER_HELM_CHART} --namespace codesealer-system \
    --set codesealerToken="${CODESEALER_TOKEN}" \
    --set worker.ingress.namespace="${INGRESS_NAMESPACE}" \
    --set worker.config.endpoint.wafMonitorMode=false \
    --set worker.config.endpoint.enableWaf=true \
    --set worker.config.endpoint.wafFullTransaction=true \
    --set worker.config.endpoint.paranoiaLevel=1

  echo "########################################################################################"
  echo "#  Upgrade Codesealer"
  echo "########################################################################################"

  read -r -s -p 'Press any key to continue.'
  kubectl rollout restart deployments --namespace codesealer-system
  kubectl rollout status deployments --namespace codesealer-system

  echo "########################################################################################"
  echo "#  Upgrade Codesealer Worker Sidecar for NGINX Ingress Controller"
  echo "########################################################################################"
  read -r -s -p 'Press any key to continue.'

  kubectl scale deployment ${INGRESS_DEPLOYMENT}  --namespace ${INGRESS_NAMESPACE} --replicas=0
  sleep 20   
  kubectl scale deployment ${INGRESS_DEPLOYMENT}  --namespace ${INGRESS_NAMESPACE} --replicas=1

else

  echo "Invalid argument!"
  echo "Usage: ./test_install.sh [install | uninstall | upgrade]"
  exit 1
fi

