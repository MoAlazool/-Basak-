#!/bin/sh
# Builds the iPhone app (.ipa for TestFlight / the App Store), on a Mac with
# Xcode and the team's Apple account signed in. Run from anywhere:
#   sh mobile_app/tool/build_ios.sh
# The same build values as the Android script (tool/build_release.ps1): the
# Firebase client values from firebase.defines.json, without which the app has
# no push notifications. Push also needs the Push Notifications capability
# (ios/Runner/Runner.entitlements); with automatic signing Xcode enables it on
# the App ID by itself.
set -e
cd "$(dirname "$0")/.."
if [ -f firebase.defines.json ]; then
  set -- --dart-define-from-file=firebase.defines.json
else
  echo "warning: firebase.defines.json is missing: this build will have no push notifications." >&2
fi
flutter pub get
flutter build ipa --release "$@"
echo "IPA: $(pwd)/build/ios/ipa/"
