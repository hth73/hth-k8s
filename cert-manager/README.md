# Kubernetes Cert-Manager

[Cert-Manager documentation](https://cert-manager.io/docs/tutorials/acme/nginx-ingress/)

Mit folgenden Befehlen wird der ***"Cert-Manager"*** in einem Kubernetes Cluster bereitgestellt.
```bash
## Install Kubernetes Cert-Manager
##
helm repo add jetstack https://charts.jetstack.io --force-update
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.17.0 --set crds.enabled=true --set crds.keep=true

kubectl get all -n cert-manager
# NAME                                           READY   STATUS
# pod/cert-manager-56d4c7dfb7-ft74l              1/1     Running
# pod/cert-manager-cainjector-6dc54dcd78-dd6gw   1/1     Running
# pod/cert-manager-webhook-5d74598b49-hbz9r      1/1     Running
# ...

## Debugging aktivieren, wenn nötig. - Wert wird von --v=2 auf --v=5 verändert.
## Dadurch wird detailierter geloggt.
##
kubectl edit deployment cert-manager -n cert-manager
# spec:
#   containers:
#   - args:
#     - --v=5

kubectl rollout restart deployment cert-manager -n cert-manager
kubectl logs -n cert-manager -l app=cert-manager -f
```

Mit folgender YAML Konfiguration erstellen wir eine SelfSign Root-CA und eine Sub-CA Zertifizierungstelle.
Dazu wird ein ***"kind: ClusterIssuer"*** benötigt, der für alle Namespace zur Verfügung steht. 
Ein ***"kind: Issuer"*** ist nur für einen expliziten Namespace zuständig.

#### Root-CA ClusterIssuer
```yaml
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: htdom-root-ca
  namespace: cert-manager
spec:
  selfSigned: {}
```

#### Root-CA Zertifikat
```yaml
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: htdom-root-ca
  namespace: cert-manager
spec:
  commonName: "htdom-root-ca"
  secretName: "htdom-root-ca-secret" # root-ca secret
  isCA: true
  duration: 43830h # 5 Years
  renewBefore: 720h # renewal 30 days before expires
  privateKey:
    rotationPolicy: Never
    algorithm: RSA
    size: 4096
  usages:
  - digital signature
  - key encipherment
  - cert sign
  subject:
    organizations:
      - "HTDOM Inc." # (O) Organization
    organizationalUnits:
      - "IT" # (OU) Organizational unit
    countries:
      - "DE" # (C) Country
    localities:
      - "Munich" # (L) Location
    provinces:
      - "Bavaria" # (ST) Province
  issuerRef:
    name: htdom-root-ca
    kind: ClusterIssuer
```

#### Sub-CA ClusterIssuer
```yaml
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: htdom-sub-ca
  namespace: cert-manager
spec:
  ca:
    secretName: htdom-sub-ca-secret
```

#### Sub-CA Zertifikat
```yaml
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: htdom-sub-ca
  namespace: cert-manager
spec:
  commonName: "htdom-sub-ca"
  secretName: "htdom-sub-ca-secret"
  isCA: true
  duration: 26280h # 3 Jahre
  renewBefore: 720h # 30 Tage vor Ablauf erneuern
  privateKey:
    algorithm: RSA
    size: 4096
    rotationPolicy: Always
  usages:
    - digital signature
    - key encipherment
    - cert sign
  subject:
    organizations:
      - "HTDOM Inc."
    organizationalUnits:
      - "IT"
    countries:
      - "DE"
    localities:
      - "Munich"
    provinces:
      - "Bavaria"
  issuerRef:
    name: htdom-root-ca
    kind: ClusterIssuer
```

#### Cert-Manger ausrollen und überprüfen
```bash
kubectl apply -f cert-manager/root_ca_cluster_issuer.yaml
kubectl apply -f cert-manager/root_ca_certificate.yaml
kubectl apply -f cert-manager/sub_ca_cluster_issuer.yaml
kubectl apply -f cert-manager/sub_ca_certificate.yaml

kubectl get clusterissuers
kubectl describe clusterissuers
kubectl get secrets -n cert-manager

kubectl get secret htdom-root-ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 --decode
kubectl get secret htdom-sub-ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 --decode

openssl x509 -in htdom-root-ca.crt -text -noout
openssl x509 -in htdom-sub-ca.crt -text -noout

cat htdom-root-ca.crt htdom-sub-ca.crt > chain.crt
openssl verify -CAfile htdom-root-ca.crt chain.crt
# combined-chain.crt: OK

kubectl get secret htdom-sub-ca-secret -n cert-manager -o yaml
# kubectl describe certificate kuard.htdom.local -n kuard
```
