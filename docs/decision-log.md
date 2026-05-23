# Decision Log

Use this file for durable product and architecture decisions that future agents should preserve. The canonical build spec remains [docs/live-translate-build-spec.md](live-translate-build-spec.md).

## 2026-05-24 - Initial MVP Architecture

Status: Accepted

Decision:

- Build an Android-first Flutter mobile app while keeping the project iOS-compatible later.
- Use AWS API Gateway + Lambda only as a token broker.
- Keep the standard OpenAI API key in backend secret storage/config only.
- Have the mobile app connect directly to OpenAI with short-lived client secrets.
- Use `gpt-realtime-translate` as the primary live translation model.
- Store transcript history only in encrypted local device storage for the MVP.
- Support Microsoft personal, Microsoft work/school organizational, and Google sign-in.

Rationale:

- Direct mobile-to-OpenAI realtime sessions keep latency low and avoid a transcript/audio proxy.
- A narrow token broker limits backend privacy risk and implementation surface area.
- Local encrypted transcript storage keeps the MVP privacy model simple and explicit.

Implications:

- AWS must never receive transcript text, translated text, prompts about transcripts, microphone audio, audio chunks, or audio-derived payloads.
- Transcript Q&A must use a direct OpenAI path or another privacy-preserving path that avoids AWS seeing transcript content.
- Backend logging, mobile logging, diagnostics, and tests must enforce redaction and no-transcript-routing behavior.

## 2026-05-24 - Supplied Mockups Are First-Pass UI Source

Status: Accepted

Decision:

- Treat the four supplied 720x1280 Android portrait JPGs in [assets/mockups](../assets/mockups) and [docs/mockup-ux-spec.md](mockup-ux-spec.md) as the visual and interaction source of truth for the first Flutter implementation.

Rationale:

- The mockups define the expected product feel, required first-pass surfaces, labels, states, and interaction hierarchy more concretely than a generic design-system description.

Implications:

- UI work must inspect the images before implementation.
- Any intentional drift from the mockups must update [docs/mockup-ux-spec.md](mockup-ux-spec.md) or this decision log, depending on whether interpretation or product direction changed.
