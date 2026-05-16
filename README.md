# UUGithubActions

Shared [GitHub Actions](https://docs.github.com/en/actions) **composite actions** and **reusable workflows** for Silverpine **UU** Android/Kotlin open-source libraries (UUKotlinCore, UUKotlinNetworking, UUKotlinTest, and similar repos).

Consumer repos keep thin workflow files under `.github/workflows/` that call into this repository with `uses: SilverPineSoftware/UUGithubActions/...@main`. Build logic lives here once; library repos only declare triggers, module names, and secrets.

Works together with **[UUKotlinBuild](https://github.com/SilverpineSoftware/UUKotlinBuild)** (Gradle convention plugins and version catalog). See that repo’s README for local Gradle setup.

---

## Typical consumer setup (Maven open-source libraries)

A standard UU library repo (e.g. **UUKotlinCore**) usually needs **three workflow files** in its own repository—nothing more for the main release loop:

| Consumer workflow | Trigger | Purpose |
| ----------------- | ------- | ------- |
| **`create-release-tag.yml`** | Manual (`workflow_dispatch`) | Cut a release: bump/read `version` in `gradle.properties`, push git tag `x.y.z` |
| **`publish_to_stage.yml`** | Push to `develop` | CI on every develop commit: test, then publish **snapshot** to Maven staging |
| **`publish.yml`** | Tag push `*.*.*` | Release pipeline: test, publish **release** to Maven Central, GitHub Release, optional version bump on `develop` |

```text
  develop push ──► publish_to_stage.yml
                        │
                        ├─► unit tests
                        ├─► instrumented tests (Gradle Managed Devices)
                        └─► snapshot publish (Sonatype)

  manual tag workflow ──► create-release-tag.yml ──► git tag 1.2.3

  tag 1.2.3 created ──► publish.yml
                        │
                        ├─► unit tests
                        ├─► instrumented tests
                        ├─► release publish (Maven Central)
                        ├─► GitHub Release (+ artifacts)
                        └─► prepare-next-version on develop (optional)
```

Optional extras in some repos: `run_tests.yml` / `run_instrumented_tests.yml` (manual or PR), `build.yml`, **`codeql.yml`** (security scanning).

---

## Organization configuration

Set these under **Settings → Secrets and variables → Actions** (organization or repository).

### Variables

| Variable | Used for |
| -------- | -------- |
| `UU_KOTLIN_BUILD` | Gradle `uu_build` — [UUKotlinBuild](https://github.com/SilverpineSoftware/UUKotlinBuild) plugin + catalog version |
| `UU_ANDROID_MIN_SDK` | Gradle `uu_min_sdk` |
| `UU_ANDROID_TARGET_SDK` | Gradle `uu_target_sdk` |
| `UU_JAVA_VERSION` | Gradle `uu_java_version` and `actions/setup-java` |
| `UU_JAVA_DISTRIBUTION` | `actions/setup-java` distribution (e.g. `temurin`) |

Reusable Android workflows run **`uu-android-load-environment-vars`** first, which maps the first four Gradle-related variables to `ORG_GRADLE_PROJECT_*` on `GITHUB_ENV`. Empty variables are skipped so committed `gradle.properties` defaults still apply.

### Secrets (consumer library repos)

| Secret | Purpose |
| ------ | ------- |
| `CI_READ_PACKAGES_GITHUB_TOKEN` | PAT with `read:packages` — passed as `READ_PACKAGES_PAT` so Gradle can resolve **UUKotlinBuild** from GitHub Packages |
| `RELEASE_PAT` | PAT with `contents: write` — create/push release tags (`create-release-tag`) |
| `MAVEN_CENTRAL_NEXUS_URL` | Sonatype / Central Portal Nexus URL |
| `MAVEN_CENTRAL_SNAPSHOT_URL` | Snapshot repository URL |
| `OSSRH_USERNAME` / `OSSRH_PASSWORD` | Sonatype credentials |
| `SIGNING_KEY_ID` / `SIGNING_PASSWORD` / `SIGNING_KEY` | Maven artifact signing |
| `SONATYPE_STAGING_PROFILE_ID` | Staging profile id |

`READ_PACKAGES_PAT` must be passed explicitly into reusable workflows; caller job `env` does not propagate into `workflow_call` children.

---

## Consumer examples

Pin the branch or tag you trust (examples use `@main`).

### 1. `create-release-tag.yml`

Manual release: create tag from `gradle.properties` or an input version.

```yaml
name: Create Release Tag
permissions:
  contents: write

on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Release version (e.g. 1.0.0). Empty = use gradle.properties'
        required: false
        type: string

jobs:
  create-tag:
    uses: SilverPineSoftware/UUGithubActions/.github/workflows/uu_create_release_tag.yml@main
    with:
      version: ${{ inputs.version }}
    secrets:
      RELEASE_PAT: ${{ secrets.RELEASE_PAT }}
```

After this succeeds, pushing the tag triggers **`publish.yml`** (if configured on `create: tags: ['*.*.*']`).

### 2. `publish_to_stage.yml`

Snapshots on every push to `develop`.

```yaml
name: Publish To Stage
permissions: read-all

on:
  push:
    branches: [develop]

concurrency:
  group: publish-to-stage-${{ github.ref }}
  cancel-in-progress: true

jobs:
  get-build-suffix:
    uses: SilverPineSoftware/UUGithubActions/.github/workflows/uu_get_snapshot_build_suffix.yml@main

  run-tests:
    needs: [get-build-suffix]
    uses: SilverPineSoftware/UUGithubActions/.github/workflows/uu_android_tests.yml@main
    with:
      module_name: library
      build_suffix: ${{ needs.get-build-suffix.outputs.build_suffix }}
    secrets:
      READ_PACKAGES_PAT: ${{ secrets.CI_READ_PACKAGES_GITHUB_TOKEN }}

  run-instrumented-tests:
    needs: [get-build-suffix, run-tests]
    uses: SilverPineSoftware/UUGithubActions/.github/workflows/uu_android_instrumented_tests.yml@main
    with:
      module_name: library
      build_suffix: ${{ needs.get-build-suffix.outputs.build_suffix }}
    secrets:
      READ_PACKAGES_PAT: ${{ secrets.CI_READ_PACKAGES_GITHUB_TOKEN }}

  publish-library-snapshot:
    needs: [get-build-suffix, run-instrumented-tests]
    uses: SilverPineSoftware/UUGithubActions/.github/workflows/uu_android_library_publish_snapshot.yml@main
    with:
      module_name: library
      build_suffix: ${{ needs.get-build-suffix.outputs.build_suffix }}
    secrets:
      READ_PACKAGES_PAT: ${{ secrets.CI_READ_PACKAGES_GITHUB_TOKEN }}
      MAVEN_CENTRAL_NEXUS_URL: ${{ secrets.MAVEN_CENTRAL_NEXUS_URL }}
      MAVEN_CENTRAL_SNAPSHOT_URL: ${{ secrets.MAVEN_CENTRAL_SNAPSHOT_URL }}
      OSSRH_USERNAME: ${{ secrets.OSSRH_USERNAME }}
      OSSRH_PASSWORD: ${{ secrets.OSSRH_PASSWORD }}
      SIGNING_KEY_ID: ${{ secrets.SIGNING_KEY_ID }}
      SIGNING_PASSWORD: ${{ secrets.SIGNING_PASSWORD }}
      SIGNING_KEY: ${{ secrets.SIGNING_KEY }}
      SONATYPE_STAGING_PROFILE_ID: ${{ secrets.SONATYPE_STAGING_PROFILE_ID }}
```

Snapshot versions look like `1.2.3.42-develop-SNAPSHOT` (`version` + build suffix from run number and branch).

### 3. `publish.yml`

Full release when a numeric tag is created.

```yaml
name: Publish
permissions:
  contents: write

on:
  create:
    tags: ['*.*.*']

jobs:
  run-tests:
    uses: SilverPineSoftware/UUGithubActions/.github/workflows/uu_android_tests.yml@main
    with:
      module_name: library
    secrets:
      READ_PACKAGES_PAT: ${{ secrets.CI_READ_PACKAGES_GITHUB_TOKEN }}

  run-instrumented-tests:
    needs: [run-tests]
    uses: SilverPineSoftware/UUGithubActions/.github/workflows/uu_android_instrumented_tests.yml@main
    with:
      module_name: library
    secrets:
      READ_PACKAGES_PAT: ${{ secrets.CI_READ_PACKAGES_GITHUB_TOKEN }}

  publish-library:
    needs: [run-instrumented-tests]
    uses: SilverPineSoftware/UUGithubActions/.github/workflows/uu_android_library_publish_release.yml@main
    with:
      module_name: library
    secrets:
      READ_PACKAGES_PAT: ${{ secrets.CI_READ_PACKAGES_GITHUB_TOKEN }}
      MAVEN_CENTRAL_NEXUS_URL: ${{ secrets.MAVEN_CENTRAL_NEXUS_URL }}
      MAVEN_CENTRAL_SNAPSHOT_URL: ${{ secrets.MAVEN_CENTRAL_SNAPSHOT_URL }}
      OSSRH_USERNAME: ${{ secrets.OSSRH_USERNAME }}
      OSSRH_PASSWORD: ${{ secrets.OSSRH_PASSWORD }}
      SIGNING_KEY_ID: ${{ secrets.SIGNING_KEY_ID }}
      SIGNING_PASSWORD: ${{ secrets.SIGNING_PASSWORD }}
      SIGNING_KEY: ${{ secrets.SIGNING_KEY }}
      SONATYPE_STAGING_PROFILE_ID: ${{ secrets.SONATYPE_STAGING_PROFILE_ID }}

  create-release:
    needs: [run-tests, run-instrumented-tests, publish-library]
    uses: SilverPineSoftware/UUGithubActions/.github/workflows/uu_create_release.yml@main
    secrets:
      UU_GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  prepare-next-version:
    needs: [create-release]
    runs-on: ubuntu-latest
    if: success()
    permissions:
      contents: write
    steps:
      - uses: SilverPineSoftware/UUGithubActions/.github/actions/uu-android-prepare-next-version@main
        continue-on-error: true
        with:
          release_pat: ${{ secrets.RELEASE_PAT }}
```

### Multi-module libraries (e.g. UUKotlinTest)

Run tests per module, but use **one** publish job: `nexus-publish` at the root publishes all subprojects in a single Gradle invocation. A second parallel publish job would race on the same Sonatype staging profile.

```yaml
  publish-libraries:
    needs: [/* all test jobs */]
    uses: SilverPineSoftware/UUGithubActions/.github/workflows/uu_android_library_publish_release.yml@main
    with:
      module_name: library   # any module; Gradle publishes all release publications
    secrets:
      # ... same Maven + READ_PACKAGES_PAT secrets ...
```

Publish artifacts are uploaded from `${{ module_folder }}/*/build/outputs` so every module’s AAR/POM outputs are captured.

### Repos with a sample `app` module

Use `module_name: app` for **`uu_android_build`** (assemble/bundle). Library publish workflows still target `module_name: library` unless the app is what you ship.

### CodeQL (`codeql.yml`)

Thin consumer workflow: triggers on `main` push/PR and a weekly schedule; delegates to **`uu_android_codeql`**.

```yaml
name: CodeQL

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    - cron: '18 8 * * 0'

jobs:
  analyze:
    uses: SilverPineSoftware/UUGithubActions/.github/workflows/uu_android_codeql.yml@main
    secrets:
      READ_PACKAGES_PAT: ${{ secrets.CI_READ_PACKAGES_GITHUB_TOKEN }}
```

The shared workflow analyzes **Actions** (`build-mode: none`) and **Java/Kotlin** (`build-mode: manual`). For Kotlin it loads org Gradle variables, runs `actions/setup-java`, then `./gradlew clean :library:assembleRelease` (override `module_name` / `module_folder` if needed).

---

## Reusable workflows

Callable via `workflow_call` from consumer repos.

| Workflow | Description |
| -------- | ----------- |
| [`uu_create_release_tag.yml`](.github/workflows/uu_create_release_tag.yml) | Create release git tag from version input or `gradle.properties` |
| [`uu_get_snapshot_build_suffix.yml`](.github/workflows/uu_get_snapshot_build_suffix.yml) | Output `build_suffix` like `123-develop-SNAPSHOT` for snapshot versioning |
| [`uu_android_tests.yml`](.github/workflows/uu_android_tests.yml) | Unit tests: `./gradlew clean :{module}:test` |
| [`uu_android_instrumented_tests.yml`](.github/workflows/uu_android_instrumented_tests.yml) | Gradle Managed Device tests (`quickGroup` by default) |
| [`uu_android_build.yml`](.github/workflows/uu_android_build.yml) | Clean, unit test, `assembleRelease`, optional `bundleRelease` (macOS) |
| [`uu_android_library_publish_release.yml`](.github/workflows/uu_android_library_publish_release.yml) | Release publish to Maven Central + artifact upload |
| [`uu_android_library_publish_snapshot.yml`](.github/workflows/uu_android_library_publish_snapshot.yml) | Snapshot publish to Sonatype staging |
| [`uu_create_release.yml`](.github/workflows/uu_create_release.yml) | GitHub Release for current tag; optional artifact upload |
| [`uu_distribute_to_firebase.yml`](.github/workflows/uu_distribute_to_firebase.yml) | Upload APK to Firebase App Distribution |
| [`uu_android_distribute_to_google_play.yml`](.github/workflows/uu_android_distribute_to_google_play.yml) | Upload AAB to Google Play (workflow file name references Firebase historically; job uses Google Play action) |
| [`uu_android_codeql.yml`](.github/workflows/uu_android_codeql.yml) | CodeQL advanced setup: Actions + manual `java-kotlin` Gradle build |

### Common inputs

| Input | Default | Workflows |
| ----- | ------- | --------- |
| `module_name` | `library` or `app` | tests, build, publish, instrumented |
| `module_folder` | `.` | all Android workflows |
| `build_suffix` | run number or from suffix workflow | tests, build, publish snapshot |
| `configuration` | `quickGroup` | instrumented tests only |
| `runner` | `ubuntu-latest` | tests, instrumented |
| `java_distribution` / `java_version` | org vars / optional override | tests, build, instrumented |
| `bundle_release` | `false` | build only |

### Workflow outputs

| Workflow | Output |
| -------- | ------ |
| `uu_get_snapshot_build_suffix` | `build_suffix` |
| `uu_android_build` | `full_version` (version string written to `gradle.properties` during prepare) |

---

## Composite actions

Lower-level steps. Reusable workflows compose these; you can call them directly from a custom job if needed.

### Environment and versioning

| Action | Purpose |
| ------ | ------- |
| [`uu-android-load-environment-vars`](.github/actions/uu-android-load-environment-vars/action.yml) | Write `ORG_GRADLE_PROJECT_uu_build`, `uu_min_sdk`, `uu_target_sdk`, `uu_java_version` to `GITHUB_ENV` |
| [`uu-android-update-version`](.github/actions/uu-android-update-version/action.yml) | Append `build_suffix` to `version=` in `gradle.properties`; output full version |
| [`uu-get-snapshot-build-suffix`](.github/actions/uu-get-snapshot-build-suffix/action.yml) | Compute `{run_number}-{branch}-SNAPSHOT` suffix |
| [`uu-create-release-tag`](.github/actions/uu-create-release-tag/action.yml) | Set `version=` if needed, commit, create and push tag |
| [`uu-android-prepare-next-version`](.github/actions/uu-android-prepare-next-version/action.yml) | After release: bump patch on `develop` when `main` and `develop` match |

### Build and test

| Action | Purpose |
| ------ | ------- |
| [`uu-android-build-prepare`](.github/actions/uu-android-build-prepare/action.yml) | Checkout, update version, setup Java |
| [`uu-android-tests`](.github/actions/uu-android-tests/action.yml) | Prepare + `clean :{module}:test` + upload test reports |
| [`uu-android-instrumented-tests`](.github/actions/uu-android-instrumented-tests/action.yml) | Prepare, Android SDK, KVM (Ubuntu), managed-device tests, upload reports |
| [`uu-android-build`](.github/actions/uu-android-build/action.yml) | Prepare, clean, test, optional signing, assemble/bundle release, upload build outputs |

Instrumented tests exclude annotations by default:

- `com.silverpine.uu.test.instrumented.annotations.UUInteractionRequired`
- `com.silverpine.uu.test.instrumented.annotations.UUIntegrationTest`

Override locally with a different Gradle `configuration` or runner arguments.

### Publish

| Action | Gradle command (typical) |
| ------ | ------------------------ |
| [`uu-android-publish-release`](.github/actions/uu-android-publish-release/action.yml) | `publishReleasePublicationToSonatypeRepository` + `closeAndReleaseSonatypeStagingRepository` |
| [`uu-android-publish-snapshot`](.github/actions/uu-android-publish-snapshot/action.yml) | `publishToSonatype` |

Both use **prepare only** (no full `uu-android-build`), then publish with signing env vars, then upload `*/build/outputs` artifacts.

### Distribution (optional)

| Action | Purpose |
| ------ | ------- |
| [`uu-distribute-to-firebase`](.github/actions/uu-distribute-to-firebase/action.yml) | Download `*-build-artifacts-*`, upload APK to Firebase |
| [`uu-android-distribute-to-google-play`](.github/actions/uu-android-distribute-to-google-play/action.yml) | Download artifacts, upload AAB to Google Play |

---

## Workflows in this repo only

These run **inside UUGithubActions** (or as local references), not as the main consumer pattern:

| File | Purpose |
| ---- | ------- |
| [`create-release-tag.yml`](.github/workflows/create-release-tag.yml) | `workflow_dispatch` using **local** `./.github/actions/uu-create-release-tag` for dogfooding |
| [`publish.yml`](.github/workflows/publish.yml) | Stub/example calling `uu_create_release` |

**UUKotlinBuild** has its own publish workflow on tags; it does not use the Android library publish workflows here.

---

## Design notes

**Composite actions vs `vars`.** Composite actions cannot read `vars` directly. Reusable workflows pass `${{ vars.UU_* }}` into `uu-android-load-environment-vars` inputs.

**GPR authentication.** Jobs that run Gradle set `GPR_TOKEN: ${{ secrets.READ_PACKAGES_PAT || github.token }}`. Use a dedicated PAT when the default `GITHUB_TOKEN` cannot read another repository’s GitHub Packages (typical for `UUKotlinBuild`).

**Java version.** Gradle reads `uu_java_version` from `ORG_GRADLE_PROJECT_*` after the load-env step. `actions/setup-java` still receives `java_version` from org variable `UU_JAVA_VERSION` (or workflow input override) in reusable workflows.

**macOS vs Ubuntu.** Publish and app build jobs use **macOS**. Unit tests and Gradle Managed Devices use **Ubuntu** (with KVM setup for emulators).

**Concurrency.** Consumer `publish_to_stage.yml` files should use `concurrency` on `develop` so overlapping pushes cancel in-flight staging deploys.

---

## Related documentation

- [UUKotlinBuild README](https://github.com/SilverpineSoftware/UUKotlinBuild) — convention plugins, `gradle.properties`, local `~/.gradle/gradle.properties`
- [GitHub reusable workflows](https://docs.github.com/en/actions/sharing-automations/reusing-workflows)
- [Gradle build environment](https://docs.gradle.org/current/userguide/build_environment.html) — `ORG_GRADLE_PROJECT_*` properties
