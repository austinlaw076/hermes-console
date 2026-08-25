# Hermes Console

Android-first Flutter **console** for a self-hosted Hermes Agent. The phone is a control surface and protocol client — not an AI provider runtime.

## Language

### Connection & identity

**Instance**:
A saved Hermes server identity the app can open (URLs + secrets + cached capabilities).
_Avoid_: account, workspace, server profile (ambiguous with Agent Profile)

**Active Instance**:
The Instance currently driving home/chat/ops in this app session.
_Avoid_: connected server (state, not identity), foreground connection

**Default Instance**:
The Instance seeded as Active on cold start.
_Avoid_: primary account, home server

**Agent Profile**:
A named Hermes profile scope (soul/skills/memory lens) selected on an Instance. Not an Instance.
_Avoid_: bot, persona (see Bot), user profile

**Pairing Link**:
A secret-bearing QR/URL payload that materializes a draft Instance.
_Avoid_: invite, login link, OAuth

### Control planes

**Gateway**:
Bearer-authenticated Hermes API plane used for chat/runs/capabilities (commonly :8642).
_Avoid_: API server (ok colloquially but prefer Gateway), backend

**Dashboard**:
Session-token admin/web API plane (commonly :9119) for profiles, skills, cron, config.
_Avoid_: admin UI only (it is an API+UI surface), portal

**Mobile Bridge**:
Optional companion process/API (commonly :9131) for provisioned local/server bridge operations.
_Avoid_: VPN, tunnel, proxy (different concepts)

**Capability**:
A server-advertised feature flag/descriptor that gates whether a Console surface is offered.
_Avoid_: permission (OS permission), entitlement, license

### Conversation surfaces

**Conversation**:
A normal chat session with the agent (streaming messages, tools, attachments).
_Avoid_: thread (ok UI-only), room (Mission Control)

**Turn**:
One user→agent interaction cycle inside a Conversation, including streaming and tool events.
_Avoid_: request, job (see Run)

**Run**:
A tracked agent execution unit exposed via runs/approvals APIs and local RunRegistry.
_Avoid_: task (Mission Control Task), job (Cron Job)

**Approval**:
A human gate the server requires before a Run may continue.
_Avoid_: permission prompt (OS), confirmation dialog (generic UI)

### Mission Control

**Bot**:
A Mission Control agent identity (blobatar/visual identity) distinct from a normal Conversation peer label.
_Avoid_: Agent Profile, Instance

**Room**:
A Mission Control collaboration space for bots/activity, not a Conversation transcript.
_Avoid_: channel, group chat

**Task**:
A Mission Control work item (kanban-ish), not a Gateway Run.
_Avoid_: Run, Cron Job, todo

### Voice

**Voice Route**:
The explicit speech path chosen for STT/TTS: on-this-phone vs Hermes-server.
_Avoid_: provider (too vague), engine (implementation)

**Dictation**:
Speech-to-text into a text field without entering full Voice conversation mode.
_Avoid_: Voice (the dedicated mode), recording

**Voice Conversation**:
The dedicated full-duplex/conversation voice experience with its own runtime and consent.
_Avoid_: call, meeting

### Release

**Play Artifact**:
The signed `play` Android App Bundle channel for Google Play only.
_Avoid_: release APK, store build (ambiguous)

**Full Artifact**:
The signed `full` release APK channel for GitHub Releases / Obtainium.
_Avoid_: universal APK, production APK (say Full Artifact)

**QA Artifact**:
Internal physical-test flavor; never a public release channel.
_Avoid_: beta, preview (unless explicitly mapped)
