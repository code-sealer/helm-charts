#!/bin/bash
set -ueo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "##+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+"
  echo "##"
  echo "##  Usage: ./test_install.sh [install | uninstall | upgrade]"
  echo "##"
  echo "##+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+"
  exit 1
fi

clear

# Github Image Registry PAT
# $CODESEALER_TOKEN=

# Public Helm Repo
export CODESEALER_HELM_REPO=https://code-sealer.github.io/helm-charts
export CODESEALER_HELM_CHART=codesealer/codesealer

# Version of release
export RELEASE_VER="1"

# Installation specific  exports
export INGRESS_NAMESPACE=ingress-nginx
export INGRESS_DEPLOYMENT=ingress-nginx-${RELEASE_VER}-controller
export INGRESS_PORT=443
export REDIS_NAMESPACE=redis

if [[ "$1" == "install" ]]; then

  echo "########################################################################################"
  echo "#  Do you wish to install NGINX Ingress Controller to access the OWASP Juice Shop Application?"
  echo "#  "
  echo "#  Documentation: https://github.com/kubernetes/ingress-nginx/tree/main/charts/ingress-nginx"
  echo "########################################################################################"
  read -r -p 'Install NGINX Ingress Controller [y/n]: '
  if [[ ${REPLY} == 'y' ]]; then
    echo "########################################################################################"
    echo "#  Waiting for NGINX Ingress Controller to start"
    echo "########################################################################################"      

    helm upgrade --install ingress-nginx-${RELEASE_VER} ingress-nginx \
    --repo https://kubernetes.github.io/ingress-nginx \
    --namespace ${INGRESS_NAMESPACE} --create-namespace \
    --set controller.hostPort.enabled=true \
    --set controller.service.type=LoadBalancer \
    --set controller.publishService.enabled=false \
    --set controller.extraArgs.publish-status-address=localhost \
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

  if [[ ${REPLY} == 'y' ]]; then
    helm repo add securecodebox https://charts.securecodebox.io/

    echo "########################################################################################"
    echo "#  Waiting for Juice Shop to start"
    echo "########################################################################################"      

    helm install juice-shop-${RELEASE_VER} securecodebox/juice-shop --namespace juice-shop --create-namespace \
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
  if [[ ${REPLY} == 'y' ]]; then

    echo "########################################################################################"
    echo "#  Waiting for Redis to start"
    echo "########################################################################################"      
    helm install redis-${RELEASE_VER} oci://registry-1.docker.io/bitnamicharts/redis \
    --namespace ${REDIS_NAMESPACE} --create-namespace \
    --set auth.enabled=true \
    --set replica.replicaCount=1 \
    --wait --timeout=60s

    # --set sentinel.enabled=false \
    # --set auth.sentinel=false \

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
  export REDIS_PASSWORD=$(kubectl get secret --namespace ${REDIS_NAMESPACE} redis-${RELEASE_VER} -o jsonpath="{.data.redis-password}" | base64 -d)
  echo "########################################################################################"
  echo "# Redis password: ${REDIS_PASSWORD}"
  echo "# "
  echo "# Waiting for Codesealer to start"
  echo "########################################################################################"      
  helm install codesealer-${RELEASE_VER} ${CODESEALER_HELM_CHART} --create-namespace --namespace codesealer-system \
    --set codesealerToken=${CODESEALER_TOKEN} \
    --set worker.ingress.namespace=${INGRESS_NAMESPACE} \
    --set worker.ingress.deployment=${INGRESS_DEPLOYMENT} \
    --set worker.ingress.port=${INGRESS_PORT} \
    --set image.pullPolicy=Always \
    --set worker.redis.service.name=redis-${RELEASE_VER}-master \
    --set worker.config.bootloader.redisUser=default \
    --set worker.config.bootloader.redisPassword=${REDIS_PASSWORD} \
    --set worker.config.bootloader.redisUseTLS=false \
    --set worker.config.bootloader.redisIgnoreTLS=true \
    --set worker.config.endpoint.wafMonitorMode=false \
    --set worker.config.endpoint.enableWaf=true \
    --set worker.config.endpoint.wafFullTransaction=true \
    --set worker.config.endpoint.crs.paranoiaLevel=1 \
    --wait --timeout=90s

    # --set worker.config.endpoint.hostScheme=https \
    # --set worker.config.endpoint.hostname=localhost \
    # --set worker.redis.namespace=codesealer-system \
    # --set ingress.namespace=codesealer-system \
    # --set ingress.enabled=true \
    # --set "ingress.tls[0].hosts[0]=core-manager.local,ingress.tls[0].secretName=ingress-tls" \
    # --set "ingress.hosts[0].host=core-manager.local,ingress.hosts[0].paths[0].path=/,ingress.hosts[0].paths[0].pathType=Prefix"

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
  echo "# "
  kubectl patch deployment ${INGRESS_DEPLOYMENT} -n ${INGRESS_NAMESPACE} -p '{"spec": {"template":{"metadata":{"annotations":{"codesealer.com/injection":"enabled"}}}} }'
  
  echo "########################################################################################"
  echo "#  Restart NGINX Ingress Controller"
  echo "########################################################################################"
  read -r -s -p 'Press any key to continue.'

  kubectl scale deployment ${INGRESS_DEPLOYMENT}  --namespace ${INGRESS_NAMESPACE} --replicas=0
  echo "########################################################################################"
  echo "#  Waiting for NGINX Ingress Controller to restart"
  echo "########################################################################################"  
  sleep 20   
  kubectl scale deployment ${INGRESS_DEPLOYMENT}  --namespace ${INGRESS_NAMESPACE} --replicas=1

elif [[ "$1" == "uninstall" ]]; then

  echo "########################################################################################"
  echo "#  Uninstall Codesealer"
  echo "########################################################################################"
  helm uninstall codesealer-${RELEASE_VER} --namespace codesealer-system
  helm repo remove codesealer
  kubectl delete namespace codesealer-system

  echo "########################################################################################"
  echo "#  Do you wish to uninstall OWASP Juice Shop Application?"
  echo "########################################################################################"
  read -r -p 'Uninstall OWASP Juice Shop [y/n]: '
  if [[ ${REPLY} == 'y' ]]; then
    helm uninstall juice-shop-${RELEASE_VER} --namespace juice-shop
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
  if [ $REPLY == 'y' ]; then
    helm uninstall redis-${RELEASE_VER} --namespace redis 
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
  if [ $REPLY == 'y' ]; then
    helm uninstall ingress-nginx-${RELEASE_VER} --namespace ${INGRESS_NAMESPACE}
    # kubectl delete namespace ${INGRESS_NAMESPACE}
  else
    echo "########################################################################################"
    echo "#  Skipping NGINX Ingress Controller uninstall"
    echo "########################################################################################"
  fi

elif [[ "$1" == "upgrade" ]]; then

  # Get the Redis password
  export REDIS_PASSWORD=$(kubectl get secret --namespace ${REDIS_NAMESPACE} redis -o jsonpath="{.data.redis-password}" | base64 -d)

  echo "########################################################################################"
  echo "#  Upgrade Codesealer Release"
  echo "########################################################################################"
  helm repo update codesealer
  helm upgrade codesealer-${RELEASE_VER} ${CODESEALER_HELM_CHART} --namespace codesealer-system \
    --set codesealerToken=${CODESEALER_TOKEN} \
    --set worker.ingress.namespace=${INGRESS_NAMESPACE} \
    --set worker.ingress.deployment=${INGRESS_DEPLOYMENT} \
    --set worker.ingress.port=${INGRESS_PORT} \
    --set worker.redis.service.name=redis-${RELEASE_VER}-master \
    --set worker.config.bootloader.redisUser=default \
    --set worker.config.bootloader.redisPassword=${REDIS_PASSWORD} \
    --set worker.config.bootloader.redisUseTLS=false \
    --set worker.config.bootloader.redisIgnoreTLS=true \
    --set worker.config.endpoint.wafMonitorMode=false \
    --set worker.config.endpoint.enableWaf=true \
    --set worker.config.endpoint.wafFullTransaction=true \
    --set worker.config.endpoint.crs.paranoiaLevel=1 \
    --wait --timeout=90s

  echo "########################################################################################"
  echo "#  Upgrade Codesealer"
  echo "########################################################################################"
  read -r -s -p 'Press any key to continue.'
  kubectl rollout restart deployments --namespace codesealer-system

  echo "########################################################################################"
  echo "#  Please wait 1 minute..."
  echo "########################################################################################"
  sleep 60

  echo "########################################################################################"
  echo "#  Upgrade Codesealer Worker Sidecar for NGINX Ingress Controller"
  echo "########################################################################################"
  read -r -s -p 'Press any key to continue.'
  # kubectl rollout restart deployments --namespace ${INGRESS_NAMESPACE}
  kubectl scale deployment ${INGRESS_DEPLOYMENT}  --namespace ${INGRESS_NAMESPACE} --replicas=0
  sleep 20   
  kubectl scale deployment ${INGRESS_DEPLOYMENT}  --namespace ${INGRESS_NAMESPACE} --replicas=1

else

  echo "##+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+"
  echo "##"
  echo "##  Invalid arguement!"
  echo "##"
  echo "##  Usage: ./test_install.sh [install | uninstall | upgrade]"
  echo "##"
  echo "##+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+"
  exit 1
fi
