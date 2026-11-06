# Notes app

## Running it on AWS

You need the AWS CLI, signed in with `aws login`.

```bash
./create-infrastructure.sh
```

This creates two EC2 instances in the default VPC, one in `eu-west-1a` and one in `eu-west-1b`, each running the app from `ghcr.io/mcandru/wdd-notes-app:load-balancing`.

To launch one more instance, set up the same way, give it a name:

```bash
./add-instance.sh instance-3
```

When you're finished, delete everything, including the load balancer you
create in the tutorial:

```bash
./destroy-infrastructure.sh
```

## Running it locally

```bash
docker compose up --build
```

Then open <http://localhost:8000>.
