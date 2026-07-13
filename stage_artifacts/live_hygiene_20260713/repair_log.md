# 라이브 데이터 위생 수리 로그 (task #48, 2026-07-13)

**성격**: 기록·배관 정합 위생 수리 — 전략/자본 무변경. book_state·holdout_interval·recon 원본(rds) 무수정.
**트리거**: monitoring 202607 + TE 진단(te_diag_202607) 2회 연속 플래그 3건.
**산출**: 본 파일 + `monthly_delta.csv` + `repair_meta_item1.json` + `repair_live_book_series.R` (재현 스크립트).

---

## Item 1 — 2026-06 ret_net 불일치 (수리 완료)

### 증상
`STR_1715_on_M4_R05_noLayer4_PG2` 라이브 recon:
- 계약-authoritative rds (`qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds`): 2026-06 ret_net = **0.072401950037505**
- `06_Registry/live_track/STR_1715_on_M4_R05_noLayer4_PG2/live_book_series.csv` (2026-07-03 12:57 생성): **0.058239732510244**
- Δ = −0.01416 (TE 진단 최대기여월 — trailing21 분산 39.2% 기여 월과 동일)

### 원인 (실측 추적 — 산술 exact)
공식(양쪽 동일): `ret_net = β_R05 × m4 × ret_orig − |Δβ_R05| × 15bps`

| 성분 | rds vintage (07-02 19:51 build) | 07-03 재생성 패널 (live_book_series 입력) |
|---|---|---|
| β_R05 | 0.5 | 0.5 (동일) |
| ret_orig | 0.14630390007501 | 0.14630390007501 (동일) |
| **m4** | **1.0** (back-solve exact: 0.5×1.0×0.146304−0.00075 = 0.072401950037505) | **0.8064** (0.5×0.8064×0.146304−0.00075 = 0.058239732510244) |

**m4 vintage flip 단독 원인.** m4는 `stage_artifacts/WT-D20260430_001_m4_extended.csv`(mtime 07-02 07:31, 2026-07-01행까지 연장)를 `run_layer5_rerun_extended.R` L112-131이 ym join + `shift(weight_str1715,1)` lag로 소비하며, **join key(ym 2026-06) 부재 시 NA→1.0 fill**(L131). rds의 입력 faith 패널은 매핑 연장(07-02 07:31) *이전* vintage — 두 메커니즘 중 하나:
- (a) 구 매핑에 2026-06-01 행 부재 → merge NA → **fill 1.0** (L131 아티팩트), 또는
- (b) 구 매핑의 2026-05-04 행 weight가 1.0이었다가 재계산에서 0.8064로 drift.

구 매핑 vintage는 git 미추적·07-02 07:31 덮어쓰기로 미보존 → (a)/(b) 직접 판별 불가(정직 보고). 어느 쪽이든 **[[project-cache-vintage-pinning]] 계열 vintage 불안정**이 실인이며, extend 스크립트 헤더가 경고한 "마지막 달 tipping"과 동종.

### 전 구간 전수 대조 (`monthly_delta.csv`, 269개월 2004-02~2026-06)
- MATCH 265 / **DIVERGENT 4** / MISSING_SIDE 0
- 유의미 불일치는 **2026-06 단 1건** (Δ −1.416e-2). 나머지 3건은 비유의:

| realized_ym | Δ (old−rds) | 성격 |
|---|---|---|
| 2008-01 | −6.4e-07 | m4 소수점 하위자리 vintage 잔차 (CSV 기록 정밀도 수준) |
| 2008-04 | −1.2e-07 | 상동 |
| 2009-06 | −2.7e-06 | 상동 |
| **2026-06** | **−1.416e-02** | m4 1.0↔0.8064 flip (상기) — 유일한 실질 불일치 |

→ **2026-06 외 유의미 Δ 없음 = 추가 데이터 사고 아님.** (2008/2009 3건은 m4 값의 ~1e-6 상대 차이 — 과거 m4_extended 재기록 시 부동소수 기록 정밀도 잔차. 수익률 영향 ≤0.0003%p.)

### 수리 내용
1. 백업: `live_book_series.csv.bak_20260713` (원본 mtime 07-03 12:57 보존).
2. `live_book_series.csv` 재생성 — **ret_net = 계약 rds passthrough** (재계산·자체합성 없음). 구 재계산치는 `ret_recompute_panel` 진단 컬럼 보존, `ret_net_source` 라벨 병기.
3. **`extend_nolayer4_series.R` 배관 패치** (백업 `.bak_20260713`): §2b "계약 rds 앵커" — rds 커버월(≤2026-06)은 rds ret_net 고정, 신규 실현월만 단일-vintage 재계산. 미패치 시 매월 3일 `run_nolayer4_monthly.sh`가 패널 재계산으로 수리를 되돌려 monitoring 플래그가 재발하는 구조였음.
4. 검증: ① 재생성 시리즈 SR_geo = **1.898** (judge 확정값 exact) ② slot 2-3 materialized(`05_Production/.../2-3.../03_period_returns.csv`)와 parity max|dif| = 4.4e-16 ③ `assert_panel_alignment` return_ym β 0.812 PASS ④ 패치된 extend 실행 → 269/269 rds 앵커 + 불일치 4개월 warn 정상 발화 ⑤ `monitor_nolayer4_paper.R` 소비 정상(TG=0 dry-run, "신규 실현월 없음").

### 파급 정합 (참고)
- `portfolio_governor.R` L769~ 가 book recon IR(ΔIR admission baseline, `ir_convention=net_active_recon_v1`)을 이 파일에서 해상 → 수리로 governor recon 경로도 rds와 단일 기준 정렬됨.
- **도훈 판단 재료 (비차단)**: rds의 2026-06 m4=1.0 자체가 NA-fill 아티팩트일 가능성(상기 (a))이 있음. 즉 "진짜" M4 모듈 lag weight는 0.8064였을 수 있고, 그 경우 계약 recon의 2026-06 행이 +1.42%p 낙관. 단 recon 원본은 본 task 무수정 원칙 + holdout interval·judge 확정값·monitoring 정합이 전부 rds 기준이므로, 수정하려면 별도 WT 프로세스(재계산→judge 재확정) 필요. 현행 유지 시에도 방향성 영향은 국소(1개월, 전 구간 SR_geo 1.898 불변).

---

## Item 2 — `.cache/regime_current.json` 부재 (하기 추가)

(작성 중 — 조사·복원 후 추가)

## Item 3 — AR 트랙 recon NOT_TRACKED (조사만, 수리 안 함)

(작성 중 — 조사 후 추가)
