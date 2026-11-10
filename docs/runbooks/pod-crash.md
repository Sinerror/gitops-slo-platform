# Runbook: поды не готовы / перезапускаются (BoutiqueDeploymentUnavailable, BoutiquePodRestarting)

```bash
kubectl -n boutique-prod get pods -o wide
kubectl -n boutique-prod describe pod <pod> | tail -30      # события: OOMKilled, probe failed, ImagePull...
kubectl -n boutique-prod logs <pod> --previous              # логи упавшего контейнера
```

| Признак | Причина | Действие |
| --- | --- | --- |
| `OOMKilled` | мало памяти | поднять `resources.limits.memory` в values (через Git) |
| `ImagePullBackOff` | нет образа / тега | проверить тег в `envs/prod/values.yaml`, пакет GHCR публичный |
| `Readiness probe failed` | сервис не отвечает | логи сервиса, зависимости |
| `CreateContainerConfigError` | нет Secret | `kubectl get externalsecret -A`, [openbao-sealed](openbao-sealed.md) |

Одиночное падение пода Deployment восстанавливает сам; у пользовательского пути в prod по 2 реплики
и PodDisruptionBudget.
