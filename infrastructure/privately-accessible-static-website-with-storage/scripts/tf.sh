#!/usr/bin/env bash
# Run the static-website stack against one environment.
#   ./privately-accessible-static-website-with-storage/scripts/tf.sh <dev|qa|uat|prod> <init|plan|apply|destroy|output|...> [extra terraform args]
# Each environment gets its own .terraform directory, so switching environments
# never reuses another environment's backend.
set -euo pipefail

env="${1:?usage: tf.sh <dev|qa|uat|prod> <command> [args]}"
cmd="${2:?usage: tf.sh <dev|qa|uat|prod> <command> [args]}"
shift 2

case "$env" in dev|qa|uat|prod) ;; *) echo "unknown environment: $env" >&2; exit 2 ;; esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stack="$root/stacks/static-website"
envdir="$root/environments/$env"
plan="$env.tfplan"

export TF_DATA_DIR="$stack/.terraform-$env"

case "$cmd" in
  init)    terraform -chdir="$stack" init -reconfigure -backend-config="$envdir/backend.hcl" "$@" ;;
  plan)    terraform -chdir="$stack" plan -var-file="$envdir/terraform.tfvars" -out="$plan" "$@" ;;
  apply)   terraform -chdir="$stack" apply "$@" "$plan" ;;
  destroy) terraform -chdir="$stack" destroy -var-file="$envdir/terraform.tfvars" "$@" ;;
  *)       terraform -chdir="$stack" "$cmd" "$@" ;;
esac
