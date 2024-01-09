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

## set -ueo pipefail

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
## export CODESEALER_HELM_REPO=https://code-sealer.github.io/helm-charts
export CODESEALER_HELM_REPO=https://raw.githubusercontent.com/tfarinacci/codesealer-helm/main/
export CODESEALER_HELM_CHART=codesealer/codesealer

export CODESEALER_HELM_CNI_REPO=https://raw.githubusercontent.com/tfarinacci/codesealer-cni/main/
export CODESEALER_HELM_CHART_CNI=codesealer-cni/codesealer-cni

# NGINX Ingress Controller Helm Repo
export INGRESS_HELM_REPO=https://kubernetes.github.io/ingress-nginx
export INGRESS_HELM_CHART=ingress-nginx

# Installation specific  exports
export INGRESS_NAMESPACE=ingress-nginx
export INGRESS_DEPLOYMENT=ingress-nginx-controller
export REDIS_NAMESPACE=redis

# Default settings
INGRESS_PORT=443
INGRESS_NODEPORT=31443
CODESEALER_NODEPORT=false
CODESEALER_CNI=false


if [[ "$1" == "install" ]]; then

  echo "########################################################################################"
  echo "#  Codesealer installation script"
  echo "#  "
  echo "#  This script installs Codesealer in one of two possible configurations:"
  echo "#  "
  echo "#     1. As a sidecar to an Ingress Controller for Cloud Native workloads (hybrid)"
  echo "#     2. As Reverse Proxy Layer in front of an Ingress Controller or API Gateway (enterprise)"
  echo "#  "
  echo "#  Both configurations leverage a Kubernetes Ingress Controller.  You have the option of using"
  echo "#  an existing Ingress Controller or have one installed for you."
  echo "#  "
  echo "########################################################################################"

  # Tailor installation based on which Kubernetes distribution is installed
  read -r -p 'Are you running Minikube for your Kubernetes Cluster? [y/n]: '
  if [[ "${REPLY}" == [Yy] ]]; then
    echo "########################################################################################"
    echo "#  Minikube configuration:"
    echo "#  "
    echo "#  The installation of the Ingress Controller will be skipped and you must specify the"
    echo "#  the Ingress Controller configuration."
    echo "#  "
    echo "#  1. Enable Ingress on your Minkube Cluster:"
    echo "#       $ minikube addons enable ingress"
    echo "#  2. Run the following command in a separate terminal to provide connectivity to your"
    echo "#     application:"
    echo "#       $ minikube tunnel"
    echo "#  "
    echo "########################################################################################"
  else
    read -r -p 'Would you like to install a Kind Cluster for your Kubernetes Cluster? [y/n]: '
    if [[ "${REPLY}" == [Yy] ]]; then

    cat <<EOF | kind create cluster --config=-
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
EOF

    fi
  fi

  echo "########################################################################################"
  echo "#  Kubernetes Ingress Controller installation options:"
  echo "#  "
  echo "#  The following Kubernetes Ingress Controllers are supported:"
  echo "#  "
  echo "#   1. Minikube Ingress Addon: https://kubernetes.io/docs/tasks/access-application-cluster/ingress-minikube/"
  echo "#   2. NGINX Ingress Controller: https://docs.nginx.com/nginx-ingress-controller/"
  echo "#   3. Contour Ingress Controller: https://projectcontour.io/docs/v1.10.0/"
  echo "#   4. Istio Ingress Gateway: https://istio.io/latest/docs/tasks/traffic-management/ingress/ingress-control/"
  echo "#   5. Public Cloud Ingress Controllers"
  echo "#  "
  echo "#  NOTE: If you are running Minikube you should use the Ingress addon option instead and"
  echo "#        skip this step."
  echo "#  "
  echo "########################################################################################"
  read -r -p 'Do you wish to install the NGINX Ingress Controller on your Kubernetes Cluster? [y/n]: '
  if [[ "${REPLY}" == [Nn] ]]; then
    echo "########################################################################################"
    echo "#  Skipping NGINX Ingress Controller installation - enter existing Ingress"
    echo "#  Controller configuration:"
    echo "########################################################################################"
    read -r -p 'Ingress Controller Namespace? [ingress-nginx]: '
    if [ -z "${REPLY}" ]; then
      export INGRESS_NAMESPACE="${INGRESS_NAMESPACE}"
    else
      export INGRESS_NAMESPACE="${REPLY}"
    fi
    read -r -p 'Ingress Controller Deployment? [ingress-nginx-controller]: '
    if [ -z "${REPLY}" ]; then
      export INGRESS_DEPLOYMENT="${INGRESS_DEPLOYMENT}"
    else
      export INGRESS_DEPLOYMENT="${REPLY}"
    fi
    read -r -p 'Ingress Controller Port? [443]: '
    if [ -z "${REPLY}" ]; then
      export INGRESS_PORT="${INGRESS_PORT}"
    else
      export INGRESS_PORT="${REPLY}"
    fi
  else
    echo "########################################################################################"
    echo "#  Installing NGINX Ingress Controller using Helm Chart"
    echo "#  "
    echo "#  This installation also will configure your NGINX Ingress Controller to operate in one the"
    echo "#  following 2 Kubernetes Ingress Controller service types:"
    echo "#  "
    echo "#     1. LoadBalancer (default)"
    echo "#        Use on Production implementations or local configurations that support routing"
    echo "#        to local LoadBalancer over port 443."  
    echo "#        - MacBooks using Docker Desktop with Kubernetes may support this configuration."
    echo "#        - This configuration works best with a Kubernetes Kind Cluster"
    echo "#     2. NodePort"
    echo "#        Use for local installations that do not support a LoadBalancer configuration."
    echo "#        - Use this configuration if LoadBalancer does not work."
    echo "#  "
    echo "#  Documentation: https://github.com/kubernetes/ingress-nginx/tree/main/charts/ingress-nginx"
    echo "########################################################################################"
    read -r -p 'Install Ingress Controller as LoadBalancer? [y/n]: '
    if [[ "${REPLY}" == [Yy] ]]; then

      # NodePort is disabled
      CODESEALER_NODEPORT=false
    
      helm repo add ${INGRESS_HELM_CHART} ${INGRESS_HELM_REPO}

      read -r -p 'Installing on a Kind Cluster? [y/n]: '
      if [[ "${REPLY}" == [Yy] ]]; then
        echo "########################################################################################"
        echo "#  Waiting for NGINX Ingress Controller to start on Kind Cluster"
        echo "########################################################################################" 
        # Kind Cluster configuration
        helm install ${INGRESS_HELM_CHART} ${INGRESS_HELM_CHART}/ingress-nginx \
        --namespace ${INGRESS_NAMESPACE} --create-namespace \
        --set controller.hostPort.enabled=true \
        --set controller.service.type=NodePort \
        --set controller.service.nodePorts.https=${INGRESS_NODEPORT} \
        --set controller.updateStrategy.rollingUpdate.maxUnavailable=1 \
        --wait --timeout=60s

        # Workaround for `tls: failed to verify certificate: x509: certificate signed by unknown authority` error
        CA=$(kubectl -n ${INGRESS_NAMESPACE} get secret ingress-nginx-admission -ojsonpath='{.data.ca}')
        kubectl patch validatingwebhookconfigurations ingress-nginx-admission --type='json' -p='[{"op": "add", "path": "/webhooks/0/clientConfig/caBundle", "value":"'$CA'"}]'  
      else
        echo "########################################################################################"
        echo "#  Waiting for NGINX Ingress Controller to start"
        echo "########################################################################################"
        # Other Clusters 
        helm install ${INGRESS_HELM_CHART} ${INGRESS_HELM_CHART}/ingress-nginx \
        --namespace ${INGRESS_NAMESPACE} --create-namespace \
        --set controller.service.nodePorts.https=${INGRESS_NODEPORT} \
        --wait --timeout=60s
      fi

    else
      # NodePort is enabled
      CODESEALER_NODEPORT=true

      echo "########################################################################################"
      echo "#  Configuring NGINX Ingress Controller using a NodePort configuration?"
      echo "#  "
      echo "#  Use this configuration for local deploments where a LoadBalancer cannot be exposed."
      echo "#  "
      echo "########################################################################################"
      read -r -p "Which port do you want NGINX Ingress Controller NodePort to use: [${INGRESS_NODEPORT}] "
      if [ -z "${REPLY}" ]; then
        # Set Ingress Controller nodePort
        echo "Using default NodePort: ${INGRESS_NODEPORT}"
        export INGRESS_NODEPORT=${INGRESS_NODEPORT}
      else
        # Set Ingress Controller nodePort
        export INGRESS_NODEPORT=${REPLY}
      fi

      echo "########################################################################################"
      echo "#  Waiting for NGINX Ingress Controller to start"
      echo "########################################################################################" 
      helm repo add ${INGRESS_HELM_CHART} ${INGRESS_HELM_REPO}
      # Other Cluster configuration
      helm install ${INGRESS_HELM_CHART} ${INGRESS_HELM_CHART}/ingress-nginx \
      --namespace ${INGRESS_NAMESPACE} --create-namespace \
      --set controller.hostPort.enabled=true \
      --set controller.service.type=NodePort \
      --set controller.service.nodePorts.https=${INGRESS_NODEPORT} \
      --set controller.updateStrategy.rollingUpdate.maxUnavailable=1 \
      --wait --timeout=60s

      # Workaround for `tls: failed to verify certificate: x509: certificate signed by unknown authority` error
      CA=$(kubectl -n ${INGRESS_NAMESPACE} get secret ingress-nginx-admission -ojsonpath='{.data.ca}')
      kubectl patch validatingwebhookconfigurations ingress-nginx-admission --type='json' -p='[{"op": "add", "path": "/webhooks/0/clientConfig/caBundle", "value":"'$CA'"}]'  
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
  if [[ "${REPLY}" == [Yy] ]]; then

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
      --set ingress.nodePort.enabled="${CODESEALER_NODEPORT}" \
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

    if [[ "${REPLY}" == [Yy] ]]; then
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
      if [[ "${CODESEALER_NODEPORT}" == true ]]; then
        echo "#  https://localhost:${INGRESS_NODEPORT}"
      else
        echo "#  https://localhost:${INGRESS_PORT}"
      fi
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
        --set worker.ingress.nodePort="${INGRESS_NODEPORT}" \
        --set worker.redis.namespace="${REDIS_NAMESPACE}" \
        --set worker.config.bootloader.redisPassword="${REDIS_PASSWORD}" \
        --set initContainers.enabled=false \
        --set ingress.nodePort.enabled="${CODESEALER_NODEPORT}" \
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
        --set worker.ingress.nodePort="${INGRESS_NODEPORT}" \
        --set worker.redis.namespace="${REDIS_NAMESPACE}" \
        --set worker.config.bootloader.redisPassword="${REDIS_PASSWORD}" \
        --set ingress.nodePort.enabled="${CODESEALER_NODEPORT}" \
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
    if [[ "${REPLY}" == [Yy] ]]; then

      read -r -p 'Force restart Ingress Controller? [y/n]: '
      if [[ "${REPLY}" == [Yy] ]]; then
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
  if [[ "${REPLY}" == [Yy] ]]; then
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
  if [[ "${REPLY}" == [Yy] ]]; then
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
  if [[ "${REPLY}" == [Yy] ]]; then
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

  echo "########################################################################################"
  echo "#  Configuring Ingress Controller installation - enter Ingress Controller"
  echo "#  configuration:"
  echo "########################################################################################"
  read -r -p 'Ingress Controller Namespace?: '
  export INGRESS_NAMESPACE="${REPLY}"
  read -r -p 'Ingress Controller Deployment?: '
  export INGRESS_DEPLOYMENT="${REPLY}"
  read -r -p 'Ingress Controller Port?: '
  export INGRESS_PORT="${REPLY}"

  read -r -p 'Which installation mode for Codesealer [hybrid/enterprise]: '
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
      --set ingress.nodePort.enabled="${CODESEALER_NODEPORT}" \
      --set worker.replicaCount="${CODESEALER_WORKERS}" \
      --set manager.enabled=true \
      --wait --timeout=60s

  else

    export CODESEALER_MODE="hybrid"

    read -r -p 'Ingress Controller NodePort?: '
    export INGRESS_NODEPORT="${REPLY}"

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
        --set worker.ingress.nodePort="${INGRESS_NODEPORT}" \
        --set worker.redis.namespace="${REDIS_NAMESPACE}" \
        --set worker.config.bootloader.redisPassword="${REDIS_PASSWORD}" \
        --set initContainers.enabled=false \
        --set ingress.nodePort.enabled="${CODESEALER_NODEPORT}" \
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
        --set worker.ingress.nodePort="${INGRESS_NODEPORT}" \
        --set worker.redis.namespace="${REDIS_NAMESPACE}" \
        --set worker.config.bootloader.redisPassword="${REDIS_PASSWORD}" \
        --set ingress.nodePort.enabled="${CODESEALER_NODEPORT}" \
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
    if [[ "${REPLY}" == [Yy] ]]; then

      read -r -p 'Force restart Ingress Controller? [y/n]: '
      if [[ "${REPLY}" == [Yy] ]]; then
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
