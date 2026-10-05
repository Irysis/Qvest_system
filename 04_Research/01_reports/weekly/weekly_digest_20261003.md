# Weekly Digest — 2026-W40 (2026-09-26 ~ 10-03)

> ⚠ **공리 활성화 HOLD 발동** — 회로차단기가 이번 주 공리 쓰기(proposed 발급·review_log·MAP)를 전면 중단했다.
> 사유 = **주입 길이 1990 > 1900**(`worst_header_render(n=8)` = judge+reinforce 조합, 2,000 예산 임박).
> 출처 `.cache/cleaner_pending.json::axiom_candidates.activation_hold`. 조치 = 같은 필드의 `action`.
> 이건 실패가 아니라 설계된 상태다. 다만 아래 §5 처럼 **HELD 사유가 원장에 안 남는 부작용**이 같이 왔다.

---

## 0. 이번 주를 한 줄로

**측정이 0건인 주다.** 1계층 무인 레인은 2026-09-26 11:16:35 에 배포 창을 위해 꺼졌고 그대로 7일,
2계층은 09-24 PIT C11 봉쇄 이후 그대로다. 연구 산출은 09-26 오후의 배포 묶음 하나(α 교정 + 사전등록 draft2 + 소비 보류 신설)가 전부이고,
그 뒤 6일은 **수집 레인과 아침 체인만** 돌았다.

### 0a. 주간 볼륨 (실측 — `.cache/cleaner_pending.json`)

| 축 | 값 | 비고 |
|---|---|---|
| 스윕 삭제 | 14건 | 전량 로그·스크래치 (§6) |
| stage_artifacts 신규 엔트리 | 32건 | **29건이 `paper_recharge/` 수집 산출** · 2건 PNG 재렌더 · 1건 `prereg/_calibration` |
| 신규 L-code | **0건** | `inventory.new_lcodes.n = 0` |
| 커밋 | **0건** | `inventory.git_log_7d.n_commits = 0` (`collect_status: ok` — 수집 실패가 아니다) |
| hypothesis_index 델타 | **0** | 2,864 → 2,864 |
| 위생 경고 | 260건 / 삭제 0건 | `06_Registry/hygiene_report.json:11,17` |
| step_status | 13/13 OK | FAIL 단계 없음 |

### 0b. ★ "stage_artifacts 신규 32" 는 신규 연구 32건이 아니다

32건을 역추적한 결과:

- **29건 = `stage_artifacts/paper_recharge/`** — 일간 논문 수집 레인(09-26·09-29·10-03)의 라우트·트리아지·핸드오프·로그. 측정 산출물이 아니다.
- **2건 = `stage_artifacts/rf_auto_report/auto_port_t.png` · `auto_mdd_oos.png`** — mtime 2026-09-29 09:20:5x. 원장 상태를 다시 그린 것이고 **새 측정은 들어 있지 않다**(같은 창에 `reinforce_ledger_l1.json` 쓰기 없음 — 마지막 쓰기 09-26 13:40:13).
- **1건 = `stage_artifacts/prereg/_calibration`** — 이게 이번 주의 유일한 실측 산출물이다(§2).

`stage_artifacts/replication/` 의 최신 런 디렉터리는 `20260925_225912_32052`(mtime 2026-09-25 23:32:48) — **창 밖**이다. 즉 이번 7일에 돌아간 백테스트 런은 0건이다.

---

## 1. 이번 주의 사건 — **레인 두 개가 동시에 꺼져 있었다**

### 1a. 1계층 — 배포 창을 위한 선제 정지 (09-26 11:16:35)

`06_Registry/reinforce_auto_config.json` (mtime 2026-09-26 11:16:35):

```
"enabled": false,
"deploy_window_20260926": "Q 배포 창 2026-09-26T11:16:35+0900 개시 — 09-25 미배포 키트
  (R3R_rb·ALLOWP·INTEG·O0a·HUMAN 등) + RUNNER-B5-BOUNDARY-FIX 배포 대기 —
  배리어 해제 뒤 B4 가 수리 전 러너로 돌지 않게 선제 정지
  (도훈 '일단 배포에 집중' 2026-09-26) (직전 enabled=True · b5_design.enabled=True)"
```

정지 자체는 근거 있는 결정이다(수리 전 러너로 B4 가 도는 것을 막는 선제 조치). 관측 사실은 **그 창이 7일째 닫히지 않았다**는 것이다.

- 스케줄러는 계속 쏜다 — `06_Registry/scheduler_task_health.json:154-169`: `Qvest_ReinforceAutoLoop` state `Ready` · `last_run 2026-10-03T10:46:51` · `next_run 2026-10-03T10:50:00` · `rc 0`.
- 즉 **tick 은 4분마다 들어오고 매번 설정 게이트에서 즉시 물러난다.** 스케줄러 건강은 초록이고(`failed_new: []` · `stale: []`), 레인 정지는 어느 경보에도 올라오지 않는다 — 유일한 기록은 설정 파일의 산문 필드다.
- 같은 창의 결과: 커밋 0 · 신규 L-code 0 · replication 런 0.

### 1b. 2계층 — C11 봉쇄, 결정은 resolved 인데 레인은 그대로

- `reinforce_auto_config.json::l2_auto` — `enabled: false` · `paused_at 2026-09-24T04:36:59` · `paused_by "C11 봉쇄 워크플로 wf_a429ee6d-8ec"`.
- 그런데 `06_Registry/decision_register.json:1120-1144` 의 `PIT-C11-REMEDIATION` 은 **`status: "resolved"`** 다 — 도훈 결정 2026-09-24T10:31:21 "안 B(계열별 가용시점 층 + 표적 재빌드 + 오염 칸 재측정) 후 안 C(ALFRED as-of 빈티지) 순차".
- 재개 전제는 결정이 아니라 **실행**이다 — 같은 설정의 `resume_how`: "enabled=true 로 되돌리고 5키 삭제 · **재개 전 `module_performance.json` 재빌드(pg2 모듈 제외 확인) 필요**".
- `06_Registry/module_performance.json` mtime = 2026-09-29 08:05:56(아침 체인). **그 재빌드가 pg2 제외를 반영한 것인지는 이 digest 에서 확인하지 않았다 — 미측정.** 확인 전에 재개 판단을 내릴 수 없다.
- 결론: **결정 resolved ≠ 봉쇄 해제.** 결정 원장에는 "remediation 실행 진척"을 담는 칸이 없어서, resolved 로 닫힌 항목과 9일째 멈춘 레인이 서로를 모른다.

### 1c. 좌초 수리 11건 (커밋 0 의 뒷면)

`06_Registry/stranded_repairs.json` (generated 2026-10-03 10:42:29):

| 축 | 값 |
|---|---|
| worktree | 12개 (uncommitted 11 · unmerged 1 · stale>3d **11**) |
| `files_lost` | **11** |
| `files_partial` | 0 |
| `collisions` | 0 |

`lost` 11건 중 10건은 미추적 검사·픽스처 파일(`08_Tests/reinforcement/test_rf_book_channel.R` · `test_overlay_probe_book.R` · `test_rf_implementation_suspect.R` · `test_rf_block_design_action_namespace.R` · `08_Tests/fixtures/rfbd_action_status/` · `08_Tests/hooks/test_auto_commit_hook_output_schema.sh` · `02_Infrastructure/reinforcement/rf_book_channel.R` · `08_Tests/reinforcement/run_rf_book_channel_realdata.R` 등, `added_lines 1` = 존재 탐지분)이고,
실질 1건은 **`06_Registry/m4_published/PROVENANCE_bocpd_guard_defect.md` — main 에 145행 전무**(`stranded_repairs.json:83`).

배포에 집중한다고 레인을 세운 주에 **main 커밋이 0** 이고 수리가 worktree 에 11건 남아 있다 — 이 둘은 같은 사실의 양면이다.

---

## 2. 유일한 실측 — 심층-capture 판정 계기의 α 교정

**가설**: `deep_capture_delta` 의 `p_gt0` 판정이 명목 5% 보다 더 자주 발화한다(적대검증 측정 FPR 0.0866). 블록 길이나 표본 길이가 원인이면 그 축으로 고치고, 아니면 문턱을 직접 교정한다.

**산출**: `stage_artifacts/prereg/_calibration/PR-L2-deep_capture_alpha_v1/calibration.json`
(id `PR-L2.deep_capture_delta.p_gt0.alpha_cal.v1` · created_at 2026-09-25T22:27:49 · 디스크 착지 2026-09-26 13:50:07 · B=2000 · seed 20260925 · reps cal 6000 / hold 3000 / adv 1000)

**결론**: 교정 채택. `alpha_cal = 0.024`(세 잡음 형태 최소값) — `ci_hi<0` 명목 규칙을 대체.

| 축 | 실측 | 출처 (`calibration.json`) |
|---|---|---|
| 문제 (명목 FPR) | 0.0866 (기대 0.05) | `problem.fpr_nominal_reported` |
| 교정값 | **0.024** (real_norm 0.024 · t5het 0.0295 · t5het_ar 0.0325) | `rule.alpha_cal` · `calibration_set.*.alpha_5pct` |
| 보류 검증 (n=1000×3) | α_cal 에서 **0.044 / 0.051 / 0.044** (명목 0.069 / 0.079 / 0.083) | `holdout.*.fpr_at_alpha_cal` |
| 양성 대조 (adv_B 재현) | 명목 0.067 → α_cal **0.041** · invalid 0.064 | `positive_control` |
| 블록 길이 what-if | 1/7/12/24 → FPR 0.063 / 0.075 / 0.080 / 0.090 (**단조 악화**) | `block_length_whatif` |
| 표본 길이 what-if | 심층월 중앙 6/13/26 → 0.067 / 0.060 / 0.073 (**크기 회복 없음**) | `mechanism_ndeep_trend` |
| 검정력 비용 | δ=−0.15 0.268→0.200 · −0.30 0.590→0.463 · −0.45 0.863→0.765 | `power_cost` |

**기전**: 블록을 늘려도 표본을 늘려도 명목 크기가 돌아오지 않는다 → 원인이 블록/표본 축이 아니므로 **크기 5% 를 직접 표적하는 문턱 교정**을 택했다(`findings.conclusion`). 보류 집합에서 0.044~0.051 로 들어왔고 양성 대조에서도 0.041 — **교정이 보류와 대조에서 둘 다 작동**했다.

**정직 경계 2건** (카드가 자기 입으로 적어 둔 것):
1. `instrument.block_rule_note` — "np 패키지 부재 → `adv_block_len` 이 HHJ n^(1/3) 로 폴백(설정 'auto' 의 Politis-White 는 이 환경에서 실현되지 않는다)". 즉 **설정은 자동이라고 적혀 있지만 실현된 블록은 7 고정**이다.
2. `label` — "계기 교정 — **등급 대체 아님 · 전략 산출물 미사용**". 이 수치는 등급이 아니다.

**후속**: 교정은 계기에만 적용됐다. 이 계기를 쓰는 사전등록(PR-L2)이 실제로 측정에 들어간 기록은 창 안에 없다 — 레인이 꺼져 있었다.

**문헌 근거** (`links`): Hall 1986 · Beran 1987(prepivoting) · Hall & Martin 1988(iterated/calibrated bootstrap) · Hesterberg 2015 · Politis & White 2004(블록 길이 — 여기서는 크기 회복 경로가 아님의 대조로 쓰임).

---

## 3. 09-26 배포 묶음 — 측정이 아니라 규율 변경

창 안에서 실제로 바뀐 것들(mtime 기준):

| 시각 | 파일 | 내용 |
|---|---|---|
| 12:42:02 | `06_Registry/overlay_probe_allowlist.json` | 오버레이 프로브 허용 목록 |
| 13:39:54~13:40:10 | `06_Registry/reinforce_ledger_l1.json` | **칸 3건 무효 종결** (아래 3a) |
| 13:40:17 | `06_Registry/a_eligibility_gate.json` | **소비 보류 신설** (아래 3b) |
| 13:44:45 | `06_Registry/reinforce_program.json` | 격자 |
| 13:45:44 | `06_Registry/prereg/{prereg_config.json, reference_floors_v2*.json}` | 기준 바닥 재교정 + 이력 스냅샷 |
| 13:50:07 | `06_Registry/prereg/{prereg_index.jsonl, drafts/PR-L2-B7ASOF-STRUCTDEF.draft2.json, drafts/PR-L1-CAPCORE.draft2.json}` | 사전등록 draft2 ×2 |

### 3a. 칸 3건 — 재지 않고 무효로 닫았다

`reinforce_ledger_l1.json:184198-184269` — `B5_21` / `B5_22` / `B5_23`, date `20260926`, 전부:

- `grade`: `"NA (미결 — 측정 무효 사유: 교차 entry 라벨 노출 설계 r1)"`
- `terminal_reason`: `"측정 무효 사유 — 교차 entry 라벨 노출 설계(r1 · possible) · B5FIX 복원 r2"`
- `lessons`: "설계 재료가 교차 entry 결과 라벨을 노출했다(B5LAB 배포 23:36 이전 · 같은 재료로 잰 B5_16..20 = possible 표식) — **PIT(C1 D-E) 가능성 있는 설계의 새 측정을 만들지 않는다**(도훈 결정 D1=r2 · B5FIX)"
- `opened_at`→`closed_at` = 3~4초. 백테스트를 돌리지 않고 닫았다.

이게 맞는 방향이다 — 오염 가능 설계로 **새 측정을 만들지 않는 것**이 사후 무효화보다 싸다.

직전 참고로 같은 entry 의 `B7_41`(closed 2026-09-25 23:33:16, 창 밖)은 실측됐다:
PORT_t 1.026 / Calmar 0.247 / net SR 0.638 / CAGR 0.147 / MDD 0.596 / OOS −0.647 / DSR 0.134 · `source: authoritative_remeasure.json` · 5조건 중 0 충족 ·
교훈 "carry 대비 MDD 0.452→0.596(+31.9%) · CAGR 0.129→0.147(+14.0%) → **수익만 늘었다(위험 축 미개입)**".
entry 의 `max_attempts` 44 · `block_order` B1→B2→B3→B6→B5→B7→B4 · 순서 사유 "기본 순서 — CAGR 0.140 · Calmar 0.220(수익 축 미충족이면 위험 축을 앞당길 근거가 없다)".

### 3b. ★ A 자격 관문에 **소비 보류**가 생겼다 (발행 보류와 다른 층)

`a_eligibility_gate.json::holds.vintage_flag.consume_hold`:

- 표식 `design_materials_cross_entry_labels` · verdicts `possible`/`consumed`
- 기전: "위 A 보류는 **발행만** 막아 교차 entry 결과 라벨 노출 설계(ORGANIC-DE Q④ possible · 7308 B5_16..20)로 잰 B5 칸이 G2 pass 를 받으면 **B4 결합·carry 로 표식 없이 퍼진다**(이 flag 는 계보 재도출 대상이 아니다)"
- 그래서 이 표식의 칸은 A 발행뿐 아니라 **소비**(블록 승자·누적 바닥·carry 기준선·승격 best)에서도 뺀다 — `rf_runner_gates.R::rf_consume_hold_config → rf_candidate_facts`
- 근거: B5FIX (c) · 도훈 결정 항목 2026-09-26 · 키 부재 = 소비 제외 없음(항등)

**이게 이번 주의 가장 깊은 변경이다.** 보류를 "발행"에만 걸면 오염이 결합·carry 경로로 **라벨 없이** 하류에 퍼진다 — 격리는 발행면이 아니라 소비면에 걸어야 막힌다. 3a 의 칸 3건이 바로 이 규율의 첫 집행이다.

### 3c. 사전등록 2건 — draft2 까지, 측정은 없음

`06_Registry/prereg/prereg_index.jsonl`:

| prereg_id | rev | written_at | bytes |
|---|---|---|---|
| `PR-L2-B7ASOF-STRUCTDEF` (FAM-PR-L2-B7ASOF-01) | 1 → **2** | 2026-09-25T19:12:42 → **22:41:15** | 67,048 → **106,555** |
| `PR-L1-CAPCORE` (FAM-PR-L1-CAPCORE-01) | 1 → **2** | 2026-09-25T19:12:42 → **22:41:15** | 38,031 → **62,579** |

`kind` 는 둘 다 `"draft"` — `registered_from: null`. **등록(registered)된 사전등록은 0건**이고, 측정 기록도 없다.
draft2 의 `config_sha256` 은 `093db7d3…` 로 §2 α 교정의 `instrument.prereg_config_sha256` 과 **일치**한다 — 교정과 draft2 가 같은 설정 판이다.

★ 정직 경계: `written_at` 은 둘 다 **2026-09-25**(창 경계 하루 전)이고 파일 mtime 만 09-26 13:50 이다. W39 digest(`weekly_digest_20260926.md`)는 PR-L1 cap_core 를 §2b 레버 권고로만 언급했고 draft2·α 교정은 담지 않았으므로, 이번 주에 **처음** 기록한다.

---

## 4. 수집 레인 — 창 안에서 유일하게 완주한 레인

| 일자 | fetched | downloaded | registry_added | skipped(중복·기등록) | mcp |
|---|---|---|---|---|---|
| 09-29 | 0 | 0 | 0 | 266 | `mcp_ok` · 후보 245 |
| 10-03 | 2 | 2 | 2 | 264 | `mcp_ok` · 후보 245 |

출처: `stage_artifacts/paper_recharge/alpha_search_handoff_2026{0929,1003}.json`

10-03 신규 2편 (`alpha_search_triage_20261003.json` 점수순):

1. **score 4** — *Regime Discovery and Intra-Regime Return Dynamics in Global Equity Markets* (arXiv 2601.08571, q-fin.ST/MF/RM) · 사유 "포트/횡단면" · `author_hit: false`
2. **score 0** — *Forecasting U.S. equity market volatility with attention and sentiment to the economy* (arXiv 2503.19767, q-fin.GN)

09-29 는 **fetched 0 / skipped 266** — 같은 MCP 후보 245건이 전부 중복 판정됐다. 중복 제거가 작동한 것이고 큐 고갈은 아니다(10-03 에 2건 통과).

**후속**: 2601.08571 은 2계층(국면 식별) 축에 직접 걸리는데 2계층 레인은 봉쇄 중이다 — 큐에 쌓이고 착수는 못 한다.

---

## 5. 공리 사이클 현황 (의무 절)

### 5a. 집계 (`.cache/cleaner_pending.json::axiom_candidates`)

| 축 | 값 |
|---|---|
| 후보 총계 / pending | 123 / **123** |
| 이번 주 **활성화** | **0건** (`activated_axioms: []`) |
| 이번 주 **정제보류(HELD)** | **0건 기록** (`held_axioms: []`) — ★아래 5c 가 핵심 |
| promote crash / skip | 0 / 0 (`promote_skips: []`) |
| `proposed_axioms` | `[]` |
| `pending_5axis` 잔량 | **103건** · 최고령 **87일** (`DIST-AR-005`) |
| `quarantined_evidence` | 6건 (초안 대상 제외 — 불변) |
| `auto_mapped_negative` | 필드 부재 (이번 주 자동 지도 0) |

실패 축 히스토그램: **independence 80** · external 65 · falsification 54 · mechanism 49 · rigor_research 5.
→ 승격을 막는 최대 축은 여전히 **독립성**(같은 클러스터가 기존 카드와 구별되지 않음)이다. `rigor_research` 5 는 리뷰가 거기까지 간 후보가 적다는 뜻이지 그 축이 쉬워서가 아니다(출처 `axiom_candidates.source`: "리뷰 없는 candidate 는 histogram 미포함(정직)").

★ **n_promote_skipped = 0** — SKILL 은 이 수가 크면 정상이고 0 으로 떨어지면 사전판정 배선이 죽은 것이라고 본다. 이번 주 0 은 **배선 사망이 아니라 HOLD** 때문이다(promote 쓰기 자체가 중단돼 스킵 판정 단계에 도달하지 않았다). 다음 주 HOLD 해제 후에도 0 이면 그때가 배선 점검 시점이다.

### 5b. HOLD 사유 해부 — 이번 주는 **활성화를 실제로 막았다**

`activation_hold`:

- 사유: **주입 길이 1990 > 1900** · 기준 `worst_header_render(n=8)`
- 헤더별 실측: `judge+reinforce` **1990**(최악) · `forge+reinforce` 1978 · `book+reinforce` 1977 · `judge` 1965 · `zz-default+reinforce` 1964 · `forge` 1953 · `book` 1952 · `zz-default-header-probe` 1939. `pc_status` 8종 전부 `ok`.
- `inject_len_last_spawn` 1939 · `n_new_active_planned` **0** · `weekly_activation_max` 3 · `dry_run_crash` 0
- 조치(`action`): 사유 검토 후 `weekly_cleaner_sweep.R` 재실행. ★같은 필드가 명시한 구분 — "`QVEST_AXIOM_UNATTENDED` 는 이 HOLD 와 별개(기본 0=OFF 라 무인 활성은 이미 0건이고 활성화는 `approve_axiom(ids, approved_by='dohoon')` 수동 경로뿐). **0 으로 둔다고 쓰기가 보류되지 않는다**."

즉 끊긴 것은 활성화가 아니라 **promote 쓰기 전체**(proposed 발급·review_log·MAP)다. 활성화 예정은 애초에 0건이었으므로 HOLD 가 막은 활성화는 없고, 막힌 것은 **기록**이다.

머리 여유는 10자다(1990 / 1900). 헤더 조합 `judge+reinforce` 가 최악이라는 건 reinforce 마커(+25자, 1965→1990)가 예산을 결정한다는 뜻이다.

### 5c. ★ HELD 가 0건으로 기록된 것은 "보류가 없었다"가 아니다 — **사유 명기**

`held_axioms: []` 인데 같은 파일의 `activation_hold.preview` 47건에는 판정이 들어 있다:

| 판정 | 건수 |
|---|---|
`verdict` PASS | 16 |
`verdict` FAIL | 19 |
`verdict` MAP | 7 |
`verdict` SKIP_UNKNOWN | 4 |
`verdict` null (refine 만) | 1 |
| **`refine_verdict` HELD** | **12** |
| `refine_verdict` REFINED | 5 |

→ **R0~R6 품질 게이트에서 12건이 HELD 로 갈렸는데 `held_axioms` 에는 0건으로 남았다.** HOLD 가 `review_log` 쓰기를 같이 멈췄기 때문이다.

**보류 사유를 적어야 다음 주에 행동이 일어난다**는 것이 이 절의 존재 이유인데, **이번 주는 사유를 적을 수 없다** — preview 레코드가 `{verdict, refine_verdict, would_activate}` 3필드뿐이고 어느 축(R0_polarity/R1_members/R2_tokens/R3_mechanism/R4_falsification/R5_revival/R6_distinct)에서 걸렸는지를 담지 않는다. 축별 사유는 `review_log`(AX-PENDING_*.json)에 들어가고 그 쓰기가 HOLD 로 중단됐다.

**따라서 HELD 12건의 사유 = 미측정이다.** 추정해서 채우지 않는다. 이건 HOLD 의 부작용이고, 다음 주 조치는 두 갈래다:
1. 주입 길이를 1900 아래로 내려 HOLD 를 풀고 `weekly_cleaner_sweep.R` 재실행 → 그때 `review_log` 가 축별 사유를 쓴다.
2. 또는 HOLD 가 `review_log`(진단 쓰기)까지 멈추는 것이 맞는지 재검토 — **활성화는 막고 진단은 남기는** 분리가 가능하면 이 공백이 반복되지 않는다. (하네스 변경이라 본 레인 밖 — 세션 과제로 올린다.)

### 5d. 도훈 confirm 대상 10건 — `within_condition_axis`

`axiom_candidates.confirm_flags` 10건 전부 같은 항목:
"conditional `direction_consistency` 재정의(`within_condition_axis`) 적용 — 주간 도훈 confirm 대상" (2026-07-04 재정의).

대상: `CAND_alpha_search_9053df8e65f9` · `CAND_judge_gate_576b3cecd1e4` · `CAND_qepm_legacy_{5c15885d429f, a4ed5d6c37c2, c487433156b2, c9cf9368331a}` · `CAND_ramp_{4253c52866e1, 5f3bdccc164d, c4308a214e2b, f70fa9d382ed}`
(review_log = 각 `AX-PENDING_<hash>.json`)

### 5e. near-miss 17건 — 상위 5건

| candidate | 실패 축 | weighted |
|---|---|---|
| `CAND_alpha_research_f94d3e05f0b0` | independence | **0.97** |
| `CAND_qepm_legacy_fc27ce62f60d` | independence | 0.845 |
| `CAND_qepm_legacy_48ec61de489a` | independence | 0.84 |
| `CAND_judge_gate_18d277dec81f` | independence | 0.825 |
| `CAND_alpha_research_8a7aa91582ea` | **external** | 0.80 |

최상위 0.97(`f94d3e05f0b0` = family `infra_process`, tags `book_enhancement,book_marginal,screen_tier`, supporting 8)은 이번 주 DIST 초안 **DIST-AR-045 와 같은 클러스터**다 — independence 가 막고 있다는 점이 초안의 (b)/retry_condition 에 그대로 반영됐다.

`8a7aa91582ea`(external 0.80)는 "KR 부실-지문류 비-return 재료 … 3연속 독립 라운드 동일 벽"으로, 실패 축이 독립성이 아니라 **외부 타당성**이라 다른 종류의 보강(다른 시장·다른 기간 재현)을 요구한다.

### 5f. DIST 자동초안 — 8건 (§ 결과 JSON)

`pending_5axis` 103건 중 supporting 상위 8건을 `proposed` 로 초안. 격리 6건은 대상 제외(불변).
상세는 `.cache/cleaner_distill/2026-W40/distill_result.json::dist_drafts` — 각 건에 `statement_refined` + 적대검증 5체크(a~e) + `frontier` + `live_trigger` + `expiry`.

이번 주 초안 8건의 **공통 수리점 2개**:

1. **구 규약 수치 인용** — 강화 격자 카드 2건(DIST-GEN-052 B3 · DIST-GEN-033 B4)의 supporting 수치는 전부 2026-08-30~09-04 측정이고 `close_t1` 규약 교체(P0-05/06, 09-25) **이전** 판이다. `04_Research/01_reports/organic_reinforce_20260925/lever_audit_final.md` 가 쓴 신 규약 집계(§②: A 0 · B 220 · C 884 · F 83 · Calmar ≥0.64 **0칸** · 커버리지 1,187/1,222 = 97%)로 성과 근거를 교체했다.
2. **구 카드의 'family 구조적 한계' 단정** — DIST-QPM-022 의 supporting L-767 이 "16회 연속 실패로 `defense_core_alpha` family 구조적 한계 확인"이라 적었다. 이 단정은 **승계하지 않았다**(AX-000) — envelope-상대 서술로 바꾸고 재도전 경로를 열었다.

★ `proposed` 는 주입 스트림에 들어가지 않는다(INV-6). 활성화 = 도훈 `approve_proposed(c("DIST-..."))`.

---

## 6. 잔재 처리 (의무 절 — 삭제·거부 요약)

### 6a. 기계 스윕 삭제 14건 — 전량 로그·스크래치

`.cache/hygiene_manifest.log` (2026-10-03 10:50:25~26):

| 분류 | 건수 | 내용 |
|---|---|---|
| `weekly_cache_scratch7d` | 2 | `.cache/_b6_battery.log` · `_b6_battery2.log` |
| `weekly_log30d` | 12 | `qm_daily_refresh_20260828~0903.log` 7건 · `qm_morning_briefing_20260831~0903.log` 4건 · `qm_paper_dispatch.log` |

지식 기록은 0건이다. 일간 위생 감사는 따로 **0건 삭제**(`hygiene_report.json:11` `n_deleted: 0`)이고 경고만 260건 남겼다.

### 6b. 세션 판단 — 후보 7건 중 **삭제 제안 0건 · 전량 보류**

| 후보 | 판단 | 사유 |
|---|---|---|
| `0.20` | 보류 | 참조 769 는 사용이 아니라 짧은 숫자 리터럴의 **이름 충돌**. 기계도 같은 이유로 거부한다 |
| `25` | 보류 | 참조 4,012 — 같은 이름 충돌(종목수 상한 리터럴) |
| `cid_smoke.rds` | 보류 | 참조 2건 **실재** — `RP_2301_09173_CID/NOTES.md` · `diag_cid_market_comovement.R`. 진단 자산 |
| `x.rds` | 보류 | 참조 5건 실재 — `cleaner_distill_lib.R` · `test_arm_gen_read_guard.sh` · `test_frontier_queue_io.R` 픽스처. **증류 레인 자신이 쓴다** |
| `downloads` | 보류 | 참조 5건 실재 — `paper_router_run.sh` · DART census 산출물 |
| `Rplots.pdf` | 보류 | 참조 1건(`02_Infrastructure/ops/cleanup.sh` 자신). **5주째 같은 자리** — 수리는 삭제가 아니라 발생원(R 그래픽 디바이스 자동 산출) 차단이고 그건 하네스 변경이라 본 레인 밖 |
| `02_Infrastructure/ast/tests/parity_factor_db_result.json` | 보류 | 참조 2건 실재(패리티 테스트 · 연산자 백로그). `misplaced_outputs` 경고는 **위치** 문제이지 사멸이 아니다 |

**0건 삭제가 이번 주의 정답이다.** 후보 7건 전부가 (a) 이름 충돌이거나 (b) 참조가 실재한다. 판단이 갈리면 보존이 규칙이고, 이 레인은 매주 돈다.

**다만 후보 목록 자체가 4주 연속 동일하다** — W39 매니페스트(`06_Registry/distill_manifest_20260926.json::preserved_deferred`)의 7건과 이번 주 7건이 같은 집합이다. SKILL §0.1b 는 "거부 사유가 매주 같으면 목록이나 가드가 낡은 것"이라고 본다. 여기서는 **가드가 낡은 게 아니라 후보 생성기가 낡았다** — 위생 감사의 `root_unauthorized` 가 이름 충돌 항목(`0.20`·`25`)을 매주 다시 올리는데, 그건 지울 수 없는 항목이라 후보로 올릴 가치가 없다. 수리 지점은 `artifact_hygiene_audit.R` 의 후보 생성 쪽이다(하네스 — 본 레인 밖).

---

## 7. ★ 레인 결함 — **증류 L-code 발행이 5주째 0건이고 원인은 한 줄이다**

`.cache/cleaner_distill_log.jsonl` 전량:

| week_of | materials n_lines | n_drafts_ok | **n_lcodes_ok** | n_deleted |
|---|---|---|---|---|
| 2026-W36 (09-05) | 654 | 8 | **0** | 1 |
| 2026-W37 (09-13) | 1,592 | 8 | **0** | 1 |
| 2026-W38 (09-19) | 1,282 | 8 | **0** | 4 |
| 2026-W39 (09-26) | 2,685 | 8 | **0** | 1 |
| 2026-W40 (10-03) | **164** | — | — | — |

초안은 매주 8/8 통과하는데 **L-code 는 한 건도 발행된 적이 없다.** 매니페스트가 사유를 적어 뒀다 —
`distill_manifest_2026{0913,0919,0926}.json::lcodes` 가 전부:

```json
"lcodes": [ {"ok": false, "reason": "subscript out of bounds"},
            {"ok": false, "reason": "subscript out of bounds"} ]
```

**근본 원인 (코드 읽어 확인):**

- `02_Infrastructure/ops/cleaner_distill_lib.R:478` — 레인이 `emit_lcode(mode = as.character(l$mode %||% "cleaner"), ...)` 로 부른다. 기본값이 `"cleaner"` 이고, 프롬프트의 결과 JSON 예시도 `"mode":"cleaner"` 다.
- `02_Infrastructure/axiom/lcode_emit.R:31-38` — `.LCODE_MODE_PREFIX` 는 **명명 문자 벡터**이고 키는 `alpha_search`/`alpha_research`/`qepm_legacy`/`judge_gate`/`governor_admission`/`strategy_rotation`/`factor_rotation`/`regime_research`/`ramp`/`overlay_research`/`paper_replication`/`reinforcement` 12종. **`cleaner` 는 없다.**
- `lcode_emit.R:121` — `prefix <- .LCODE_MODE_PREFIX[[mode]] %||% "GEN"`.
  원자 벡터에 `[[`로 **없는 이름**을 넣으면 R 은 `NULL` 을 돌려주지 않고 **`subscript out of bounds` 를 던진다**. 그래서 `%||% "GEN"` 폴백은 **도달 불가 코드**다.

즉 레인의 기본 mode 가 폴백 테이블에 없고, 폴백 연산자는 예외 때문에 실행되지 않는다 → **`mode="cleaner"` 로 요청한 L-code 는 결정론적으로 100% 실패한다.** 3주 × 2건 = 6/6 실패가 전부 이 경로다.

**조용한 실패가 아니라 기록된 실패다** — `ok:false` 가 매니페스트에 매주 남았고 `n_lcodes_ok: 0` 도 로그에 남았다. 남은 기록을 **아무도 소비하지 않았다**는 것이 실제 결함이다(릴리스는 `digest_ok` 만 보고 통과한다).

**이번 주 조치**: 결과 JSON 의 L-code 2건을 유효 mode(`qepm_legacy` → prefix `QPM`, 선례 `L-QPM-20260718_101841` 이 같은 Cleaner-레인 ops 교훈을 이 mode 로 적립)로 요청해 **우회**했다. 우회는 수리가 아니다 — 수리 지점 두 곳:
1. `lcode_emit.R:121` 의 `[[` → `[` 또는 `match()` 기반 조회로 바꿔 폴백 `"GEN"` 을 실제로 살린다(한 줄).
2. `cleaner_distill_lib.R:478` 의 기본 mode 를 테이블에 있는 값으로 바꾸거나 `cleaner = "CLN"` 을 테이블에 등재한다.
둘 다 하네스 변경이라 본 레인 밖이다 — 세션 과제.

**교훈의 일반형** (§L-code 로 적립 요청): `%||%` 류 null-폴백은 **`[[` 가 예외를 던지는 자료형에서는 방어가 아니다**. 같은 계통이 저장소에 더 있는지는 미측정 — next_probe 로 남긴다.

---

## 8. 이번 주 요지

**켜진 것 3개.**
① **소비면 격리** — A 자격 관문에 `consume_hold` 가 생겨, 오염 가능 표식 칸이 발행뿐 아니라 블록 승자·carry·승격 best 소비에서도 빠진다. 발행면만 막으면 B4 결합·carry 로 라벨 없이 퍼진다는 기전이 명시됐고, 칸 3건(B5_21/22/23)이 **재지 않고** 무효 종결로 첫 집행을 받았다.
② **판정 계기의 크기 교정** — `deep_capture_delta::p_gt0` 의 명목 FPR 0.0866 을 α_cal 0.024 로 교정했고 보류 3집합에서 0.044/0.051/0.044, 양성 대조에서 0.041 로 들어왔다. 블록·표본 축이 원인이 아님을 what-if 로 배제한 뒤 문턱을 직접 표적한 것이다.
③ **수집 레인** — 10-03 신규 2편(최상위 = 국면 발견·국면 내 수익 동역학, score 4).

**꺼진 것 3개.**
① **측정 전체** — 1계층 레인은 09-26 11:16 배포 창 이후 7일째 `enabled=false`(스케줄러는 4분마다 정상 발화하므로 경보가 안 뜬다), 2계층은 09-24 봉쇄 이후 9일째. 커밋 0 · L-code 0 · replication 런 0 · 수리 11건 worktree 좌초.
② **공리 기록** — 주입 길이 1990 > 1900 으로 promote 쓰기가 전면 중단돼, R0~R6 가 갈라낸 HELD 12건의 **축별 사유가 기록되지 않았다**(추정으로 채우지 않음 — 미측정). 활성화 예정은 0건이었으므로 HOLD 가 막은 활성화는 없다.
③ **증류 L-code 레인** — 5주 연속 발행 0건. 원인은 `lcode_emit.R:121` 의 `[[` 가 없는 이름에 예외를 던져 `%||% "GEN"` 폴백이 도달 불가인 것이고, 레인 기본 mode `"cleaner"` 가 테이블에 없다. 이번 주는 유효 mode 로 우회했고 수리는 세션 과제로 남겼다.

**백로그**: `pending_5axis` 103건(최고령 87일, `DIST-AR-005`) · 격리 6건 9주 정체 · 삭제 후보 7건 4주 연속 동일 집합.
전주 104 → 103 으로, `max_drafts`(8) 가 유입을 겨우 상쇄하는 중이다.

---

*생성: Cleaner 무인 증류 레인 (`cleaner_distill_run.sh`) · week_of 2026-W40 · 재료 `.cache/cleaner_pending.json`(generated 2026-10-03 10:38:52) · 결과 JSON `.cache/cleaner_distill/2026-W40/distill_result.json`*
