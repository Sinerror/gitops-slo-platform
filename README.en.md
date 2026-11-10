# GitOps with SLOs and incident reviews

Moving a microservice app from manual deploys to a production-grade setup: infrastructure as code,
Git-driven delivery, SLOs with error budgets, verified backups, and failure drills with postmortems.
Русский: [README.md](README.md).

The app is someone else's: [Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo)
(11 microservices, Apache-2.0) plus my own Kafka consumer. The point is the platform and operations.
Service code and CI live in [gitops-slo-app](https://github.com/Sinerror/gitops-slo-app).

## Results

See the tables in [README.md](README.md#результаты) — numbers are the same; every one comes from a
real run on the local stand (kind, 4 nodes, 32 GB laptop), raw data in [`measurements/`](measurements/).

Highlights:
- Cluster + ArgoCD from zero with `terraform apply`: **76 s** (kind node image already cached).
- Found a real latency incident while bringing the stand up: the upstream frontend does a DNS lookup of
  `metadata.google.internal` on **every** home page request; with a degraded upstream resolver p95 was
  **4.02 s → 0.021 s** after a GitOps-managed CoreDNS fix ([postmortem 00](postmortems/00-dns-metadata-lookup.md)).
- Five chaos scenarios, nine runs: clean runs recover in **17–304 s**; alerts fire in **111–141 s** for
  node, bad-release and Redis failures. The first runs of 03, 04 and 05 took 12.5–21 min because our own
  remediation tooling failed silently (path conversion, a missed alert, a failed `git push`) — each is
  written up in a postmortem ([03](postmortems/03-bad-release.md), [04](postmortems/04-redis-disk-full.md),
  [05](postmortems/05-kafka-consumer-lag.md)) and fixed.
- The Trivy gate (same command as in CI, run locally before the first push) failed the first two images
  (7 + 4 HIGH CVEs in Go stdlib / x/net / compress); after bumping the builder and dependencies — 0.

## Stack

| Concern | Choice | Why |
| --- | --- | --- |
| IaC | Terraform modules `kind-cluster`, `argocd-bootstrap`; envs `local` (kind) and `yandex` (Managed K8s, remote state in Object Storage) | one bootstrap module for local and cloud |
| Delivery | ArgoCD app-of-apps with sync waves and self-heal; own Helm chart with per-env values; PostSync smoke test | state in Git, rollback = `git revert` |
| Ingress | Gateway API + Envoy Gateway, one Gateway per env, TLS via cert-manager | ingress-nginx was archived in March 2026 |
| SLOs | SLIs from Envoy (client view), multi-window multi-burn-rate alerts + fast symptom alerts, runbook links | page on budget, not on every blip |
| Logs | Loki + Grafana Alloy | Promtail EOL (March 2026) |
| Queue | Kafka (Strimzi 1.3, KRaft) with consumer-lag alert | async order processing |
| Secrets | OpenBao + External Secrets Operator (Kubernetes auth) | MPL-2.0 Vault fork; HashiCorp endpoints unreachable from the stand's network |
| Backups | Velero + Kopia file-system backup to SeaweedFS (S3), daily schedule, restore drill | local-path volumes can't be snapshotted; MinIO no longer ships images |
| Security | default-deny NetworkPolicies, RBAC (developers read-only, on-call emergency actions in prod, no secret access), non-root + read-only rootfs, Trivy gate, Actions pinned by SHA | prod changes go through Git only |

## SLOs

| SLO | Target | SLI | 30-day budget |
| --- | --- | --- | --- |
| Shop availability | 99.5% | non-5xx share at the prod Gateway | 0.5% of requests |
| Checkout speed | 95% under 1 s | `POST /cart/checkout`, Envoy histogram | 5% of requests |

## Run it

```bash
make up            # terraform apply + wait for ArgoCD + OpenBao init; prints URLs
make chaos-01      # failure drill
make backup-test   # backup -> delete namespace -> restore -> verify data
make destroy
```

Shop: http://shop.localtest.me:18080 · Grafana: http://grafana.localtest.me:18090 (`make grafana-password`).

`registry.terraform.io` is not reachable from RU/KZ networks, so `make up` installs providers through
the Yandex Cloud mirror (`terraform/terraformrc.mirror`, disable with `TF_MIRROR=0`).

## Limitations

Demo app, synthetic load (upstream Locust, 10 users); single Kafka broker and a single OpenBao
instance with manual unseal; single-replica services are SPOFs. The Yandex Cloud environment passes
`terraform validate` but was not applied as part of this project.
