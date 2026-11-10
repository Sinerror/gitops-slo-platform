# Runbook: медленное оформление заказа (SLOCheckoutLatencyFastBurn)

**Что значит:** больше 5% `POST /cart/checkout` дольше 1 секунды, бюджет сгорает быстро.

## Диагностика

1. Дашборд SLO → панель «Оформление заказа: задержка»: p50 тоже вырос (всё медленное) или только хвост p99?
2. Оформление заказа последовательно вызывает cart → productcatalog → currency → shipping → payment
   → email и публикует событие в Kafka (асинхронно, на задержку не влияет). Ищите медленный сервис в логах checkoutservice:
   ```bash
   kubectl -n boutique-prod logs deploy/checkoutservice --since=15m | grep -iE 'error|warn|deadline'
   ```
3. Нагрузка на узлы: `docker stats --no-stream` (kind) / дашборд Node Exporter.
4. DNS: известный случай — внешние DNS-запросы в горячем пути
   ([postmortems/00-dns-metadata-lookup.md](../../postmortems/00-dns-metadata-lookup.md)).

## Действия

- Свежий релиз → откат (`git revert`), см. [bad-release](bad-release.md).
- Не хватает реплик → увеличить `services.<svc>.replicas` в `envs/prod/values.yaml` (через PR).
