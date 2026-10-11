#!/usr/bin/env bash
# Crée le bucket S3 du state partagé (une seule fois, par le référent AWS).
# Le bucket n'est PAS géré par Terraform : il doit exister avant le premier init.
# Il n'est pas détruit entre les sessions (stockage S3 non facturé à l'heure, quasi gratuit).
set -euo pipefail

REGION="eu-west-3"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="novasphere-tfstate-${ACCOUNT_ID}"

echo "Compte : ${ACCOUNT_ID}"
echo "Bucket : ${BUCKET}"

if aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "Le bucket existe déjà, on vérifie seulement sa configuration."
else
  # Hors us-east-1, la région doit être répétée dans LocationConstraint
  aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"
fi

# Versionnage : permet de restaurer un state précédent
aws s3api put-bucket-versioning --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

# Chiffrement par défaut côté serveur
aws s3api put-bucket-encryption --bucket "${BUCKET}" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'

# Aucun accès public
aws s3api put-public-access-block --bucket "${BUCKET}" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Inscrit le vrai nom du bucket dans les deux backend.tf
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
for env in dev prod; do
  sed -i.bak "s/novasphere-tfstate-[A-Z0-9_]*\"/${BUCKET}\"/" \
    "${SCRIPT_DIR}/../envs/${env}/backend.tf"
  rm -f "${SCRIPT_DIR}/../envs/${env}/backend.tf.bak"
done

echo
echo "Vérification :"
aws s3api get-bucket-versioning --bucket "${BUCKET}"
aws s3api get-bucket-encryption --bucket "${BUCKET}" --query 'ServerSideEncryptionConfiguration.Rules[0]'
echo
echo "OK. Commitez envs/dev/backend.tf et envs/prod/backend.tf, puis lancez terraform init."
