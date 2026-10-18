#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 -B scripts/assistant/prepare_dependencies.py
python3 -B scripts/assistant/configure.py
mkdir -p .build/artifacts
python3 -B scripts/assistant/check_project.py
python3 -B scripts/assistant/review_contracts.py
xcrun swiftc AltStore/LocationAssistant/AssistantCoordinate.swift tests/assistant/main.swift -o .build/coordinate-tests
.build/coordinate-tests
xcrun swiftc AltStore/LocationAssistant/AssistantSigningPolicy.swift tests/assistant/signing/main.swift -o .build/signing-tests
.build/signing-tests
xcrun swiftc AltStore/LocationAssistant/AssistantLoginPolicy.swift AltStore/LocationAssistant/AssistantCredentialMigration.swift tests/assistant/login/main.swift -o .build/login-tests
.build/login-tests
xcrun swiftc AltStore/LocationAssistant/AssistantHealthPolicy.swift tests/assistant/health/main.swift -o .build/health-tests
.build/health-tests
xcrun swiftc -parse-as-library AltStore/LocationAssistant/AssistantPairingPolicy.swift AltStore/LocationAssistant/AssistantFavoriteStore.swift AltStore/LocationAssistant/AssistantHealthPolicy.swift Dependencies/SideSign/Sources/Anisette/AnisetteSocketDeadline.swift SideStore/DeepLinks/URLHandler.swift tests/assistant/review/main.swift -o .build/review-tests
.build/review-tests
xcrun swiftc -parse-as-library AltStore/LocationAssistant/AssistantDDIAssets.swift tests/assistant/ddi/main.swift -o .build/ddi-tests
.build/ddi-tests
xcrun clang -c tests/assistant/native/TestBridge.c -o .build/native-bridge.o
xcrun swiftc -I tests/assistant/native AltStore/LocationAssistant/AssistantPairingPolicy.swift AltStore/LocationAssistant/AssistantHealthPolicy.swift AltStore/LocationAssistant/AssistantCoordinate.swift AltStore/LocationAssistant/AssistantNative.swift AltStore/LocationAssistant/AssistantDDIAssets.swift tests/assistant/native/PairingStub.swift tests/assistant/native/main.swift .build/native-bridge.o -o .build/native-tests
.build/native-tests
xcodebuild -quiet archive -project AltStore.xcodeproj -scheme SideStore -sdk iphoneos \
  -configuration Release -destination 'generic/platform=iOS' \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  -archivePath .build/Assistant -derivedDataPath .build/DerivedData \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=XYZ0123456 \
  ORG_IDENTIFIER=com.locationassistant 2>&1 | tee .build/build.log
app=".build/Assistant.xcarchive/Products/Applications/SideStore.app"
test -d "$app"
ldid -SAltStore/Resources/ReleaseEntitlements.plist "$app/SideStore"
# The upstream widget is outside the assistant scope and is not shipped.
mkdir -p .build/package/Payload
cp -R "$app" .build/package/Payload/
python3 -B - <<'PY'
from pathlib import Path
import shutil
payload = Path('.build/package/Payload').resolve()
plugins = payload / 'SideStore.app/PlugIns'
assert plugins.resolve().is_relative_to(payload)
if plugins.exists(): shutil.rmtree(plugins)
PY
(cd .build/package && zip -qry ../artifacts/LocationAssistant.ipa Payload)
(cd .build/artifacts && shasum -a 256 LocationAssistant.ipa > SHA256SUMS.txt)
cp upstream-lock.json THIRD_PARTY_NOTICES.md LICENSE Vendor/StikDebug-LICENSE .build/artifacts/
cp AltStore.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved .build/artifacts/
cp docs/安装与恢复指南.md docs/验收记录.md .build/artifacts/
cp docs/0.1.2-登录修复与更新.md .build/artifacts/
cp docs/0.2.0-重构说明.md .build/artifacts/
cp docs/0.2.1-内部审查.md docs/0.2.2-开发者服务准备.md .build/artifacts/
echo 'IPA generated; on-device validation is still required.'
