#!/usr/bin/env bash
set -e

# Match the version currently running on your system
FLUTTER_VERSION="3.44.0"

echo "=== Starting Netlify Build Pipeline ==="

# 1. Restore the git-ignored service_account.json from environment variables (if provided)
if [ -n "$SERVICE_ACCOUNT_JSON" ]; then
  echo "Recreating assets/service_account.json from Netlify environment variable..."
  mkdir -p assets
  echo "$SERVICE_ACCOUNT_JSON" > assets/service_account.json
  echo "✅ service_account.json restored successfully."

  # Also write to netlify/functions/ so send-notification.js can read it from disk
  # at Lambda runtime (avoids the 4KB AWS Lambda env var size limit)
  mkdir -p netlify/functions
  echo "$SERVICE_ACCOUNT_JSON" > netlify/functions/service_account.json
  echo "✅ netlify/functions/service_account.json written for runtime use."
else
  echo "⚠️ Warning: SERVICE_ACCOUNT_JSON environment variable is not defined."
  echo "Creating empty placeholder JSONs to prevent build errors..."
  mkdir -p assets
  echo "{}" > assets/service_account.json
  mkdir -p netlify/functions
  echo "{}" > netlify/functions/service_account.json
  echo "⚠️ Placeholders created. FCM notifications will fail at runtime."
fi

# 2. Check cache or download/extract Flutter SDK
if [ ! -d "flutter" ]; then
  echo "Downloading Flutter SDK v$FLUTTER_VERSION..."
  curl -O https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz
  echo "Extracting Flutter SDK..."
  tar xf flutter_linux_${FLUTTER_VERSION}-stable.tar.xz
  rm flutter_linux_${FLUTTER_VERSION}-stable.tar.xz
  echo "✅ Flutter SDK set up successfully."
else
  echo "✅ Using cached Flutter SDK."
fi

# 3. Add Flutter to local build session PATH
export PATH="$PATH:`pwd`/flutter/bin"

# 4. Compile the Flutter Web build
echo "Running Flutter doctor..."
flutter doctor

echo "Compiling Flutter Web in Release mode..."
flutter build web --release --base-href /

echo "=== Netlify Build Completed Successfully! ==="
