#!/usr/bin/env bash
# Run once after the first cdk deploy to store the real portal credentials.
# The CDK creates the secret with a placeholder password; this overwrites it.

set -euo pipefail

SECRET_ARN=$(aws cloudformation describe-stacks \
  --stack-name InfraStack \
  --query "Stacks[0].Outputs[?OutputKey=='PortalSecretArn'].OutputValue" \
  --output text)

echo "Updating secret: $SECRET_ARN"

aws secretsmanager put-secret-value \
  --secret-id "$SECRET_ARN" \
  --secret-string '{"username":"Cristina.Giraldo@ingrammicro.com","password":"ADJU2025"}'

echo "Done. Portal credentials stored in Secrets Manager."
