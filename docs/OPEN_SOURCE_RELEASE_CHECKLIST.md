# Open-source release checklist

Candidate version: `1.2.7+915`, maintained in an isolated fresh-history export.
Record the final public SHA after all audit commits are complete. This checklist
is an engineering gate, not legal advice. Do not create a public remote or
distribute a GPL-labelled APK/AAB until every blocking item is closed on the
exact candidate commit.

## Source repository

- [x] Export only the Android application; the parent workspace is excluded.
- [x] Exclude signing files, APK/AAB files, generated builds, private agent
  handoffs, device serials, workstation paths and private topology.
- [x] Replace private fixture values with neutral examples.
- [x] Start a fresh public history rather than exposing the private history.
- [x] Define CI gates for REUSE, Gitleaks, TruffleHog, deterministic source
  SBOMs, static analysis and tests.
- [x] Keep adversarial user-info URL fixtures while documenting that CI excludes
  TruffleHog's noisy `URI` detector; Gitleaks still scans the complete tree and
  TruffleHog runs every other detector family.
- [x] Verify the final exported tree and fresh history with two independent
  secret scanners immediately before publication.
- [x] Clone the exact final commit into a new directory and repeat all gates.

## Licensing and provenance

- [x] Declare project-authored code as `GPL-3.0-only`.
- [x] Preserve the upstream `rusty4444/hermes-android` MIT notice.
- [x] Preserve font, dependency, companion and project-artwork notices.
- [x] Record deterministic source SBOMs and an explicit unresolved-license
  queue for both public distribution flavors.
- [x] Add REUSE/SPDX annotations without relicensing third-party files.
- [x] Use `qr_code_scanner_plus` with ZXing Core and Android Embedded under
  BSD-2-Clause/Apache-2.0 terms; the proprietary scanner stack is absent.
- [x] Remove the retired always-listening prototype, its model assets and its
  build-time switches from the candidate source.
- [x] Review every SBOM `NOASSERTION` and every custom/non-standard Android AAR
  term against the final binary.

## Product and release parity

- [x] Keep chat behavior frozen except for the approved structured-image path.
- [x] Document `1.2.7+915` against the previous Play baseline `1.2.6+913`.
- [x] Build `fullRelease` from a clean clone for GitHub/Obtainium and build
  `playRelease` separately through the private Play process, using the final
  signing configuration held outside Git.
- [x] Confirm the published source commit exactly matches the source used to
  build the signed Play/Obtainium artifacts.
- [x] Configure release CI to archive artifact SBOMs, SHA-256 manifests and
  signing-certificate reports without publishing signing material.
- [x] Complete owner-led Pixel QA for chat, Bots/rooms/profiles, generated
  images, navigation, QR pairing, Voice and dictation on the 1.2.7 candidate;
  repeat install/start/permission/process smoke on the exact signed 915 APK in
  an Android 16 emulator. The 914-to-915 delta is limited to version metadata
  and release hardening covered by automated tests.
- [x] Confirm QR camera lifecycle and a real pairing payload on the physically
  tested 1.2.7 candidate, plus permission and R8 startup behavior on signed 915.
- [ ] Reconcile Privacy, Play Data Safety, foreground-service declarations and
  the final merged manifest.

## GitHub publication

- [x] Have the owner review the rendered README, logo, Spanish README, license,
  notices, security contact and release notes in a private preview.
- [x] Create `xP3ta/hermes-console` only after explicit owner approval.
- [x] Configure `main` protection, required CI, secret scanning/push protection,
  Dependabot, private vulnerability reporting, issue/PR templates, topics,
  description and homepage.
- [x] Confirm the public anonymous clone, license detection and release URLs.

## Current decision

**GO — source and `v1.2.7` release published on 2026-08-23.** The release tag
points to `8006b01ad99d8d8f5d64c6bbde3ef29841b9a79d`; both signed distribution
channels were built from that source. Remaining unchecked items are
owner-operated Play Console policy confirmation, not unresolved source,
licence, secret or binary gates.
