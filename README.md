# Notes app

## Running it on AWS

You need the AWS CLI, signed in with `aws login`.

```bash
./scripts/create-infrastructure.sh
```

When the tutorial asks to create a load balancer, run:

```bash
./scripts/create-load-balancer.sh
```

When you're finished, delete everything:

```bash
./scripts/destroy-infrastructure.sh
```

## Running it locally

```bash
docker compose up --build
```

Then open <http://localhost:8000>. Locally, attached files are written to
`backend/uploads` instead of S3.
