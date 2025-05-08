# Kubernetes mit k3d

### Inhaltsverzeichnis

* [cert-manager](cert-manager/README.md)
* [kubernetes-dashboard](prometheus.htdom.local.md)
* [nextcloud](prometheus.htdom.local.md)


## Beschreibung

Zusätzlich zu meiner kompletten [Docker Demo Umgebung](https://github.com/hth73/hth-docker), wird in einer weiteren Demo Umgebung ein kleiner Kubernetes Cluster mit k3d betrieben, um ein bisschen testen zu können.

### Voraussetzungen:

* [docker](https://docs.docker.com/engine/install)
* [k3d](https://github.com/k3d-io/k3d/releases)
* [helm](https://github.com/helm/helm/releases)
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux)
* [k9s](https://github.com/derailed/k9s/releases)

Damit dieses Skript erfolgreich durchläuft, sollten die beschriebenen Tools installiert sein.

```bash
## Bitte "HOSTIP=192.168.xxx.xxx" im Skript "install_local_k8s.sh" anpassen.

## Damit die Namensauflösung im K8s Cluster funktioniert, musste auch noch in der Docker Demo Umgebung ein "dnsmasq" Service installiert werden.
## Dieser wird mit der "coredns-custom.yaml" konfiguriert. Bitte auch hier die passende IP-Adresse nachkonfigurieren. 
## Wenn das nicht benötigt wird, bitte Zeile 101 auskommentieren.

./install_local_k8s.sh [start-cluster | delete-cluster | stop-cluster | install-cluster [ANZAHL_AGENTEN 0-2]]
```
