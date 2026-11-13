#!/usr/bin/env bash
# Moves cnp-audit-archive from 30 days of Object Lock (and no expiry) to a
# rolling 6 months, the low end of what the CNIL recommends for access logs:
#   - default retention COMPLIANCE 180 days for every new object version;
#   - lifecycle: a delete marker at 190 days, the version itself one day later
#     (once its lock has run out), then the leftover marker.
# COMPLIANCE retention can be extended but never shortened, by anyone: after
# this runs, objects written from then on stay 180 days whatever happens.
#
# Run by hand from a machine with the platform kubeconfig and the RGW in
# reach. It uses the bucket owner (observability/audit-archive):
#   ./audit-archive-retention.sh                    # lock + lifecycle
#   ./audit-archive-retention.sh --extend-existing  # also lifts the versions
#       already archived to 180 days after their creation (else they keep 30)
set -euo pipefail

context=3-istor-prod@kubernetes
bucket=cnp-audit-archive

secret() {
  kubectl --context "$context" -n observability get secret \
    rook-ceph-object-user-openstack-rgw-audit-archive -o "jsonpath={.data.$1}" | base64 -d
}
AWS_ACCESS_KEY_ID=$(secret AccessKey)
AWS_SECRET_ACCESS_KEY=$(secret SecretKey)
endpoint=$(secret Endpoint)
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION=us-east-1
s3() { aws --endpoint-url "$endpoint" "$@"; }

s3 s3api put-object-lock-configuration --bucket "$bucket" \
  --object-lock-configuration '{"ObjectLockEnabled":"Enabled","Rule":{"DefaultRetention":{"Mode":"COMPLIANCE","Days":180}}}'

# One prefix per rule: an Expiration takes either Days or
# ExpiredObjectDeleteMarker, and older RGWs reject two rules on one prefix.
s3 s3api put-bucket-lifecycle-configuration --bucket "$bucket" --lifecycle-configuration '{
  "Rules": [
    {"ID": "audit-190-days", "Status": "Enabled", "Filter": {"Prefix": "audit/"},
     "Expiration": {"Days": 190}, "NoncurrentVersionExpiration": {"NoncurrentDays": 1}},
    {"ID": "compliance-190-days", "Status": "Enabled", "Filter": {"Prefix": "compliance/"},
     "Expiration": {"Days": 190}, "NoncurrentVersionExpiration": {"NoncurrentDays": 1}},
    {"ID": "expired-delete-markers", "Status": "Enabled", "Filter": {"Prefix": ""},
     "Expiration": {"ExpiredObjectDeleteMarker": true}}
  ]
}'

s3 s3api get-object-lock-configuration --bucket "$bucket"
s3 s3api get-bucket-lifecycle-configuration --bucket "$bucket"

if [[ "${1:-}" == "--extend-existing" ]]; then
  s3 s3api list-object-versions --bucket "$bucket" \
    --query 'Versions[].[Key, VersionId, LastModified]' --output text |
    while read -r key version modified; do
      until=$(date -u -d "$modified + 180 days" +%Y-%m-%dT%H:%M:%SZ)
      s3 s3api put-object-retention --bucket "$bucket" --key "$key" --version-id "$version" \
        --retention "Mode=COMPLIANCE,RetainUntilDate=$until"
    done
  echo "existing versions now retained 180 days after creation"
fi
