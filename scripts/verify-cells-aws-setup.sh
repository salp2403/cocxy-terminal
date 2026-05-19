#!/usr/bin/env bash
set -uo pipefail

# Read-only verifier for AWS Cocxy Cells setup.
#
# This script does not create, modify, or delete AWS resources. It records
# whether the current AWS principal can inspect the expected role/profile and
# pass the profile to EC2 via a dry-run launch.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_ROOT="${COCXY_AWS_VERIFY_ARTIFACTS:-${PROJECT_ROOT}/build/cells-aws-setup-verify/${TIMESTAMP}}"
SUMMARY_FILE="${ARTIFACT_ROOT}/summary.txt"
CHECKS_FILE="${ARTIFACT_ROOT}/checks.tsv"
REMEDIATION_FILE="${ARTIFACT_ROOT}/remediation.md"
REGION="${COCXY_AWS_REGION:-us-east-1}"
ROLE_NAME="${COCXY_AWS_SETUP_ROLE:-CocxyCellsSSMRole}"
INSTANCE_PROFILE="${COCXY_AWS_INSTANCE_PROFILE:-${COCXY_AWS_SETUP_INSTANCE_PROFILE:-CocxyCellsSSMProfile}}"
IMAGE="${COCXY_AWS_IMAGE:-}"
VM_SIZE="${COCXY_AWS_VM_SIZE:-t3.micro}"
BLOCKERS=()
FINAL_STATUS=""
FINAL_RESULT=""
FINAL_BLOCKERS_TEXT=""
FINAL_WARNINGS_TEXT=""

usage() {
  cat <<'USAGE'
usage: scripts/verify-cells-aws-setup.sh

Read-only AWS verifier for Cocxy Cells setup. It writes artifacts under
build/cells-aws-setup-verify and never creates cloud resources.

Required for EC2 dry-run:
  COCXY_AWS_IMAGE=<valid AMI for COCXY_AWS_REGION>

Optional:
  COCXY_AWS_REGION=us-east-1
  COCXY_AWS_PROFILE=<aws-cli-profile>
  COCXY_AWS_INSTANCE_PROFILE=CocxyCellsSSMProfile
  COCXY_AWS_SETUP_ROLE=CocxyCellsSSMRole
  COCXY_AWS_VM_SIZE=t3.micro
USAGE
}

aws_cli() {
  if [ -n "${COCXY_AWS_PROFILE:-}" ]; then
    aws --profile "$COCXY_AWS_PROFILE" "$@"
  else
    aws "$@"
  fi
}

record_check() {
  local name="$1"
  local status="$2"
  local detail="$3"
  local output="${4:-}"
  local error="${5:-}"

  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$name" \
    "$status" \
    "$detail" \
    "${output#${PROJECT_ROOT}/}" \
    "${error#${PROJECT_ROOT}/}" >> "$CHECKS_FILE"
}

blocker() {
  BLOCKERS+=("$1")
}

join_blockers() {
  if [ "$#" -eq 0 ]; then
    echo "-"
    return 0
  fi

  local old_ifs="${IFS}"
  IFS=","
  echo "$*"
  IFS="${old_ifs}"
}

check_status() {
  local name="$1"
  awk -F '\t' -v name="$name" \
    'NR > 1 && $1 == name { print $2; exit }' \
    "$CHECKS_FILE"
}

all_blockers_are_iam_inspection_denied() {
  local item
  if [ "${#BLOCKERS[@]}" -eq 0 ]; then
    return 1
  fi

  for item in "${BLOCKERS[@]}"; do
    case "$item" in
      role:access-denied|\
      role-ssm-policy:access-denied|\
      instance-profile:access-denied|\
      instance-profile-roles:access-denied)
        ;;
      *)
        return 1
        ;;
    esac
  done
  return 0
}

launch_dry_runs_are_authorized() {
  [ "$(check_status run-instances-with-profile-dry-run)" = "authorized" ] &&
    [ "$(check_status run-instances-with-profile-arn-dry-run)" = "authorized" ] &&
    [ "$(check_status run-instances-without-profile-dry-run)" = "authorized" ]
}

compute_final_state() {
  if [ "${#BLOCKERS[@]}" -eq 0 ]; then
    FINAL_STATUS="ok"
    FINAL_RESULT="aws-setup-ok"
    FINAL_BLOCKERS_TEXT="-"
    FINAL_WARNINGS_TEXT="-"
    return 0
  fi

  if all_blockers_are_iam_inspection_denied &&
     [ "$(check_status caller-identity)" = "ok" ] &&
     launch_dry_runs_are_authorized; then
    FINAL_STATUS="ready"
    FINAL_RESULT="aws-setup-ready"
    FINAL_BLOCKERS_TEXT="-"
    FINAL_WARNINGS_TEXT="$(join_blockers "${BLOCKERS[@]}")"
    return 0
  fi

  FINAL_STATUS="blocked"
  FINAL_RESULT="aws-setup-blocked"
  FINAL_BLOCKERS_TEXT="$(join_blockers "${BLOCKERS[@]}")"
  FINAL_WARNINGS_TEXT="-"
}

classify_aws_error() {
  local error_file="$1"
  if grep -q "DryRunOperation" "$error_file"; then
    echo "authorized"
  elif grep -q "AccessDenied\\|not authorized" "$error_file"; then
    echo "access-denied"
  elif grep -q "NoSuchEntity\\|cannot be found" "$error_file"; then
    echo "not-found"
  elif grep -q "Invalid IAM Instance Profile\\|iamInstanceProfile" "$error_file"; then
    echo "invalid-instance-profile"
  elif grep -q "InvalidAMIID" "$error_file"; then
    echo "invalid-ami"
  elif grep -q "UnauthorizedOperation" "$error_file"; then
    echo "unauthorized-operation"
  else
    echo "failed"
  fi
}

run_json_check() {
  local name="$1"
  local detail="$2"
  shift 2
  local output="${ARTIFACT_ROOT}/${name}.out"
  local error="${ARTIFACT_ROOT}/${name}.err"
  local status

  if aws_cli "$@" > "$output" 2> "$error"; then
    record_check "$name" "ok" "$detail" "$output" "$error"
    return 0
  fi

  status="$(classify_aws_error "$error")"
  record_check "$name" "$status" "$detail" "$output" "$error"
  blocker "${name}:${status}"
  return 1
}

run_instance_profile_roles_check() {
  local output="${ARTIFACT_ROOT}/instance-profile-roles.out"
  local error="${ARTIFACT_ROOT}/instance-profile-roles.err"
  local roles
  local status

  if aws_cli iam get-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE" \
    --query 'InstanceProfile.Roles[].RoleName' \
    --output text > "$output" 2> "$error"; then
    roles="$(tr '\t' ' ' < "$output" | xargs)"
    if [ -z "$roles" ] || [ "$roles" = "None" ]; then
      record_check "instance-profile-roles" "has-no-role" "$INSTANCE_PROFILE" "$output" "$error"
      blocker "instance-profile-roles:has-no-role"
      return 1
    fi
    if [[ " ${roles} " == *" ${ROLE_NAME} "* ]]; then
      record_check "instance-profile-roles" "ok" "$roles" "$output" "$error"
      return 0
    fi
    record_check "instance-profile-roles" "wrong-role" "$roles" "$output" "$error"
    blocker "instance-profile-roles:wrong-role:${roles}"
    return 1
  fi

  status="$(classify_aws_error "$error")"
  record_check "instance-profile-roles" "$status" "$INSTANCE_PROFILE" "$output" "$error"
  blocker "instance-profile-roles:${status}"
  return 1
}

run_ssm_policy_check() {
  local output="${ARTIFACT_ROOT}/role-attached-policies.out"
  local error="${ARTIFACT_ROOT}/role-attached-policies.err"
  local status

  if aws_cli iam list-attached-role-policies \
    --role-name "$ROLE_NAME" \
    --output json > "$output" 2> "$error"; then
    if grep -q 'AmazonSSMManagedInstanceCore' "$output"; then
      record_check "role-ssm-policy" "ok" "$ROLE_NAME" "$output" "$error"
      return 0
    fi
    record_check "role-ssm-policy" "missing" "$ROLE_NAME" "$output" "$error"
    blocker "role-ssm-policy:missing"
    return 1
  fi

  status="$(classify_aws_error "$error")"
  record_check "role-ssm-policy" "$status" "$ROLE_NAME" "$output" "$error"
  blocker "role-ssm-policy:${status}"
  return 1
}

run_dry_run_check() {
  local name="$1"
  local with_profile="$2"
  local output="${ARTIFACT_ROOT}/${name}.out"
  local error="${ARTIFACT_ROOT}/${name}.err"
  local status
  local args=()

  if [ -z "$IMAGE" ]; then
    record_check "$name" "missing-image" "set COCXY_AWS_IMAGE" "$output" "$error"
    blocker "${name}:missing-image"
    return 1
  fi

  args=(
    ec2 run-instances
    --dry-run
    --region "$REGION"
    --image-id "$IMAGE"
    --instance-type "$VM_SIZE"
  )
  if [ "$with_profile" = "yes" ]; then
    args+=(--iam-instance-profile "Name=${INSTANCE_PROFILE}")
  fi
  args+=(
    --count 1
    --query "Instances[0].InstanceId"
    --output text
  )

  if aws_cli "${args[@]}" > "$output" 2> "$error"; then
    record_check "$name" "unexpected-success" "$IMAGE" "$output" "$error"
    return 0
  fi

  status="$(classify_aws_error "$error")"
  record_check "$name" "$status" "$IMAGE" "$output" "$error"
  if [ "$status" != "authorized" ]; then
    blocker "${name}:${status}"
    return 1
  fi
  return 0
}

aws_account_id() {
  local identity

  identity="$(
    aws_cli sts get-caller-identity --output json 2>/dev/null || true
  )"
  sed -n 's/.*"Account"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<< "$identity" | head -1
}

run_profile_arn_dry_run_check() {
  local name="run-instances-with-profile-arn-dry-run"
  local output="${ARTIFACT_ROOT}/${name}.out"
  local error="${ARTIFACT_ROOT}/${name}.err"
  local account_id
  local profile_arn
  local status
  local args=()

  if [ -z "$IMAGE" ]; then
    record_check "$name" "missing-image" "set COCXY_AWS_IMAGE" "$output" "$error"
    blocker "${name}:missing-image"
    return 1
  fi

  account_id="$(aws_account_id)"
  if [ -z "$account_id" ]; then
    record_check "$name" "missing-account" "$INSTANCE_PROFILE" "$output" "$error"
    blocker "${name}:missing-account"
    return 1
  fi

  profile_arn="arn:aws:iam::${account_id}:instance-profile/${INSTANCE_PROFILE}"
  args=(
    ec2 run-instances
    --dry-run
    --region "$REGION"
    --image-id "$IMAGE"
    --instance-type "$VM_SIZE"
    --iam-instance-profile "Arn=${profile_arn}"
    --count 1
    --query "Instances[0].InstanceId"
    --output text
  )

  if aws_cli "${args[@]}" > "$output" 2> "$error"; then
    record_check "$name" "unexpected-success" "$IMAGE" "$output" "$error"
    return 0
  fi

  status="$(classify_aws_error "$error")"
  record_check "$name" "$status" "$IMAGE" "$output" "$error"
  if [ "$status" != "authorized" ]; then
    blocker "${name}:${status}"
    return 1
  fi
  return 0
}

write_remediation() {
  local blockers_text="${FINAL_BLOCKERS_TEXT:-$(join_blockers "${BLOCKERS[@]}")}"
  local warnings_text="${FINAL_WARNINGS_TEXT:--}"

  cat > "$REMEDIATION_FILE" <<MARKDOWN
# AWS Cocxy Cells Setup Verification

This file was generated by \`scripts/verify-cells-aws-setup.sh\`.

It is a read-only diagnosis artifact. It does not prove that setup was applied,
and it must not be treated as lifecycle smoke evidence.

## Current Inputs

- Region: \`${REGION}\`
- Image: \`${IMAGE:-missing}\`
- VM size: \`${VM_SIZE}\`
- Role: \`${ROLE_NAME}\`
- Instance profile: \`${INSTANCE_PROFILE}\`
- AWS CLI profile: \`${COCXY_AWS_PROFILE:-default}\`
- Checks: \`${CHECKS_FILE#${PROJECT_ROOT}/}\`

## Current Blockers

\`${blockers_text}\`

## Current Warnings

\`${warnings_text}\`

## Expected Green Checks

The verifier reports \`status=ok\` only when:

- \`caller-identity\` is \`ok\`.
- \`role\` is \`ok\` for \`${ROLE_NAME}\`.
- \`role-ssm-policy\` is \`ok\` and includes \`AmazonSSMManagedInstanceCore\`.
- \`instance-profile\` is \`ok\` for \`${INSTANCE_PROFILE}\`.
- \`instance-profile-roles\` is \`ok\` and includes \`${ROLE_NAME}\`.
- \`run-instances-with-profile-dry-run\` is \`authorized\`.
- \`run-instances-with-profile-arn-dry-run\` is \`authorized\`.
- \`run-instances-without-profile-dry-run\` is \`authorized\`.

It reports \`status=ready\` when IAM inspection calls are denied but all EC2
dry-run launch paths are authorized. That state is enough to run the guarded
AWS lifecycle smoke, but it is not lifecycle success by itself.

## Remediation Sequence

1. Generate setup artifacts without mutating AWS:

   \`\`\`sh
   scripts/setup-cells-aws-account.sh
   \`\`\`

2. Have an AWS owner apply the generated \`setup-principal-policy.json\` to the
   principal that is allowed to create or update the role, instance profile, and
   caller policy.

3. Only with explicit owner approval, run the setup helper in apply mode:

   \`\`\`sh
   COCXY_AWS_SETUP_APPLY=1 scripts/setup-cells-aws-account.sh
   \`\`\`

4. Verify the setup again:

   \`\`\`sh
   COCXY_AWS_IMAGE=${IMAGE:-<valid-ami-for-region>} scripts/verify-cells-aws-setup.sh
   \`\`\`

5. When this verifier reports \`status=ok\`, continue with:

   \`\`\`sh
   COCXY_AWS_IMAGE=${IMAGE:-<valid-ami-for-region>} scripts/preflight-cells-cloud-account.sh aws
   COCXY_CELLS_CLOUD_E2E=1 COCXY_AWS_IMAGE=${IMAGE:-<valid-ami-for-region>} scripts/smoke-cells-cloud-account.sh aws
   scripts/preflight-cells-cloud-account.sh all
   \`\`\`
MARKDOWN
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

mkdir -p "$ARTIFACT_ROOT"
: > "$CHECKS_FILE"
printf 'check\tstatus\tdetail\toutput\terror\n' > "$CHECKS_FILE"

if ! command -v aws >/dev/null 2>&1; then
  record_check "aws-cli" "missing" "aws" "" ""
  blocker "aws-cli:missing"
else
  record_check "aws-cli" "present" "$(command -v aws)" "" ""
  run_json_check "caller-identity" "current principal" sts get-caller-identity --output json
  run_json_check "role" "$ROLE_NAME" iam get-role --role-name "$ROLE_NAME" --output json
  run_ssm_policy_check
  run_json_check "instance-profile" "$INSTANCE_PROFILE" iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE" --output json
  run_instance_profile_roles_check
  run_dry_run_check "run-instances-with-profile-dry-run" "yes"
  run_profile_arn_dry_run_check
  run_dry_run_check "run-instances-without-profile-dry-run" "no"
fi

compute_final_state
write_remediation

{
  echo "status=${FINAL_STATUS}"
  echo "artifactRoot=${ARTIFACT_ROOT}"
  echo "checks=${CHECKS_FILE#${PROJECT_ROOT}/}"
  echo "remediation=${REMEDIATION_FILE#${PROJECT_ROOT}/}"
  echo "region=${REGION}"
  echo "image=${IMAGE:-missing}"
  echo "vmSize=${VM_SIZE}"
  echo "roleName=${ROLE_NAME}"
  echo "instanceProfile=${INSTANCE_PROFILE}"
  echo "profile=${COCXY_AWS_PROFILE:-default}"
  echo "blockers=${FINAL_BLOCKERS_TEXT}"
  echo "warnings=${FINAL_WARNINGS_TEXT}"
  echo "result=${FINAL_RESULT}"
  echo "next=if status=ok or status=ready, run scripts/preflight-cells-cloud-account.sh aws and then the guarded cloud smoke"
} | tee "$SUMMARY_FILE"

if [ "$FINAL_STATUS" = "ok" ] || [ "$FINAL_STATUS" = "ready" ]; then
  exit 0
fi
exit 1
