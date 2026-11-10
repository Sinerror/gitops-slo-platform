# Алерты в Telegram (опционально)

По умолчанию алерты видны только в Alertmanager (http://alertmanager.localtest.me:18090) и Grafana.
Чтобы получать их в Telegram:

1. Создать бота у [@BotFather](https://t.me/BotFather), получить токен. Написать боту любое
   сообщение и узнать `chat_id`: `https://api.telegram.org/bot<TOKEN>/getUpdates`.
2. Положить токен в OpenBao (не в Git):
   ```bash
   kubectl -n openbao exec -it openbao-0 -- sh -c \
     'BAO_TOKEN=<root-token> bao kv put -mount=kv platform/telegram bot-token=<TOKEN>'
   ```
3. Добавить ExternalSecret в `platform/secrets/manifests/`:
   ```yaml
   apiVersion: external-secrets.io/v1
   kind: ExternalSecret
   metadata: { name: alertmanager-telegram, namespace: monitoring }
   spec:
     secretStoreRef: { kind: ClusterSecretStore, name: openbao }
     target: { name: alertmanager-telegram }
     data:
       - secretKey: bot-token
         remoteRef: { key: platform/telegram, property: bot-token }
   ```
4. В `platform/monitoring/kube-prometheus-stack.values.yaml`:
   ```yaml
   alertmanager:
     alertmanagerSpec:
       secrets: [alertmanager-telegram]      # смонтируется в /etc/alertmanager/secrets/
     config:
       receivers:
         - name: local
           telegram_configs:
             - chat_id: <CHAT_ID>
               bot_token_file: /etc/alertmanager/secrets/alertmanager-telegram/bot-token
               parse_mode: HTML
   ```
5. Закоммитить — ArgoCD применит. Проверка: `make chaos-01` или Watchdog-маршрут временно на `local`.
