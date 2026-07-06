Write-Host "Preparing to push UniGrid codebase to GitHub..." -ForegroundColor Cyan

# 1. Add files under secure .gitignore rules (ignores service_account.json & functions/node_modules)
Write-Host "Staging files..." -ForegroundColor Yellow
git add .

# 2. Prompt for commit message
$commitMsg = Read-Host "Enter commit message (default: 'chore: update codebase')"
if ([string]::IsNullOrEmpty($commitMsg)) {
    $commitMsg = "chore: update codebase"
}

# 3. Create a commit
Write-Host "Creating commit..." -ForegroundColor Yellow
git commit -m "$commitMsg"

# 4. Push to remote repository (safe push without force option)
Write-Host "Pushing code to GitHub (main)..." -ForegroundColor Green
git push origin main

Write-Host "All set! Your code is now live on GitHub at https://github.com/mridulhasan13/UniGrid" -ForegroundColor Cyan
