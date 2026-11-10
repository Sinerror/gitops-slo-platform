# «До»: ручной деплой (базовая линия для DORA)

Так выкатывала релиз команда из постановки задачи: инструкция в вики, `kubectl`/SSH руками,
никакой проверки после. Этот каталог нужен только чтобы **честно замерить** «до»:
человек проходит шаги по инструкции, `stopwatch.sh` записывает время каждого шага.

```bash
bash legacy/stopwatch.sh          # пройти инструкцию ниже с секундомером
```

Без человека те же шаги выполняет `bash legacy/auto-baseline.sh` — это только нижняя граница
(машинное время, без чтения инструкции, набора команд и кликов): 139 с в прогоне 2026-11-10.

Результат дописывается в `measurements/legacy-deploy.csv` и попадает в таблицу «до / после» в README.

## Инструкция «как было» (выкатка новой версии checkoutservice)

Деплой идёт в отдельный namespace `legacy`, чтобы не трогать GitOps-окружения.

1. Собрать образ на своей машине:
   `docker build -t ghcr.io/sinerror/checkoutservice:manual ../gitops-slo-app/src/checkoutservice`
2. Доставить образ на кластер: `kind load docker-image --name gitops-slo ghcr.io/sinerror/checkoutservice:manual`
3. Скачать манифесты апстрима (release/kubernetes-manifests.yaml, v0.10.7) и вручную поправить
   `image:` у checkoutservice на `ghcr.io/sinerror/checkoutservice:manual`.
4. `kubectl create namespace legacy` (если нет) и `kubectl -n legacy apply -f kubernetes-manifests.yaml`.
5. Дождаться, пока поды поднимутся: `kubectl -n legacy get pods -w`.
6. Проверить руками: `kubectl -n legacy port-forward svc/frontend 9999:80`, открыть http://localhost:9999,
   положить товар в корзину и оформить заказ.
7. Записать в «журнал релизов», что выкачено и когда.

Откат «как было»: повторить шаги 3–5 со старым тегом (если его кто-то записал).

После замера: `kubectl delete namespace legacy`.
