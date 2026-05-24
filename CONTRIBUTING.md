# Contributing

This repo is currently a planning and implementation handoff workspace for an Android-first Flutter app. Keep contributions aligned with the canonical build spec and the open GitHub issue scope.

## Before You Change Files

1. Read [AGENTS.md](AGENTS.md).
2. Read [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md).
3. Read [README.md](README.md).
4. Read the relevant docs under [docs](docs), especially [docs/development-workflow.md](docs/development-workflow.md), [docs/architecture.md](docs/architecture.md), [docs/v2-future-scope.md](docs/v2-future-scope.md), [docs/cybersecurity-report.md](docs/cybersecurity-report.md), [docs/environment.md](docs/environment.md), and [docs/testing-strategy.md](docs/testing-strategy.md).
5. For UI or Flutter work, inspect [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md) and every image in [assets/mockups](assets/mockups).

## Scope

- Work from a focused GitHub issue.
- Preserve existing product, architecture, privacy, cybersecurity, and mockup decisions unless the task explicitly changes them.
- Record durable product or architecture decisions in [docs/decision-log.md](docs/decision-log.md).
- Do not scaffold app/cloud/backend code from a docs-only task.
- Keep setup and verification instructions current in the same change that changes them.

## Privacy And Secret Handling

- Never commit real OpenAI, Microsoft, Google, AWS, signing, account, cookie, or token credentials.
- Never put a standard OpenAI API key in mobile source, mobile config, assets, tests, screenshots, or build outputs.
- Do not add AWS, Lambda, token broker, app backend, cloud sync, server mailer, or cloud identity to the MVP.
- Do not route transcript, audio, prompt, summary, recipient, or export payloads through app-owned backend infrastructure.
- Keep AI chat on a direct OpenAI path scoped to `This meeting` or `All meetings`.
- Use placeholder values in docs and examples.

## Cybersecurity

- Treat dependency hygiene, supply-chain checks, mobile permission minimization, secret scanning, and logging/diagnostics redaction as acceptance criteria.
- Update [docs/cybersecurity-report.md](docs/cybersecurity-report.md) when package versions, dependency state, advisory checks, or rerun triggers change.
- Once implementation exists, pin dependency versions through lockfiles and run `bash scripts/check-supply-chain.sh` plus any required manual advisory checks before merging package changes.

## Verification

For docs-only changes:

```bash
bash scripts/check-docs.sh
git diff --check
```

Once implementation exists, add the relevant gates from [docs/testing-strategy.md](docs/testing-strategy.md), including Flutter analysis/tests, secret checks, dependency/advisory checks, privacy/logging checks, and Android emulator smoke checks.

For dependency-bearing or security-sensitive changes, run:

```bash
bash scripts/check-supply-chain.sh
```

## Pull Requests

Every PR should state:

- Which issue it addresses.
- Which source-of-truth docs changed or were checked.
- What validation ran.
- Any skipped verification and the exact reason.
- Any privacy/security boundary touched.
- Any dependency/package or permission change and the advisory check result.
