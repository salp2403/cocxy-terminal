#!/usr/bin/env bash
set -euo pipefail

# Manual AWS account setup helper for Cocxy Cells.
#
# Safe default: dry-run only. It writes the IAM trust/policy documents and the
# exact AWS CLI commands needed to prepare an SSM-capable EC2 instance profile.
# It mutates AWS only when COCXY_AWS_SETUP_APPLY=1 is set explicitly.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_ROOT="${COCXY_AWS_SETUP_ARTIFACTS:-${PROJECT_ROOT}/build/cells-aws-account-setup/${TIMESTAMP}}"
APPLY="${COCXY_AWS_SETUP_APPLY:-0}"
REGION="${COCXY_AWS_REGION:-us-east-1}"
ROLE_NAME="${COCXY_AWS_SETUP_ROLE:-CocxyCellsSSMRole}"
INSTANCE_PROFILE="${COCXY_AWS_INSTANCE_PROFILE:-${COCXY_AWS_SETUP_INSTANCE_PROFILE:-CocxyCellsSSMProfile}}"
CALLER_POLICY_NAME="${COCXY_AWS_SETUP_CALLER_POLICY_NAME:-CocxyCellsCallerPolicy}"
ATTACH_USER="${COCXY_AWS_SETUP_ATTACH_USER:-}"
IMAGE="${COCXY_AWS_IMAGE:-}"
VM_SIZE="${COCXY_AWS_VM_SIZE:-t3.micro}"
SETUP_WAIT_TIMEOUT="${COCXY_AWS_SETUP_PROPAGATION_TIMEOUT_SECONDS:-120}"
SETUP_WAIT_INTERVAL="${COCXY_AWS_SETUP_PROPAGATION_INTERVAL_SECONDS:-5}"
COMMANDS_FILE="${ARTIFACT_ROOT}/commands.sh"
SUMMARY_FILE="${ARTIFACT_ROOT}/summary.txt"
TRUST_POLICY="${ARTIFACT_ROOT}/ec2-trust-policy.json"
CALLER_POLICY="${ARTIFACT_ROOT}/caller-policy.json"
SETUP_PRINCIPAL_POLICY="${ARTIFACT_ROOT}/setup-principal-policy.json"
DIAGNOSTIC_POLICY="${ARTIFACT_ROOT}/diagnostic-policy.json"
VERIFY_SCRIPT="${ARTIFACT_ROOT}/verify-aws-setup.sh"
OWNER_HANDOFF_README="${ARTIFACT_ROOT}/AWS_OWNER_APPLY_README.md"
role_resource_arn="*"
instance_profile_resource_arn="*"
PROFILE_ROLE_PROPAGATION_STATUS="not-run"
PROFILE_DRY_RUN_PROPAGATION_STATUS="not-run"

usage() {
  cat <<'USAGE'
usage: scripts/setup-cells-aws-account.sh

Dry-run by default. Writes setup artifacts under build/cells-aws-account-setup.

Set COCXY_AWS_SETUP_APPLY=1 to create/update:
  - an EC2 trust role
  - an EC2 instance profile
  - AmazonSSMManagedInstanceCore attachment on the EC2 role
  - a caller policy for Cocxy Cells lifecycle operations
  - optional attachment of that caller policy to a user

Environment:
  COCXY_AWS_REGION                         default: us-east-1
  COCXY_AWS_SETUP_ROLE                     default: CocxyCellsSSMRole
  COCXY_AWS_INSTANCE_PROFILE               default: CocxyCellsSSMProfile
  COCXY_AWS_SETUP_CALLER_POLICY_NAME       default: CocxyCellsCallerPolicy
  COCXY_AWS_SETUP_ATTACH_USER              optional user to attach caller policy
  COCXY_AWS_PROFILE                        optional AWS CLI profile
  COCXY_AWS_IMAGE                          optional AMI for post-apply EC2 dry-run propagation check
  COCXY_AWS_VM_SIZE                        default: t3.micro
  COCXY_AWS_SETUP_PROPAGATION_TIMEOUT_SECONDS default: 120
  COCXY_AWS_SETUP_PROPAGATION_INTERVAL_SECONDS default: 5
  COCXY_AWS_SETUP_APPLY=1                  perform mutations

Artifacts:
  ec2-trust-policy.json                    trust policy for the EC2 role
  caller-policy.json                       runtime/smoke policy for the Cocxy Cells caller
  setup-principal-policy.json              IAM setup policy for the principal running this helper
  diagnostic-policy.json                   optional read-only diagnostics for preflight policy simulation
  verify-aws-setup.sh                      read-only verification commands to run after IAM setup
  AWS_OWNER_APPLY_README.md                owner handoff with guardrails and done criteria

After apply, export:
  COCXY_AWS_INSTANCE_PROFILE=<profile>
  COCXY_AWS_SETUP_ROLE=<role-inside-instance-profile>
  COCXY_AWS_IMAGE=<valid AMI for COCXY_AWS_REGION>
Then run:
  COCXY_AWS_PERMISSION_PROBE_IMAGE=<valid AMI> scripts/preflight-cells-cloud-account.sh aws
  scripts/verify-cells-aws-setup.sh
  COCXY_CELLS_CLOUD_E2E=1 scripts/smoke-cells-cloud-account.sh aws
USAGE
}

write_json_documents() {
  mkdir -p "$ARTIFACT_ROOT"
  cat > "$TRUST_POLICY" <<'JSON'
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
JSON

  cat > "$CALLER_POLICY" <<JSON
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
      "Resource": "${role_resource_arn}",
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
      "Resource": "${role_resource_arn}"
    },
    {
      "Sid": "CocxyCellsInspectInstanceProfile",
      "Effect": "Allow",
      "Action": "iam:GetInstanceProfile",
      "Resource": "${instance_profile_resource_arn}"
    }
  ]
}
JSON

  cat > "$SETUP_PRINCIPAL_POLICY" <<JSON
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
      "Resource": "${role_resource_arn}",
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

  cat > "$DIAGNOSTIC_POLICY" <<'JSON'
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
}

write_verify_script() {
  local profile_export=""

  if [ -n "${COCXY_AWS_PROFILE:-}" ]; then
    profile_export="export COCXY_AWS_PROFILE=$(shell_quote "$COCXY_AWS_PROFILE")"
  fi

  cat > "$VERIFY_SCRIPT" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail

# Read-only AWS setup verification for Cocxy Cells.
# This script does not create, modify, or delete AWS resources.

${profile_export}
export COCXY_AWS_REGION=$(shell_quote "$REGION")
export COCXY_AWS_INSTANCE_PROFILE=$(shell_quote "$INSTANCE_PROFILE")
: "\${COCXY_AWS_IMAGE:?set COCXY_AWS_IMAGE to a valid AMI for \$COCXY_AWS_REGION}"

AWS=(aws)
if [ -n "\${COCXY_AWS_PROFILE:-}" ]; then
  AWS+=(--profile "\$COCXY_AWS_PROFILE")
fi

identity_json="\$("\${AWS[@]}" sts get-caller-identity --output json)"
printf '%s\n' "\$identity_json"
account_id="\$(sed -n 's/.*"Account"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<< "\$identity_json" | head -1)"
if [ -z "\$account_id" ]; then
  echo "missing AWS account id from sts get-caller-identity" >&2
  exit 1
fi
"\${AWS[@]}" iam get-role --role-name $(shell_quote "$ROLE_NAME") --output json
"\${AWS[@]}" iam list-attached-role-policies --role-name $(shell_quote "$ROLE_NAME") --output json
"\${AWS[@]}" iam get-instance-profile --instance-profile-name "\$COCXY_AWS_INSTANCE_PROFILE" --output json
profile_roles="\$("\${AWS[@]}" iam get-instance-profile \\
  --instance-profile-name "\$COCXY_AWS_INSTANCE_PROFILE" \\
  --query 'InstanceProfile.Roles[].RoleName' \\
  --output text)"
case " \${profile_roles} " in
  *" $(shell_quote "$ROLE_NAME") "*) ;;
  *)
    echo "instance profile \$COCXY_AWS_INSTANCE_PROFILE does not include role $(shell_quote "$ROLE_NAME"): \${profile_roles}" >&2
    exit 1
    ;;
esac

run_ec2_dry_run() {
  local label="\$1"
  shift
  local error_file
  error_file="\$(mktemp)"
  if "\${AWS[@]}" ec2 run-instances "\$@" > /dev/null 2> "\$error_file"; then
    rm -f "\$error_file"
    echo "\${label}=unexpected-success"
    return 0
  fi
  if grep -q "DryRunOperation" "\$error_file"; then
    rm -f "\$error_file"
    echo "\${label}=authorized"
    return 0
  fi
  cat "\$error_file" >&2
  rm -f "\$error_file"
  return 1
}

profile_arn="arn:aws:iam::\${account_id}:instance-profile/\${COCXY_AWS_INSTANCE_PROFILE}"
run_ec2_dry_run run-instances-with-profile-dry-run \\
  --dry-run \\
  --region "\$COCXY_AWS_REGION" \\
  --image-id "\$COCXY_AWS_IMAGE" \\
  --instance-type "\${COCXY_AWS_VM_SIZE:-t3.micro}" \\
  --iam-instance-profile "Name=\$COCXY_AWS_INSTANCE_PROFILE" \\
  --count 1 \\
  --query "Instances[0].InstanceId" \\
  --output text
run_ec2_dry_run run-instances-with-profile-arn-dry-run \\
  --dry-run \\
  --region "\$COCXY_AWS_REGION" \\
  --image-id "\$COCXY_AWS_IMAGE" \\
  --instance-type "\${COCXY_AWS_VM_SIZE:-t3.micro}" \\
  --iam-instance-profile "Arn=\$profile_arn" \\
  --count 1 \\
  --query "Instances[0].InstanceId" \\
  --output text
SCRIPT

  chmod 700 "$VERIFY_SCRIPT"
}

write_owner_handoff_readme() {
  cat > "$OWNER_HANDOFF_README" <<MARKDOWN
# AWS Cocxy Cells Owner Handoff

This file was generated by \`scripts/setup-cells-aws-account.sh\`.

It is a private handoff for the AWS owner. It intentionally avoids account IDs,
ARNs, user names, and any credential values.

## Guardrails

- Do not run this from CI.
- Do not treat the dry-run bundle as AWS lifecycle success.
- Do not treat a \`DryRunOperation\` RunInstances result as exec/logs/attach
  success; it does not prove SSM runtime permissions.
- Do not publish this file or the generated IAM bundle.
- Keep the AWS lifecycle smoke manual because it can create billable resources.
- Do not run setup apply until an AWS owner has reviewed the generated policies.

## Owner Sequence

1. Review the generated IAM documents in this bundle:

   \`\`\`sh
   less setup-principal-policy.json
   less caller-policy.json
   less diagnostic-policy.json
   less ec2-trust-policy.json
   less commands.sh
   \`\`\`

   \`setup-principal-policy.json\` must include \`iam:PassRole\`; AWS requires it
   when adding the EC2 role to the instance profile.
   \`caller-policy.json\` must include the runtime SSM actions used by Cocxy
   Cells: \`ssm:SendCommand\`, \`ssm:GetCommandInvocation\`,
   \`ssm:ListCommandInvocations\`, and \`ssm:StartSession\`. Applying only
   \`iam:PassRole\` is insufficient because AWS Cells exec, logs, and attach
   use SSM after the EC2 instance reaches \`running\`.
   A green EC2 dry-run only proves \`ec2:RunInstances\` and the instance profile
   handoff. AWS is not complete until SSM runtime is proven by
   \`ssmRuntimePolicySimulation=allowed\` or by a lifecycle smoke that archives
   \`result=cells-cloud-aws-ok\`.
   \`COCXY_AWS_SETUP_ROLE\` must match the actual role inside
   \`COCXY_AWS_INSTANCE_PROFILE\` before relying on the scoped generated
   \`iam:PassRole\` and role-inspection statements. If the AWS owner created
   the role and instance profile with the same name, export the same value for
   both variables.
   \`diagnostic-policy.json\` is optional and read-only. It allows
   \`iam:SimulatePrincipalPolicy\` and self-inspection so the preflight can
   prove SSM runtime access before the billable lifecycle smoke. If the owner
   does not grant it, the smoke remains the source of truth.

2. Apply setup only from an approved owner shell:

   \`\`\`sh
   export COCXY_AWS_IMAGE=<valid-ami-for-region>
   COCXY_AWS_SETUP_APPLY=1 scripts/setup-cells-aws-account.sh
   \`\`\`

   When \`COCXY_AWS_IMAGE\` is set, apply mode waits until EC2 dry-run accepts
   the instance profile by both name and ARN.

3. Export a region-valid AMI and expected instance profile:

   \`\`\`sh
   export COCXY_AWS_REGION=${REGION}
   export COCXY_AWS_INSTANCE_PROFILE=${INSTANCE_PROFILE}
   export COCXY_AWS_SETUP_ROLE=${ROLE_NAME}
   export COCXY_AWS_IMAGE=<valid-ami-for-region>
   \`\`\`

4. Run the read-only checks:

   \`\`\`sh
   scripts/verify-cells-aws-setup.sh
   scripts/preflight-cells-cloud-account.sh aws
   \`\`\`

   When IAM simulation is permitted, the preflight diagnostics should report
   \`ssmRuntimePolicySimulation=allowed\`. If the owner intentionally does not
   grant \`iam:SimulatePrincipalPolicy\`, the preflight may report
   \`ssmRuntimePolicySimulation=access-denied\`; in that case the billable AWS
   lifecycle smoke is still the source of truth and must pass before AWS is
   considered complete.

5. Run the single ordered readiness sequence. It stops before billable AWS smoke
   unless \`COCXY_CELLS_CLOUD_E2E=1\` is explicitly set:

   \`\`\`sh
   scripts/run-cells-aws-readiness-sequence.sh
   \`\`\`

6. Only after the read-only checks are green, run the billable lifecycle smoke:

   \`\`\`sh
   COCXY_CELLS_CLOUD_E2E=1 scripts/smoke-cells-cloud-account.sh aws
   scripts/preflight-cells-cloud-account.sh all
   scripts/audit-agent-workspace-os-completion.sh
   \`\`\`

## Definition Of Done

- \`scripts/verify-cells-aws-setup.sh\` reports \`status=ok\`.
- \`scripts/preflight-cells-cloud-account.sh aws\` reports AWS ready or complete.
- If IAM simulation is available, AWS diagnostics report
  \`ssmRuntimePolicySimulation=allowed\`; otherwise the lifecycle smoke below
  must prove SSM runtime access.
- \`scripts/smoke-cells-cloud-account.sh aws\` archives \`result=cells-cloud-aws-ok\`.
- \`scripts/preflight-cells-cloud-account.sh all\` reports \`complete=5\`.
- \`scripts/run-cells-aws-readiness-sequence.sh\` reports \`result=cells-aws-readiness-sequence-ok\`.
- \`scripts/audit-agent-workspace-os-completion.sh\` no longer reports AWS blockers.
MARKDOWN
  chmod 600 "$OWNER_HANDOFF_README"
}

shell_quote() {
  printf '%q' "$1"
}

normalize_wait_settings() {
  case "$SETUP_WAIT_TIMEOUT" in
    ''|*[!0-9]*) SETUP_WAIT_TIMEOUT=120 ;;
  esac
  case "$SETUP_WAIT_INTERVAL" in
    ''|*[!0-9]*) SETUP_WAIT_INTERVAL=5 ;;
  esac
  if [ "$SETUP_WAIT_INTERVAL" -eq 0 ]; then
    SETUP_WAIT_INTERVAL=1
  fi
}

record_command() {
  local first=1
  local arg
  for arg in "$@"; do
    if [ "$first" -eq 0 ]; then
      printf ' ' >> "$COMMANDS_FILE"
    fi
    shell_quote "$arg" >> "$COMMANDS_FILE"
    first=0
  done
  printf '\n' >> "$COMMANDS_FILE"
}

record_comment() {
  printf '# %s\n' "$1" >> "$COMMANDS_FILE"
}

run_command() {
  record_command "$@"
  if [ "$APPLY" = "1" ]; then
    "$@"
  fi
}

aws_cli() {
  if [ -n "${COCXY_AWS_PROFILE:-}" ]; then
    aws --profile "$COCXY_AWS_PROFILE" "$@"
  else
    aws "$@"
  fi
}

run_aws_command() {
  if [ -n "${COCXY_AWS_PROFILE:-}" ]; then
    run_command aws --profile "$COCXY_AWS_PROFILE" "$@"
  else
    run_command aws "$@"
  fi
}

aws_succeeds() {
  aws_cli "$@" >/dev/null 2>&1
}

apply_read_check() {
  local label="$1"
  local expected_missing_pattern="$2"
  shift 2
  local output_file="${ARTIFACT_ROOT}/apply-preflight-${label}.out"
  local error_file="${ARTIFACT_ROOT}/apply-preflight-${label}.err"

  if aws_cli "$@" > "$output_file" 2> "$error_file"; then
    return 0
  fi

  if grep -q "$expected_missing_pattern" "$error_file"; then
    return 0
  fi

  {
    echo "status=blocked"
    echo "reason=apply-preflight-${label}-failed"
    echo "artifactRoot=${ARTIFACT_ROOT}"
    echo "output=${output_file#${PROJECT_ROOT}/}"
    echo "error=${error_file#${PROJECT_ROOT}/}"
  } | tee "$SUMMARY_FILE"
  exit 1
}

verify_apply_read_permissions() {
  if [ "$APPLY" != "1" ]; then
    return
  fi

  apply_read_check \
    "get-role" \
    "NoSuchEntity\\|cannot be found" \
    iam get-role \
    --role-name "$ROLE_NAME"
  apply_read_check \
    "get-instance-profile" \
    "NoSuchEntity\\|cannot be found" \
    iam get-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE"
  if [ -n "${policy_arn:-}" ]; then
    apply_read_check \
      "get-policy" \
      "NoSuchEntity\\|cannot be found" \
      iam get-policy \
      --policy-arn "$policy_arn"
  fi
}

ensure_role() {
  if [ "$APPLY" = "1" ] && aws_succeeds iam get-role --role-name "$ROLE_NAME"; then
    record_comment "role ${ROLE_NAME} already exists; refreshing trust policy"
    run_aws_command iam update-assume-role-policy \
      --role-name "$ROLE_NAME" \
      --policy-document "file://${TRUST_POLICY}"
  else
    run_aws_command iam create-role \
      --role-name "$ROLE_NAME" \
      --assume-role-policy-document "file://${TRUST_POLICY}" \
      --description "Cocxy Cells EC2 role for SSM-backed exec logs attach"
  fi
}

ensure_instance_profile() {
  if [ "$APPLY" = "1" ] && aws_succeeds iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE"; then
    record_comment "instance profile ${INSTANCE_PROFILE} already exists"
  else
    run_aws_command iam create-instance-profile \
      --instance-profile-name "$INSTANCE_PROFILE"
  fi
}

ensure_role_in_instance_profile() {
  local profile_roles

  if [ "$APPLY" != "1" ]; then
    run_aws_command iam add-role-to-instance-profile \
      --instance-profile-name "$INSTANCE_PROFILE" \
      --role-name "$ROLE_NAME"
    return
  fi

  profile_roles="$(
    aws_cli iam get-instance-profile \
      --instance-profile-name "$INSTANCE_PROFILE" \
      --query 'InstanceProfile.Roles[].RoleName' \
      --output text 2>/dev/null || true
  )"

  if [[ " ${profile_roles} " == *" ${ROLE_NAME} "* ]]; then
    record_comment "instance profile ${INSTANCE_PROFILE} already contains role ${ROLE_NAME}"
    return
  fi

  if [ -n "$profile_roles" ]; then
    {
      echo "status=blocked"
      echo "reason=instance-profile-has-different-role"
      echo "instanceProfile=${INSTANCE_PROFILE}"
      echo "existingRoles=${profile_roles}"
      echo "expectedRole=${ROLE_NAME}"
      echo "artifactRoot=${ARTIFACT_ROOT}"
    } | tee "$SUMMARY_FILE"
    exit 1
  fi

  run_aws_command iam add-role-to-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE" \
    --role-name "$ROLE_NAME"
}

wait_for_instance_profile_role_attachment() {
  local output="${ARTIFACT_ROOT}/profile-role-propagation.out"
  local error="${ARTIFACT_ROOT}/profile-role-propagation.err"
  local deadline
  local roles

  if [ "$APPLY" != "1" ]; then
    PROFILE_ROLE_PROPAGATION_STATUS="not-run"
    return
  fi

  deadline="$(($(date +%s) + SETUP_WAIT_TIMEOUT))"
  while true; do
    if roles="$(
      aws_cli iam get-instance-profile \
        --instance-profile-name "$INSTANCE_PROFILE" \
        --query 'InstanceProfile.Roles[].RoleName' \
        --output text > "$output" 2> "$error" &&
        tr '\t' ' ' < "$output" | xargs
    )"; then
      if [[ " ${roles} " == *" ${ROLE_NAME} "* ]]; then
        PROFILE_ROLE_PROPAGATION_STATUS="ok"
        record_comment "instance profile ${INSTANCE_PROFILE} role attachment is visible"
        return
      fi
    fi

    if [ "$(date +%s)" -ge "$deadline" ]; then
      PROFILE_ROLE_PROPAGATION_STATUS="timeout"
      {
        echo "status=blocked"
        echo "reason=instance-profile-role-propagation-timeout"
        echo "instanceProfile=${INSTANCE_PROFILE}"
        echo "expectedRole=${ROLE_NAME}"
        echo "lastRoles=${roles:-unknown}"
        echo "artifactRoot=${ARTIFACT_ROOT}"
        echo "output=${output#${PROJECT_ROOT}/}"
        echo "error=${error#${PROJECT_ROOT}/}"
      } | tee "$SUMMARY_FILE"
      exit 1
    fi

    sleep "$SETUP_WAIT_INTERVAL"
  done
}

classify_setup_dry_run_error() {
  local error_file="$1"
  if grep -q "DryRunOperation" "$error_file"; then
    echo "authorized"
  elif grep -q "Invalid IAM Instance Profile\\|iamInstanceProfile" "$error_file"; then
    echo "invalid-instance-profile"
  elif grep -q "InvalidAMIID" "$error_file"; then
    echo "invalid-ami"
  elif grep -q "AccessDenied\\|UnauthorizedOperation\\|not authorized" "$error_file"; then
    echo "access-denied"
  else
    echo "failed"
  fi
}

setup_ec2_dry_run_status() {
  local output="$1"
  local error="$2"
  shift 2
  local status

  if aws_cli ec2 run-instances "$@" > "$output" 2> "$error"; then
    echo "unexpected-success"
    return 0
  fi

  status="$(classify_setup_dry_run_error "$error")"
  echo "$status"
  return 0
}

wait_for_ec2_instance_profile_dry_run() {
  local name_output="${ARTIFACT_ROOT}/profile-name-propagation-dry-run.out"
  local name_error="${ARTIFACT_ROOT}/profile-name-propagation-dry-run.err"
  local arn_output="${ARTIFACT_ROOT}/profile-arn-propagation-dry-run.out"
  local arn_error="${ARTIFACT_ROOT}/profile-arn-propagation-dry-run.err"
  local deadline
  local profile_arn
  local name_status
  local arn_status

  if [ "$APPLY" != "1" ]; then
    PROFILE_DRY_RUN_PROPAGATION_STATUS="not-run"
    return
  fi

  if [ -z "$IMAGE" ]; then
    PROFILE_DRY_RUN_PROPAGATION_STATUS="skipped-missing-image"
    record_comment "skipping EC2 instance profile propagation dry-run because COCXY_AWS_IMAGE is not set"
    return
  fi

  if [ -z "${account_id:-}" ]; then
    PROFILE_DRY_RUN_PROPAGATION_STATUS="blocked-missing-account"
    {
      echo "status=blocked"
      echo "reason=ec2-profile-propagation-missing-account"
      echo "artifactRoot=${ARTIFACT_ROOT}"
    } | tee "$SUMMARY_FILE"
    exit 1
  fi

  profile_arn="arn:aws:iam::${account_id}:instance-profile/${INSTANCE_PROFILE}"
  deadline="$(($(date +%s) + SETUP_WAIT_TIMEOUT))"
  while true; do
    name_status="$(
      setup_ec2_dry_run_status \
        "$name_output" \
        "$name_error" \
        --dry-run \
        --region "$REGION" \
        --image-id "$IMAGE" \
        --instance-type "$VM_SIZE" \
        --iam-instance-profile "Name=${INSTANCE_PROFILE}" \
        --count 1 \
        --query "Instances[0].InstanceId" \
        --output text
    )"
    arn_status="$(
      setup_ec2_dry_run_status \
        "$arn_output" \
        "$arn_error" \
        --dry-run \
        --region "$REGION" \
        --image-id "$IMAGE" \
        --instance-type "$VM_SIZE" \
        --iam-instance-profile "Arn=${profile_arn}" \
        --count 1 \
        --query "Instances[0].InstanceId" \
        --output text
    )"

    if [ "$name_status" = "authorized" ] && [ "$arn_status" = "authorized" ]; then
      PROFILE_DRY_RUN_PROPAGATION_STATUS="authorized"
      record_comment "EC2 dry-run accepts instance profile by name and ARN"
      return
    fi

    if [ "$name_status" != "invalid-instance-profile" ] || [ "$arn_status" != "invalid-instance-profile" ]; then
      PROFILE_DRY_RUN_PROPAGATION_STATUS="${name_status},${arn_status}"
      {
        echo "status=blocked"
        echo "reason=ec2-profile-propagation-dry-run-failed"
        echo "nameDryRun=${name_status}"
        echo "arnDryRun=${arn_status}"
        echo "artifactRoot=${ARTIFACT_ROOT}"
        echo "nameOutput=${name_output#${PROJECT_ROOT}/}"
        echo "nameError=${name_error#${PROJECT_ROOT}/}"
        echo "arnOutput=${arn_output#${PROJECT_ROOT}/}"
        echo "arnError=${arn_error#${PROJECT_ROOT}/}"
      } | tee "$SUMMARY_FILE"
      exit 1
    fi

    if [ "$(date +%s)" -ge "$deadline" ]; then
      PROFILE_DRY_RUN_PROPAGATION_STATUS="timeout"
      {
        echo "status=blocked"
        echo "reason=ec2-profile-propagation-timeout"
        echo "nameDryRun=${name_status}"
        echo "arnDryRun=${arn_status}"
        echo "artifactRoot=${ARTIFACT_ROOT}"
        echo "nameOutput=${name_output#${PROJECT_ROOT}/}"
        echo "nameError=${name_error#${PROJECT_ROOT}/}"
        echo "arnOutput=${arn_output#${PROJECT_ROOT}/}"
        echo "arnError=${arn_error#${PROJECT_ROOT}/}"
      } | tee "$SUMMARY_FILE"
      exit 1
    fi

    sleep "$SETUP_WAIT_INTERVAL"
  done
}

ensure_caller_policy_version_slot() {
  local version_count
  local oldest_non_default

  if [ "$APPLY" != "1" ] || [ -z "${policy_arn:-}" ]; then
    return
  fi

  version_count="$(
    aws_cli iam list-policy-versions \
      --policy-arn "$policy_arn" \
      --query 'length(Versions)' \
      --output text 2>/dev/null || true
  )"

  case "$version_count" in
    ''|*[!0-9]*)
      record_comment "could not count existing caller policy versions for ${policy_arn}; create-policy-version will enforce AWS limits"
      return
      ;;
  esac

  if [ "$version_count" -lt 5 ]; then
    return
  fi

  oldest_non_default="$(
    aws_cli iam list-policy-versions \
      --policy-arn "$policy_arn" \
      --query 'sort_by(Versions[?IsDefaultVersion==`false`], &CreateDate)[0].VersionId' \
      --output text 2>/dev/null || true
  )"

  if [ -z "$oldest_non_default" ] || [ "$oldest_non_default" = "None" ]; then
    {
      echo "status=blocked"
      echo "reason=caller-policy-version-limit"
      echo "callerPolicyArn=${policy_arn}"
      echo "artifactRoot=${ARTIFACT_ROOT}"
    } | tee "$SUMMARY_FILE"
    exit 1
  fi

  record_comment "caller policy ${policy_arn} has ${version_count} versions; deleting non-default version ${oldest_non_default}"
  run_aws_command iam delete-policy-version \
    --policy-arn "$policy_arn" \
    --version-id "$oldest_non_default"
}

ensure_caller_policy() {
  if [ "$APPLY" = "1" ] && [ -n "$policy_arn" ] && aws_succeeds iam get-policy --policy-arn "$policy_arn"; then
    record_comment "caller policy ${policy_arn} already exists; creating a new default policy version"
    ensure_caller_policy_version_slot
    run_aws_command iam create-policy-version \
      --policy-arn "$policy_arn" \
      --policy-document "file://${CALLER_POLICY}" \
      --set-as-default
  else
    run_aws_command iam create-policy \
      --policy-name "$CALLER_POLICY_NAME" \
      --policy-document "file://${CALLER_POLICY}"
  fi
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if ! command -v aws >/dev/null 2>&1; then
  mkdir -p "$ARTIFACT_ROOT"
  {
    echo "status=blocked"
    echo "reason=aws-cli-missing"
    echo "artifactRoot=${ARTIFACT_ROOT}"
  } | tee "$SUMMARY_FILE"
  exit 1
fi

normalize_wait_settings
mkdir -p "$ARTIFACT_ROOT"
: > "$COMMANDS_FILE"
chmod 700 "$COMMANDS_FILE"

identity_json="${ARTIFACT_ROOT}/caller-identity.json"
if aws_cli sts get-caller-identity --output json > "$identity_json" 2> "${ARTIFACT_ROOT}/caller-identity.err"; then
  account_id="$(sed -n 's/.*"Account"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$identity_json" | head -1)"
  caller_arn="$(sed -n 's/.*"Arn"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$identity_json" | head -1)"
else
  account_id=""
  caller_arn=""
fi

policy_arn="${COCXY_AWS_SETUP_CALLER_POLICY_ARN:-}"
if [ -z "$policy_arn" ] && [ -n "$account_id" ]; then
  policy_arn="arn:aws:iam::${account_id}:policy/${CALLER_POLICY_NAME}"
fi
if [ -n "$account_id" ]; then
  role_resource_arn="arn:aws:iam::${account_id}:role/${ROLE_NAME}"
  instance_profile_resource_arn="arn:aws:iam::${account_id}:instance-profile/${INSTANCE_PROFILE}"
fi

if [ -z "$ATTACH_USER" ] && [[ "${caller_arn:-}" == arn:aws:iam::*:user/* ]]; then
  ATTACH_USER="${caller_arn##*/}"
fi

write_json_documents
write_verify_script
write_owner_handoff_readme
verify_apply_read_permissions
ensure_role
run_aws_command iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
ensure_instance_profile
ensure_role_in_instance_profile
wait_for_instance_profile_role_attachment
wait_for_ec2_instance_profile_dry_run
ensure_caller_policy
if [ -n "$ATTACH_USER" ] && [ -n "$policy_arn" ]; then
  run_aws_command iam attach-user-policy \
    --user-name "$ATTACH_USER" \
    --policy-arn "$policy_arn"
fi

{
  if [ "$APPLY" = "1" ]; then
    echo "status=applied"
  else
    echo "status=dry-run"
  fi
  echo "artifactRoot=${ARTIFACT_ROOT}"
  echo "commands=${COMMANDS_FILE#${PROJECT_ROOT}/}"
  echo "trustPolicy=${TRUST_POLICY#${PROJECT_ROOT}/}"
  echo "callerPolicy=${CALLER_POLICY#${PROJECT_ROOT}/}"
  echo "setupPrincipalPolicy=${SETUP_PRINCIPAL_POLICY#${PROJECT_ROOT}/}"
  echo "diagnosticPolicy=${DIAGNOSTIC_POLICY#${PROJECT_ROOT}/}"
  echo "verifyScript=${VERIFY_SCRIPT#${PROJECT_ROOT}/}"
  echo "ownerHandoff=${OWNER_HANDOFF_README#${PROJECT_ROOT}/}"
  echo "region=${REGION}"
  echo "roleName=${ROLE_NAME}"
  echo "instanceProfile=${INSTANCE_PROFILE}"
  echo "profileRolePropagation=${PROFILE_ROLE_PROPAGATION_STATUS}"
  echo "profileDryRunPropagation=${PROFILE_DRY_RUN_PROPAGATION_STATUS}"
  echo "propagationTimeoutSeconds=${SETUP_WAIT_TIMEOUT}"
  echo "propagationIntervalSeconds=${SETUP_WAIT_INTERVAL}"
  echo "callerPolicyName=${CALLER_POLICY_NAME}"
  echo "callerPolicyArn=${policy_arn:-unknown}"
  echo "attachUser=${ATTACH_USER:-manual}"
  echo "callerArn=${caller_arn:-unknown}"
  echo "next=export COCXY_AWS_INSTANCE_PROFILE=${INSTANCE_PROFILE}; set a valid COCXY_AWS_IMAGE; run preflight then smoke"
} | tee "$SUMMARY_FILE"
