# Deploy Basak Edge Functions (run from the project root in PowerShell).
# One-time: npx supabase@latest login
$ref = "hnwpkkryxovhmsrokdsd"
$functions = @("admin-create-company-admin", "admin-create-student", "admin-delete-student", "student-delete-account")
foreach ($fn in $functions) {
  Write-Host "Deploying $fn ..."
  npx supabase@latest functions deploy $fn --project-ref $ref --no-verify-jwt --use-api
  if ($LASTEXITCODE -ne 0) { Write-Error "Failed: $fn"; exit 1 }
}
Write-Host "All functions deployed."
