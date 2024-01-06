#!/bin/bash
# Github Image Registry PAT
if [ -z "${CODESEALER_TOKEN}" ]; then
  echo "####################################################################################################################"
  echo "#"
  echo "#  Please set CODESEALER_TOKEN variable"
  echo "#"
  echo "#    $ export CODESEALER_TOKEN=<Registry Access Token>"
  echo "#"
  echo "#####################################################################################################################"
  exit 1
fi

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

# Codesealer Public Helm Repo
export CODESEALER_HELM_REPO=https://code-sealer.github.io/helm-charts
export CODESEALER_HELM_CHART=codesealer/codesealer

export CODESEALER_HELM_CNI_REPO=https://code-sealer.github.io/helm-charts
export CODESEALER_HELM_CHART_CNI=codesealer-cni/codesealer-cni

# NGINX Ingress Controller Helm Repo
export INGRESS_HELM_REPO=https://kubernetes.github.io/ingress-nginx
export INGRESS_HELM_CHART=ingress-nginx

# Installation specific  exports
export INGRESS_NAMESPACE=ingress-nginx
export INGRESS_DEPLOYMENT=ingress-nginx-controller
export REDIS_NAMESPACE=redis

# Default settings
INGRESS_PORT=31443
CODESEALER_CNI=false


if [[ "$1" == "install" ]]; then
  # Check which Kubernetes distribution is installed
  echo "########################################################################################"
  echo "#  Codesealer installation script"
  echo "#  "
  echo "#  This script installs Codesealer in one of two possible configurations:"
  echo "#  "
  echo "#     1. As a sidecar to an Ingress Controller for Cloud Native workloads (hybrid)"
  echo "#     2. As Reverse Proxy Layer in front of an Ingress Controller or API Gateway (enterprise)"
  echo "#  "
  echo "#  If you do not have an Ingress Controller installed NGINX Ingress will be installed by default"
  echo "#  "
  echo "#  This installation also will configure your Ingress Controller to operate in one the "
  echo "#  following 2 Kubernetes Ingress Controller service types:"
  echo "#  "
  echo "#     1. NodePort - DEVELOP (default)"
  echo "#        Use for local installations that do not support a LoadBalancer configuration."
  echo "#        This is the default installation mode."
  echo "#     2. LoadBalancer - PROD"
  echo "#        Use on Production implementations or local configurations that support routing"
  echo "#        to local LoadBalancer over port 443.  Some MacBooks using Docker Desktop with"
  echo "#        Kubernetes support this configuration."
  echo "#  "
  echo "########################################################################################"
  read -r -p 'Which Ingress Controller configuration? [DEVELOP/PROD]: '
  if [[ "${REPLY}" == [Pp][Rr][Oo][Dd] ]]; then

    # Set environment
    CODESEALER_ENV=PROD
  
    echo "########################################################################################"
    echo "#  Do you wish to install NGINX Ingress Controller using a LoadBalancer configuration?"
    echo "#  "
    echo "#  Documentation: https://github.com/kubernetes/ingress-nginx/tree/main/charts/ingress-nginx"
    echo "########################################################################################"
    read -r -p 'Install NGINX Ingress Controller on port 443? [y/n]: '
    if [[ "${REPLY}" == 'y' ]]; then
      echo "########################################################################################"
      echo "#  Waiting for NGINX Ingress Controller to start"
      echo "########################################################################################" 
      helm repo add ${INGRESS_HELM_CHART} ${INGRESS_HELM_REPO}
      helm install ${INGRESS_HELM_CHART} ${INGRESS_HELM_CHART}/ingress-nginx \
      --namespace ${INGRESS_NAMESPACE} --create-namespace \
      --wait --timeout=60s

    else
      echo "########################################################################################"
      echo "#  Skipping NGINX Production Ingress Controller installation"
      echo "########################################################################################"
    fi

    # Set Ingress Controller port
    INGRESS_PORT=443

  else

    # Set environment
    CODESEALER_ENV=DEVELOP

    echo "########################################################################################"
    echo "#  Configuring NGINX Ingress Controller using a NodePort configuration?"
    echo "#  "
    echo "#  Documentation: https://github.com/kubernetes/ingress-nginx/tree/main/charts/ingress-nginx"
    echo "########################################################################################"
    read -r -p "Which port do you want NGINX Ingress Controller to use: [${INGRESS_PORT}] "
    if [ -z "${REPLY}" ]; then
      # Set Ingress Controller port
      echo "Using default NodePort: ${INGRESS_PORT}"
    else
      # Set Ingress Controller port
      INGRESS_PORT=${REPLY}
    fi

    read -r -p "Install NGINX Ingress Controller using a NodePort on port ${INGRESS_PORT} [y/n]: "
    if [[ "${REPLY}" == 'y' ]]; then

      echo "########################################################################################"
      echo "#  Waiting for NGINX Ingress Controller to start"
      echo "########################################################################################" 
      helm repo add ${INGRESS_HELM_CHART} ${INGRESS_HELM_REPO}
      # Other Cluster configuration
      helm install ${INGRESS_HELM_CHART} ${INGRESS_HELM_CHART}/ingress-nginx \
      --namespace ${INGRESS_NAMESPACE} --create-namespace \
      --set controller.hostPort.enabled=true \
      --set controller.service.type=NodePort \
      --set controller.service.nodePorts.https=${INGRESS_PORT} \
      --set controller.updateStrategy.rollingUpdate.maxUnavailable=1 \
      --wait --timeout=60s

    # Workaround for `tls: failed to verify certificate: x509: certificate signed by unknown authority` error
    CA=$(kubectl -n ${INGRESS_NAMESPACE} get secret ingress-nginx-admission -ojsonpath='{.data.ca}')
    kubectl patch validatingwebhookconfigurations ingress-nginx-admission --type='json' -p='[{"op": "add", "path": "/webhooks/0/clientConfig/caBundle", "value":"'$CA'"}]'  

    else
      echo "########################################################################################"
      echo "#  Skipping NGINX Development Ingress Controller installation - enter Ingress Controller"
      echo "#  configuration:"
      echo "########################################################################################"
      read -r -p 'Ingress Controller Namespace?: '
      export INGRESS_NAMESPACE="${REPLY}"
      read -r -p 'Ingress Controller Deployment?: '
      export INGRESS_DEPLOYMENT="${REPLY}"
      read -r -p 'Ingress Controller Port?: '
      export INGRESS_PORT="${REPLY}"
    fi

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

    # Get the Redis password from the prior installation
    export REDIS_PASSWORD=$(kubectl get secret --namespace ${REDIS_NAMESPACE} redis -o jsonpath="{.data.redis-password}" | base64 -d)

  else
    echo "########################################################################################"
    echo "# Skipping Redis installation - enter Redis configuration"
    echo "########################################################################################"
    read -r -p 'Redis Namespace?: '
    export REDIS_NAMESPACE="${REPLY}"
    read -r -p 'Redis Password?: '
    export REDIS_PASSWORD="${REPLY}"
  fi

  echo "########################################################################################"
  echo "# Install Codesealer"
  echo "########################################################################################"
  read -r -s -p 'Press any key to continue.'
  echo ""
  # Install Codesealer helm repo
  helm repo add codesealer ${CODESEALER_HELM_REPO}

  echo "########################################################################################"
  echo "# Codesealer installation options:"
  echo "#  "
  echo "#  hybrid (default) - installs Codesealer as a sidecar to an Ingress Controller or service on Kubernetes"
  echo "#  "
  echo "#  enterprise - installs Codesealer as a standalone reverse proxy layer in front of an application"
  echo "#  "
  echo "########################################################################################"
  read -r -p 'Which installation mode for Codesealer? [hybrid/enterprise]: '

  # Check if they want the sample application for testing
  if [[ "${REPLY}" == "enterprise" ]]; then

    export CODESEALER_MODE=${REPLY}

    echo "########################################################################################"
    echo "#  How many Codesealer workers do you want to install?"
    echo "########################################################################################"
    read -r -p 'Number of Codesealer workers?: '
    if [ -z "${REPLY}" ]; then
      # Set the number of Codesealer workers to 1 
      CODESEALER_WORKERS=1
    else
      # Set the number of Codesealer workers from the input
      CODESEALER_WORKERS=${REPLY}
    fi

    # Start Codesealer in `enterprise` mode
    helm install codesealer ${CODESEALER_HELM_CHART} \
      --create-namespace --namespace codesealer-system \
      --set codesealerToken="${CODESEALER_TOKEN}" \
      --set worker.ingress.namespace="${INGRESS_NAMESPACE}" \
      --set worker.ingress.deployment="${INGRESS_DEPLOYMENT}" \
      --set worker.ingress.port="${INGRESS_PORT}" \
      --set worker.redis.namespace="${REDIS_NAMESPACE}" \
      --set worker.config.bootloader.redisPassword="${REDIS_PASSWORD}" \
      --set environment="${CODESEALER_ENV}" \
      --set worker.replicaCount="${CODESEALER_WORKERS}" \
      --set manager.enabled=true \
      --wait --timeout=60s

  else

    export CODESEALER_MODE="hybrid"

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

      echo "########################################################################################"
      echo "#  To access Juice Shop application:"
      echo "#  "
      echo "#  https://localhost:${INGRESS_PORT}"
      echo "########################################################################################"

    else
      echo "########################################################################################"
      echo "#  Skipping Juice Shop installation"
      echo "########################################################################################"
    fi

    echo "########################################################################################"
    echo "# Redis password: ${REDIS_PASSWORD}"
    echo "# "
    echo "# Waiting for Codesealer to start in ${CODESEALER_MODE} mode"
    echo "########################################################################################"

    # Start Codesealer in `hybrid` mode
    if [[ ${CODESEALER_CNI} == true ]]; then
      # Use Codesealer CNI to pre-route traffic
      helm install codesealer ${CODESEALER_HELM_CHART} \
        --create-namespace --namespace codesealer-system \
        --set codesealerToken="${CODESEALER_TOKEN}" \
        --set worker.ingress.namespace="${INGRESS_NAMESPACE}" \
        --set worker.ingress.deployment="${INGRESS_DEPLOYMENT}" \
        --set worker.ingress.port="${INGRESS_PORT}" \
        --set worker.redis.namespace="${REDIS_NAMESPACE}" \
        --set worker.config.bootloader.redisPassword="${REDIS_PASSWORD}" \
        --set initContainers.enabled=false \
        --set environment="${CODESEALER_ENV}" \
        --wait --timeout=60s

      echo "########################################################################################"
      echo "#  Installing Codesealer CNI"
      echo "########################################################################################"
      helm repo add codesealer-cni ${CODESEALER_HELM_CNI_REPO}
      helm install codesealer-cni ${CODESEALER_HELM_CHART_CNI} --namespace kube-system

    else
      # Use Codesealer init-container to pre-route traffic
      helm install codesealer ${CODESEALER_HELM_CHART} \
        --create-namespace --namespace codesealer-system \
        --set codesealerToken="${CODESEALER_TOKEN}" \
        --set worker.ingress.namespace="${INGRESS_NAMESPACE}" \
        --set worker.ingress.deployment="${INGRESS_DEPLOYMENT}" \
        --set worker.ingress.port="${INGRESS_PORT}" \
        --set worker.redis.namespace="${REDIS_NAMESPACE}" \
        --set worker.config.bootloader.redisPassword="${REDIS_PASSWORD}" \
        --set environment="${CODESEALER_ENV}" \
        --wait --timeout=60s
    fi

    echo "########################################################################################"
    echo "#  Activate Codesealer by applying labels and annotations:"
    echo "# "
    echo "# $ kubectl label ns ${INGRESS_NAMESPACE} codesealer.com/webhook=enabled"
    echo "# "
    echo "# $ kubectl patch deployment ${INGRESS_DEPLOYMENT} -n ${INGRESS_NAMESPACE} \ "
    echo "#   -p '{"spec": {"template":{"metadata":{"annotations":{"codesealer.com/injection":"enabled", "codesealer.com/dport":"'${INGRESS_PORT}'"}}}} }'"
    echo "# "
    echo "########################################################################################"
    read -r -s -p 'Press any key to continue.'

    kubectl label ns "${INGRESS_NAMESPACE}" codesealer.com/webhook=enabled
    kubectl patch deployment "${INGRESS_DEPLOYMENT}" -n "${INGRESS_NAMESPACE}" \
      -p '{"spec": {"template":{"metadata":{"annotations":{"codesealer.com/injection":"enabled", "codesealer.com/dport":"'${INGRESS_PORT}'"}}}} }'

    sleep 10
    echo "########################################################################################"
    echo "#  Current status of NGINX Ingress Controller"
    echo "########################################################################################"
    kubectl get pods --namespace "${INGRESS_NAMESPACE}"

    echo "########################################################################################"
    echo "#  Restart NGINX Ingress Controller - only necessary if the patch did not trigger the"
    echo "#  restart"
    echo "########################################################################################"
    read -r -p 'Restart Ingress Controller? [y/n]: '
    if [[ "${REPLY}" == 'y' ]]; then

      if [[ "${CODESEALER_ENV}" == "DEVELOP" ]]; then
        # Use force delete instead
        kubectl scale deployment "${INGRESS_DEPLOYMENT}" --namespace "${INGRESS_NAMESPACE}" --replicas=0
        sleep 5
        POD=$(kubectl get pods -n ${INGRESS_NAMESPACE} | grep controller | cut -d " " -f1 | tail -n 1 )
        echo "Deleting pod: ${POD} in namespace ${INGRESS_NAMESPACE}"
        kubectl delete pod "${POD}" --namespace "${INGRESS_NAMESPACE}" --force
        sleep 10
        kubectl scale deployment "${INGRESS_DEPLOYMENT}" --namespace "${INGRESS_NAMESPACE}" --replicas=1
        kubectl get pods --namespace "${INGRESS_NAMESPACE}"
      else
        kubectl rollout restart deployment/"${INGRESS_DEPLOYMENT}" --namespace "${INGRESS_NAMESPACE}"
        echo "########################################################################################"
        echo "#  Waiting for NGINX Ingress Controller to restart"
        echo "########################################################################################"  
        kubectl rollout status deployment/"${INGRESS_DEPLOYMENT}" --namespace "${INGRESS_NAMESPACE}" --watch
      fi

    else
      echo "########################################################################################"
      echo "#  Skipping Ingress Controller Restart"
      echo "########################################################################################"
      kubectl get pods --namespace "${INGRESS_NAMESPACE}"
    fi

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
    helm uninstall ${INGRESS_HELM_CHART} --namespace ${INGRESS_NAMESPACE}
    helm repo remove ${INGRESS_HELM_CHART}
    sleep 5
    POD=$(kubectl get pods -n ${INGRESS_NAMESPACE} | grep controller | cut -d " " -f1 | tail -n 1 )
    echo "Deleting pod: ${POD} in namespace ${INGRESS_NAMESPACE}"
    kubectl delete pod "${POD}" --namespace "${INGRESS_NAMESPACE}" --force
    kubectl delete namespace ${INGRESS_NAMESPACE} --force --grace-period=0
  else
    echo "########################################################################################"
    echo "#  Skipping NGINX Ingress Controller uninstall"
    echo "########################################################################################"
  fi

elif [[ "$1" == "upgrade" ]]; then
  # Get the Redis password
  export REDIS_PASSWORD=$(kubectl get secret --namespace ${REDIS_NAMESPACE} redis -o jsonpath="{.data.redis-password}" | base64 -d)
  helm repo update codesealer

  echo "########################################################################################"
  echo "#  Upgrading Codesealer Release"
  echo "########################################################################################"
  read -r -p 'Which installation mode for Codesealer [hybrid/enterprise]: '
  # Check if they want the sample application for testing
  if [[ "${REPLY}" == "enterprise" ]]; then

    export CODESEALER_MODE="${REPLY}"

    echo "########################################################################################"
    echo "#  How many Codesealer workers do you want to install?"
    echo "########################################################################################"
    read -r -p 'Number of Codesealer workers?: '
    if [ -z "${REPLY}" ]; then
      # Set the number of Codesealer workers to 1 
      CODESEALER_WORKERS=1
    else
      # Set the number of Codesealer workers from the input
      CODESEALER_WORKERS=${REPLY}
    fi

    # Start Codesealer in `enterprise` mode
    helm upgrade codesealer ${CODESEALER_HELM_CHART} \
      --create-namespace --namespace codesealer-system \
      --set codesealerToken="${CODESEALER_TOKEN}" \
      --set worker.ingress.namespace="${INGRESS_NAMESPACE}" \
      --set worker.ingress.deployment="${INGRESS_DEPLOYMENT}" \
      --set worker.ingress.port="${INGRESS_PORT}" \
      --set worker.redis.namespace="${REDIS_NAMESPACE}" \
      --set worker.config.bootloader.redisPassword="${REDIS_PASSWORD}" \
      --set environment="${CODESEALER_ENV}" \
      --set worker.replicaCount="${CODESEALER_WORKERS}" \
      --set manager.enabled=true \
      --wait --timeout=60s

  else

    export CODESEALER_MODE="hybrid"

    echo "########################################################################################"
    echo "# Redis password: ${REDIS_PASSWORD}"
    echo "# "
    echo "# Waiting for Codesealer to start in ${CODESEALER_MODE} mode"
    echo "########################################################################################"

    # Start Codesealer in `hybrid` mode
    if [[ ${CODESEALER_CNI} == true ]]; then
      # Use Codesealer CNI to pre-route traffic
      helm upgrade codesealer ${CODESEALER_HELM_CHART} \
        --namespace codesealer-system \
        --set codesealerToken="${CODESEALER_TOKEN}" \
        --set worker.ingress.namespace="${INGRESS_NAMESPACE}" \
        --set worker.ingress.deployment="${INGRESS_DEPLOYMENT}" \
        --set worker.ingress.port="${INGRESS_PORT}" \
        --set worker.redis.namespace="${REDIS_NAMESPACE}" \
        --set worker.config.bootloader.redisPassword="${REDIS_PASSWORD}" \
        --set initContainers.enabled=false \
        --set environment="${CODESEALER_ENV}" \
        --wait --timeout=60s

      echo "########################################################################################"
      echo "#  Installing Codesealer CNI"
      echo "########################################################################################"
      helm repo add codesealer-cni ${CODESEALER_HELM_CNI_REPO}
      helm install codesealer-cni ${CODESEALER_HELM_CHART_CNI} --namespace kube-system

    else
      # Use Codesealer init-container to pre-route traffic
      helm upgrade codesealer ${CODESEALER_HELM_CHART} \
        --namespace codesealer-system \
        --set codesealerToken="${CODESEALER_TOKEN}" \
        --set worker.ingress.namespace="${INGRESS_NAMESPACE}" \
        --set worker.ingress.deployment="${INGRESS_DEPLOYMENT}" \
        --set worker.ingress.port="${INGRESS_PORT}" \
        --set worker.redis.namespace="${REDIS_NAMESPACE}" \
        --set worker.config.bootloader.redisPassword="${REDIS_PASSWORD}" \
        --set environment="${CODESEALER_ENV}" \
        --wait --timeout=60s
    fi

    echo "########################################################################################"
    echo "#  Activate Codesealer by applying labels and annotations:"
    echo "# "
    echo "# $ kubectl label ns ${INGRESS_NAMESPACE} codesealer.com/webhook=enabled"
    echo "# "
    echo "# $ kubectl patch deployment ${INGRESS_DEPLOYMENT} -n ${INGRESS_NAMESPACE} \ "
    echo "#   -p '{"spec": {"template":{"metadata":{"annotations":{"codesealer.com/injection":"enabled", "codesealer.com/dport":"'${INGRESS_PORT}'"}}}} }'"
    echo "# "
    echo "########################################################################################"
    read -r -s -p 'Press any key to continue.'

    kubectl label ns ${INGRESS_NAMESPACE} codesealer.com/webhook=enabled
    kubectl patch deployment ${INGRESS_DEPLOYMENT} -n ${INGRESS_NAMESPACE} \
      -p '{"spec": {"template":{"metadata":{"annotations":{"codesealer.com/injection":"enabled", "codesealer.com/dport":"'${INGRESS_PORT}'"}}}} }'

    sleep 10
    echo "########################################################################################"
    echo "#  Current status of NGINX Ingress Controller"
    echo "########################################################################################"
    kubectl get pods --namespace "${INGRESS_NAMESPACE}"

    echo "########################################################################################"
    echo "#  Restart NGINX Ingress Controller - only necessary if the patch did not trigger the"
    echo "#  restart"
    echo "########################################################################################"
    read -r -p 'Restart Ingress Controller? [y/n]: '
    if [[ "${REPLY}" == 'y' ]]; then

      if [[ "${CODESEALER_ENV}" == "DEVELOP" ]]; then
        # Use force delete instead
        kubectl scale deployment "${INGRESS_DEPLOYMENT}" --namespace "${INGRESS_NAMESPACE}" --replicas=0
        sleep 5
        POD=$(kubectl get pods -n ${INGRESS_NAMESPACE} | grep controller | cut -d " " -f1 | tail -n 1 )
        echo "Deleting pod: ${POD} in namespace ${INGRESS_NAMESPACE}"
        kubectl delete pod "${POD}" --namespace "${INGRESS_NAMESPACE}" --force
        sleep 10
        kubectl scale deployment "${INGRESS_DEPLOYMENT}" --namespace "${INGRESS_NAMESPACE}" --replicas=1
        kubectl get pods --namespace "${INGRESS_NAMESPACE}"
      else
        kubectl rollout restart deployment/${INGRESS_DEPLOYMENT} --namespace ${INGRESS_NAMESPACE}
        echo "########################################################################################"
        echo "#  Waiting for NGINX Ingress Controller to restart"
        echo "########################################################################################"  
        kubectl rollout status deployment/${INGRESS_DEPLOYMENT} --namespace ${INGRESS_NAMESPACE} --watch
      fi

    else
      echo "########################################################################################"
      echo "#  Skipping Ingress Controller Restart"
      echo "########################################################################################"
      kubectl get pods --namespace ${INGRESS_NAMESPACE}
    fi

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
