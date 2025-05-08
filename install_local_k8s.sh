#!/usr/bin/env bash
set -e

## Setup Variables
DOMAIN="htdom.local"
HOSTIP="192.168.xxx.xxx"
CLUSTERNAME="k8s"
CLUSTER_EXIST=$(k3d cluster list --no-headers --output json | jq -r --arg NAME "$CLUSTERNAME" '.[] | select(.name == $NAME) | .name')
echo "CLUSTERNAME ist: $CLUSTER_EXIST"

if [[ -z "$CLUSTER_EXIST" ]]; then
  EXIT_CODE=1
else
  EXIT_CODE=0
fi

get_workdir() {
  DIRPATH=$(dirname "$0")
  cd "$DIRPATH"
  pwd
}

export WORKDIR=$(get_workdir)

generate_k3d_config() {
  AGENT_COUNT=$1
  CONFIG_FILE="$WORKDIR/k3d-config.yaml"

  echo "Erstelle dynamische k3d-Konfiguration mit $AGENT_COUNT Agent(en)..."

  cat <<EOF > "$CONFIG_FILE"
apiVersion: k3d.io/v1alpha5
kind: Simple
metadata:
  name: $CLUSTERNAME
servers: 1
agents: $((AGENT_COUNT))
kubeAPI:
  host: "${CLUSTERNAME}.${DOMAIN}"
  hostIP: "${HOSTIP}"
  hostPort: "6445"
volumes:
  - volume: $HOME/k3d/storage/server0:/var/lib/rancher/k3s/storage/
    nodeFilters:
      - server:0
EOF

  for ((i=0; i<AGENT_COUNT; i++)); do
    echo "  - volume: $HOME/k3d/storage/agent$i:/var/lib/rancher/k3s/storage/" >> "$CONFIG_FILE"
    echo "    nodeFilters:" >> "$CONFIG_FILE"
    echo "      - agent:$i" >> "$CONFIG_FILE"
  done

  cat <<EOF >> "$CONFIG_FILE"
ports:
  - port: 80:80
    nodeFilters:
      - server:*
  - port: 443:443
    nodeFilters:
      - server:*
registries:
  create:
    image: docker.io/registry:3
    name: k3d-registry.127.0.0.1.nip.io
    host: 127.0.0.1
    hostPort: "5000"
    volumes:
      - $HOME/k3d/registry:/var/lib/registry
options:
  k3d:
    wait: true
    timeout: "60s"
  runtime:
    serversMemory: 3G
    agentsMemory: 2G
  k3s:
    extraArgs:
      - arg: --disable=traefik
        nodeFilters:
          - server:*
EOF
}

install-cluster() {
  AGENT_COUNT=${1:-2}
  
  mkdir -p $HOME/k3d/registry
  mkdir -p $HOME/k3d/storage/server0
  for ((i=0; i<AGENT_COUNT; i++)); do
    mkdir -p $HOME/k3d/storage/agent$i
  done

  generate_k3d_config "$AGENT_COUNT"

  echo "Starte Cluster mit $AGENT_COUNT Agent(en)..."
  k3d cluster create --config "$WORKDIR/k3d-config.yaml"
  sleep 10

  ## install custom cordns nameserver (192.168.xxx.xxx)
  kubectl apply -f "$WORKDIR/coredns-custom.yaml"

  ## install ingress-nginx
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
  helm upgrade --install ingress-nginx ingress-nginx --namespace ingress-nginx --repo https://kubernetes.github.io/ingress-nginx --create-namespace -f "$WORKDIR/ingress-controller/ingress-values.yaml"
  kubectl rollout status deployment ingress-nginx-controller -n ingress-nginx --timeout=60s

  ## install cert-manager and create root and sub-ca
  helm repo add jetstack https://charts.jetstack.io --force-update
  helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.17.2 --set crds.enabled=true --set crds.keep=true

  kubectl apply -f cert-manager/root_ca_cluster_issuer.yaml
  sleep 5
  kubectl apply -f cert-manager/root_ca_certificate.yaml
  sleep 5
  kubectl apply -f cert-manager/sub_ca_cluster_issuer.yaml
  sleep 5
  kubectl apply -f cert-manager/sub_ca_certificate.yaml
  sleep 5
  echo "create htdom-root-ca.crt"
  kubectl get secret htdom-root-ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 --decode > htdom-root-ca.crt
  sleep 5
  echo "create htdom-sub-ca.crt"
  kubectl get secret htdom-sub-ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 --decode > htdom-sub-ca.crt

  # install demo application kuard
  kubectl apply -k kuard/

  # install kubernetes-dashboard
  helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard --force-update
  helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace kubernetes-dashboard

  kubectl apply -k kubernetes-dashboard/
  sleep 5
  kubectl create token admin-user -n kubernetes-dashboard
}

start-cluster() {
  k3d cluster start "$CLUSTERNAME"
}

stop-cluster() {
  k3d cluster stop "$CLUSTERNAME"
}

delete-cluster() {
  k3d cluster delete "$CLUSTERNAME"
}

CMDS=(k3d kubectl k9s helm)
for c in "${CMDS[@]}"; do
  if ! command -v "$c" &> /dev/null; then
    echo "${c} wurde nicht gefunden"
    exit
  fi
done

case $1 in
  install-cluster)
    if [[ "${EXIT_CODE}" -eq 1 ]]; then
      echo "Kein Cluster gefunden, wird installiert mit ${2:-2} Agents..."
      install-cluster "${2:-2}"
    else
      echo "Cluster: ${CLUSTERNAME} ist bereits installiert, wird gestartet."
      start-cluster
    fi
    ;;
  start-cluster)
    if [[ "${EXIT_CODE}" -eq 0 ]]; then
      echo "Cluster: ${CLUSTERNAME} wird gestartet."
      start-cluster
    else
      echo "Kein Cluster gefunden, wird installiert mit ${2:-2} Agents..."
      install-cluster "${2:-2}"
    fi
    ;;
  stop-cluster)
    if [[ "${EXIT_CODE}" -eq 0 ]]; then
      echo "Cluster: ${CLUSTERNAME} wird gestoppt."
      stop-cluster
    fi
    ;;
  delete-cluster)
    if [[ "${EXIT_CODE}" -eq 0 ]]; then
      echo "Cluster: ${CLUSTERNAME} wird gelöscht."
      delete-cluster
    fi
    ;;
  *)
    echo "$0 install-cluster [ANZAHL_AGENTEN 0-2] | start-cluster | stop-cluster | delete-cluster"
    ;;
esac
