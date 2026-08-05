#!/usr/bin/env bash
set -e

# Match the version currently running on your system
FLUTTER_VERSION="3.44.0"

echo "=== Starting Netlify Build Pipeline ==="

# 1. Restore service_account.json from env var OR use repo's existing assets/service_account.json
if [ -n "$SERVICE_ACCOUNT_JSON" ]; then
  echo "Recreating assets/service_account.json from Netlify environment variable..."
  mkdir -p assets
  echo "$SERVICE_ACCOUNT_JSON" > assets/service_account.json
  mkdir -p netlify/functions
  echo "$SERVICE_ACCOUNT_JSON" > netlify/functions/service_account.json
  echo "✅ service_account.json restored from environment variable."
elif [ -f "assets/service_account.json" ] && [ -s "assets/service_account.json" ] && [ "$(cat assets/service_account.json)" != "{}" ]; then
  echo "✅ Using existing repository assets/service_account.json..."
  mkdir -p netlify/functions
  cp assets/service_account.json netlify/functions/service_account.json
  echo "✅ Copied service_account.json to netlify/functions/."
else
  echo "⚠️ Warning: SERVICE_ACCOUNT_JSON environment variable is not defined and no local service_account.json found."
  echo "Creating empty placeholder JSONs..."
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
