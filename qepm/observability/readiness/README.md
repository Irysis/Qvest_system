# Qvest v8.0 Design Readiness Gate

**핵심 질문**: "현재 Qvest는 v8.0 설계를 시작해도 될 만큼 안정적인가?"

v7.0 Hardening + v7.1-lite 패치 완료 후, v8.0 설계 착수 전 자동 판정 도구.

## 목적

v8.0은 자기진화형 연구 OS 단계. 설계 착수 전 v7.x kernel + observability + legacy 격리가 안정적이어야. 이 gate는 15 check를 자동 실행해서 PASS/FAIL/WARN 판정.

## v8 설계 착수 조건

다음 조건 모두 충족 시 `ready_for_v8_design = true`:

1. **strict mode**: 15 check 모두 PASS
2. **non-strict mode**: FAIL 0건 + WARN 허용 (단 critical check는 strict 필수)
3. **3-day soak**: 최근 3일 내 readiness gate 2회 이상 실행 + critical_failure_count = 0
4. **Human 확인**: v8 설계 착수 전 도훈 명시 승인

## 15 Checks

| ID | 의미 | 도구 |
|---|---|---|
| hook_dryrun | 30/30 hook PASS | `08_Tests/hooks/run_all_hooks.sh` |
| e2e_kernel | 4 시나리오 12/12 + production guard | `test_wt_lifecycle_e2e.R` |
| router_selftest | qvest_hook_router selftest | python3 |
| state_machine_selftest | sm_validated_advance 정합 | Rscript |
| cert_rules_selftest | 5 cert eligibility | Rscript |
| schema_active_wt | active WT 14 schema validation | router validate-schema |
| legacy_active_hook_zero | settings.json legacy 0건 | grep |
| synthetic_residue_zero | WT-D9999* 0건 | filesystem |
| qvest_search | search CLI 작동 | resolve_tool() |
| qvest_wt | WT viewer CLI 작동 | resolve_tool() |
| timeline_generation | wt_timeline.R 작동 | Rscript --dry-run/full |
| registry_integrity | strategy_registry.json + book_state parse OK | jsonlite |
| release_metadata | v7.0.1 + v7.1.0 tag + CHANGELOG | git tag + grep |
| soak_record | 3-day soak 2회+ critical 0 | qepm/observability/readiness/soak_log.json |
| **memory_health** (v7.2.1) | Memory Knowledge Health hard=0 + warn count | `02_Infrastructure/memory/memory_knowledge_health.R` (no_write 시 `qepm/observability/memory_health_latest.json` cached read) |

## PASS / FAIL / WARN 의미

- **PASS**: 모든 check 통과, v8 설계 착수 가능 (단 soak 3일 추가 권장)
- **FAIL**: critical check 1+ 실패 → 해소 필요. v8 설계 착수 보류
- **WARN**: optional/generated 부재 또는 non-critical 이슈. strict=FALSE에서는 진행 가능
- **SKIP**: no_write 또는 의존 부재로 skip (production 무손상 우선)

## 3-day soak rule

readiness gate는 한 번의 PASS만으로 충분하지 않음. 3일 내 **2회 이상** 실행 + 그 사이 **critical_failure_count = 0** 필요. soak_log.json에 자동 기록.

운용 권고:
```bash
# Day 1
bash 02_Infrastructure/tools/qvest_v8_ready --strict
# Day 2
bash 02_Infrastructure/tools/qvest_v8_ready --strict
# Day 3 — soak_record check가 PASS
bash 02_Infrastructure/tools/qvest_v8_ready --strict --json | jq .ready_for_v8_design
```

첫 실행에서는 soak_log.json 부재 → soak_record check가 WARN. 정상.

## 실행 명령

```bash
# 기본 (strict + report 작성)
bash 02_Infrastructure/tools/qvest_v8_ready

# JSON only
bash 02_Infrastructure/tools/qvest_v8_ready --json

# Production 무손상 read-only (no_write)
bash 02_Infrastructure/tools/qvest_v8_ready --no-write

# Strict + JSON
bash 02_Infrastructure/tools/qvest_v8_ready --strict --json

# R 직접 호출
Rscript -e 'source("02_Infrastructure/validation/v8_readiness_gate.R");
            res <- run_v8_readiness_gate(strict=FALSE, no_write=TRUE);
            print(res$overall)'
```

Exit code:
- 0 = PASS
- 1 = FAIL
- 2 = WARN only

## 실패 시 조치

### Critical FAIL

| Check | 조치 |
|---|---|
| `hook_dryrun` | `bash 08_Tests/hooks/run_all_hooks.sh` 직접 실행 → 실패 hook 디버깅 |
| `e2e_kernel` | `Rscript 08_Tests/integration/test_wt_lifecycle_e2e.R` + production guard 위반 시 즉시 cleanup |
| `synthetic_residue_zero` | `bash 08_Tests/integration/_e2e_cleanup_guard.sh --force` |
| `legacy_active_hook_zero` | `.claude/settings.json`에서 legacy hook 등록 제거 |
| `release_metadata` | `git tag v7.0.1 v7.1.0` + CHANGELOG 동기화 |

### WARN

대부분 첫 실행 또는 generated artifact 부재 (search_index.jsonl / soak_log.json / wt_timeline cache). 자연스럽게 재실행으로 해소.

## no_write 모드

`--no-write` 플래그는 다음을 보장:
- `qepm/observability/readiness/v8_readiness_*.json` 작성 안 함
- `soak_log.json` append 안 함
- `e2e_kernel` check skip (재실행 안 함, production 무손상 절대 우선)
- `timeline_generation` check은 `--dry-run` 지원 시만 실행

production / book_state / registry / search index / timeline cache **모두 무손상**.

## Generated artifact 부재 (첫 실행 WARN)

다음은 첫 실행 시 WARN 가능:
- `qepm/observability/search_index.jsonl` (qvest_search 첫 build 필요)
- `qepm/observability/timelines/*.json` (qvest_wt 첫 호출로 생성)
- `qepm/observability/readiness/soak_log.json` (gate 첫 실행)

각각 해당 도구 1회 실행 후 재시도.

## Output schema

`v8_readiness_latest.json` 구조:
```json
{
  "gate_id": "v8_design_readiness",
  "ran_at": "ISO8601",
  "project_root": "/...",
  "overall": "PASS|FAIL|WARN",
  "ready_for_v8_design": true,
  "checks": [
    {"id": "...", "name": "...", "status": "PASS|FAIL|WARN|SKIP",
     "details": "...", "evidence_path": "..."}
  ],
  "summary": {"pass": 0, "fail": 0, "warn": 0, "skip": 0},
  "next_actions": [...],
  "strict": true,
  "no_write": false,
  "report_paths": {"latest": "...", "timestamped": "...", "soak_log": "..."}
}
```

## 참조

- 구현: `02_Infrastructure/validation/v8_readiness_gate.R`
- CLI: `02_Infrastructure/tools/qvest_v8_ready`
- Test: `08_Tests/integration/test_v8_readiness_gate.R`
- v7.0 Hardening Plan: `/home/quant/.claude/plans/nifty-tickling-hinton.md`
- v7.1-lite Plan: `/home/quant/.claude/plans/v7-1-cheerful-balloon.md`
