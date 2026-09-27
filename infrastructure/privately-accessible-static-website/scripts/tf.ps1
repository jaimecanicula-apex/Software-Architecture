# Run the static-website stack against one environment.
#   ./privately-accessible-static-website/scripts/tf.ps1 -Environment dev -Command plan [-- extra terraform args]
# Each environment gets its own .terraform directory, so switching environments
# never reuses another environment's backend.
param(
    [Parameter(Mandatory)][ValidateSet('dev', 'qa', 'uat', 'prod')][string]$Environment,
    [Parameter(Mandatory)][string]$Command,
    [Parameter(ValueFromRemainingArguments)][string[]]$ExtraArgs = @()
)
$ErrorActionPreference = 'Stop'

$root   = Split-Path -Parent $PSScriptRoot
$stack  = Join-Path $root 'stacks/static-website'
$envDir = Join-Path $root "environments/$Environment"
$plan   = "$Environment.tfplan"

$env:TF_DATA_DIR = Join-Path $stack ".terraform-$Environment"

switch ($Command) {
    'init'    { terraform "-chdir=$stack" init -reconfigure "-backend-config=$envDir/backend.hcl" @ExtraArgs }
    'plan'    { terraform "-chdir=$stack" plan "-var-file=$envDir/terraform.tfvars" "-out=$plan" @ExtraArgs }
    'apply'   { terraform "-chdir=$stack" apply @ExtraArgs $plan }
    'destroy' { terraform "-chdir=$stack" destroy "-var-file=$envDir/terraform.tfvars" @ExtraArgs }
    default   { terraform "-chdir=$stack" $Command @ExtraArgs }
}
exit $LASTEXITCODE
