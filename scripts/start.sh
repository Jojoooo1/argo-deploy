#!/bin/bash

DIR="$(cd "$(dirname "$0")" && pwd)"
ARGO_CHART_VERSION="5.51.4"
ARGO_APP_NAME="argocd-helm"
ARGO_HELM_CHART_PATH="https://raw.githubusercontent.com/Jojoooo1/argo-deploy-applications-infra/main/argo-apps/base/argocd-helm.yaml"

DNS_ENV="-local"
DNS_DOMAIN="cloud-diplomats.com"

message() {
  echo -e "\n######################################################################"
  echo "# $1"
  echo "######################################################################"
}

[[ ! -x "$(command -v kubectl)" ]] && echo "kubectl not found, you need to install kubectl" && exit 1
[[ ! -x "$(command -v helm)" ]] && echo "helm not found, you need to install helm" && exit 1
[[ ! -x "$(command -v kustomize)" ]] && echo "kustomize not found, you need to install kustomize" && exit 1
[[ ! -x "$(command -v argocd)" ]] && echo "argocd not found, you need to install argocd-cli" && exit 1

installK3s() {
  [[ -f /usr/local/bin/k3s-uninstall.sh ]] && /usr/local/bin/k3s-uninstall.sh
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.27.4+k3s1" INSTALL_K3S_EXEC="server --write-kubeconfig ~/.kube/k3s-config --write-kubeconfig-mode 666 --disable traefik" sh
  export KUBECONFIG=~/.kube/k3s-config
}

installArgoCD() {
  message ">>> deploying ArgoCD"

  # Install chart
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo update
  helm uninstall $ARGO_APP_NAME
  helm install $ARGO_APP_NAME argo/argo-cd --create-namespace --namespace=argocd --version $ARGO_CHART_VERSION \
    --set fullnameOverride=argocd \
    --set applicationSet.enabled=false \
    --set notifications.enabled=false \
    --set dex.enabled=false \
    --set configs.cm."kustomize\.buildOptions"="--load-restrictor LoadRestrictionsNone" \
    --set configs.cm."timeout\.reconciliation"="10s"

  kubectl -n argocd rollout status deployment/argocd-server
}

setupSelfManagedArgoCD() {
  curl $ARGO_HELM_CHART_PATH | sed "s|\${ARGOCD_ENV_DNS_ENV}|$DNS_ENV|g" | sed "s|\${ARGOCD_ENV_DNS_DOMAIN}|$DNS_DOMAIN|g" | kubectl create -f -
}

syncArgoCD() {
  message ">>> Awaiting ArgoCD to sync..."
  export ARGOCD_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
  until argocd login --core --username admin --password $ARGOCD_PWD --insecure; do :; done
  kubectl config set-context --current --namespace=argocd
  until argocd app sync $ARGO_APP_NAME; do echo "awaiting argocd to be sync..." && sleep 10; done
  kubectl -n argocd rollout status deployment/argocd-repo-server
}

installArgoApplications() {
  local ARGO_DIR="$DIR/../argo"

  message ">>> deploying ArgoCD infra-applications"
  kubectl apply -f $ARGO_DIR/applications-infra.yaml
  kubectl apply -f $ARGO_DIR/applications-observability.yaml
  # kubectl apply -f $ARGO_DIR/applications-data.yaml
  # kubectl apply -f $ARGO_DIR/applications-experimental.yaml
  # kubectl apply -f $ARGO_DIR/applications.yaml
  until argocd app sync argo-apps-infra; do echo "awaiting applications-infra to be sync..." && sleep 10; done
}

deployNginxIngress() {
  message ">>> Deploying nginx-ingress"
  until argocd app sync ingress-nginx-helm; do echo "awaiting ingress-nginx to be deployed..." && sleep 20; done
  export NGINX_INGRESS_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -ojson | jq -r '.status.loadBalancer.ingress[].ip')
}

addUrlToHost() {
  host=$1
  if ! grep -q $host "/etc/hosts"; then
    echo "$NGINX_INGRESS_IP $host" | sudo tee -a /etc/hosts
  fi
}

installK3s
installArgoCD
setupSelfManagedArgoCD
syncArgoCD
installArgoApplications
deployNginxIngress

addUrlToHost "argo$DNS_ENV.$DNS_DOMAIN"
addUrlToHost "apisix$DNS_ENV.$DNS_DOMAIN"
addUrlToHost "identity$DNS_ENV.$DNS_DOMAIN"
addUrlToHost "rabbitmq$DNS_ENV.$DNS_DOMAIN"
addUrlToHost "grafana$DNS_ENV.$DNS_DOMAIN"
addUrlToHost "prometheus$DNS_ENV.$DNS_DOMAIN"
addUrlToHost "alertmanager$DNS_ENV.$DNS_DOMAIN"
addUrlToHost "kafka$DNS_ENV.$DNS_DOMAIN"
addUrlToHost "redpanda$DNS_ENV.$DNS_DOMAIN"
addUrlToHost "conduktor$DNS_ENV.$DNS_DOMAIN"
addUrlToHost "clickhouse$DNS_ENV.$DNS_DOMAIN"
addUrlToHost "api$DNS_ENV.$DNS_DOMAIN"
addUrlToHost "schema-registry$DNS_ENV.$DNS_DOMAIN"
addUrlToHost "debezium-ui$DNS_ENV.$DNS_DOMAIN"
addUrlToHost "debezium$DNS_ENV.$DNS_DOMAIN"

message ">>> argo: http://argo$DNS_ENV.$DNS_DOMAIN - username: 'admin', password: '$ARGOCD_PWD'"
