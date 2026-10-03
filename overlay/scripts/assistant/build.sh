#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 -B scripts/assistant/prepare_dependencies.py
python3 -B scripts/assistant/configure.py
mkdir -p .build/artifacts
python3 -B scripts/assistant/check_project.py
xcrun swiftc AltStore/LocationAssistant/AssistantCoordinate.swift tests/assistant/main.swift -o .build/coordinate-tests
.build/coordinate-tests
xcodebuild archive -project AltStore.xcodeproj -scheme SideStore -sdk iphoneos \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath .build/Assistant -derivedDataPath .build/DerivedData \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=XYZ0123456 \
  ORG_IDENTIFIER=com.locationassistant | tee .build/build.log
app=".build/Assistant.xcarchive/Products/Applications/SideStore.app"
test -d "$app"
ldid -SAltStore/Resources/ReleaseEntitlements.plist "$app/SideStore"
if [ -d "$app/PlugIns/AltWidgetExtension.appex" ]; then
  ldid -SAltWidget/Resources/ReleaseEntitlements.plist "$app/PlugIns/AltWidgetExtension.appex/AltWidgetExtension"
fi
mkdir -p .build/package/Payload
cp -R "$app" .build/package/Payload/
(cd .build/package && zip -qry ../artifacts/LocationAssistant.ipa Payload)
shasum -a 256 .build/artifacts/LocationAssistant.ipa > .build/artifacts/SHA256SUMS.txt
cp upstream-lock.json THIRD_PARTY_NOTICES.md .build/artifacts/
cp docs/安装与恢复指南.md docs/验收记录.md .build/artifacts/
echo 'IPA generated; on-device validation is still required.'
