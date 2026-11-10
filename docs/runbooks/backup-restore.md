# Runbook: бэкапы и восстановление (VeleroBackupFailed)

Velero делает бэкап namespace `boutique-prod` каждый день в 03:00 (хранение 7 дней):
манифесты + содержимое томов (файловый бэкап Kopia, т.к. снапшоты local-path томов невозможны).
Хранилище — SeaweedFS (S3 API) в namespace `backup-storage`; ключи — из OpenBao.

## Проверить бэкапы

```bash
kubectl -n velero get backups.velero.io
kubectl -n velero get backupstoragelocation      # PHASE=Available
```

## Восстановить namespace

1. Остановить автосинк ArgoCD (иначе он пересоздаст пустой namespace раньше Velero):
   ```bash
   kubectl -n argocd patch app root          --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
   kubectl -n argocd patch app boutique-prod --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
   ```
2. Создать `Restore` из нужного бэкапа (пример — в `scripts/backup-restore-test.sh`).
3. Дождаться `Completed`, проверить магазин, вернуть автосинк.

Регулярная проверка, что бэкап действительно восстанавливается:
`bash scripts/backup-restore-test.sh` (удаляет namespace и восстанавливает его, меряет время
и проверяет данные корзины).
