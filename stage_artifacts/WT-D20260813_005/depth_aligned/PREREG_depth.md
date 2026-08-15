# 사전등록 봉인 — WT-D20260813_005 후속 · FQ-237 **깊이-정합 재측정**

작성: 2026-08-13 · **측정 착수 전** 작성 · alpha-research
직전 라운드 정본: `stage_artifacts/WT-D20260813_005/PREREG_impl_lock.md` + `alpha_validation.json` (Q5 판정, 변경 금지)
승계 가설 정본: `qepm/mailbox/worktask/WT-D20260813_005/alpha_hypothesis.json` (mechanism / falsification / regime_scope 무수정 승계)

---

## §0 왜 이 라운드인가 (직전 라운드가 스스로 적발한 최강 자기비판 C1)

직전 라운드의 존재 이유는 "선별 통계량을 **소비 형태와 같은 함수형**으로 바꾼다" 였다.
그런데 **선별은 Q5(상위 20%, 월 ~69종)**, **소비는 top-25(~7.3%)** — 깊이가 약 3배 어긋났다.
왜도-구동 괴리(가설의 기전)는 꼬리로 갈수록 커지므로 깊이 불일치는 검정 대상 효과를 **체계적으로 희석**한다.
⇒ 직전의 `NOT_SUPPORTED`(paired NW3 t **+0.4930**)는 **가설의 시험이 아니었다**. 본 라운드가 그 시험이다.

## §1 이 라운드의 **유일한 변경점** (단일 축)

**선별 목적함수의 분위 깊이를 소비 깊이에 맞춘다.**

| 항목 | 직전 (Q5) | **본 라운드 (DEPTH)** |
|---|---|---|
| 선별 통계량 상위 버킷 | 5분위 Q5 = 상위 20% (월 ~69종) | **상위 D = 25종 (절대 개수)** |
| 소비 깊이 | top-25 (`canonical_screen_bt(top_n=25)`) | **동일 (불변)** |
| 깊이 정합 | 20% vs 7.3% (3배 어긋남) | **일치** |

- **D = 25 는 튜닝 대상이 아니라 소비 형태에서 파생된 값**이다: `top_n = 25` (Production Constraints 종목수 상한, 고정 축).
  월중앙 유니버스 344종(직전 실측) 기준 **25/344 = 7.27%**. 비율이 아니라 **절대 개수**로 못박는 이유는
  소비가 비율이 아니라 절대 25종이기 때문이다(월별 N 변동 시에도 정합 유지).
- ★**깊이를 스윕하지 않는다.** 여러 깊이(예: 10/25/50/69)를 돌려 최선을 고르는 순간
  `selection_type = sweep` + **DSR ≥ 0.5 HARD** 가 붙는다(measurement-graduation §3). **D = 25 단일 고정.**
- 스프레드의 기준선은 **직전과 동일하게 `mean(fwd | valid 전체)`** 로 둔다 — 기준선까지 바꾸면 축이 둘이 된다.

## §2 §1 외 전부 직전과 동일 (상수로 고정)

| 항목 | 확정값 (승계) |
|---|---|
| K (선별 팩터 수) | **5** |
| trailing 창 W | **36개월** |
| 선별 통계량 정규화 | **전 arm NW lag-3 t** (교란 차단 — 함수형 축만 격리) |
| 재료 | **320종** (`master_panel_FIXED` 팩터 집합 = lane_a 331종 − alias 11종) |
| 결합 | `z_score_aligned_equal_weight` (선별 K개 Z_Score_Aligned 종목별 단순평균, 유효 ≥1) |
| 구성 | **top-25 EW long-only · 15bps one-way · 월간 리밸** |
| 벤치마크 | `.cache/benchmark.parquet` (IKS200) 일별 → `apply.monthly(Return.cumulative)`, **ym 키** |
| 기간 | anchor ≤ **2026-07-01** (미완료 홀딩월 2건 격리), 홀딩월 **221개월** (2008-03 ~ 2026-07) |
| PIT 컷오프 | 홀딩월 T 의 선별은 **anchor < A_T** 인 월의 실현 통계만 (직전 36개) |
| `m_*` 사용 | **선별 입력 금지** — 선별 통계량은 lane_a 원자료에서 **매 시점 trailing 재산출** |
| 패널 절단 | `lane_a_feature_panel.parquet` ≤ 2026-07-01 (2026-08 월중 부분수익 +13.6% · 2026-09 전종목 fwd 정확히 0 격리) |

## §3 arm 정의 (6종 — 재료·구성 전부 동일, **선별 통계량만** 다르다)

| arm | 선별 통계량 | 역할 |
|---|---|---|
| `OBJ_RANK` | trailing rank-IC 의 NW3 t 상위 K | **base** (직전과 동일 — 재현 검문 대상) |
| `OBJ_MEAN_DEPTH` | trailing **(mean(fwd\|top-25 by z) − mean(fwd\|all))** 의 NW3 t 상위 K | ★**primary** |
| `OBJ_MEAN_Q5` | trailing (mean(fwd\|Q5) − mean(fwd\|all)) 의 NW3 t 상위 K | **보조 대조 1** — 깊이 효과 분리 (직전 t +0.4930 재현 대상) |
| `OBJ_MED_DEPTH` | trailing **(median(fwd\|top-25) − median(fwd\|all))** 의 NW3 t 상위 K | **negative control** (같은 깊이) |
| `LOOKAHEAD_DEPTH` | `OBJ_MEAN_DEPTH` 인데 창에 **홀딩월 자신 포함** | ★위반 주입 (검사 판별력) |
| `LAG1_DEPTH` | `OBJ_MEAN_DEPTH` 인데 창을 한 칸 더 물림(T−2 까지) | PIT 스트레스 |

## §4 판정 규칙 (착수 전 고정)

- **primary endpoint** = paired 월별 active 차이 **(OBJ_MEAN_DEPTH − OBJ_RANK)** 의 **NW lag-3 t**, 문턱 **≥ +2.0**.
  base = 직전과 같은 `OBJ_RANK` (직전 실측 cap-w PORT_t **0.9474** · active_sr(=IR) **0.2281**).
- **세 값 동시 보고 의무**: `OBJ_RANK` / `OBJ_MEAN_Q5`(직전 +0.4930) / **`OBJ_MEAN_DEPTH`(신규 primary)**.
- **supported**: primary t ≥ +2.0 ∧ 반증축 3종 전부 미발화.
- **not-supported**: primary t < +2.0.
  - 그리고 `OBJ_MEAN_DEPTH ≈ OBJ_MEAN_Q5` (paired t 차이가 작음) → **깊이는 드라이버 아님** 확정.
    ⇒ "선별 통계량 교체는 이 프레임에서 레버 아님" 확정 → **재료 축(FQ-234 일별) 라우팅**. 계열 확대 금지(INV-7).
- **기전 기각 (반증축)**:
  ① `Jaccard(S_mean_depth, S_rank)` 중앙 > 0.8 → 집합이 안 갈림 = 기전 물리적 여지 부재
  ② 왜도 프로파일 분기 **방향** 불일치 (depth-선별 arm 이 rank-선별 arm 대비 상위 버킷 왜도를 **더 높게** 고르지 못함) → 기각
  ③ `OBJ_MED_DEPTH` paired t ≥ +2.0 → **특이성 기각** (임의 통계량 교체로도 개선 = 기전 무관)
- **안정성 비용 상쇄**: primary 문턱 통과여도 회전율 배율(depth/rank) > **1.5** ∧ net(15bps) paired 개선이 문턱 아래 → supported 선언 금지.
- `selection_type` = **chain** (primary 1개, 가설주도 paired 단일 검정, 깊이 스윕 0회). DSR 은 진단 산출·기록.

## §5 검사 판별력 확인 의무 (착수 전 고정 — "통과했다"를 근거로 쓰기 전에)

- **주입 arm** `LOOKAHEAD_DEPTH`: 홀딩월 T 의 선별창에 **T 월 자신의 실현 통계** 포함(1개월 누출). 그 외 전부 동일.
- **기대 자릿수** (직전 arm 실측): PORT_t 0.9899 → **3.4289** (Δ +2.44) · paired t 0.4930 → **4.1557**.
  신규 arm 에서도 **같은 자릿수**(PORT_t Δ > +0.5, paired t 가 문턱 +2.0 을 크게 상회)가 나와야
  null 을 "효과 부재"로 읽을 수 있다. 안 나오면 **"이 측정 장치는 문턱급 효과를 못 본다"** 로 정직 기록하고
  null 을 기각 근거로 쓰지 않는다.
- **LAG1 스트레스 병기**: 직전 단조 반응(LAG1 0.527 < clean 0.990 < LOOKAHEAD 3.429)이 신규 arm 에서도 유지되는지.
  단조 유지 = 오염이 아니라 약한 실신호의 지문.

## §6 프레임 재현 검문 (착수 전 고정 — 승계가 성립하는지 먼저)

깊이만 바꿨으므로 **직전 arm 2종은 소수점까지 재현되어야 한다**. 안 되면 프레임이 드리프트한 것이므로 중단한다.

- (a) `OBJ_RANK` cap-w PORT_t = **0.94741** (±0.0005), active_sr(=IR) = **0.22811** (±0.0005)
- (b) `OBJ_MEAN_Q5` paired NW3 t = **+0.49298** (±0.0005), PORT_t = **0.98991** (±0.0005)
- (c) 홀딩월 수 = **221**, 기간 2008-03-01 ~ 2026-07-01
- (d) 프레임 정상성: `|평균IC| > 0.10` **0종** · 최대 |평균IC| ≈ **0.0488** (앵커 규약 회귀 지문 46종·0.94 급의 부재)
  ※ 승계 지문 중 `M04_Mom_1 +0.0170` / `최대 0.0509` 는 **채택하지 않는다** — 직전 라운드가 그 출처 자산
  (`master_panel_FIXED.rds`)이 원천 재현에 실패함을 실측(27종 표본 cor≥0.99 **8/27**, M04_Mom_1 cor **0.3372**)했고,
  대체 검사(원천 재현성 27/27 + IC 프로파일 정상성)를 봉인해 진행했다. 본 라운드는 그 대체 규약을 승계한다.

## §7 조인/축 감시 (개수 검문만으로는 키 오류를 못 잡는다)

직전 WT-004 실측: **손실이 1행뿐인데 축이 1개월 어긋난** 사례(book 키 `return_ym` 정합 0.700 vs `realized_ym` 0.083).
따라서 **개수 + 축 정합** 이중 검문:

- (a) 각 단계 개월수를 이론값과 대조 — **5% 초과 손실 시 중단**.
- (b) **축 정합**: 합성 스코어 → forward 수익 IC 부호가 **양수**(앵커 규약 정상 지문). 음수 대폭이면 앵커 오정렬.
- (c) 벤치 축 덮개 ≥ 95% + 포트 월↔벤치 월 **ym 일치율 100%** + 중복 0.
- (d) paired 조인은 **손실 0 요구** (`nrow(join) == nrow(base)`) — 동일 축이므로 1행이라도 빠지면 중단.

## §8 basis 명시

- 계약 `net_sr` = `mean(active)/sd(active)*sqrt(12)` = **active SR (= IR)**. **total SR 아님.** 인용 시 항상 `active_sr(=IR)` 라벨.
- **1급 축** = paired 월별 active **NW3 t** (primary) + **canonical PORT_t** (cap-w 벤치) 병기.
- `canonical PORT_t` = `metric_type="canonical_screen"` — **자본 판정 아님**(forge-authoritative).
- 승계 비-성과 반증축(Jaccard · 왜도 프로파일 · negative control 특이성)은 §4 에 그대로 승계.

## §9 산출물 (전부 `stage_artifacts/WT-D20260813_005/depth_aligned/`)

- `PREREG_depth.md` (본 문서 — 측정 전 발행)
- `d1_depth_stats.R` / `d1_depth_stats.rds` — 월별 팩터 깊이-통계 (top-25 평균/중앙값 스프레드)
- `d2_walkforward_depth.R` / `d2_result.rds` — 6 arm walk-forward + 측정 + primary
- `d3_emit.R` → `alpha_validation_depth.json` · `alpha_scores_depth.parquet` (primary arm)
- `challenge_note_depth.md` (self-adversarial)
- ★직전 라운드의 `qepm/mailbox/.../alpha_package.json`(Q5 판정 확정본)은 **덮어쓰지 않는다** — 사후 개작 금지.
  본 라운드 산출은 `alpha_package_depth.json` 으로 depth_aligned/ 에 별도 발행한다.
