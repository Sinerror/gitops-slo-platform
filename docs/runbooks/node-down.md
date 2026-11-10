# Runbook: узел NotReady (NodeNotReady)

**Что значит:** kubelet узла не отвечает больше минуты. Поды на узле продолжают числиться Running,
но не обслуживают трафик; Kubernetes выселит их только через 300 с (tolerations по умолчанию).

## Диагностика

```bash
kubectl get nodes
kubectl get pods -A -o wide --field-selector spec.nodeName=<node>
docker ps -a --filter name=<node>      # kind: узел = Docker-контейнер
```

## Действия

1. Вернуть узел: kind — `docker start <node>`; облако — перезапуск ВМ / замена через node group.
2. Если узел не вернуть за 5 минут — не ждать выселения:
   ```bash
   kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --force
   ```
3. Проверить, что все Deployment в prod доступны: дашборд **Delivery**, панель «Реплики в prod».

## Почему prod пережил потерю узла

У frontend, cart, checkout, catalog, currency по 2 реплики, раскиданные по узлам
(`topologySpreadConstraints`), и PDB. Сервисы с одной репликой (ad, email, payment, shipping,
recommendation, redis) — единая точка отказа: это осознанное ограничение стенда.
