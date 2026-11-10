# Runbook: плохой релиз (CheckoutErrorRateHigh, ArgoCDAppDegraded)

**Что значит:** после выкатки выросли ошибки, или ArgoCD не может довести приложение до Healthy
(например, упал smoke-тест PostSync).

## Откат — первым делом, разбор потом

Всё состояние прода — в Git, поэтому откат = revert коммита:

```bash
cd gitops-slo-platform
git log --oneline -5 -- envs/prod          # найти коммит релиза ("prod: sha-xxxxxxx" или правку values)
git revert --no-edit <commit>
git push
```

ArgoCD подхватит изменение (опрос раз в 60 с; можно ускорить кнопкой Refresh в UI).
Альтернатива для образов — workflow **promote** в gitops-slo-app с тегом предыдущей версии.

**Не делайте** `kubectl edit/rollout undo` в prod: selfHeal ArgoCD вернёт состояние из Git,
а дрейф потеряется из истории.

## Проверка

```bash
kubectl -n argocd get app boutique-prod           # Synced / Healthy
kubectl -n boutique-prod get job smoke-test       # Complete
```

На дашборде SLO доля 5xx возвращается к нулю за 2–5 минут (окна rate).
