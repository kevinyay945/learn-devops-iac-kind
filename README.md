## How to start

create cluster by kind
```bash
kind create cluster --config ./component/kind/kind-config.yaml
```

install ingress controller for kind version
```bash
pushd ./component/ingress/scripts
./ingress-for-kind.sh
popd
```

chech ingress controller is install in node worker
```bash
kubectl get pods -n ingress-nginx -o wide
```

start the service
```bash
kubectl apply -k .
```
