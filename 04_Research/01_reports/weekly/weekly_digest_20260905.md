# Weekly Digest — 2026-W36 (2026-08-29 ~ 09-05)

**작성**: 2026-09-05 (Q / `/cleaner` 증류 · owner=`auto_distill`)
**기계 스윕**: 2026-09-05 09:00 (`weekly_cleaner_sweep.R`, `dry_run=false`, 삭제 219건)
**수집 창**: 직전 스윕 이후 지난 7일 (08-29 v10 2계층 재편 이후 첫 만주(滿週) 무인 강화 산출)
**출처**: `.cache/cleaner_pending.json`(schema `cleaner_pending_v2`) + `06_Registry/reinforce_ledger_l1.json` + `06_Registry/knowledge_index.md` + 각 L-code 기록
**수치 규약**: 아래 등급·SR 은 전부 해당 L-code 기록(`metric_type` 병기)에서 인용. 본 증류는 개별 `authoritative_remeasure.json` 을 재열지 않았으므로 등급은 **원장에 적립된 값**을 인용한다(재계산·손계산 없음). 값이 없는 축은 "미측정".

> ⚠ **활성화 HOLD 발동** — 이번 주 공리 promote 쓰기가 **전면 중단**됐다. 신규 활성 예정 4건 > `WEEKLY_ACTIVATION_MAX` 3. 4건은 활성화되지 못하고 검토 대기다(§3). **이번 주 실제 활성화 = 0건.**

---

## 0. 주간 볼륨 (실측 — `inventory` / `sweep_detail`)

| 항목 | 값 | 출처 |
|---|---|---|
| 스윕 삭제 | **219** | `sweep_deleted_n` |
| stage_artifacts 신규 | 1,193 | `inventory.stage_artifacts_new` |
| 신규 L-code | 599 | `inventory.new_lcodes` |
| 커밋(7일) | 147 | `inventory.git_log_7d` |
| 위생 경고 | 235 (감사 삭제 1) | `sweep_detail.hygiene_n_warnings` |
| L-code 무결성 | **COLLISIONS_PRESENT** — 1,075 기록 / 990 고유 / **85 충돌** | `sweep_detail.lcode_integrity` |

이번 주는 무인 강화(reinforcement) 레인이 압도적 다수를 차지했다 — 599 신규 L-code 의 대부분이 격자 B1~B5 재현(RF_PAR/RF_AUTO)과 논문 충실구현(RP_AUTO)이다.

---

## 1. 강화 격자 B1~B5 — 블록별 천장 (실측)

출처: `06_Registry/reinforce_ledger_l1.json` · L-code 요약(`knowledge_index.md`). 전 블록 공통: **A등급 0건**, 최고 다중검정 t 는 신호가 실재함을 보이나 Calmar(위험 축)가 합격 구간(≥0.64) 밖에서 갇힌다.

| 블록 | 최고 t | 최고 Calmar | 최고 15bps SR (등급) | 대표 L-code |
|---|---|---|---|---|
| **B1 멀티팩터** | 2.280 (B1_1 risk·catalog) | 0.40 (B1_4) | profit_core 0.79 (C) · value 0.87 (B) | `L-RF-20260904_223318` · `L-RP-20260904_204206` |
| **B2 비중방법** | 2.109 (B2_6 cvar) | 0.41 (B2_7) | **cvar 0.95 (B)** | `L-RF-20260904_194435` · `L-RP-20260904_194418` |
| **B3 유니버스** | **2.630 (B3_12 KOSPI200)** | 0.34 | index 0.73 (B) | `L-RF-20260830_184746` |
| **B4 결합** | 2.251 (B4_18) | 0.34 (B4_25) | 비중제외 LOO 0.73 (B) | `L-RF-20260904_220226` · `L-RP-20260830_194914` |
| **B5 리스크오버레이** | 2.025 (B5_17 csd_idio_tilt) | 0.40 | **vol_x_dd 1.01 (C)** · csd_idio_tilt 0.98 (C/B) | `L-RF-20260904_205939` · `L-RP-20260905_090841` |

**세 줄 요지**
1. **신호는 있고 위험 축이 막는다** — t 는 2.63(B3_12)까지 올라가 신호 존재를 보이는데, 어느 블록도 Calmar 0.42 를 못 넘는다. 낙폭이 40~72% 대역이라 합격선이 연복리 25~51% 를 요구한다. 구속 축은 신호가 아니라 낙폭이다([[project-lean-loop-day1-13-rounds-20260823]] 재확인).
2. **B5 에서 처음으로 스칼라형이 아닌 오버레이가 t=2 를 넘겼다** — `csd_idio_tilt`(횡단면 특이변동 순위 차등)가 t 2.025·등급 B(`L-RF-20260904_205939`). 반면 스칼라 총노출 축소형(vol_target·dd_brake·ml_tail_gate)은 반복적으로 음수 t. 오버레이의 유효 축은 총노출 스칼라가 아니라 **횡단면 차등**이라는 [[project-label-diversity-is-not-action-diversity-20260903]] 과 정합.
3. **팩터·비중 단독 교체는 위험축을 못 접는다** — B1 적층(1→5팩터)이 t 를 단조 개선하지 않고(깊을수록 하락 사례 다수), B2 SchurDamping 은 반복적으로 최하위. 최강은 얕은 조합·catalog 비중이었다(cvar·ivol).

---

## 2. 논문 충실구현 (RP_AUTO 단독 논문) — 등급

출처: 각 `L-RP-*` 기록(`metric_type=backtested`). **A·B 통과 0건.** 최고 = C.

| 논문 | 등급 | 15bps SR | L-code |
|---|---|---|---|
| Traveling Waves (rank entry/exit) | C | 0.60 | `L-RP-20260830_131619` |
| Experts' earning forecasts (herding) | C | 0.60 | `L-RP-20260901_150451` |
| Regression Trees factor conditioning | C | 0.41 | `L-RP-20260903_082033` |
| Tabular DL cross-regime | C→F | 0.50→0.12 | `L-RP-20260831_130733` |
| JT1993 6-6 모멘텀 | **F** | 0.16 | `L-RP-20260829_122633` |
| CID 베타 LS (Pinchuk 2023) | **F** | 0.15 | `L-RP-20260902_123434` |
| Maximum Drawdown/Recovery/Momentum | F | 0.44 | `L-RP-20260904_160918` |
| 13-Sharpe OOS Factor (drift regimes) | F | 0.17 | `L-RP-20260904_171835` |
| Contrarian (China) | F | −0.42 | `L-RP-20260904_091820` |
| Spatio-Temporal Momentum | F | 0.07 | `L-RP-20260904_095747` |
| 결합: Pinchuk + Regression Trees | F→C | 0.30→0.66 | `L-RP-20260904_112811` |

★ JT1993 F(KR 모멘텀 부재)와 CID 베타 F(역베타 회계 — [[project-cid-beta-spread-is-inverse-market-beta-in-kr-20260902]])는 둘 다 기전이 특정된 정직한 실패다. 이번 주 모든 B 등급은 **논문 단독이 아니라 강화 격자**(Amihud·유니버스·cvar·csd_idio_tilt)에서만 나왔다.

---

## 3. 공리 사이클 현황 (의무 절)

**집계** (`axiom_candidates`, 스윕 [3.5] 실측):

| 항목 | 값 |
|---|---|
| pending 후보 / 스폰 생략 | 91 / 0 |
| 이번 주 활성 예정 | **4** (전부 HOLD 로 미활성) |
| 정제보류(HELD) | **15** |
| promote crash | 0 |
| L-code 무결성 | COLLISIONS_PRESENT (85, §4) |

### 3a. ⚠ 활성화 HOLD (맨 위 경고 재게)
`held_at 2026-09-05T09:03` · 사유 = **신규 활성 예정 4건 > WEEKLY_ACTIVATION_MAX 3** → "이번 주 promote 쓰기 전면 중단". 활성 예정이었던 4건(검토 후 `weekly_cleaner_sweep.sh` 재실행 또는 `QVEST_AXIOM_UNATTENDED=0` 유지):
- `CAND_alpha_research_894c7d3df737` (REFINED, would_activate)
- `CAND_alpha_research_f94d3e05f0b0` (PASS·REFINED)
- `CAND_ramp_c4308a214e2b` (PASS·REFINED)
- `CAND_ramp_f70fa9d382ed` (PASS·REFINED)

→ **도훈 결정 대기**: 4건 중 3건만 활성화할지(상한 준수), 상한을 이번 주 4로 올릴지. 자동 진행 금지(INV-6).

### 3b. 정제보류(HELD) 15건 — **사유 명기** (사유 없는 보류는 다음 주 무행동)
정제 게이트 미통과. 실린 필드(멤버 L-code `next_probe`/`live_trigger`·반증 시도·polarity 라벨)를 고치면 다음 스윕 자동 재시도. 수동 해제 = `approve_axiom`.

| 공리 | mode | n_sup | 미달 축 | 해석 |
|---|---|---|---|---|
| AX-AR-001 | alpha_research | 6 | `R0_polarity` | polarity 라벨 미확정 |
| AX-AR-003 | alpha_research | 13 | `R0_polarity` | 동일 |
| AX-AS-001 | alpha_search | 187 | `미기록`(attempts 0) | 정제 미시도 — 다음 스윕 재큐 |
| AX-AS-002 | alpha_search | 507 | `R1_members`·`R4_falsification` | 멤버 next_probe·반증 시도 부재 |
| AX-AS-003 | alpha_search | 204 | `R6_distinct` | 기존 공리와 구별성 부족 |
| AX-JG-001 | judge_gate | 13 | `R5_revival` | live_trigger(부활 조건) 부재 |
| AX-QPM-001~004 | qepm_legacy | 9·11·14·19 | `R5_revival` | 동일 — 4건 전부 부활 조건 결측 |
| AX-QPM-005 | qepm_legacy | 4 | `R4_falsification` | 반증 시도 부재 |
| AX-RAMP-001 | ramp | 13 | `R1`·`R2`·`R4`·`R5`·`R6` | 5축 결측(가장 미성숙) |
| AX-RAMP-002 | ramp | 11 | `R2_tokens`·`R4`·`R6` | 통계·반증·구별성 |
| AX-RAMP-003 | ramp | 12 | `R2_tokens`·`R5_revival` | 통계·부활 조건 |
| AX-RAMP-004 | ramp | 7 | `R4_falsification` | 반증 시도 부재 |

★ 병목의 지배 축 = **`R5_revival`(부활 조건)** 6건 + **`R4_falsification`(반증 시도)** 5건. 둘 다 L-code emit 시점에 채울 수 있는 필드다 — 승격률 레버는 강화·리서치 emit 지점의 `live_trigger`/반증 서술 보강(후속 등재).

### 3c. DIST 자동초안 — 8건 → proposed (§ 결과 JSON)
pending_5axis 백로그 상위 8건에 `statement_refined` + 적대검증 5체크. 전부 `proposed` 까지(주입 안 됨, 활성화는 도훈 권한):
DIST-GEN-048(replication 450) · GEN-047(B5/B4 overlay 30) · GEN-045(B1 17) · GEN-049(B2 17) · **AR-055**(방법론 16) · GEN-041(B3 16) · **GEN-023**(B2 negative 14) · **GEN-027**(B5 negative 14). 두 negative(023·027)는 frontier+live_trigger+expiry 동반.

---

## 4. L-code 무결성 충돌 85건 (신규 관찰)

`lcode_integrity.status = COLLISIONS_PRESENT` — 1,075 기록 중 990 고유, **85 ID 충돌**. 전부 `L-RP-*`(paper_replication) `cross_strategy` 종류로, **병렬 강화 재현(RF_PAR)이 초(second) 해상도 타임스탬프를 공유**해 같은 ID 로 발급됐다(예: `L-RP-20260830_201656` 이 `RP_20260830_200417_29008`·`_33452` 두 전략에서 동시 발급). 기계 action = "최초 1건만 번호 유지·나머지 미발급 번호로 신규 발급(리넘버 아님)". §3 재료의 중복 L-code(같은 ID 가 2~5회 반복)가 이 충돌의 표면이다 — 측정은 살아 있으나 **식별자가 병렬 소각**된다. 후속: 강화 러너의 L-code ID 에 전략 접미사 또는 밀리초 해상도 부여(원장 층 수리, 본 증류 범위 밖).

---

## 5. 잔재 처리 (§4 · 의무 절)

**기계 스윕 삭제**: 219건(매니페스트 `.cache/hygiene_manifest.log`) + 위생 감사 1건. `.cache/_*` 스크래치(_dfa_*·_mfro_* 등 수십 건)는 `weekly_cache_scratch_7d` 로 기계가 자동 처리.

**세션 삭제 판단**: §5 삭제 후보 12건 중 **1건만 삭제, 11건 보류**. 참조≥1 또는 이름 충돌 또는 직전 digest 가 "이동 pending confirm" 으로 보존한 항목은 전부 보류.

| 항목 | 판정 | 사유 |
|---|---|---|
| `delta20_monthend.csv` | **삭제** | root_unauthorized·참조0·13.5일 스크래치 CSV(월말 델타 중간산출). 기계가 git grep 참조0 재도출로 최종 확인 |
| `0.20` · `25` | 보류 | 참조 699·3214 = 이름 충돌(짧은 이름). 기계 어차피 거부 |
| `cid_smoke.rds` · `x.rds` · `parity_factor_db_result.json` | 보류 | 참조 2건씩 실재(x.rds·parity 는 테스트 픽스처) |
| `downloads/` | 보류 | 참조 5 — `alpha_frontier_queue.json` 이 arXiv PDF 실참조 |
| 루트 실행기 5종(`run_as_queue_20260806.R`·`run_fx_intensity.R`·`run_spec_lowfreq_mass.R`·`run_vol_hurst.R`·`run_within_sector_reversal.R`) | 보류 | 참조0 이나 실제 리서치 실행 코드 — 직전 digest 가 "삭제 아닌 **이동**, 도훈 confirm 사안" 으로 보존 승계 |

**거부 요약**: 이번 주 무인 스윕이 219건을 이미 삭제. 세션 추가 삭제는 delta20_monthend.csv 1건 후보뿐이며, 나머지는 전부 "판단이 갈리면 보존" 원칙으로 deferred.

---

## 6. 이번 주 요지 (계통 관찰)

1. **격자의 천장은 신호 천장이 아니라 위험 천장이다** — 5블록 전부 t 는 실재(최고 2.63)한데 Calmar 가 0.42 를 못 넘어 A 0건. 다음 라운드의 레버는 t 를 더 올리는 게 아니라 낙폭을 접는 축(횡단면 차등 오버레이·국면조건부 배합)이다.
2. **오버레이의 유효 축이 갈렸다** — 스칼라 총노출 축소형(vol_target·dd_brake)은 음수 t 로 죽고, 횡단면 차등형(csd_idio_tilt)이 처음으로 B 를 냈다. B5 의 미탐색 인접은 이 방향(2계층 국면조건부 배합).
3. **식별자가 병렬에서 소각된다** — 85 L-code ID 충돌은 측정이 아니라 기록의 결함. 강화 병렬 러너의 ID 발급이 초 해상도라 같은 초에 끝난 두 전략이 겹친다.

---

**증류 산출물**: 본 digest · `.cache/cleaner_distill/2026-W36/distill_result.json`(DIST 초안 8 · 삭제 1 · 보류 11) · 신규 L-code 0건(유의미 미적립 교훈 없음 — 주간 발견은 DIST·본 digest 에 귀속)
