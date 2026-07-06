Write-Host "Preparing to push IPE 51 codebase to GitHub..." -ForegroundColor Cyan

# 1. Purge old local git history to erase previous secret commits completely
if (Test-Path .git) {
    Write-Host "Clearing previous local Git history..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force .git
}

# 2. Re-initialize a fresh, clean Git repository
Write-Host "Initializing a clean Git repository..." -ForegroundColor Yellow
git init
git branch -M main

# 3. Configure Remote URL
Write-Host "Configuring remote origin..." -ForegroundColor Yellow
git remote add origin https://github.com/mridulhasan13/UniGrid.git

# 4. Add files under secure .gitignore rules (ignores service_account.json & functions/node_modules)
Write-Host "Staging secure files..." -ForegroundColor Yellow
git add .

# 5. Make a clean initial commit with zero history of secrets
Write-Host "Creating clean initial commit..." -ForegroundColor Yellow
git commit -m "feat: complete IPE 51 rebranding, secure Google Auth, stable updates and custom branding"

# 6. Push to remote repository
Write-Host "Pushing code to GitHub (main)..." -ForegroundColor Green
git push -f -u origin main

Write-Host "All set! Your code is now live on GitHub at https://github.com/mridulhasan13/UniGrid" -ForegroundColor Cyan
