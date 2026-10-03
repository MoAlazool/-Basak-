# Deploy Basak Edge Functions (run from the project root in PowerShell).
# One-time: npx.cmd supabase@latest login
$ref = "hnwpkkryxovhmsrokdsd"
$functions = @("admin-create-company-admin", "admin-create-student", "admin-delete-student", "admin-create-supervisor", "admin-delete-supervisor", "student-delete-account", "student-reset-password", "admin-reset-student-password", "student-change-password")
foreach ($fn in $functions) {
  Write-Host "Deploying $fn ..."
  npx.cmd supabase@latest functions deploy $fn --project-ref $ref --no-verify-jwt --use-api
  if ($LASTEXITCODE -ne 0) { Write-Error "Failed: $fn"; exit 1 }
}
Write-Host "All functions deployed."
