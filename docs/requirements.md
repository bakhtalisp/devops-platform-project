# Project Requirements

## Services
- api-service: handles user requests (Node/Python/Go - pick your language)
- worker-service: background job processor (consumes from a queue or DB)

## Environments
- dev (local Kind cluster)
- prod (simulated via separate namespace/overlay, same cluster)

## Assumptions
- Low traffic demo app (not real production load)
- Data layer: PostgreSQL + Redis (in-cluster containers, not managed AWS services, to keep cost $0)

## Cost Constraint
- AWS free-trial services used only for brief Terraform apply+destroy (VPC/EC2/S3 proof)
- Primary cluster runs locally via Kind — zero ongoing AWS cost
