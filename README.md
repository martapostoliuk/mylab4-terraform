# Лабораторна робота №4 — Варіант 15 «Дедуплікація подій»

**Дисципліна:** Хмарні технології та сервіси  
**Платформа:** AWS | **IaC:** Terraform 1.14.7  
**Студентка:** Постолюк Марта

---

## Архітектура

```
Client → API Gateway (HTTP v2) → Lambda (Python 3.12) → DynamoDB (idempotency check)
                                                       ↘ SQS FIFO (якщо унікальна)
```

## Стек сервісів

| Сервіс | Призначення |
|---|---|
| AWS Lambda | Бізнес-логіка: перевірка дублів + постановка в чергу |
| Amazon API Gateway (HTTP v2) | Публічний ендпоінт `/events` |
| Amazon DynamoDB | Зберігання `idempotency_key` для перевірки дублів |
| Amazon SQS FIFO | Черга унікальних подій + DLQ |
| Amazon S3 | Remote state Terraform |

## Структура репозиторію

```
serverless-lab4/
├── src/
│   └── app.py                    # Lambda-обробник
├── modules/
│   ├── dynamodb/main.tf
│   ├── sqs/main.tf
│   ├── lambda/main.tf
│   └── api_gateway/main.tf
├── envs/dev/
│   ├── main.tf                   # Кореневий модуль
│   └── backend.tf                # S3 remote state
└── README.md
```

## API

| Метод | Шлях | Опис |
|---|---|---|
| `POST` | `/events` | Прийняти подію з `idempotency_key` |
| `GET` | `/events` | Переглянути всі збережені події |

### Приклад запиту

```bash
curl -X POST https://<api-id>.execute-api.eu-central-1.amazonaws.com/events \
  -H "Content-Type: application/json" \
  -d '{"idempotency_key": "event-001", "payload": {"type": "order_created"}}'
```

### Можливі відповіді

```json
// Нова подія
{"status": "queued", "idempotency_key": "event-001", "message": "Event accepted and placed in queue."}

// Дублікат
{"status": "duplicate", "idempotency_key": "event-001", "message": "Event already processed. Skipped."}

// Відсутній ключ
{"error": "idempotency_key is required"}
```

## Розгортання

```bash
# 1. Налаштування AWS CLI
aws configure

# 2. Створення S3-бакету для стану
aws s3api create-bucket --bucket tf-state-lab4-postoliuk-marta-15 \
  --region eu-central-1 \
  --create-bucket-configuration LocationConstraint=eu-central-1

# 3. Terraform
cd envs/dev/
terraform init
terraform plan
terraform apply -auto-approve

# 4. Знищення після захисту
terraform destroy -auto-approve
```
