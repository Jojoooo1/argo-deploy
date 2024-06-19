#!/bin/bash

DIR="$(cd "$(dirname "$0")" && pwd)"
K3S_VERSION="v1.30.0+k3s1"
ARGO_CHART_VERSION="7.1.5"
ARGO_APP_NAME="infra-argocd-helm"

# We need to use export to make the variables available in the envsubst command
export ENV="local"
export DNS_ENV="-$ENV"
export DNS_DOMAIN="cloud-diplomats.com"

GITHUB_USER="Jojoooo1"
export GITHUB_REPO="https://github.com/$GITHUB_USER"

ARGO_HELM_CHART_PATH="https://raw.githubusercontent.com/$GITHUB_USER/argo-deploy-applications-infra/main/argo-apps/base/argocd-helm.yaml"

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
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K3S_VERSION INSTALL_K3S_EXEC="server --write-kubeconfig ~/.kube/k3s-config --write-kubeconfig-mode 600 --disable traefik" sh
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
  envsubst <$ARGO_DIR/applications-infra.yaml | kubectl apply -f -
  envsubst <$ARGO_DIR/applications-observability.yaml | kubectl apply -f -
  envsubst <$ARGO_DIR/applications-cloud-diplomats.yaml | kubectl apply -f -
  # envsubst <$ARGO_DIR/applications-data.yaml | kubectl apply -f -
  # envsubst <$ARGO_DIR/applications-experimental.yaml | kubectl apply -f -

  until argocd app sync argo-apps-observability; do echo "awaiting applications-observability to be sync..." && sleep 10; done
  until argocd app sync argo-apps-infra; do echo "awaiting applications-infra to be sync..." && sleep 10; done
}

deployNginxIngress() {
  message ">>> Deploying nginx-ingress"
  until argocd app sync infra-ingress-nginx-helm; do echo "awaiting ingress-nginx to be deployed..." && sleep 20; done
  export NGINX_INGRESS_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -ojson | jq -r '.status.loadBalancer.ingress[].ip')
}

addUrlsToHost() {
  hosts=("$@")

  for host in "${hosts[@]}"; do
    if ! grep -q "$host" "/etc/hosts"; then
      echo "$NGINX_INGRESS_IP $host" | sudo tee -a /etc/hosts
    else
      echo "$host already exists in /etc/hosts skipping."
    fi
  done
}

installK3s
installArgoCD
setupSelfManagedArgoCD
syncArgoCD
installArgoApplications
deployNginxIngress
addUrlsToHost "argo$DNS_ENV.$DNS_DOMAIN" "argo-rollout$DNS_ENV.$DNS_DOMAIN" "grafana$DNS_ENV.$DNS_DOMAIN" "pyroscope$DNS_ENV.$DNS_DOMAIN" "prometheus$DNS_ENV.$DNS_DOMAIN" "alertmanager$DNS_ENV.$DNS_DOMAIN" "api$DNS_ENV.$DNS_DOMAIN" "identity$DNS_ENV.$DNS_DOMAIN" "rabbitmq$DNS_ENV.$DNS_DOMAIN"
# addUrlsToHost "argo$DNS_ENV.$DNS_DOMAIN" "argo-rollout$DNS_ENV.$DNS_DOMAIN" "grafana$DNS_ENV.$DNS_DOMAIN" "pyroscope$DNS_ENV.$DNS_DOMAIN" "prometheus$DNS_ENV.$DNS_DOMAIN" "alertmanager$DNS_ENV.$DNS_DOMAIN" "api$DNS_ENV.$DNS_DOMAIN" "identity$DNS_ENV.$DNS_DOMAIN" "rabbitmq$DNS_ENV.$DNS_DOMAIN" "kafka$DNS_ENV.$DNS_DOMAIN" "redpanda$DNS_ENV.$DNS_DOMAIN" "conduktor$DNS_ENV.$DNS_DOMAIN" "clickhouse$DNS_ENV.$DNS_DOMAIN" "schema-registry$DNS_ENV.$DNS_DOMAIN" "debezium-ui$DNS_ENV.$DNS_DOMAIN" "debezium$DNS_ENV.$DNS_DOMAIN"

message ">>> argo: http://argo$DNS_ENV.$DNS_DOMAIN - username: 'admin', password: '$ARGOCD_PWD'"
