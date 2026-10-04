# Template: ${BACKEND_HOST} is the DNS name of the backend's internal NLB, known only after the
# backend is deployed. Rendered by scripts/render-gateway.sh (envsubst) at deploy time.
apiVersion: v1
kind: ConfigMap
metadata:
  name: gateway-nginx
  namespace: sentinel
  labels:
    app.kubernetes.io/name: gateway
    app.kubernetes.io/part-of: rapyd-sentinel
data:
  default.conf: |
    server {
      listen 80;

      # Answered locally so the load balancer health check does not depend on the backend.
      location = /healthz {
        access_log off;
        default_type text/plain;
        return 200 "ok\n";
      }

      location / {
        # The backend NLB has private IPs reachable only over the VPC peering connection.
        # Using a variable makes nginx resolve the name at request time (not only at startup),
        # through the VPC resolver (VPC CIDR base + 2), so NLB IP changes are picked up.
        resolver 10.10.0.2 valid=30s;
        set $backend "${BACKEND_HOST}";

        proxy_pass http://$backend;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_connect_timeout 3s;
        proxy_read_timeout 10s;
      }
    }
