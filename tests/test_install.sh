#!/bin/bash
set -ueo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "####################################################################################################################"
  echo "#"
  echo "#  Usage: ./test_install.sh [install | uninstall | upgrade]"
  echo "#"
  echo "####################################################################################################################"
  exit 1
fi

clear

# Github Image Registry PAT
if [ -z "${CODESEALER_TOKEN}" ]; then 
  echo "####################################################################################################################"
  echo "#"
  echo "#  Please set CODESEALER_TOKEN variable"
  echo "#"
  echo "#    $ export CODESEALER_TOKEN=<Registry Access Token>"
  echo "#"
  echo "####################################################################################################################"
fi

# Public Helm Repo
export CODESEALER_HELM_REPO=https://raw.githubusercontent.com/tfarinacci/codesealer-helm/main/
export CODESEALER_HELM_CHART=codesealer/codesealer

# Installation specific  exports
export INGRESS_NAMESPACE=ingress-nginx
export INGRESS_DEPLOYMENT=ingress-nginx-controller
export INGRESS_PORT=443
export REDIS_NAMESPACE=redis

if [[ "$1" == "install" ]]; then
  echo "########################################################################################"
  echo "#  Do you wish to install NGINX Ingress Controller to access the OWASP Juice Shop Application?"
  echo "#  "
  echo "#  Documentation: https://github.com/kubernetes/ingress-nginx/tree/main/charts/ingress-nginx"
  echo "########################################################################################"
  read -r -p 'Install NGINX Ingress Controller [y/n]: '
  if [[ "${REPLY}" == 'y' ]]; then
    echo "########################################################################################"
    echo "#  Waiting for NGINX Ingress Controller to start"
    echo "########################################################################################"      

    helm upgrade --install ingress-nginx ingress-nginx \
    --repo https://kubernetes.github.io/ingress-nginx \
    --namespace ${INGRESS_NAMESPACE} --create-namespace \
    --set controller.updateStrategy.rollingUpdate.maxUnavailable=1  \
    --set controller.hostPort.enabled=true \
    --wait --timeout=60s
  else
    echo "########################################################################################"
    echo "#  Skipping NGINX Ingress Controller installation"
    echo "########################################################################################"
  fi

  echo "########################################################################################"
  echo "#  Install OWASP Juice Shop Application"
  echo "#  "
  echo "#  Documentation: https://artifacthub.io/packages/helm/securecodebox/juice-shop"
  echo "########################################################################################"
  read -r -p 'Install OWASP Juice Shop [y/n]: '

  if [[ "${REPLY}" == 'y' ]]; then
    helm repo add securecodebox https://charts.securecodebox.io/

    echo "########################################################################################"
    echo "#  Waiting for Juice Shop to start"
    echo "########################################################################################"      

    helm install juice-shop securecodebox/juice-shop --namespace juice-shop --create-namespace \
      --set ingress.enabled=true \
      --set "ingress.hosts[0].host=localhost,ingress.hosts[0].paths[0].path=/" \
      --set "ingress.tls[0].hosts[0]=localhost,ingress.tls[0].secretName=" \
      --set ingress.pathType=Prefix \
      --wait --timeout=60s
  else
    echo "########################################################################################"
    echo "#  Skipping Juice Shop installation"
    echo "########################################################################################"
  fi

  echo "########################################################################################"
  echo "#  Do you wish to install Redis?"
  echo "#  "
  echo "#   This is required by Codesealer.  Either use this installation helm chart"
  echo "#   or follow the Codesealer documentation to install your own version"
  echo "#  "
  echo "#   -- Using github.com/bitnami/charts repository"
  echo "#      Documentation: https://github.com/bitnami/charts/blob/main/bitnami/redis/README.md"
  echo "########################################################################################"
  read -r -p 'Install Redis in single master mode [y/n]: '
  if [[ "${REPLY}" == 'y' ]]; then

    echo "########################################################################################"
    echo "#  Waiting for Redis to start"
    echo "########################################################################################"      
    helm install redis oci://registry-1.docker.io/bitnamicharts/redis \
    --namespace ${REDIS_NAMESPACE} --create-namespace \
    --set auth.enabled=true \
    --set replica.replicaCount=1 \
    --wait --timeout=60s
  else
    echo "########################################################################################"
    echo "# Skipping Redis installation"
    echo "########################################################################################"
  fi

  echo "########################################################################################"
  echo "# Install Codesealer"
  echo "########################################################################################"
  read -r -s -p 'Press any key to continue.'
  # Install Codesealer helm repo
  helm repo add codesealer ${CODESEALER_HELM_REPO}

  # Get the Redis password
  export REDIS_PASSWORD=$(kubectl get secret --namespace ${REDIS_NAMESPACE} redis -o jsonpath="{.data.redis-password}" | base64 -d)
  read -r -p 'Which installation mode for Codesealer [hybrid/standalone]: '
  echo "########################################################################################"
  echo "# Redis password: ${REDIS_PASSWORD}"
  echo "# "
  echo "# Waiting for Codesealer to startin ${REPLY} mode"
  echo "########################################################################################"
  if [[ "${REPLY}" == "hybrid" ]]; then
    # Start Codesealer in `hybrid` mode
    helm install codesealer ${CODESEALER_HELM_CHART} --create-namespace --namespace codesealer-system \
      --set codesealerToken="${CODESEALER_TOKEN}" \
      --set worker.ingress.namespace=${INGRESS_NAMESPACE} \
      --set worker.ingress.deployment=${INGRESS_DEPLOYMENT} \
      --set worker.ingress.port=${INGRESS_PORT} \
      --set worker.config.bootloader.redisPassword="${REDIS_PASSWORD}" \
      --wait --timeout=90s

    echo "########################################################################################"
    echo "#  Activate Codesealer by applying labels and annotations:"
    echo "# "
    echo "# $ kubectl label ns ${INGRESS_NAMESPACE} codesealer.com/webhook=enabled"
    echo "# "
    echo "# $ kubectl patch deployment ${INGRESS_DEPLOYMENT} -n ${INGRESS_NAMESPACE} -p '{"spec": {"template":{"metadata":{"annotations":{"codesealer.com/injection":"enabled"}}}} }'"
    echo "# "
    echo "########################################################################################"
    read -r -s -p 'Press any key to continue.'

    kubectl label ns ${INGRESS_NAMESPACE} codesealer.com/webhook=enabled
    kubectl patch deployment ${INGRESS_DEPLOYMENT} -n ${INGRESS_NAMESPACE} -p '{"spec": {"template":{"metadata":{"annotations":{"codesealer.com/injection":"enabled"}}}} }'
    
    echo "########################################################################################"
    echo "#  Restart NGINX Ingress Controller"
    echo "########################################################################################"
    read -r -s -p 'Press any key to continue.'

    kubectl rollout restart deployment/${INGRESS_DEPLOYMENT} --namespace ${INGRESS_NAMESPACE}
    echo "########################################################################################"
    echo "#  Waiting for NGINX Ingress Controller to restart"
    echo "########################################################################################"  
    kubectl rollout status deployment/${INGRESS_DEPLOYMENT} --namespace ${INGRESS_NAMESPACE} --watch

  elif [[ "${REPLY}" == "standalone" ]]; then
    # Start Codesealer in `standalone` mode
    helm install codesealer ${CODESEALER_HELM_CHART} --create-namespace --namespace codesealer-system \
      --set codesealerToken="${CODESEALER_TOKEN}" \
      --set worker.ingress.namespace=${INGRESS_NAMESPACE} \
      --set worker.ingress.deployment=${INGRESS_DEPLOYMENT} \
      --set worker.ingress.port=${INGRESS_PORT} \
      --set worker.config.bootloader.redisPassword="${REDIS_PASSWORD}" \
      --set worker.config.bootloader.fsEndpoints=false \
      --set manager.enabled=true \
      --set ingress.enabled=true \
      --wait --timeout=90s
  else
    echo "####################################################################################################################"
    echo "#  Invalid arguement!"
    echo "#  Must specify: [hybrid | standalone]"
    echo "####################################################################################################################"
    exit 1
  fi

elif [[ "$1" == "uninstall" ]]; then
  echo "########################################################################################"
  echo "#  Uninstall Codesealer"
  echo "########################################################################################"
  helm uninstall codesealer --namespace codesealer-system
  helm repo remove codesealer
  kubectl delete namespace codesealer-system

  echo "########################################################################################"
  echo "#  Do you wish to uninstall OWASP Juice Shop Application?"
  echo "########################################################################################"
  read -r -p 'Uninstall OWASP Juice Shop [y/n]: '
  if [[ "${REPLY}" == 'y' ]]; then
    helm uninstall juice-shop --namespace juice-shop
    helm repo remove securecodebox
    kubectl delete namespace juice-shop
  else
    echo "########################################################################################"
    echo "#  Skipping Juice Shop uninstall"
    echo "########################################################################################"
  fi

  echo "########################################################################################"
  echo "#  Do you wish to uninstall Redis?"
  echo "########################################################################################"
  read -r -p 'Uninstall Redis [y/n]: '
  if [ "${REPLY}" == 'y' ]; then
    helm uninstall redis --namespace redis 
    kubectl delete namespace redis
  else
    echo "########################################################################################"
    echo "#  Skipping Redis uninstall"
    echo "########################################################################################"
  fi

  echo "########################################################################################"
  echo "#  Do you wish to uninstall NGINX Ingress Controller?"
  echo "########################################################################################"
  read -r -p 'Uninstall NGINX Ingress Controller [y/n]: '
  if [ "${REPLY}" == 'y' ]; then
    helm uninstall ingress-nginx --namespace ${INGRESS_NAMESPACE}
    kubectl delete namespace ${INGRESS_NAMESPACE}
  else
    echo "########################################################################################"
    echo "#  Skipping NGINX Ingress Controller uninstall"
    echo "########################################################################################"
  fi

elif [[ "$1" == "upgrade" ]]; then
  # Get the Redis password
  export REDIS_PASSWORD=$(kubectl get secret --namespace ${REDIS_NAMESPACE} redis -o jsonpath="{.data.redis-password}" | base64 -d)

  read -r -p 'Which installation mode for Codesealer [hybrid/standalone]: '
  echo "########################################################################################"
  echo "#  Upgrade Codesealer Release"
  echo "########################################################################################"
  helm repo update codesealer
  if [[ "${REPLY}" == "hybrid" ]]; then
    helm upgrade codesealer ${CODESEALER_HELM_CHART} --namespace codesealer-system \
      --set codesealerToken="${CODESEALER_TOKEN}" \
      --set worker.ingress.namespace=${INGRESS_NAMESPACE} \
      --set worker.ingress.deployment=${INGRESS_DEPLOYMENT} \
      --set worker.ingress.port=${INGRESS_PORT} \
      --set worker.config.bootloader.redisPassword="${REDIS_PASSWORD}" \
      --wait --timeout=90s

    echo "########################################################################################"
    echo "#  Upgrade Codesealer"
    echo "########################################################################################"
    read -r -s -p 'Press any key to continue.'
    kubectl rollout restart deployments --namespace codesealer-system
    echo "########################################################################################"
    echo "#  Waiting for Codesealer to restart"
    echo "########################################################################################"  
    kubectl rollout status deployments --namespace codesealer-system --watch

    echo "########################################################################################"
    echo "#  Upgrade Codesealer Worker Sidecar for NGINX Ingress Controller"
    echo "########################################################################################"
    read -r -s -p 'Press any key to continue.'

    kubectl rollout restart deployment/${INGRESS_DEPLOYMENT} --namespace ${INGRESS_NAMESPACE}
    echo "########################################################################################"
    echo "#  Waiting for NGINX Ingress Controller to restart"
    echo "########################################################################################"  
    kubectl rollout status deployment/${INGRESS_DEPLOYMENT} --namespace ${INGRESS_NAMESPACE} --watch

  elif [[ "${REPLY}" == "standalone" ]]; then
    helm upgrade codesealer ${CODESEALER_HELM_CHART} --namespace codesealer-system \
      --set codesealerToken="${CODESEALER_TOKEN}" \
      --set worker.ingress.namespace=${INGRESS_NAMESPACE} \
      --set worker.ingress.deployment=${INGRESS_DEPLOYMENT} \
      --set worker.ingress.port=${INGRESS_PORT} \
      --set worker.config.bootloader.redisPassword="${REDIS_PASSWORD}" \
      --set worker.config.bootloader.fsEndpoints=false \
      --set manager.enabled=true \
      --set ingress.enabled=true \
      --wait --timeout=90s
  else
    echo "####################################################################################################################"
    echo "#  Invalid arguement!"
    echo "#  Must specify: [hybrid | standalone]"
    echo "####################################################################################################################"
    exit 1
  fi

else
  echo "####################################################################################################################"
  echo "#"
  echo "#  Invalid arguement!"
  echo "#"
  echo "#  Usage: ./test_install.sh [install | uninstall | upgrade]"
  echo "#"
  echo "####################################################################################################################"
  exit 1
fi
