import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import { HvigorNode, HvigorPlugin } from '@ohos/hvigor';
import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Builds the KMP shared library (libsakipay.so) and copies it into this module
 * before the native build, so the HAP can be built from DevEco Studio alone.
 *
 * Only arm64-v8a is produced — this matches `abiFilters` in build-profile.json5
 * and covers both a physical device and an arm64 emulator. If you ever need an
 * x86_64 emulator, add "x86_64" back there and add
 * `:sharedLogic:publishDebugBinariesToHarmonyAppX64` to the command below.
 *
 * It skips Gradle entirely when libsakipay.so is already newer than the KMP
 * sources, so ArkTS-only iterations do not pay Gradle's startup cost. Set
 * KMP_FORCE_PUBLISH=1 to force a rebuild, or KMP_SKIP_PUBLISH=1 to skip.
 *
 * The task runs before `default@BuildNativeWithCmake` (see `./hvigorw taskTree`).
 * Remove the plugin (set `plugins: []`) to manage the library by hand instead.
 */

const LIB_RELATIVE_PATH = path.join('libs', 'arm64-v8a', 'libsakipay.so');

/** Walks up from this file until it finds the Gradle root. */
function findGradleRoot(startDir: string): string {
  let dir = startDir;
  for (let i = 0; i < 6; i++) {
    if (fs.existsSync(path.join(dir, 'gradlew')) || fs.existsSync(path.join(dir, 'settings.gradle.kts'))) {
      return dir;
    }
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  throw new Error(`[kmp] could not locate the Gradle root (searched up from ${startDir})`);
}

/** Newest modification time among the inputs that affect libsakipay.so. */
function newestSourceMtime(gradleRoot: string): number {
  let newest = 0;
  const track = (file: string): void => {
    if (fs.existsSync(file)) {
      newest = Math.max(newest, fs.statSync(file).mtimeMs);
    }
  };
  track(path.join(gradleRoot, 'settings.gradle.kts'));
  track(path.join(gradleRoot, 'gradle.properties'));
  track(path.join(gradleRoot, 'gradle', 'libs.versions.toml'));
  track(path.join(gradleRoot, 'sharedLogic', 'build.gradle.kts'));

  const stack: string[] = [path.join(gradleRoot, 'sharedLogic', 'src')];
  while (stack.length > 0) {
    const dir = stack.pop() as string;
    if (!fs.existsSync(dir)) continue;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        stack.push(full);
      } else {
        newest = Math.max(newest, fs.statSync(full).mtimeMs);
      }
    }
  }
  return newest;
}

function kmpSharedLibrary(): HvigorPlugin {
  return {
    pluginId: 'kmp-shared-library',
    apply(node: HvigorNode) {
      node.registerTask({
        name: 'KmpBuildSharedLibrary',
        run: () => {
          if (process.env.KMP_SKIP_PUBLISH === '1') {
            console.log('[kmp] KMP_SKIP_PUBLISH=1 — skipping');
            return;
          }

          const gradleRoot = findGradleRoot(__dirname);
          const libraryPath = path.join(__dirname, LIB_RELATIVE_PATH);
          const force = process.env.KMP_FORCE_PUBLISH === '1';

          if (!force && fs.existsSync(libraryPath)
              && fs.statSync(libraryPath).mtimeMs >= newestSourceMtime(gradleRoot)) {
            console.log('[kmp] libsakipay.so is up to date — skipping Gradle');
            return;
          }

          const gradlew = process.platform === 'win32' ? 'gradlew.bat' : './gradlew';
          const command = `${gradlew} :sharedLogic:publishDebugBinariesToHarmonyApp`;

          console.log(`[kmp] gradle root: ${gradleRoot}`);
          console.log(`[kmp] JAVA_HOME: ${process.env.JAVA_HOME ?? '(unset)'}`);
          console.log(`[kmp] running: ${command}`);

          try {
            const output = execSync(command, {
              cwd: gradleRoot,
              encoding: 'utf-8',
              maxBuffer: 32 * 1024 * 1024,
            });
            if (output) {
              console.log(output);
            }
          } catch (error) {
            // Surface Gradle's own output — hvigor hides it otherwise.
            const failure = error as { stdout?: string; stderr?: string; message?: string };
            console.error('[kmp] ---- gradle stdout ----');
            console.error(failure.stdout ?? '(none)');
            console.error('[kmp] ---- gradle stderr ----');
            console.error(failure.stderr ?? '(none)');
            throw new Error(`[kmp] publishing the shared library failed: ${failure.message ?? error}`);
          }
        },
        postDependencies: ['default@BuildNativeWithCmake'],
      });
    },
  };
}

export default {
  system: hapTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: [kmpSharedLibrary()],
};
