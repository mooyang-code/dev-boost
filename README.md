# dev-boost

Reusable Codex skills for Go engineering workflows.

This repository contains the public GitHub-oriented skill set migrated from the
original moo development boost collection. Internal-only release dry-run and
ticket story creation skills are intentionally not included.

## Skills

| Skill | Purpose |
| --- | --- |
| `moo-git-commit` | Conventional Commit and GitHub Issue/PR commit guidance |
| `moo-go-cli-server-build` | Go CLI + server build templates |
| `moo-golang-architecture` | tRPC-Go architecture and project layout guidance |
| `moo-golang-cli-design` | AI-agent friendly CLI design guidance |
| `moo-golang-code-style` | Go coding style and tRPC-Go usage guidance |
| `moo-golang-secure-coding` | SQL injection and SSRF secure coding guidance |
| `moo-golang-unit-test` | Go unit testing with `github.com/tencent/goom` |
| `moo-skill-review` | Skill review checklist and release-readiness checks |

## Public Components

The migrated skills use public GitHub-compatible components, matching the style
used by `github.com/mooyang-code/xData-mini/storage`:

- `trpc.group/trpc-go/trpc-go`
- `trpc.group/trpc-go/trpc-filter/validation`
- `trpc.group/trpc-go/trpc-database/localcache`
- `github.com/mooyang-code/go-commlib`
- `github.com/tencent/goom`
