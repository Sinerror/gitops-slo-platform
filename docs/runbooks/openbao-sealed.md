# Runbook: OpenBao запечатан (OpenBaoSealed)

**Что значит:** после рестарта пода OpenBao запечатан (sealed) и не отдаёт секреты.
Уже созданные Kubernetes Secret продолжают работать — приложения не падают, но External
Secrets не может обновлять секреты, а новые поды с новыми секретами не стартуют.

## Действие

```bash
bash scripts/openbao-init.sh      # идемпотентно: распечатает и проверит настройки
kubectl get clustersecretstore openbao   # READY=True
```

Ключ распечатывания лежит в `.secrets/openbao-init.json` (в `.gitignore`).
В облаке вместо ручного unseal — auto-unseal через KMS (Yandex KMS).
