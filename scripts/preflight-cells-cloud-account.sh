#!/usr/bin/env bash
set -euo pipefail

# Read-only preflight for account-backed Cells cloud smokes.
#
# This does not create, attach to, or destroy cloud resources. It only checks
# whether the required provider CLI, required environment variables, and
# already archived E2E summaries are present before running the manual,
# cost-guarded smoke-cells-cloud-account.sh script.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVIDER="${1:-all}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_ROOT="${COCXY_CELLS_CLOUD_PREFLIGHT_ARTIFACTS:-${PROJECT_ROOT}/build/cells-cloud-preflight/${TIMESTAMP}}"
SUMMARY="${ARTIFACT_ROOT}/summary.tsv"
CLOUD_ARTIFACT_BASE="${COCXY_CELLS_CLOUD_ARTIFACT_ROOT:-${PROJECT_ROOT}/build}"

usage() {
  cat <<'USAGE'
usage: scripts/preflight-cells-cloud-account.sh [all|e2b|fly|aws|gcp|azure]

This is read-only and safe to run without COCXY_CELLS_CLOUD_E2E=1.
It reports whether each provider has:
  - required CLI on PATH
  - required environment variables by name only
  - read-only provider prerequisites required before lifecycle smoke
  - existing status=ok cloud E2E summary artifact
  - output evidence files referenced by that summary with matching SHA-256

It never creates cloud resources and never prints secret values.
USAGE
}

provider_tool() {
  case "$1" in
    e2b) echo "e2b" ;;
    fly) echo "fly" ;;
    aws) echo "aws" ;;
    gcp) echo "gcloud" ;;
    azure) echo "az" ;;
    *) echo "" ;;
  esac
}

required_env_names() {
  case "$1" in
    e2b) echo "COCXY_E2B_TEMPLATE" ;;
    fly) echo "COCXY_FLY_APP" ;;
    aws) echo "COCXY_AWS_IMAGE COCXY_AWS_REGION COCXY_AWS_INSTANCE_PROFILE" ;;
    gcp) echo "COCXY_GCP_IMAGE COCXY_GCP_PROJECT COCXY_GCP_ZONE" ;;
    azure) echo "COCXY_AZURE_IMAGE COCXY_AZURE_RESOURCE_GROUP" ;;
  esac
}

field_value() {
  local field="$1"
  local file="$2"
  sed -n "s/^${field}=//p" "$file" | tail -1
}

resolve_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s\n' "${PROJECT_ROOT}/${path}"
  fi
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

verify_referenced_file() {
  local summary="$1"
  local path_field="$2"
  local hash_field="${path_field}Sha256"
  local raw_path
  local expected_hash
  local path

  raw_path="$(field_value "$path_field" "$summary")"
  expected_hash="$(field_value "$hash_field" "$summary")"
  if [ -z "$raw_path" ] || [ -z "$expected_hash" ]; then
    return 1
  fi

  path="$(resolve_path "$raw_path")"
  if [ ! -f "$path" ]; then
    return 1
  fi

  [ "$(sha256_file "$path")" = "$expected_hash" ]
}

verify_cloud_evidence() {
  local summary="$1"
  local field
  for field in \
    createOutput \
    statusOutput \
    execOutput \
    logsOutput \
    attachOutput \
    listOutput \
    destroyOutput
  do
    verify_referenced_file "$summary" "$field" || return 1
  done
  return 0
}

latest_ok_summary() {
  local provider="$1"
  local directory="${CLOUD_ARTIFACT_BASE}/cells-cloud-${provider}"
  local file
  if [ ! -d "$directory" ]; then
    return 1
  fi

  while IFS= read -r file; do
    if grep -q '^status=ok$' "$file" &&
       grep -q "^provider=${provider}$" "$file" &&
       grep -q '^create=ok$' "$file" &&
       grep -q '^status-check=ok$' "$file" &&
       grep -q '^exec=ok$' "$file" &&
       grep -q '^logs=ok$' "$file" &&
       grep -q '^attach=ok$' "$file" &&
       grep -q '^list=ok$' "$file" &&
       grep -q '^destroy=ok$' "$file" &&
       grep -q "^result=cells-cloud-${provider}-ok$" "$file" &&
       verify_cloud_evidence "$file"; then
      printf '%s\n' "$file"
      return 0
    fi
  done < <(
    find "$directory" -maxdepth 2 -type f -name summary.txt -print 2>/dev/null |
      LC_ALL=C sort -r
  )

  return 1
}

latest_any_summary() {
  local provider="$1"
  local directory="${CLOUD_ARTIFACT_BASE}/cells-cloud-${provider}"
  if [ ! -d "$directory" ]; then
    return 1
  fi

  find "$directory" -maxdepth 2 -type f -name summary.txt -print 2>/dev/null |
    LC_ALL=C sort -r |
    head -1
}

relative_artifact_path() {
  local path="$1"
  if [ -z "$path" ]; then
    echo "-"
  elif [[ "$path" = "${PROJECT_ROOT}/"* ]]; then
    printf '%s\n' "${path#${PROJECT_ROOT}/}"
  else
    printf '%s\n' "$path"
  fi
}

join_missing_env() {
  local provider="$1"
  local missing=()
  local name
  for name in $(required_env_names "$provider"); do
    if [ -z "${!name:-}" ]; then
      missing+=("$name")
    fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    echo "-"
  else
    local IFS=","
    echo "${missing[*]}"
  fi
}

gcp_compute_api_enabled() {
  local output
  local error_file="${ARTIFACT_ROOT}/gcp-compute-service.err"

  output="$(
    gcloud services list \
      --enabled \
      --project "$COCXY_GCP_PROJECT" \
      --filter=compute.googleapis.com \
      --format='value(config.name)' \
      2> "$error_file" || true
  )"

  [ "$output" = "compute.googleapis.com" ]
}

write_gcp_diagnostics() {
  local diagnostics="${ARTIFACT_ROOT}/gcp-diagnostics.txt"
  local active_account
  local active_project
  local compute_enabled="no"

  active_account="$(
    gcloud auth list \
      --filter=status:ACTIVE \
      --format='value(account)' \
      2>/dev/null | head -1 || true
  )"
  active_project="$(
    gcloud config get-value project \
      2>/dev/null || true
  )"
  if gcp_compute_api_enabled; then
    compute_enabled="yes"
  fi

  {
    echo "project=${COCXY_GCP_PROJECT:-missing}"
    echo "zone=${COCXY_GCP_ZONE:-missing}"
    echo "image=${COCXY_GCP_IMAGE:-missing}"
    echo "activeAccount=${active_account:-unknown}"
    echo "activeProject=${active_project:-unknown}"
    echo "computeApiEnabled=${compute_enabled}"
    echo "computeServiceError=${ARTIFACT_ROOT}/gcp-compute-service.err"
  } > "$diagnostics"

  printf '%s\n' "$diagnostics"
}

aws_scoped_arguments() {
  if [ -n "${COCXY_AWS_REGION:-}" ]; then
    printf '%s\n' "--region"
    printf '%s\n' "$COCXY_AWS_REGION"
  fi
  if [ -n "${COCXY_AWS_PROFILE:-}" ]; then
    printf '%s\n' "--profile"
    printf '%s\n' "$COCXY_AWS_PROFILE"
  fi
}

aws_profile_arguments() {
  if [ -n "${COCXY_AWS_PROFILE:-}" ]; then
    printf '%s\n' "--profile"
    printf '%s\n' "$COCXY_AWS_PROFILE"
  fi
}

aws_instance_profile_lookup() {
  local output_file="${ARTIFACT_ROOT}/aws-get-instance-profile.out"
  local error_file="${ARTIFACT_ROOT}/aws-get-instance-profile.err"
  local command=()

  command=(
    aws iam get-instance-profile
  )
  if [ -n "${COCXY_AWS_PROFILE:-}" ]; then
    command+=(--profile "$COCXY_AWS_PROFILE")
  fi
  command+=(
    --instance-profile-name "$COCXY_AWS_INSTANCE_PROFILE"
    --query "InstanceProfile.Roles[].RoleName"
    --output text
  )

  "${command[@]}" \
    > "$output_file" \
    2> "$error_file"
}

aws_instance_profile_prerequisite() {
  local output_file="${ARTIFACT_ROOT}/aws-get-instance-profile.out"
  local error_file="${ARTIFACT_ROOT}/aws-get-instance-profile.err"
  local roles

  if [ -z "${COCXY_AWS_INSTANCE_PROFILE:-}" ]; then
    echo "-"
    return 0
  fi

  if aws_instance_profile_lookup; then
    roles="$(tr '\t' ' ' < "$output_file" | xargs)"
    if [ -z "$roles" ] || [ "$roles" = "None" ]; then
      echo "AWS_INSTANCE_PROFILE_HAS_NO_ROLE"
    else
      echo "-"
    fi
    return 0
  fi

  if grep -q "NoSuchEntity\\|cannot be found" "$error_file"; then
    echo "AWS_INSTANCE_PROFILE_NOT_FOUND"
  elif grep -q "AccessDenied\\|not authorized\\|iam:GetInstanceProfile" "$error_file"; then
    echo "AWS_IAM_GET_INSTANCE_PROFILE_DENIED"
  else
    echo "AWS_INSTANCE_PROFILE_LOOKUP_FAILED"
  fi
}

aws_run_instances_dry_run_for_image() {
  local image="$1"
  local label="$2"
  local output_file="${ARTIFACT_ROOT}/aws-run-instances-${label}.out"
  local error_file="${ARTIFACT_ROOT}/aws-run-instances-${label}.err"
  local args=()
  local command=()

  while IFS= read -r item; do
    args+=("$item")
  done < <(aws_scoped_arguments)

  command=(
    aws ec2 run-instances
    --dry-run
    "${args[@]}"
    --image-id "$image"
    --instance-type "${COCXY_AWS_VM_SIZE:-t3.micro}"
  )
  if [ -n "${COCXY_AWS_INSTANCE_PROFILE:-}" ]; then
    command+=(--iam-instance-profile "Name=${COCXY_AWS_INSTANCE_PROFILE}")
  fi
  command+=(
    --count 1
    --query "Instances[0].InstanceId"
    --output text
  )

  "${command[@]}" \
    > "$output_file" \
    2> "$error_file"
}

aws_run_instances_without_instance_profile_dry_run_for_image() {
  local image="$1"
  local label="$2"
  local output_file="${ARTIFACT_ROOT}/aws-run-instances-${label}.out"
  local error_file="${ARTIFACT_ROOT}/aws-run-instances-${label}.err"
  local args=()
  local command=()

  while IFS= read -r item; do
    args+=("$item")
  done < <(aws_scoped_arguments)

  command=(
    aws ec2 run-instances
    --dry-run
    "${args[@]}"
    --image-id "$image"
    --instance-type "${COCXY_AWS_VM_SIZE:-t3.micro}"
    --count 1
    --query "Instances[0].InstanceId"
    --output text
  )

  "${command[@]}" \
    > "$output_file" \
    2> "$error_file"
}

aws_run_instances_profile_arn_dry_run_for_image() {
  local image="$1"
  local label="$2"
  local account_id="$3"
  local output_file="${ARTIFACT_ROOT}/aws-run-instances-${label}.out"
  local error_file="${ARTIFACT_ROOT}/aws-run-instances-${label}.err"
  local profile_arn="arn:aws:iam::${account_id}:instance-profile/${COCXY_AWS_INSTANCE_PROFILE}"
  local args=()
  local command=()

  while IFS= read -r item; do
    args+=("$item")
  done < <(aws_scoped_arguments)

  command=(
    aws ec2 run-instances
    --dry-run
    "${args[@]}"
    --image-id "$image"
    --instance-type "${COCXY_AWS_VM_SIZE:-t3.micro}"
    --iam-instance-profile "Arn=${profile_arn}"
    --count 1
    --query "Instances[0].InstanceId"
    --output text
  )

  "${command[@]}" \
    > "$output_file" \
    2> "$error_file"
}

aws_run_instances_dry_run() {
  aws_run_instances_dry_run_for_image "$COCXY_AWS_IMAGE" "dry-run"
}

aws_classify_run_instances_error() {
  local error_file="$1"

  if grep -q "DryRunOperation" "$error_file"; then
    echo "-"
  elif grep -q "InvalidAMIID" "$error_file"; then
    echo "AWS_INVALID_AMI"
  elif grep -q "SsmAccessDenied\\|ssm:GetParameter" "$error_file"; then
    echo "AWS_SSM_GETPARAMETERS_DENIED"
  elif grep -q "Invalid IAM Instance Profile\\|iamInstanceProfile" "$error_file"; then
    echo "AWS_INVALID_INSTANCE_PROFILE"
  elif grep -q "UnauthorizedOperation" "$error_file"; then
    echo "AWS_RUNINSTANCES_UNAUTHORIZED"
  else
    echo "AWS_RUNINSTANCES_DRY_RUN_FAILED"
  fi
}

aws_dry_run_prerequisite() {
  local error_file="${ARTIFACT_ROOT}/aws-run-instances-dry-run.err"
  local prerequisite
  local profile_prerequisite
  local probe_error_file="${ARTIFACT_ROOT}/aws-run-instances-permission-probe.err"
  local probe_prerequisite

  if aws_run_instances_dry_run; then
    echo "-"
    return 0
  fi

  prerequisite="$(aws_classify_run_instances_error "$error_file")"
  if [ "$prerequisite" = "AWS_INVALID_INSTANCE_PROFILE" ]; then
    profile_prerequisite="$(aws_instance_profile_prerequisite)"
    if [ "$profile_prerequisite" != "-" ]; then
      echo "${prerequisite},${profile_prerequisite}"
      return 0
    fi
  fi
  if [ "$prerequisite" = "AWS_INVALID_AMI" ] &&
     [ -n "${COCXY_AWS_PERMISSION_PROBE_IMAGE:-}" ]; then
    if aws_run_instances_dry_run_for_image "$COCXY_AWS_PERMISSION_PROBE_IMAGE" "permission-probe"; then
      echo "$prerequisite"
      return 0
    fi
    probe_prerequisite="$(aws_classify_run_instances_error "$probe_error_file")"
    if [ "$probe_prerequisite" != "-" ] &&
       [ "$probe_prerequisite" != "$prerequisite" ]; then
      echo "${prerequisite},${probe_prerequisite}"
      return 0
    fi
  fi

  echo "$prerequisite"
}

aws_without_instance_profile_dry_run_status() {
  local error_file="${ARTIFACT_ROOT}/aws-run-instances-without-profile-dry-run.err"
  local prerequisite

  if aws_run_instances_without_instance_profile_dry_run_for_image "$COCXY_AWS_IMAGE" "without-profile-dry-run"; then
    echo "unexpected-success"
    return 0
  fi

  prerequisite="$(aws_classify_run_instances_error "$error_file")"
  if [ "$prerequisite" = "-" ]; then
    echo "authorized"
  else
    echo "$prerequisite"
  fi
}

aws_profile_arn_dry_run_status() {
  local account_id="$1"
  local error_file="${ARTIFACT_ROOT}/aws-run-instances-profile-arn-dry-run.err"
  local prerequisite

  if [ -z "$account_id" ] || [ -z "${COCXY_AWS_INSTANCE_PROFILE:-}" ]; then
    echo "not-run"
    return 0
  fi

  if aws_run_instances_profile_arn_dry_run_for_image "$COCXY_AWS_IMAGE" "profile-arn-dry-run" "$account_id"; then
    echo "unexpected-success"
    return 0
  fi

  prerequisite="$(aws_classify_run_instances_error "$error_file")"
  if [ "$prerequisite" = "-" ]; then
    echo "authorized"
  else
    echo "$prerequisite"
  fi
}

aws_iam_read_status() {
  local label="$1"
  shift
  local output_file="${ARTIFACT_ROOT}/aws-iam-${label}.out"
  local error_file="${ARTIFACT_ROOT}/aws-iam-${label}.err"
  local command=(aws "$@")

  if [ -n "${COCXY_AWS_PROFILE:-}" ]; then
    command+=(--profile "$COCXY_AWS_PROFILE")
  fi
  command+=(--output json)

  if "${command[@]}" > "$output_file" 2> "$error_file"; then
    echo "ok"
  elif grep -q "AccessDenied\\|not authorized" "$error_file"; then
    echo "access-denied"
  elif grep -q "NoSuchEntity\\|cannot be found" "$error_file"; then
    echo "not-found"
  else
    echo "failed"
  fi
}

aws_ssm_runtime_policy_simulation() {
  local identity="$1"
  local output_file="${ARTIFACT_ROOT}/aws-ssm-runtime-simulate-principal-policy.out"
  local error_file="${ARTIFACT_ROOT}/aws-ssm-runtime-simulate-principal-policy.err"
  local command=(
    aws iam simulate-principal-policy
    --policy-source-arn "$identity"
    --action-names
    ssm:SendCommand
    ssm:GetCommandInvocation
    ssm:ListCommandInvocations
    ssm:StartSession
    --resource-arns "*"
    --output json
  )

  if [ -n "${COCXY_AWS_PROFILE:-}" ]; then
    command+=(--profile "$COCXY_AWS_PROFILE")
  fi

  if [ -z "$identity" ] || [ "$identity" = "unknown" ]; then
    echo "not-run"
    return 0
  fi

  if "${command[@]}" > "$output_file" 2> "$error_file"; then
    if grep -q '"EvalDecision"[[:space:]]*:[[:space:]]*"explicitDeny"' "$output_file"; then
      echo "explicit-deny"
    elif grep -q '"EvalDecision"[[:space:]]*:[[:space:]]*"implicitDeny"' "$output_file"; then
      echo "implicit-deny"
    elif [ "$(grep -o '"EvalDecision"[[:space:]]*:[[:space:]]*"allowed"' "$output_file" | wc -l | tr -d ' ')" -ge 4 ]; then
      echo "allowed"
    else
      echo "unknown"
    fi
  elif grep -q "AccessDenied\\|not authorized" "$error_file"; then
    echo "access-denied"
  else
    echo "failed"
  fi
}

write_aws_required_policy() {
  local policy="${ARTIFACT_ROOT}/aws-required-policy.json"
  local account_id="${1:-}"
  local setup_role_name="${2:-${COCXY_AWS_SETUP_ROLE:-CocxyCellsSSMRole}}"
  local instance_profile_name="${3:-${COCXY_AWS_INSTANCE_PROFILE:-}}"
  local pass_role_resource="*"
  local inspect_role_resource="*"
  local inspect_profile_resource="*"

  if [ -n "$account_id" ] && [ -n "$setup_role_name" ]; then
    pass_role_resource="arn:aws:iam::${account_id}:role/${setup_role_name}"
    inspect_role_resource="$pass_role_resource"
  fi
  if [ -n "$account_id" ] && [ -n "$instance_profile_name" ]; then
    inspect_profile_resource="arn:aws:iam::${account_id}:instance-profile/${instance_profile_name}"
  fi

  cat > "$policy" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CocxyCellsEC2Lifecycle",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeRegions",
        "ec2:RunInstances",
        "ec2:TerminateInstances"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CocxyCellsSSMLifecycle",
      "Effect": "Allow",
      "Action": [
        "ssm:GetCommandInvocation",
        "ssm:ListCommandInvocations",
        "ssm:SendCommand",
        "ssm:StartSession"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CocxyCellsPassInstanceProfileRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "${pass_role_resource}",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "ec2.amazonaws.com"
        }
      }
    },
    {
      "Sid": "CocxyCellsInspectInstanceProfileRole",
      "Effect": "Allow",
      "Action": [
        "iam:GetRole",
        "iam:ListAttachedRolePolicies"
      ],
      "Resource": "${inspect_role_resource}"
    },
    {
      "Sid": "CocxyCellsInspectInstanceProfile",
      "Effect": "Allow",
      "Action": "iam:GetInstanceProfile",
      "Resource": "${inspect_profile_resource}"
    }
  ]
}
JSON

  printf '%s\n' "$policy"
}

write_aws_diagnostic_policy() {
  local policy="${ARTIFACT_ROOT}/aws-diagnostic-policy.json"

  cat > "$policy" <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CocxyCellsDiagnosticIdentityRead",
      "Effect": "Allow",
      "Action": [
        "iam:GetUser",
        "iam:ListAttachedUserPolicies",
        "iam:ListGroupsForUser",
        "iam:ListUserPolicies"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CocxyCellsDiagnosticPolicySimulation",
      "Effect": "Allow",
      "Action": "iam:SimulatePrincipalPolicy",
      "Resource": "*"
    }
  ]
}
JSON

  printf '%s\n' "$policy"
}

write_aws_setup_principal_policy() {
  local account_id="${1:-}"
  local setup_role_name="${2:-CocxyCellsSSMRole}"
  local policy="${ARTIFACT_ROOT}/aws-setup-principal-policy.json"
  local pass_role_resource="*"

  if [ -n "$account_id" ] && [ -n "$setup_role_name" ]; then
    pass_role_resource="arn:aws:iam::${account_id}:role/${setup_role_name}"
  fi

  cat > "$policy" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CocxyCellsSetupIdentity",
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    },
    {
      "Sid": "CocxyCellsSetupRoleAndProfile",
      "Effect": "Allow",
      "Action": [
        "iam:AddRoleToInstanceProfile",
        "iam:AttachRolePolicy",
        "iam:CreateInstanceProfile",
        "iam:CreateRole",
        "iam:GetInstanceProfile",
        "iam:GetRole",
        "iam:ListAttachedRolePolicies",
        "iam:ListInstanceProfiles",
        "iam:ListRoles",
        "iam:UpdateAssumeRolePolicy"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CocxyCellsSetupPassRoleToInstanceProfile",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "${pass_role_resource}",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "ec2.amazonaws.com"
        }
      }
    },
    {
      "Sid": "CocxyCellsSetupCallerPolicy",
      "Effect": "Allow",
      "Action": [
        "iam:AttachUserPolicy",
        "iam:CreatePolicy",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:GetPolicy",
        "iam:ListPolicyVersions"
      ],
      "Resource": "*"
    }
  ]
}
JSON

  printf '%s\n' "$policy"
}

write_aws_required_setup() {
  local setup="${ARTIFACT_ROOT}/aws-required-setup.md"

  cat > "$setup" <<'MARKDOWN'
# AWS Cocxy Cells Required Setup

This account-backed smoke cannot pass until the AWS owner configures both:

1. A caller identity that can create, inspect, SSM-connect to, and terminate disposable EC2 instances.
2. An EC2 instance profile whose role lets the launched VM register with AWS Systems Manager.

## Required Environment

```sh
export COCXY_AWS_REGION=us-east-1
export COCXY_AWS_IMAGE=<valid-ami-for-region>
export COCXY_AWS_INSTANCE_PROFILE=<ssm-capable-instance-profile-name>
```

Optional:

```sh
export COCXY_AWS_PROFILE=<aws-cli-profile>
export COCXY_AWS_SETUP_ROLE=<role-inside-instance-profile>
export COCXY_AWS_SUBNET=<subnet-id>
export COCXY_AWS_SECURITY_GROUP=<security-group-id[,security-group-id...]>
export COCXY_AWS_KEY_NAME=<ec2-keypair-name>
export COCXY_AWS_VM_SIZE=t3.micro
```

## Caller Policy

Apply `aws-required-policy.json` to the IAM principal that runs the smoke, or an equivalent least-privilege policy scoped to the account resources. This runtime policy must include the SSM actions used after the EC2 instance reaches `running`: `ssm:SendCommand`, `ssm:GetCommandInvocation`, `ssm:ListCommandInvocations`, and `ssm:StartSession`. A `DryRunOperation` from `ec2:RunInstances` proves only the launch/profile path; it does not prove Cocxy Cells exec, logs, or attach.

The preflight reads the configured instance profile with `iam:GetInstanceProfile` so it can distinguish a missing or unreadable profile from an EC2 dry-run failure. The setup verifier also reads the expected EC2 role with `iam:GetRole` and `iam:ListAttachedRolePolicies` to prove `AmazonSSMManagedInstanceCore` is attached before treating AWS as green.

The caller must also be allowed to pass the EC2 role backing `COCXY_AWS_INSTANCE_PROFILE` to EC2. Set `COCXY_AWS_SETUP_ROLE` to the actual role inside that instance profile before relying on the scoped generated policies. If the AWS owner created the role and instance profile with the same name, export the same value for both `COCXY_AWS_SETUP_ROLE` and `COCXY_AWS_INSTANCE_PROFILE`.

When the preflight can read the AWS account ID from `sts get-caller-identity`, it writes `aws-required-policy.json` with `iam:PassRole`, `iam:GetRole`, and `iam:ListAttachedRolePolicies` scoped to the expected Cells role, plus `iam:GetInstanceProfile` scoped to the expected instance profile. Prefer that generated policy over a broad wildcard copy.

## Optional Diagnostic Policy

`aws-diagnostic-policy.json` is optional and read-only. It lets the preflight
inspect the active IAM user's policy attachments and run
`iam:SimulatePrincipalPolicy` before any billable lifecycle smoke. If an owner
does not grant it, the preflight records `ssmRuntimePolicySimulation=access-denied`
and the AWS lifecycle smoke remains the source of truth.

## Diagnostic Read Access

For clean preflight diagnostics, the runtime or an admin verifier should be able to inspect the configured IAM setup:

```sh
aws iam get-instance-profile --instance-profile-name "$COCXY_AWS_INSTANCE_PROFILE"
aws iam get-role --role-name "$COCXY_AWS_SETUP_ROLE"
aws iam list-attached-role-policies --role-name "$COCXY_AWS_SETUP_ROLE"
aws iam list-instance-profiles
aws iam list-roles
```

If the runtime identity is an IAM user, the preflight also records whether it can inspect its own attachment state with `iam:GetUser`, `iam:ListAttachedUserPolicies`, `iam:ListUserPolicies`, and `iam:ListGroupsForUser`. These self-inspection checks are diagnostic. The lifecycle blockers are the SSM-capable instance profile/`iam:PassRole` launch path and the caller's SSM runtime permissions for exec/logs/attach.

## Setup Principal Policy

If the current principal cannot create or inspect IAM roles, policies, and instance profiles, first run the setup helper in dry-run mode:

```sh
scripts/setup-cells-aws-account.sh
```

This preflight archives `aws-setup-principal-policy.json`, the policy for the IAM principal allowed to run the setup helper itself. The setup helper dry-run also writes the same policy as `setup-principal-policy.json`. This setup policy includes `iam:PassRole` because AWS requires it when adding the role to the EC2 instance profile. This is separate from `aws-required-policy.json`, which is the runtime/smoke policy.

After an AWS owner applies `setup-principal-policy.json` to a setup principal, run:

```sh
COCXY_AWS_SETUP_APPLY=1 scripts/setup-cells-aws-account.sh
```

## Instance Profile

The EC2 instance profile should point to a role trusted by EC2:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Attach AWS managed policy `AmazonSSMManagedInstanceCore` or equivalent permissions to that role. Cocxy uses SSM for AWS Cell exec, logs, and attach.

## Verification Commands

```sh
COCXY_AWS_PERMISSION_PROBE_IMAGE=<known-valid-ami> scripts/preflight-cells-cloud-account.sh aws
scripts/verify-cells-aws-setup.sh
COCXY_CELLS_CLOUD_E2E=1 scripts/smoke-cells-cloud-account.sh aws
scripts/preflight-cells-cloud-account.sh all
```
MARKDOWN

  printf '%s\n' "$setup"
}

write_aws_diagnostics() {
  local diagnostics="${ARTIFACT_ROOT}/aws-diagnostics.txt"
  local required_policy
  local diagnostic_policy
  local setup_principal_policy
  local required_setup
  local identity="unknown"
  local identity_command=()
  local dry_run="unknown"
  local profile_arn_dry_run="not-run"
  local without_profile_dry_run="unknown"
  local instance_profile_check="-"
  local profile_name="${COCXY_AWS_PROFILE:-default}"
  local profile_source="default"
  local configured_profiles_output="${ARTIFACT_ROOT}/aws-configured-profiles.out"
  local configured_profiles_error="${ARTIFACT_ROOT}/aws-configured-profiles.err"
  local configured_profile_count="unknown"
  local caller_identity_type="unknown"
  local caller_account_id=""
  local caller_user_name=""
  local iam_get_user="skipped"
  local iam_list_attached_user_policies="skipped"
  local iam_list_user_policies="skipped"
  local iam_list_groups_for_user="skipped"
  local setup_role_name="${COCXY_AWS_SETUP_ROLE:-CocxyCellsSSMRole}"
  local iam_get_setup_role="skipped"
  local iam_list_roles="skipped"
  local iam_list_instance_profiles="skipped"
  local ssm_runtime_policy_simulation="not-run"

  if [ -n "${COCXY_AWS_PROFILE:-}" ]; then
    profile_source="COCXY_AWS_PROFILE"
  fi
  if aws configure list-profiles > "$configured_profiles_output" 2> "$configured_profiles_error"; then
    configured_profile_count="$(awk 'NF { count++ } END { print count + 0 }' "$configured_profiles_output")"
  fi

  identity_command=(
    aws sts get-caller-identity
  )
  if [ -n "${COCXY_AWS_PROFILE:-}" ]; then
    identity_command+=(--profile "$COCXY_AWS_PROFILE")
  fi
  identity_command+=(
    --query Arn
    --output text
  )

  identity="$(
    "${identity_command[@]}" 2>/dev/null || true
  )"
  if [[ "$identity" == arn:aws:* ]]; then
    local arn_part partition_part service_part region_part account_part rest_part
    IFS=':' read -r arn_part partition_part service_part region_part account_part rest_part <<< "$identity"
    caller_account_id="$account_part"
  fi
  if [[ "$identity" == arn:aws:iam::*:user/* ]]; then
    caller_identity_type="user"
    caller_user_name="${identity##*/}"
    iam_get_user="$(aws_iam_read_status "get-user" iam get-user --user-name "$caller_user_name")"
    iam_list_attached_user_policies="$(
      aws_iam_read_status \
        "list-attached-user-policies" \
        iam list-attached-user-policies \
        --user-name "$caller_user_name"
    )"
    iam_list_user_policies="$(
      aws_iam_read_status \
        "list-user-policies" \
        iam list-user-policies \
        --user-name "$caller_user_name"
    )"
    iam_list_groups_for_user="$(
      aws_iam_read_status \
        "list-groups-for-user" \
        iam list-groups-for-user \
        --user-name "$caller_user_name"
    )"
  elif [ -n "$identity" ] && [ "$identity" != "unknown" ]; then
    caller_identity_type="non-user"
  fi
  if [[ "$identity" == arn:aws:* ]]; then
    ssm_runtime_policy_simulation="$(aws_ssm_runtime_policy_simulation "$identity")"
  fi
  iam_get_setup_role="$(aws_iam_read_status "get-setup-role" iam get-role --role-name "$setup_role_name")"
  iam_list_roles="$(aws_iam_read_status "list-roles" iam list-roles)"
  iam_list_instance_profiles="$(aws_iam_read_status "list-instance-profiles" iam list-instance-profiles)"
  if [ -n "${COCXY_AWS_INSTANCE_PROFILE:-}" ]; then
    instance_profile_check="$(aws_instance_profile_prerequisite)"
  fi
  dry_run="$(aws_dry_run_prerequisite)"
  profile_arn_dry_run="$(aws_profile_arn_dry_run_status "$caller_account_id")"
  without_profile_dry_run="$(aws_without_instance_profile_dry_run_status)"
  required_policy="$(write_aws_required_policy "$caller_account_id" "$setup_role_name" "${COCXY_AWS_INSTANCE_PROFILE:-}")"
  diagnostic_policy="$(write_aws_diagnostic_policy)"
  setup_principal_policy="$(write_aws_setup_principal_policy "$caller_account_id" "$setup_role_name")"
  required_setup="$(write_aws_required_setup)"

  {
    echo "region=${COCXY_AWS_REGION:-missing}"
    echo "image=${COCXY_AWS_IMAGE:-missing}"
    echo "vmSize=${COCXY_AWS_VM_SIZE:-t3.micro}"
    echo "profile=${profile_name}"
    echo "profileSource=${profile_source}"
    echo "configuredProfileCount=${configured_profile_count}"
    echo "configuredProfilesOutput=${configured_profiles_output}"
    echo "configuredProfilesError=${configured_profiles_error}"
    echo "callerIdentityType=${caller_identity_type}"
    echo "iamGetUser=${iam_get_user}"
    echo "iamGetUserOutput=${ARTIFACT_ROOT}/aws-iam-get-user.out"
    echo "iamGetUserError=${ARTIFACT_ROOT}/aws-iam-get-user.err"
    echo "iamListAttachedUserPolicies=${iam_list_attached_user_policies}"
    echo "iamListAttachedUserPoliciesOutput=${ARTIFACT_ROOT}/aws-iam-list-attached-user-policies.out"
    echo "iamListAttachedUserPoliciesError=${ARTIFACT_ROOT}/aws-iam-list-attached-user-policies.err"
    echo "iamListUserPolicies=${iam_list_user_policies}"
    echo "iamListUserPoliciesOutput=${ARTIFACT_ROOT}/aws-iam-list-user-policies.out"
    echo "iamListUserPoliciesError=${ARTIFACT_ROOT}/aws-iam-list-user-policies.err"
    echo "iamListGroupsForUser=${iam_list_groups_for_user}"
    echo "iamListGroupsForUserOutput=${ARTIFACT_ROOT}/aws-iam-list-groups-for-user.out"
    echo "iamListGroupsForUserError=${ARTIFACT_ROOT}/aws-iam-list-groups-for-user.err"
    echo "setupRole=${setup_role_name}"
    echo "iamGetSetupRole=${iam_get_setup_role}"
    echo "iamGetSetupRoleOutput=${ARTIFACT_ROOT}/aws-iam-get-setup-role.out"
    echo "iamGetSetupRoleError=${ARTIFACT_ROOT}/aws-iam-get-setup-role.err"
    echo "iamListRoles=${iam_list_roles}"
    echo "iamListRolesOutput=${ARTIFACT_ROOT}/aws-iam-list-roles.out"
    echo "iamListRolesError=${ARTIFACT_ROOT}/aws-iam-list-roles.err"
    echo "iamListInstanceProfiles=${iam_list_instance_profiles}"
    echo "iamListInstanceProfilesOutput=${ARTIFACT_ROOT}/aws-iam-list-instance-profiles.out"
    echo "iamListInstanceProfilesError=${ARTIFACT_ROOT}/aws-iam-list-instance-profiles.err"
    echo "ssmRuntimePolicySimulation=${ssm_runtime_policy_simulation}"
    echo "ssmRuntimePolicySimulationOutput=${ARTIFACT_ROOT}/aws-ssm-runtime-simulate-principal-policy.out"
    echo "ssmRuntimePolicySimulationError=${ARTIFACT_ROOT}/aws-ssm-runtime-simulate-principal-policy.err"
    echo "instanceProfile=${COCXY_AWS_INSTANCE_PROFILE:-missing}"
    echo "instanceProfileCheck=${instance_profile_check}"
    echo "instanceProfileLookupOutput=${ARTIFACT_ROOT}/aws-get-instance-profile.out"
    echo "instanceProfileLookupError=${ARTIFACT_ROOT}/aws-get-instance-profile.err"
    echo "identity=${identity:-unknown}"
    echo "runInstancesDryRun=${dry_run}"
    echo "runInstancesDryRunOutput=${ARTIFACT_ROOT}/aws-run-instances-dry-run.out"
    echo "runInstancesDryRunError=${ARTIFACT_ROOT}/aws-run-instances-dry-run.err"
    echo "runInstancesProfileArnDryRun=${profile_arn_dry_run}"
    echo "runInstancesProfileArnDryRunOutput=${ARTIFACT_ROOT}/aws-run-instances-profile-arn-dry-run.out"
    echo "runInstancesProfileArnDryRunError=${ARTIFACT_ROOT}/aws-run-instances-profile-arn-dry-run.err"
    echo "runInstancesWithoutProfileDryRun=${without_profile_dry_run}"
    echo "runInstancesWithoutProfileDryRunOutput=${ARTIFACT_ROOT}/aws-run-instances-without-profile-dry-run.out"
    echo "runInstancesWithoutProfileDryRunError=${ARTIFACT_ROOT}/aws-run-instances-without-profile-dry-run.err"
    echo "requiredPolicy=${required_policy#${PROJECT_ROOT}/}"
    echo "diagnosticPolicy=${diagnostic_policy#${PROJECT_ROOT}/}"
    echo "setupPrincipalPolicy=${setup_principal_policy#${PROJECT_ROOT}/}"
    echo "requiredSetup=${required_setup#${PROJECT_ROOT}/}"
    if [ -n "${COCXY_AWS_PERMISSION_PROBE_IMAGE:-}" ]; then
      echo "permissionProbeImage=${COCXY_AWS_PERMISSION_PROBE_IMAGE}"
      if [ -f "${ARTIFACT_ROOT}/aws-run-instances-permission-probe.out" ] ||
         [ -f "${ARTIFACT_ROOT}/aws-run-instances-permission-probe.err" ]; then
        echo "permissionProbeStatus=ran"
        echo "permissionProbeOutput=${ARTIFACT_ROOT}/aws-run-instances-permission-probe.out"
        echo "permissionProbeError=${ARTIFACT_ROOT}/aws-run-instances-permission-probe.err"
      else
        echo "permissionProbeStatus=not-run"
      fi
    fi
  } > "$diagnostics"

  printf '%s\n' "$diagnostics"
}

azure_create_validate() {
  local output_file="${ARTIFACT_ROOT}/azure-vm-create-validate.out"
  local error_file="${ARTIFACT_ROOT}/azure-vm-create-validate.err"

  local command=(
    az vm create
    --validate
  )
  if [ -n "${COCXY_AZURE_SUBSCRIPTION:-}" ]; then
    command+=(--subscription "$COCXY_AZURE_SUBSCRIPTION")
  fi

  "${command[@]}" \
    --resource-group "$COCXY_AZURE_RESOURCE_GROUP" \
    --name "cocxy-preflight-${TIMESTAMP}" \
    --image "$COCXY_AZURE_IMAGE" \
    --admin-username "${COCXY_AZURE_USER:-cocxy}" \
    --size "${COCXY_AZURE_VM_SIZE:-Standard_B1s}" \
    ${COCXY_AZURE_LOCATION:+--location "$COCXY_AZURE_LOCATION"} \
    --tags dev.cocxy.cell=true \
    --query id \
    --output tsv \
    > "$output_file" \
    2> "$error_file"
}

azure_validate_prerequisite() {
  local error_file="${ARTIFACT_ROOT}/azure-vm-create-validate.err"

  if azure_create_validate; then
    echo "-"
    return 0
  fi

  if grep -q "SkuNotAvailable" "$error_file"; then
    echo "AZURE_SKU_NOT_AVAILABLE"
  elif grep -q "admin user name cannot" "$error_file"; then
    echo "AZURE_INVALID_ADMIN_USERNAME"
  elif grep -q "AuthorizationFailed\\|not authorized" "$error_file"; then
    echo "AZURE_AUTHORIZATION_FAILED"
  else
    echo "AZURE_VM_CREATE_VALIDATE_FAILED"
  fi
}

write_azure_diagnostics() {
  local diagnostics="${ARTIFACT_ROOT}/azure-diagnostics.txt"
  local account="unknown"
  local group_location="unknown"
  local validation="unknown"

  account="$(
    az account show \
      --query user.name \
      --output tsv \
      2>/dev/null || true
  )"
  group_location="$(
    az group show \
      --name "$COCXY_AZURE_RESOURCE_GROUP" \
      --query location \
      --output tsv \
      2>/dev/null || true
  )"
  validation="$(azure_validate_prerequisite)"

  {
    echo "resourceGroup=${COCXY_AZURE_RESOURCE_GROUP:-missing}"
    echo "resourceGroupLocation=${group_location:-unknown}"
    echo "image=${COCXY_AZURE_IMAGE:-missing}"
    echo "location=${COCXY_AZURE_LOCATION:-resource-group-default}"
    echo "vmSize=${COCXY_AZURE_VM_SIZE:-Standard_B1s}"
    echo "adminUsername=${COCXY_AZURE_USER:-cocxy}"
    echo "account=${account:-unknown}"
    echo "vmCreateValidate=${validation}"
    echo "vmCreateValidateOutput=${ARTIFACT_ROOT}/azure-vm-create-validate.out"
    echo "vmCreateValidateError=${ARTIFACT_ROOT}/azure-vm-create-validate.err"
  } > "$diagnostics"

  printf '%s\n' "$diagnostics"
}

join_missing_prerequisites() {
  local provider="$1"
  local tool_status="$2"
  local missing_env="$3"
  local missing=()
  local aws_prerequisite
  local azure_prerequisite

  if [ "$missing_env" != "-" ]; then
    missing+=("$missing_env")
  fi

  if [ "$provider" = "gcp" ] &&
     [ "$tool_status" = "present" ] &&
     [ -n "${COCXY_GCP_PROJECT:-}" ] &&
     ! gcp_compute_api_enabled; then
    missing+=("GCP_COMPUTE_API_NOT_ENABLED")
  fi

  if [ "$provider" = "aws" ] &&
     [ "$tool_status" = "present" ] &&
     [ -n "${COCXY_AWS_IMAGE:-}" ] &&
     [ -n "${COCXY_AWS_REGION:-}" ]; then
    aws_prerequisite="$(aws_dry_run_prerequisite)"
    if [ "$aws_prerequisite" != "-" ]; then
      missing+=("$aws_prerequisite")
    fi
  fi

  if [ "$provider" = "azure" ] &&
     [ "$tool_status" = "present" ] &&
     [ -n "${COCXY_AZURE_IMAGE:-}" ] &&
     [ -n "${COCXY_AZURE_RESOURCE_GROUP:-}" ]; then
    azure_prerequisite="$(azure_validate_prerequisite)"
    if [ "$azure_prerequisite" != "-" ]; then
      missing+=("$azure_prerequisite")
    fi
  fi

  if [ "${#missing[@]}" -eq 0 ]; then
    echo "-"
  else
    local IFS=","
    echo "${missing[*]}"
  fi
}

emit_provider() {
  local provider="$1"
  local tool
  local tool_status="missing"
  local missing_env
  local missing_prerequisites
  local artifact="-"
  local latest_smoke_artifact="-"
  local latest_smoke_status="-"
  local latest_smoke_reason="-"
  local latest_smoke_output="-"
  local status="blocked"

  tool="$(provider_tool "$provider")"
  if command -v "$tool" >/dev/null 2>&1; then
    tool_status="present"
  fi

  missing_env="$(join_missing_env "$provider")"
  missing_prerequisites="$(join_missing_prerequisites "$provider" "$tool_status" "$missing_env")"
  if artifact_path="$(latest_ok_summary "$provider")"; then
    artifact="${artifact_path#${PROJECT_ROOT}/}"
    missing_prerequisites="-"
    status="complete"
  elif [ "$tool_status" = "present" ] && [ "$missing_prerequisites" = "-" ]; then
    status="ready"
  fi

  if latest_smoke_path="$(latest_any_summary "$provider")"; then
    latest_smoke_artifact="$(relative_artifact_path "$latest_smoke_path")"
    latest_smoke_status="$(field_value status "$latest_smoke_path")"
    latest_smoke_reason="$(field_value reason "$latest_smoke_path")"
    latest_smoke_output="$(relative_artifact_path "$(field_value output "$latest_smoke_path")")"
    latest_smoke_status="${latest_smoke_status:-unknown}"
    latest_smoke_reason="${latest_smoke_reason:-unknown}"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$provider" \
    "$status" \
    "$tool" \
    "$tool_status" \
    "$missing_prerequisites" \
    "$artifact" \
    "$latest_smoke_artifact" \
    "$latest_smoke_status" \
    "$latest_smoke_reason" \
    "$latest_smoke_output" | tee -a "$SUMMARY" >/dev/null
}

case "$PROVIDER" in
  -h|--help)
    usage
    exit 0
    ;;
  all|e2b|fly|aws|gcp|azure) ;;
  *)
    usage
    exit 2
    ;;
esac

mkdir -p "$ARTIFACT_ROOT"
printf 'provider\tstatus\ttool\ttoolStatus\tmissingPrerequisites\tokArtifact\tlatestSmokeArtifact\tlatestSmokeStatus\tlatestSmokeReason\tlatestSmokeOutput\n' > "$SUMMARY"
GCP_DIAGNOSTICS=""
AWS_DIAGNOSTICS=""
AZURE_DIAGNOSTICS=""

if [ "$PROVIDER" = "all" ]; then
  for item in e2b fly aws gcp azure; do
    emit_provider "$item"
  done
else
  emit_provider "$PROVIDER"
fi

if { [ "$PROVIDER" = "all" ] || [ "$PROVIDER" = "gcp" ]; } &&
   command -v gcloud >/dev/null 2>&1 &&
   [ -n "${COCXY_GCP_PROJECT:-}" ]; then
  GCP_DIAGNOSTICS="$(write_gcp_diagnostics)"
fi

if { [ "$PROVIDER" = "all" ] || [ "$PROVIDER" = "aws" ]; } &&
   command -v aws >/dev/null 2>&1 &&
   [ -n "${COCXY_AWS_IMAGE:-}" ] &&
   [ -n "${COCXY_AWS_REGION:-}" ]; then
  AWS_DIAGNOSTICS="$(write_aws_diagnostics)"
fi

if { [ "$PROVIDER" = "all" ] || [ "$PROVIDER" = "azure" ]; } &&
   command -v az >/dev/null 2>&1 &&
   [ -n "${COCXY_AZURE_IMAGE:-}" ] &&
   [ -n "${COCXY_AZURE_RESOURCE_GROUP:-}" ]; then
  AZURE_DIAGNOSTICS="$(write_azure_diagnostics)"
fi

blocked_count="$(awk -F '\t' 'NR > 1 && $2 == "blocked" { count++ } END { print count + 0 }' "$SUMMARY")"
ready_count="$(awk -F '\t' 'NR > 1 && $2 == "ready" { count++ } END { print count + 0 }' "$SUMMARY")"
complete_count="$(awk -F '\t' 'NR > 1 && $2 == "complete" { count++ } END { print count + 0 }' "$SUMMARY")"

{
  total_count="$(awk -F '\t' 'NR > 1 { count++ } END { print count + 0 }' "$SUMMARY")"
  if [ "$blocked_count" -eq 0 ] && [ "$complete_count" -eq "$total_count" ]; then
    echo "status=complete"
  elif [ "$blocked_count" -eq 0 ]; then
    echo "status=ready"
  else
    echo "status=blocked"
  fi
  echo "artifactRoot=${ARTIFACT_ROOT}"
  echo "summary=${SUMMARY}"
  echo "blocked=${blocked_count}"
  echo "ready=${ready_count}"
  echo "complete=${complete_count}"
  if [ -n "$GCP_DIAGNOSTICS" ]; then
    echo "gcpDiagnostics=${GCP_DIAGNOSTICS#${PROJECT_ROOT}/}"
  fi
  if [ -n "$AWS_DIAGNOSTICS" ]; then
    echo "awsDiagnostics=${AWS_DIAGNOSTICS#${PROJECT_ROOT}/}"
  fi
  if [ -n "$AZURE_DIAGNOSTICS" ]; then
    echo "azureDiagnostics=${AZURE_DIAGNOSTICS#${PROJECT_ROOT}/}"
  fi
  echo "next=scripts/smoke-cells-cloud-account.sh <provider> with COCXY_CELLS_CLOUD_E2E=1 against disposable resources"
} | tee "${ARTIFACT_ROOT}/preflight.txt"

cat "$SUMMARY"

if [ "$blocked_count" -eq 0 ]; then
  exit 0
fi
exit 1
