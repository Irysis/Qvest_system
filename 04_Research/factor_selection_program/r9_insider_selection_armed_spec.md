# R9 — PORT_t-정렬 선별 × insider 패널: armed 스펙 (FQ-019)

**작성**: 2026-07-12 | **상태**: `armed_await_crawl` — 배관 완성, 본측정은 크롤 완결 게이트
**성격**: 이 문서는 *사전등록 초안 + 발사 절차*다. 본측정 실행 전 본 문서의 사전등록 절을 확정(도훈 confirm 불요 — 스펙 범위 내 실행은 FQ-019 armed 위임)하고, 크롤 완결 조건 충족을 확인한다.

---

## 1. 가설·위치 (선별-규율 아크 잔존 frontier)

- **가설**: 선별 기질(substrate)을 return-파생 102 승인팩터에서 **{102 + insider 파생 3종} 확장 패널**로 바꾸면, PORT_t-정렬 trailing 선별(R6에서 유일 양성: 선별격리 paired +3.01)이 return-substrate의 post-2017 감쇠 벽을 우회하는가.
- **아크 맥락**: R4/R5 relevance-선별 전멸 → R6 PORT_t-정렬 첫 양성(cap-w 2.61 < 2.95 미달) → R7 라벨 basis 축 소진. 잔존 frontier = **"PORT_t-정렬 선별 × 비-수익(insider) 패널"** (FQ-014 revival ①, FQ-015 next_action, memory `project-selection-discipline-arc-r4r5r6`).
- **FQ-001과의 구분 (정직 prior)**: standalone insider는 07-10 예비 canonical에서 **DEAD_PRELIM**(placebo 70pct·EW-basis 음·book 비직교 0.49). 본 건은 standalone 재탕이 아니라 **선별 풀 참여**(insider 팩터가 trailing PORT_t 순위에서 스스로 선별되는가) — 결합 가설로서 hypothesis_index 미등재 신규. 그래도 EV는 보수적으로 본다.

## 2. 크롤 완결 확인 조건 (본측정 게이트 — fail-closed 코드 강제)

| 조건 | 값 | 확인 방법 |
|---|---|---|
| 체크포인트 시작 | `200501` | `.cache/dart/insider_backfill/*.csv` 최소 ym |
| 체크포인트 최종월 | **≥ `202604`** (env `R9_REQ_LAST_YM` 로 조정) | 최대 ym. 102-팩터 패널 지평(2026-04)과 정합 |
| 연속성 | **gap = 0** (200501~최종월) | 러너가 자동 검사 |

- 미충족 시 FULL 모드는 `run_ramp_r9_insider_ext.R`이 **stop()으로 거부**한다 (부분 데이터 판정 발화 절대 금지 — FQ-019 wall_check).
- 크롤 스케줄태스크(`Qvest_InsiderBackfill`)·체크포인트 파일은 **read-only 소비** — 어떤 단계도 쓰지 않는다.
- `202402.csv.invalid_elestock_param_bug` 등 비정상 파일은 `^\d{6}\.csv$` 패턴으로 자동 배제.

## 3. 1커맨드 실행 절차 (크롤 완결 즉시)

```bash
cd /c/Users/99922/OneDrive/Quant_Module_Moltbot
RAMP_R6_INSIDER=1 RAMP_R9_FULL=1 Rscript -e 'source("02_Infrastructure/ramp/run_ramp_r6_portt_boruta.R", encoding="UTF-8")'
```

이 1커맨드가 자동으로: ① 크롤 연속성 fail-closed 검사 → ② insider 패널 **재빌드**(`build_insider_factor_panel.R` — 완결 크롤 소비, PIT truncation-invariance assert 포함) → ③ 사전등록 4-config 본측정 → ④ `outputs/ramp/r9_insider_{prereg,gates,paired,summary}_*.{json,parquet}` 산출.

- 실행 규율: 단일스레드(setDTthreads 1)·arrow io 2·`.R` source 경유 — 스크립트에 내장.
- smoke 재검(선택): `RAMP_R6_INSIDER=1`만 설정(FULL 미설정) — 부분창 배관 검증만, 산출 `.cache/` 한정.

## 4. 사전등록 초안 (본측정)

### 4.1 기질·팩터 (배관 확정분)

- **확장 패널** = r6 102 승인팩터 배포권 패널(`r6_factor_deployzone_active.parquet`, 재사용) + insider 3종 append(`insider_factor_deployzone_active.parquet`, 동일 산식 canonical top-25 EW net15bps cap-w active).
- **insider 팩터 3종** (임원 × 시장거래(장내/장외/시간외)만 — mechanical 제외, CMP 2012 / `dart_insider_signal_ic.R` 정의 재사용):
  - `INS01_OffNetBuyIntensity3m` — trailing 3m 순매수 notional, sign·log1p (강도)
  - `INS02_OffBuyBreadth6m` — trailing 6m (매수건−매도건)/(총건) (빈도)
  - `INS03_OffNetBuyRecency` — 최근 순매수월 경과월 ×(−1), 24m cap (최근성)
  - 활동 없는 종목-월 = NA (이벤트 팩터 규약; composite 단계 NA→0 중립).
- **PIT**: 신호월 m = 공시 **접수월**(rcept_dt), forward = m+1월 → 홀딩월 시작 전 데이터만(C5 정합). 빌더에 truncation-invariance assert(표본월 3곳, 미래 행 제거 재계산 == 전체 계산) HARD 내장.

### 4.2 config (≤6 준수: **4 trial**) — [2026-07-13 개정: R12~R15 챔피언 구성 이식]

> **개정 사유**(사전등록 확정 전 초안 수정 — 규율 정합): R12~R15 chain이 construction 3대 축을 실측 완결 — 챔피언 = **F-1 구성(반기 진입 top-K by level36 · 분기 순위-단독 퇴출 · level36-top 충원)**, cap-w 2.937·oos +0.048로 plain(무퇴출 2.612)을 지배. R15 next_probe 1("novel 재료 × 검증된 F-1 구성 이식") 소비. 구 초안의 W60_K10 plain arm(정보량 최소)을 F-1 arm 2개로 교체 — trial 수 4 불변.

| 축 | 값 |
|---|---|
| arms (trial) | `Ppins_W36_K20_plain`(R6-parity) · `Ppins_W60_K20_plain` · **`Ppins_W36_K20_F1`(챔피언 구성)** · **`Ppins_W36_K10_F1`** = 4 |
| controls (비-trial) | 각 arm과 **동일 construction**의 102-only 기질 대응쌍 (insider 한계기여 격리 — construction 교란 제거) |
| cadence | 진입 6m 고정(R6 parity) · F-1 arm은 퇴출 분기(R12 구현 재사용) |
| 측정 | canonical top-25 EW·15bps·liq 2e8·cap-w authoritative (R6 `gates()` 복제) |
| **Boruta arm** | **없음** — Boruta-on-PORT_t-pool 음-소진 (FQ-014 재시도 금지) |
| (참고) R10~R15 | P-pure construction chain(비-sweep·chain 회계, lineage 33) — 본 family sweep 회계에 비산입, DSR 진단 시 병기 |

### 4.3 판정 구조 (paired + kill + HARD)

- **paired**: `Ppins_WxKy vs Pbase_WxKy` per config, NW-t lag3 — insider 참여의 한계기여만 격리.
- **KILL (사전등록)**: 전 config paired < **2.0** → insider 풀-참여 무효. 선별-정렬 아크의 마지막 잔존 frontier 소진 → 아크 종결 L-code + DIST 후보(주간 Cleaner 회부).
- **graduation (불변)**: any `Ppins` cap-w PORT_t ≥ 2.95 ∧ oos_retention ≥ 0.7 ∧ calmar ≥ 0.64 ∧ DSR ≥ 0.5. screening-tier 라벨은 미달 시 통상 규약.
- **dual-basis 진단 병기(v8.3 M2)**: 기각 전 EW-유니버스 대비·cap-tier 분해 확인 의무 — cap-w HARD 판정 자체는 불변. (R7 교훈: 감쇠 상당분 = 벤치 아티팩트이나 EW-oos도 미달이면 D3 재료도 안 됨.)

### 4.4 n_trials family 연속 회계

| Round | trials | 누적 |
|---|---|---|
| R4 (Boruta) | 4 | 4 |
| R5 (StabSel+mRMR) | 6 | 10 |
| R6 (PORT_t-pool ± Boruta) | 6 | 16 |
| R7 (EW-basis 라벨) | 4 | 20 |
| **R9 (insider 확장)** | **4** | **24** |

DSR 산출 시 `n_trials_family = 24` (env `RAMP_R9_NTRIALS` — R8 등 중간 라운드가 family trial을 추가 소비하면 상향 조정 후 실행).

### 4.5 예상 결과 분기 (사전 서약)

| 결과 | 해석·후속 |
|---|---|
| 전 config paired < 2.0 | KILL — 선별-정렬 아크 종결(비-수익 기질로도 무효). L-code + DIST 후보 |
| paired ≥ 2.0 ∧ HARD 미달 | screen-tier — insider 참여 실효는 실재하나 자본 미달. cap-tier/EW 진단으로 국소화 특성 기록 |
| paired ≥ 2.0 ∧ HARD 전건 통과 | graduation 후보 — book-marginal ΔIR(§4 admission)로 이행. governor/도훈 수동 |

## 5. 배관 검증 기록 (SMOKE, 2026-07-12)

- SMOKE 실행: 부분창(2005-01~크롤말 2019-12) end-to-end 1회. **성과 수치는 로그에만(SMOKE_ONLY) — 증거력 없음, 판정 발화 없음.**
- 검증 4종: ① 산출 스키마(gates 10컬럼) ② parity-1(INS01 canonical 재계산 vs 패널 저장 max|Δ|) ③ parity-2(Pbase_W36_K20 vs R6 저장 Ppure_W36_K20 겹침월 max|Δ| — 기계 복제 무결성) ④ PIT assert(truncation-invariance + 신호 최종월 ≤ 크롤말).
- 결과: 스모크 로그 `.cache/_ramp_r9_insider_smoke_*.txt` + manifest `.cache/_ramp_r9_insider_smoke_manifest_*.json` 참조.

## 6. 파일 지도

| 역할 | 경로 |
|---|---|
| 패널 빌더 | `02_Infrastructure/ramp/build_insider_factor_panel.R` |
| R9 하네스 | `02_Infrastructure/ramp/run_ramp_r9_insider_ext.R` |
| 진입점(config 분기) | `02_Infrastructure/ramp/run_ramp_r6_portt_boruta.R` (`RAMP_R6_INSIDER=1`) |
| insider 신호 z | `outputs/ramp/insider_factor_scores.parquet` |
| insider 배포권 패널 | `outputs/ramp/insider_factor_deployzone_active.parquet` |
| 패널 meta(partial 라벨·PIT) | `outputs/ramp/insider_panel_meta.json` |
| 크롤 체크포인트(read-only) | `.cache/dart/insider_backfill/*.csv` |
| 큐 항목 | `06_Registry/alpha_frontier_queue.json` FQ-019 |
