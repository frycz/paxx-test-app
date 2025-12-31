# Deploying paxx-test-app

## Required Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | Yes | PostgreSQL connection string |
| `SECRET_KEY` | Yes | Cryptographic signing key |
| `LOG_LEVEL` | No | DEBUG, INFO, WARNING, ERROR (default: INFO) |
| `LOG_FORMAT` | No | `json` or `console` (default: json in production) |

Generate a secret key:

```bash
openssl rand -hex 32
```

## Building

```bash
docker build -t paxx_test_app .
```

## Migrations

Run migrations **before** deploying new containers, not during startup:

```bash
alembic upgrade head
```

On platforms like Fly.io:

```bash
fly ssh console -C "alembic upgrade head"
```

## Health Check

`GET /health` returns:
- `200` when healthy
- `503` when database is unreachable

Configure your platform's readiness probe to use this endpoint.

## Scaling

The Dockerfile runs 4 uvicorn workers by default. Scale horizontally with multiple container instances, or adjust workers:

```bash
uvicorn main:app --host 0.0.0.0 --workers 8
```

---

For detailed platform guides (Fly.io, Railway, ECS), see the [paxx deployment docs](https://github.com/your-org/paxx#deployment).
