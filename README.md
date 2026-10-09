# Sakipay — Kotlin Multiplatform

Sakipay is one Kotlin Multiplatform project: a single shared logic module plus
three native app projects. Every platform consumes the same implementation, so the
numbers can't drift.

| Platform | App project | How it gets the logic |
|---|---|---|
| **KMP shared** | `sharedLogic/` | `commonMain` — the authoritative implementation |
| **iOS** | `iosApp/` | links the `SharedLogic` framework |
| **HarmonyOS** | `harmonyApp/` | links `libsakipay.so` over NAPI |
| **Android** | `androidApp/` | direct dependency on `:sharedLogic` |

**UI is native on every platform; only behaviour is shared.** The platform apps
are thin adapters — if you're writing a business rule in Swift or ArkTS, it belongs
in `commonMain`.

> `sharedUI` (the project wizard's Compose module) is intentionally excluded from
> the build — UI is native per platform. Its sources are left on disk untouched.

## Source sets

| Source set | Contents |
|---|---|
| `commonMain` | the whole domain, no platform dependencies |
| `iosMain` | iOS-specific actuals, if any |
| `ohosMain` | the `@CName` C-ABI exports consumed by the HarmonyOS NAPI bridge (`OhosExports.kt`) |
| `androidMain` | (empty — no Android-specific actuals needed yet) |
| `commonTest` | parity tests — run with `./gradlew :sharedLogic:jvmTest` |

`commonMain` holds `EarningsCalculator`, `SakipayConfig`, `VoluntaryOvertime`,
`HolidayCalendarService` (with the holiday data embedded), `MiniJson`, `CivilDate`
and `SakipayCore`. Persistence stays native (SwiftData + AppGroup on iOS,
`@ohos.data.preferences` on HarmonyOS, none on Android yet); each platform stores
the config as a Kotlin-produced JSON document and hands it back for every
calculation.

## Toolchain

The `ohosArm64` / `ohosX64` targets come from the **KMP&CMP HarmonyOS** Kotlin
release — they are **not** in upstream Kotlin. That fixes the version set for the
whole build:

- Kotlin **2.2.21-1.0.0** (fallback: `2.2.21-0.3.0-07`), resolved from the eazytec
  Maven repo listed first in `settings.gradle.kts`.
- AGP **8.11.2**, Gradle **8.14.3**, JDK **17+** (21 recommended).
  `gradle/gradle-daemon-jvm.properties` pins the daemon to JDK 21 — Gradle 8.14.x
  cannot run on JDK 25.
- `compileSdk` **36** / `minSdk` 24 (see `gradle/libs.versions.toml`). Install
  Android SDK Platform 36 if it is missing.

AGP 9.x / Kotlin 2.4.x / Compose 1.12.x (the wizard's defaults) are **not**
compatible with the OpenHarmony toolchain and have been removed.

## Build & run

```bash
# Shared logic tests — the fastest check that the logic is correct.
./gradlew :sharedLogic:jvmTest

# Android
./gradlew :androidApp:assembleDebug
# …or open this folder in Android Studio and Run the `androidApp` configuration
```

### iOS

Open `iosApp/sakipay.xcodeproj` in Xcode and build. A "Compile Kotlin Framework"
run-script phase on the app and widget targets invokes
`./gradlew :sharedLogic:embedAndSignAppleFrameworkForXcode` automatically.

```bash
./gradlew :sharedLogic:linkDebugFrameworkIosSimulatorArm64   # simulator
./gradlew :sharedLogic:linkDebugFrameworkIosArm64            # device
```

### HarmonyOS

Open `harmonyApp/` in DevEco Studio and build — a hvigor plugin
(`harmonyApp/main/hvigorfile.ts`) builds and publishes the shared library before
the native build, so there is no separate step:

```bash
cd harmonyApp
./deploy.sh                  # build, install, launch (first connected target)
./deploy.sh 127.0.0.1:5555   # pick a target explicitly
./deploy.sh --skip-build     # install whatever is already built
```

There is no `hvigorw` wrapper checked into `harmonyApp/`; the CLI form needs
DevEco's own copy plus its SDK and Node. `deploy.sh` sets all of that up.

The published library lands in `main/libs/arm64-v8a/libsakipay.so` plus
`main/src/main/cpp/include/libsakipay_api.h`; `napi_init.cpp` links the former and
`Index.d.ts` declares the functions ArkTS sees as `import testNapi from 'libentry.so'`.

Only **arm64-v8a** is produced (matching `abiFilters`), which covers a physical
device and an arm64 emulator. For an x86_64 emulator, add `"x86_64"` to
`abiFilters` and `:sharedLogic:publishDebugBinariesToHarmonyAppX64` to the plugin's
command.

The plugin skips Gradle entirely when `libsakipay.so` is already newer than the KMP
sources, so ArkTS-only iterations don't pay Gradle's startup cost. Override with
`KMP_FORCE_PUBLISH=1` (always rebuild) or `KMP_SKIP_PUBLISH=1` (never). To manage
the library by hand instead, set `plugins: []` in that hvigorfile and run
`./gradlew :sharedLogic:publishDebugBinariesToHarmonyApp`.

#### "Push Hap Timeout" / the app never deploys

The symptom is DevEco sitting on a deploy for ten minutes and then reporting:

```
Push Hap Timeout.: executeRemoteCommand timed out after 600000ms
```

That message looks like a signing failure but is not one. The HAP is signed
correctly — `hdc` has simply wedged: `hdc shell` still answers while every file
transfer hangs forever, so the HAP is never pushed. Rebuilding or regenerating the
signing config does not help.

Confirm it in one line — this hangs if the channel is wedged:

```bash
printf hi > /tmp/p.txt
hdc -t 127.0.0.1:5555 file send /tmp/p.txt /data/local/tmp/p.txt
```

Recover by restarting the hdc server and re-attaching the emulator's TCP target:

```bash
hdc kill
hdc tconn 127.0.0.1:5555
```

If transfers still hang, cold-boot the emulator from DevEco's Device Manager.
`deploy.sh` does the probe-and-restart automatically and installs under a timeout,
so a wedge fails in ~20s instead of 10 minutes. `DEPLOY_REBOOT=1 ./deploy.sh` also
reboots the target when restarting the server isn't enough.

To check whether a HAP is signed, use the tool rather than eyeballing the file:

```bash
java -jar /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar \
  verify-app -inFile main/build/default/outputs/default/main-default-signed.hap \
  -outCertChain /tmp/c.cer -outProfile /tmp/p.p7b
```

Look for `verify-app success`.

## Adding logic

Put it in `commonMain` and expose it through `SakipayCore`. iOS and Android call
the Kotlin API directly; for HarmonyOS add a matching `@CName` export in
`ohosMain/OhosExports.kt`, a wrapper in `napi_init.cpp` and a declaration in
`Index.d.ts`. Then run `./gradlew :sharedLogic:jvmTest`.
