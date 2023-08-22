#!/bin/bash

DIR="$(cd "$(dirname "$0")" && pwd)"
ARGO_CHART_VERSION="5.43.4"

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

installAndSyncArgoCD() {
  message ">>> deploying ArgoCD"

  local ARGO_DIR="$DIR/../argo"

  # Install chart
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo update
  helm uninstall argocd
  helm install argocd argo/argo-cd --create-namespace --namespace=argocd --version $ARGO_CHART_VERSION \
    --set applicationSet.enabled=false \
    --set notifications.enabled=false \
    --set dex.enabled=false \
    --set configs.cm."kustomize\.buildOptions"="--load-restrictor LoadRestrictionsNone" \
    --set configs.cm."timeout\.reconciliation"="10s"

  kubectl -n argocd rollout status deployment/argocd-server

  # Install ArgoCD applications and await new argocd-server to start with CMP plugins.
  kubectl apply -f $ARGO_DIR/argocd-helm.yaml
  syncArgoCD

  kubectl apply -f $ARGO_DIR/applications-infra.yaml
  kubectl apply -f $ARGO_DIR/applications-observability.yaml
  kubectl apply -f $ARGO_DIR/applications-data.yaml

  until argocd app sync parent-applications-infra; do echo "awaiting applications-infra to be sync..." && sleep 10; done
}

syncArgoCD() {
  message ">>> Awaiting ArgoCD applications to sync..."
  export ARGOCD_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
  until argocd login --core --username admin --password $ARGOCD_PWD --insecure; do :; done
  kubectl config set-context --current --namespace=argocd
  until argocd app sync argocd; do echo "awaiting argocd to be sync..." && sleep 10; done
  until argocd app sync observability-kube-prometheus-crds; do echo "awaiting kube-prometheus-crds to be sync..." && sleep 10; done
  kubectl -n argocd rollout status deployment/argocd-repo-server
}

deployNginxIngress() {
  message ">>> Deploying nginx-ingress"
  until argocd app sync ingress-nginx; do echo "awaiting ingress-nginx to be deployed..." && sleep 20; done
  export NGINX_INGRESS_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -ojson | jq -r '.status.loadBalancer.ingress[].ip')
}

addUrlToHost() {
  host=$1
  if ! grep -q $host "/etc/hosts"; then
    echo "$NGINX_INGRESS_IP $host" | sudo tee -a /etc/hosts
  fi
}

installK3s
installAndSyncArgoCD
deployNginxIngress

addUrlToHost "argo.local.com.br"
addUrlToHost "apisix.local.com.br"
addUrlToHost "identity.local.com.br"
addUrlToHost "rabbitmq.local.com.br"
addUrlToHost "grafana.local.com.br"
addUrlToHost "prometheus.local.com.br"
addUrlToHost "alertmanager.local.com.br"
addUrlToHost "kafka.local.com.br"
addUrlToHost "redpanda.local.com.br"
addUrlToHost "conduktor.local.com.br"
addUrlToHost "clickhouse.local.com.br"

message ">>> argo: http://argo.local.com.br - username: 'admin', password: '$ARGOCD_PWD'"
