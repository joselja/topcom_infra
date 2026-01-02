Run once

```bash
cd terraform/bootstrap
terraform init
terraform apply -var="state_bucket_name=<globally-unique-bucket>"
```