# Runbook: отставание consumer Kafka (KafkaConsumerLagHigh, OrderConsumerDown)

**Что значит:** order-consumer обрабатывает события заказов медленнее, чем они приходят.
Покупатель заказ оформил (checkout от Kafka не зависит), но обработка (подтверждения, учёт)
запаздывает. Данные не теряются: события лежат в топике `orders` (retention 7 дней).

## Диагностика

```bash
kubectl -n boutique-prod get pods -l app=order-consumer
kubectl -n boutique-prod logs deploy/order-consumer --tail=20
# lag по партициям
kubectl -n kafka exec events-dual-role-0 -- bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --describe --group order-consumer
```

На дашборде SLO: панели «Kafka: отставание consumer-групп» и «Обработанные события заказов».
Если обработанных событий стало меньше, а ошибок `invalid` нет — consumer тормозит
(медленная зависимость, `processingDelayMs`), если consumer-подов нет — он упал.

## Действия

1. Свежий релиз consumer'а → `git revert` (см. [bad-release](bad-release.md)).
2. Нужно быстрее разгрести хвост → увеличить `orderConsumer.replicas` (до числа партиций, их 3).
3. Consumer падает на конкретном сообщении → в логах offset; сообщение пропускается
   как `invalid` (consumer не блокируется на «ядовитом» сообщении).
