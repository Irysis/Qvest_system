# Qvest Versioning Policy

**Effective**: 2026-05-01 (v7.0 Sprint 2)

## Format

`vMAJOR.MINOR.PATCH` (semver strict)

- **MAJOR** — 우회 불가능한 계약 변경. wt_advance/cert/state machine API 등 kernel layer 변경. 기존 WT artifact 호환성 깨짐.
- **MINOR** — backward-compatible 신규 기능 (예: schema 추가, hook 신규, CLI command 추가).
- **PATCH** — bug fix / docs / internal refactor (계약 보존).

## 예시

| Version | 의미 |
|---|---|
| v6.4.0 | Harness Kernel Stabilization (Sprint 1+2+3) — Major release |
| v7.0.0 | v7.0 Hardening (execution path unification + CI + schema strict + E2E + legacy + ledger) |
| v7.0.1 | v7.0 patch (CI fix, hook bug 등) |
| v7.1.0 | Plugin / docs / dashboard (확장 layer) |
| v8.0.0 | Opus 4.8-Native + R→Python 1급(polyglot) + Axiom 엔진 리뉴얼 — Major |
| v8.1.0 | 3-Mode 헌법 + 실측 거버넌스 + 모듈 자동흐름 (MINOR — backward-compatible 신규) |

## Pre-release tag

| Tag | 의미 |
|---|---|
| `pre-vX.Y.Z-...` | 작업 전 backup (rollback 지점) |
| `vX.Y.Z-sprintN-end` | sprint 완료 checkpoint |
| `vX.Y.Z-rcN` | release candidate (선택) |

## 자동 검증

- CI에서 tag format `vX.Y.Z` lint
- `master` push 시에만 release 가능 (branch protection)

## Charter / SOT 변경

Charter v1.X bump (예: v1.7 → v1.8)는 별도 정책.
- Charter MAJOR → Qvest MAJOR 이상
- Charter MINOR → Qvest MINOR 이상

## 참조

- `CHANGELOG.md` — 모든 release entry (Keep a Changelog 형식)
- `00_Lawbook/Multi_Agent/qvest_master_charter_v1_X.md` — Charter SOT
- `02_Infrastructure/docs/qvest_v8_1_sot.md` + `02_Infrastructure/docs/qvest_modes_sot.md` — Active SOT
- `02_Infrastructure/docs/qvest_v6_4_sot.md` — absorbed historical SOT (read-only retain)
