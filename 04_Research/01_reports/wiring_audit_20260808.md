# 배선 감사 — 표준은 있는데 소비자가 도달하지 않는 지점

**작성** 2026-08-08 · **지시** 도훈 · **생성기** `02_Infrastructure/ops/wiring_map_build.R`
**원장** `06_Registry/wiring_map.json` (기계용·판정 포함) + `wiring_map_baseline.json` (래칫 기준선)
**metric_type**: `static_reference_scan` — 코드 참조 실측. 성과 수치 아님.

## 왜

"올바른 표준이 존재하는데 소비자가 도달하지 않는다"가 **개별 사건이 아니라 반복 계통**임이 2026-08-08 세션에서 7건으로 확인됐다. 그중 5건은 같은 날 수리했고, 6번째(`align_signal_return_ym`)가 FQ-043의 실제 잔여 과제였다.

이 감사를 **정적 보고서로 만들지 않은 이유**: 지도는 만든 순간부터 낡고, **낡은 지도는 "배선 완료"로 위장한다**. 그래서 생성기 + 정기 재생성 + 드리프트 감지(악화만 경고)로 만들었다. 선례 = `artifact_index.json`/`ARTIFACTS.md`(daily_refresh 매일 재생성).

## 실측 (스캔 10,010 파일 · `.claude/worktrees` 제외)

| 구분 | 수 |
|---|---|
| 표준 총계 | **49** (helper 44 · verdict_ledger 5) |
| `orphan` — 실코드 소비자 0 | **11** |
| `thin` — 1~2 | **21** |
| `wired` — 3+ | **17** |
| 단일 lane 배선 (범용 표준인데 한 존에만) | **25** |

판정 기준: `n_consumers_nontest` = **실행 파일(.R/.py/.sh)이 표준 파일 자체를 참조**한 수. 검사기(`08_Tests/`)는 별도 집계해 제외한다 — 검사기만 부르는 표준은 "쓰이는" 게 아니다.

### orphan 11건 — 아무도 안 쓰는 표준

```
aligned_metrics.R                      audit_logger.R
ax_cand_3rd_member_screening.R         essence_backfill.R
lcode_revalidator_v2.R                 poison_pill_ic_return_audit.R
preflight_check.R                      role_honesty_runner.R
signal_portfolio_translation_audit.R
lcode_distill_execution_20260704.json  (verdict_ledger · 1회성 manifest — 정상)
wiring_map.json                        (★자기 산출물 — 알려진 잡음, 아래 한계 참조)
```

### thin 21건 중 우선순위 높은 것

| 표준 | 소비자 | 왜 문제인가 |
|---|---|---|
| `align_signal_return_ym.R` | 2 (전부 ramp) | **FQ-043의 실체.** ym-병합 표준인데 RAMP lane 밖으로 안 나감. 헤더가 배선을 "권고, 강제 아님"으로 명시 유예. exact-Date 병합이 92/255월 소실을 만든 그 결함의 재발 방지책이 국소에만 있음 |
| `benchmark_source_parity.R` | 2 | 오늘 2026-07-27 스케일 단절을 잡아낸 감시기 |
| `panel_alignment_guard.R` | 2 | 패널 정렬 가드 — 같은 계열 |
| `sharpe_standard.R` | 1 | 성과 지표 표준인데 1곳 |
| `close_round.R` | 2 | 연속성 계약 |
| `stranded_repairs.json` · `scheduler_task_health.json` | 2 | 오늘 bootstrap 재판정을 수리한 두 원장 |

## 우선순위 (판정 변경 > 관측 상실 > 중복)

1. **판정 변경 위험** — `align_signal_return_ym`(측정 결과를 바꿈, 실증됨) · `panel_alignment_guard` · `sharpe_standard`
2. **관측 상실** — `audit_logger` · `role_honesty_runner` 등 orphan 헬퍼
3. **무해/정상** — 1회성 manifest, 자기 산출물

## 자동 갱신 배선

- 생성기: `Rscript 02_Infrastructure/ops/wiring_map_build.R` (기준선 갱신은 `--set-baseline`)
- **드리프트 = 악화만 경고**: 소비자 수가 기준선보다 **감소**하면(=누군가 표준을 우회하기 시작) exit 2. 신규 표준이 등재되면 별도 표기
- 판정을 원장에 적는다 — 소비자가 `n_consumers`로 **재판정하지 않게**. (오늘 수리한 bootstrap 4i/§4h가 정확히 그 실패였다)

## ★ 한계 — 검증되지 않은 축은 발행하지 않았다

**재구현 탐지 축(`_unverified_*` 접두)은 판정에 쓰지 않는다.** 직접 대조에서 재현되지 않았기 때문이다:
`weighted_screen_bt.R`을 `canonical_screen_bt`의 재구현자로 실었으나, 같은 술어를 그 파일에 직접 적용하면 `called=FALSE · defined=FALSE`다(그 파일은 주석에서 이름만 언급한다). 계산 경로 어딘가가 어긋나 있고, 원인 규명 전이다.

검증 안 된 수치를 발행하면 **이 감사가 잡으려는 병(잘못된 것을 재고 초록으로 보이기)을 그대로 재현**하므로 보류한다. 후속 과제.

## ★ 이 지도가 구조적으로 못 잡는 변종 — "배선은 됐는데 호출 계기가 없다"

FQ-056 실측(2026-08-08)에서 드러났다. `build_module_performance.R` 은 소비자 수로는 **정상**이다
(`run_factor_rotation.R:32` 가 실제 `source()` 한다 — 이 지도는 `wired` 로 센다). 그런데 그 러너는
**사람이 `/factor-rotation` 을 띄울 때만** 돈다. 그 모드가 06-13 이후 미실행이라 산출물이
`generated=2026-06-13` 으로 **56일 정지**했다(재실행 시 모듈 192→209, +17).

즉 세 상태가 구분되어야 한다:
| 상태 | 소비자 수 | 이 지도 | 실제 |
|---|---|---|---|
| 미배선 | 0~2 | orphan/thin ✅ | 잡힘 |
| 재구현 | 낮음 | `_unverified_` ⚠️ | 미검증 |
| **호출 계기 부재** | **정상(3+)** | **wired ❌** | **못 잡음** |

∴ 소비자 **수**만으로는 부족하고 **산출물의 신선도**를 함께 봐야 한다. 후속 축 후보:
표준이 산출물을 쓰는 경우 그 산출물의 `generated`/mtime 이 정체돼 있으면 `stale_producer` 로 표시.
(FQ-056 은 `daily_refresh.sh` §8.2 무조건-실행으로 개별 해소했으나, **일반 탐지 축은 미구현**.)

## 생성기 자신에게서 발견한 결함 4건 (전부 양성 대조가 검출)

`align_signal_return_ym`은 실소비자가 2개임을 사전에 직접 확인해 둔 **양성 대조**였다. 이것이 네 번 틀렸다가 맞았다:

1. **심볼 매치 과대계상** — 16개로 셈. 원인 = 표준 심볼 `ym_of`/`ym_shift`가 너무 일반적이라 자기 파일에 같은 이름을 정의한 무관한 코드가 매치
2. **자기참조** — 생성기 헤더가 표준 파일명을 나열하고 `wiring_map.json`이 전 표준명을 담아, **모든 표준이 소비자를 얻음**(orphan 3→0)
3. **문서/데이터 언급을 배선으로 계상** — `ast_field_map_v0.json`이 이름만 언급했는데 소비자로 셈(3→2)
4. **재구현 축 미재현** — 위 한계 절

★ 교훈: 정답을 미리 아는 대조가 **한 건이라도** 없었으면 이 지도는 "표준 49건 중 wired 36" 같은 그럴듯한 초록을 냈을 것이다.

## 참조
- 메모리: `project-alarm-inversion-false-volume-20260808` · `project-screen-route-consumer-zero-20260802` · `project-research-pool-predicates-promoted-20260802`
- FQ-043 (`06_Registry/alpha_frontier_queue.json`)
