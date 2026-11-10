#!/usr/bin/env bash
# Авария 4: заполненный диск БД корзин. Том /data у redis-cart — tmpfs фиксированного
# размера (charts/boutique values redis.dataSizeLimit); забиваем его мусорным файлом,
# Redis получает ENOSPC при записи AOF и отклоняет запись -> 5xx при добавлении в корзину.
# Исправление после алерта: удалить мусор (в жизни — расширить том / почистить диск).
export SCENARIO=04-redis-disk-full
source "$(dirname "$0")/lib.sh"
require_cluster
assert_quiet "RedisAOFWriteFailing BoutiqueHighErrorRate SLOAvailabilityFastBurn"

POD="$(kubectl -n boutique-prod get pod -l app=redis-cart -o jsonpath='{.items[0].metadata.name}')"
rx() { kexec -n boutique-prod "$POD" -c redis -- "$@"; }

e0="$(gateway_5xx_total)"
t0="$(now)"
log "inject: fill /data on $POD"
rx sh -c 'dd if=/dev/zero of=/data/fill.bin bs=1M count=1024 2>&1 | tail -1; df -h /data | tail -1' >>"$LOG" 2>&1 || true

wait_alert "RedisAOFWriteFailing BoutiqueHighErrorRate SLOAvailabilityFastBurn" 600 || true

log "mitigate: rm /data/fill.bin"
rx rm -f /data/fill.bin
aof_ok() {
  rx redis-cli INFO persistence | grep -q 'aof_last_write_status:ok' \
    && curl -s -o /dev/null -w '%{http_code}' -X POST -d product_id=OLJCESPC7Z -d quantity=1 \
         -b 'shop_session-id=chaos04' http://localhost:18080/cart | grep -qE '^(2|3)'
}
wait_until 300 "Redis снова пишет AOF и корзина работает" aof_ok
t_rec="$(now)"

record "$t0" "$t_rec" "$e0" "tmpfs /data filled; mitigation rm junk file"
