# Runbook: Redis корзин не может писать (RedisAOFWriteFailing)

**Что значит:** Redis не смог дописать AOF (append-only file) на диск. Пока запись не восстановится,
Redis отклоняет команды записи — добавление в корзину и оформление заказа отвечают 500.

## Диагностика

```bash
POD=$(kubectl -n boutique-prod get pod -l app=redis-cart -o name)
kubectl -n boutique-prod exec $POD -c redis -- df -h /data
kubectl -n boutique-prod exec $POD -c redis -- redis-cli INFO persistence | grep -E 'aof_last_write_status|aof_enabled'
kubectl -n boutique-prod exec $POD -c redis -- ls -la /data
```

## Действия

1. Освободить место: удалить постороннее из `/data`, либо увеличить том
   (`redis.dataSizeLimit` в values, через Git; на PVC — расширить PVC).
2. Redis сам продолжит писать, как только fsync AOF пройдёт успешно — рестарт не нужен
   (рестарт пода с tmpfs-томом потеряет корзины, тогда — восстановление из Velero, см.
   [backup-restore](backup-restore.md)).
3. Проверка: `aof_last_write_status:ok`, на дашборде 5xx вернулись к нулю.
