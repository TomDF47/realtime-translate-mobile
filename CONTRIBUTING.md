# Contributing

This repo is currently a planning and implementation handoff workspace for an Android-first Flutter app. Keep contributions aligned with the canonical build spec and the open GitHub issue scope.

## Before You Change Files

1. Read [AGENTS.md](AGENTS.md).
2. Read [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md).
3. Read [README.md](README.md).
4. Read the relevant docs under [docs](docs), especially [docs/development-workflow.md](docs/development-workflow.md), [docs/architecture.md](docs/architecture.md), [docs/environment.md](docs/environment.md), and [docs/testing-strategy.md](docs/testing-strategy.md).
5. For UI or Flutter work, inspect [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md) and every image in [assets/mockups](assets/mockups).

## Scope

- Work from a focused GitHub issue.
- Preserve existing product, architecture, privacy, and mockup decisions unless the task explicitly changes them.
- Record durable product or architecture decisions in [docs/decision-log.md](docs/decision-log.md).
- Do not scaffold app/backend code from a docs-only task.
- Keep setup and verification instructions current in the same change that changes them.

## Privacy And Secret Handling

- Never commit real OpenAI, Microsoft, Google, AWS, or signing credentials.
- Never put a standard OpenAI API key in mobile source, mobile config, assets, tests, or build outputs.
- Do not create AWS routes that ingest, log, persist, or proxy transcript/audio content.
- Keep transcript Q&A on a direct OpenAI path or another privacy-preserving path that avoids AWS seeing transcript content.
- Use placeholder values in docs and examples.

## Verification

For docs-only changes:

```bash
bash scripts/check-docs.sh
```

Once implementation exists, add the relevant gates from [docs/testing-strategy.md](docs/testing-strategy.md), including Flutter analysis/tests, backend tests, secret checks, and Android emulator smoke checks.

## Pull Requests

Every PR should state:

- Which issue it addresses.
- Which source-of-truth docs changed or were checked.
- What validation ran.
- Any skipped verification and the exact reason.
- Any privacy/security boundary touched.
