# Argo infra personal labs

## Network

Network with wifi router configuration can block some port and leave the k3s without stable communication. If you want to make sure there is none, try using your 4G network.

## Dependencies

* [kubectl](https://kubernetes.io/docs/tasks/tools)
* [helm](https://helm.sh/docs/intro/install)
* [kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize)
* [argocd](https://argo-cd.readthedocs.io/en/stable/cli_installation) greater than 2.8

## Getting Started

Create local cluster with [k3s](https://k3s.io/):

```bash
make start
```

### Argocd dashboard

* [http://argo-local.jonathan.com.br](http://argo-local.jonathan.com.br/)
  * login: admin password: see the logs

### Infra applications

<https://github.com/Jojoooo1/argo-deploy-applications-infra>

### Observability applications

<https://github.com/Jojoooo1/argo-deploy-applications-observability>
