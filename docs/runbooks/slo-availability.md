# Runbook: доступность магазина (SLOAvailability*, BoutiqueHighErrorRate)

**Что значит:** растёт доля ответов 5xx через prod Gateway. `BoutiqueHighErrorRate` — >5% за 5 минут
(явная авария). `SLOAvailabilityFastBurn` — бюджет ошибок (0.5% за 30 дней) сгорает в 14.4/6 раз
быстрее нормы, `SlowBurn` — в 3/1 раз.

## Диагностика (5 минут)

1. Grafana → **Boutique — SLO и бюджет ошибок**: какой класс ответов растёт, с какого времени.
2. Что поменялось? ArgoCD → `boutique-prod` → History: был ли синк в момент начала.
   ```bash
   git -C gitops-slo-platform log --since="2 hours ago" --oneline -- envs/prod charts/
   ```
3. Какой сервис падает — логи ошибок в Grafana Explore (Loki):
   ```logql
   {namespace="boutique-prod", level=~"error|warning"}
   ```
4. Состояние подов и узлов:
   ```bash
   kubectl -n boutique-prod get pods -o wide | grep -v Running
   kubectl get nodes
   ```

## Действия

| Причина | Действие | Runbook |
| --- | --- | --- |
| Свежий релиз | `git revert <коммит>` в gitops-репозитории, push | [bad-release](bad-release.md) |
| Поды падают / не готовы | смотреть события и логи пода | [pod-crash](pod-crash.md) |
| Узел NotReady | | [node-down](node-down.md) |
| Ошибки корзины, Redis | | [redis-disk-full](redis-disk-full.md) |

После восстановления: проверить, что `slo:sli_error:ratio_rate5m{slo="availability"}` вернулся к 0,
и завести постмортем (`postmortems/TEMPLATE.md`), если сгорело >5% месячного бюджета.
