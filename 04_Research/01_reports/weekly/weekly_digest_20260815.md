# Weekly Digest — 2026-W33 (2026-08-08 ~ 08-15)

**작성**: 2026-08-15 (Q-Lead, `/cleaner` 증류 세션 · owner=`session_main`)
**기계 스윕**: 2026-08-15 13:15:36~13:20 (토 09:00 트리거가 부팅 시 지연 발화), 13 steps 전건 OK, `n_fail_steps=0`, `dry_run=false`, 삭제 1건
**수집 창**: 직전 스윕(2026-08-08 09:00:01) 이후 — 08-08 오후분부터 포함
**출처**: `.cache/cleaner_pending.json`(schema `cleaner_pending_v2`) + `.cache/lcode_corpus.json` + 각 런 아티팩트
**수치 규약**: 아래 수치는 전부 해당 런의 기록 파일 인용. `metric_type` 병기 — 라벨 없는 "backtested" 주장 없음.

---

## 0. 주간 볼륨 (실측)

| 항목 | 값 | 출처 |
|---|---|---|
| stage_artifacts 신규 | 1,965 | `inventory.stage_artifacts_new.n` |
| 신규 L-code | 25 | `inventory.new_lcodes.n` |
| hypothesis_index | 1,143 → 1,213 (**+70**) | `inventory.hypothesis_index` |
| 커밋(7일) | 568 | `inventory.git_log_7d.n_commits` |
| 스윕 삭제 | 1 | `sweep_deleted_n` |

커밋 일자 분포(실측 `git log`): 08-08 149 · 08-09 347 · 08-10 21 · 08-13 51 · **08-14~15 0**.

---

## 1. 알파 리서치 — 실험별 결론

### 1.1 측정 형태 아크 — v8.4 Lane A 전제가 실측으로 섰다

**`L-AR-20260813_R31R33`** · grade `N/A_panel_statistic` · `metric_type=unavailable`(패널 통계) · family=measurement_form
출처 `stage_artifacts/l_code/alpha_research/l_code_AR_fq233_r31r33_target_form_premise_20260813.json`

가설: "평균 표적은 꼬리에 속고 순위·중앙값 표적은 안 속는다"가 factor DB **전반의 측정 가능한 성질**인가.
결론: **세 층 독립 확인**.

- **R31** (D03_RealVol 단일, 258개월): rank-IC **+0.0462**(NW3 t **+3.95**)로 선별력은 강한데, Q5−Q1 **평균** 스프레드 연 **−2.71%**(t −0.55) = 0과 구별 불가 · **중앙값** 스프레드 연 **+15.60%**(t **+3.33**). 같은 팩터·같은 기간에서 평균만 뒤집힌다.
- **R32** (320종 전수): 평균/중앙값 부호 갈림 **123/320(38.4%)**, 그리고 **비대칭** — "중앙값 양수 ∧ 평균 음수"(D03형) **102종** vs 반대형 **21종**(무작위면 반반). "중앙값 유의 양수(t>2) ∧ 평균 비유의(|t|<2)" **99종(30.9%)**, 그중 **46종은 평균이 음수**.
  - **기전 직접 측정**: `cor(왜도기울기, 중앙값−평균 gap) = −0.728`. gap>0 인 팩터 **233/320(72.8%)**.
  - 부수: 준-단조(m_mono≥0.8) 분위 프로파일 **0/320** — 선형·단조 가정이 광범위하게 깨져 있다.
- **R33** (D03 5점 프로파일, 259개월·월중앙 343종목): **혹(hump)형 정점 Q2**. Q1 은 중앙값 최악(**−15.68%**)인데 평균은 **+10.54%**이고 왜도 최고(1.027) — 소수 극단 상승이 Q1 평균을 떠받친다. 왜도 Q1→Q5 단조 감소(1.027→0.726).
  - **독립 2경로 일치**: R31(패널 집계) vs R33(원천 재구축) — 평균 −2.71 vs −2.36 · 중앙값 +15.60 vs +15.42 · 왜도기울기 −0.315 vs −0.302 (0.3%p 안쪽).

**부수 수확 — 무효 스탬프가 인용 문서로 전파되지 않았다**: probe0·probe4 에 `INVALID_FRAME_ERROR` 스탬프가 이미 있었는데 `qvest_v8_4_asymmetry_ml_sot.md` §3 이 그 수치 위에 "Lane A 근거가 실측으로 섰다"를 세워두고 있었다. 본 라운드가 무효 표기 + 재산출로 교체.

---

**`L-AR-20260813_WT005`** · grade C · `metric_type=canonical_screen` · family=measurement_form (FQ-237)
출처 `stage_artifacts/l_code/alpha_research/l_code_AR_wt005_selection_objective_fq237_20260813.json`

가설: 선별 통계량을 rank-IC → **분위 평균 스프레드**로 교체하면 자본 소비면이 개선되는가.
결론: **조건부 보류** (기각 아님).

| arm | paired NW3 t | cap-w PORT_t | IR |
|---|---|---|---|
| 1차 (선별 깊이 20%) | +0.4930 | — | — |
| 2차 (깊이 7.27% 정합) | **+1.5706** | 0.9899 → **1.7775** | 0.2668 → **0.4859** |
| base OBJ_RANK | — | 0.9474 | 0.2281 |

- 자기 적발한 최강 비판 = **깊이 불일치**(선별 Q5 20% vs 소비 top-25 = **7.3%**). 정합 후 점추정 **3.2배 이동**했으나 문턱 2.0 미달.
- **두 분기 어느 쪽도 성립 안 함**: t<2.0 이라 "깊이가 드라이버" 확립 불가이고, DEPTH−Q5 직접 paired t **+1.1753** 이라 "선별 통계량 교체는 레버 아님"도 지지되지 않는다.
- **검사 판별력을 먼저 실증**(★): 1개월 누출 주입 시 1차 t 0.4930 → **4.1557**, 2차 1.5706 → **4.0282**. 동일 통계·동일 n 에서 문턱 크기 효과 탐지 능력 실재 ⇒ **null 은 장치의 무능이 아니다**. LAG1 단조 반응 유지(1.185 < 1.778 < 3.560) = 약한 실신호의 지문.
- 반증축 3종 전부 미발화(두 통계량이 실제로 다른 집합 선택 — Jaccard 중앙 0.111~0.25 · 왜도 프로파일 분기 방향 일치 t −9.788 · negative control 미개선 −0.667/−1.621).
- 최강 반대 증거: 이득 전반부 집중(sp1 2008-14 t 1.88 / sp2 0.67 / **sp3 2020+ −0.32**), 상위 5개월 제거 시 t 1.571 → **0.763**.
- 부수 확립: **paired 설계는 basis 불변**(cap-w t +1.5706 vs EW-유니버스 +1.5709) — 판정이 벤치 구성 논쟁과 독립.
- **승계 자산 결함 적발**: `master_panel_FIXED.rds` 가 원천에서 재현 안 됨(27종 표본 중 8종만 cor≥0.99 · 지문 팩터 M04_Mom_1 **0.3372**). "지문 3/3 일치"는 IC 정상성만 보증하지 원천 재현성은 말하지 않는다.

**next_probe**: ① 깊이 정합을 top-25(7.3%) 고정하고 표본 확장(sp3 이후 구간 축적) 후 재측정 ② 분위 평균 스프레드 대신 **꼬리초과확률** 표적으로 통계량 3안 비교 ③ `master_panel_FIXED.rds` 승계 자산의 원천-충실 재빌드 후 R32 결론 재확인(본 라운드에서 부호갈림 127/… 로 부분 재확인됨).

### 1.2 국면·overlay — 기전 관문에서 2건 기각 (성과 미산출)

두 라운드 모두 **성과 수치 0건**이다. 미달이 아니라 **미측정** — 인용 금지.

**`L-AR-20260813_WT002`** · grade `N/A_mechanism_gate_fail` · `metric_type=unavailable` · family=overlay_regime

하방 꼬리월 AUC: 신규 꼬리표적 **0.7143** < MSM 상태-baseline **0.7472** (VOL 0.7504 · BEAR 0.6789) → **F1_FAIL**.
기전 3중:
1. **꼬리 '형태'에는 정보가 거의 없다** — vol 성분 제거한 TAIL_SHAPE AUC **0.5549 ≈ 우연**. 판별력은 전부 변동성 수준에서 온다(spearman TAIL~VOL **0.838**).
2. **증분 없음** — MSM 직교화 잔차 AUC 0.4361(귀무 밴드 [0.408, 0.612] 내), 역방향 MSM|TAIL 0.6590 = MSM 이 TAIL 을 정보적으로 포함.
3. ★**소비 형태 불일치 — 네 예측기 전부 방향이 아니라 분산을 예측한다**(시계열 rank-IC 넷 다 |t|<1).

★이것이 **overlay 드레인 16건 전량 INFERIOR 라는 기존 실측에 처음으로 기전을 준다**(종래엔 prior 로만 인용).
20 격자 전수(4 lookback × 5 사건정의)에서 신규 표적이 두 baseline 을 모두 상회한 칸 **0/20**. 가설이 사전 지목한 MSM-중립 323개월에서도 사건 포착 **0건**.
자기 적발: expanding-z warm-up 불일치(VOL 367행 vs TAIL 427행)로 초판 VOL 0.7729 과대평가 → 재산출 0.7504, 자기 주장 하향(판정 불변).

---

**`L-AR-20260813_WT003`** · grade `N/A_mechanism_gate_fail` · `metric_type=unavailable` · family=overlay_regime

vol-target 이식. **VT2 PASS / VT2b REJECT** — VT4(성과) 미착수.

| 관문 | 실측 | 판정 |
|---|---|---|
| VT1 예측 링크 | spearman(σ̂, 홀딩월 실현vol) **0.7219** | 실재 |
| VT2 분산 타이밍 이득 | **G 0.1408** vs circular-shift 순열 q95 0.0427 (p<0.0005, 최소효과 0.02 의 **7배**) | 실재 |
| VT2b 수확 | cov(e,r) **−1.480%/yr** (NW3 t −1.108) / 드래그 이득 +0.790 / **순 −0.691%/yr** | REJECT |

표준함수 대조 `Return.annualized` 5.976% vs 통제 6.768% = **−0.792%p**(근사와 일치).

★**분해 성공** — 인접 negative 3건(OVL_book_voltarget_R3 Calmar 1.267 vs base 1.940 · PL_VolTargetFloored/Strict ΔIR −0.288/−0.414 · 06-18 H2)은 전부 **순성과만** 재서 "예측이 죽었는지 수확이 죽었는지"를 못 갈랐다. 본 라운드가 병목을 **수확(cov(e,r))** 으로 확정 ⇒ "vol-managed KR 비이전"이 관찰에서 **기전**으로 승격.

★★**404년 검정력 벽**: 순효과 |t|=1.96 도달에 약 **4,845개월(404년)** 필요(현 366, |t|≈0.539). **시장-레벨 overlay 의 cov(e,r) 채널은 월간 벤치 자료로 원리적 미해소**이며, 인접 3건이 ΔIR·Calmar 로 갈리지 못한 것은 구현 실수가 아니라 **구조**였다.

★설계 핵심 = **exposure-matched 통제**. vol-target 은 노출을 줄여 **기계적으로** vol 을 낮추므로 통제 없이는 "vol 감소"가 성공으로 위장된다.
**기각 범위 = 연속 비율 매핑 한정**: 동일 PIT-clean 규칙에서 TAIL 선별월 −2.333%/월 vs σ̂ 선별월 +0.079%/월(겹침 23/33) — spearman 0.838 인데 부호가 갈린다. **문턱형 미검**.
자기 적발 4건(발행 전 정정): tie_rule 미구현으로 PROCEED_VT4 오판 직전 · parity 대조 numeric(0)→max=−Inf 침묵 통과 · 회귀 기울기 NW t 가 OLS 1계조건으로 항등 0 · 선별율 불일치 비교(9% vs 20%).

**next_probe (양 라운드 공통)**: ① **문턱형(이진) 노출 매핑** — 연속 비율은 기각됐으나 문턱형은 미검 ② 착수 전 "이 설계가 404년 벽을 통과하나"를 검정력 계약(`required_effect_size.R`)으로 선판정하는 관문 신설 ③ 예측기가 분산을 예측한다면 소비면을 **방향 게이트 → 분산 소비면**(사이징이 아니라 리스크 예산)으로 재라우팅 — 단 WT003 이 그 경로의 수확 채널을 이미 −0.691%/yr 로 재었으므로 **일별 축**에서 재측정.

### 1.3 계약·컨센서스 재료 — 두 소비면 실측

**`L-AR-20260809_223000`** · grade C · `metric_type=canonical_screen` (FQ-002b)

계약수주 magnitude(w_ratio = 12M 계약금액/최근매출액)는 **랭킹과 배제형 필터 두 소비면 모두에서 자본 자격 미달**이고, 필터 쪽은 단순 미달이 아니라 **부호가 반대**다.
- ① 랭킹(FQ-125 stage1, 79개월): rank-IC t_NW **1.9942** 인데 canonical top-20 **PORT_t 0.5108(p 0.61)** = 전이 벽. 파일럿 밖 독립 55개월은 t_NW 1.2942 로 더 약함.
- ② 필터(79개월 2020-01~2026-07): 계약-커버 종목(24.0%, 4.80종/20)의 w_ratio 하위 3분위 제외 → 월평균 1.29종 제외 시 **ΔIR −0.1255**, PORT_t 2.768 → 2.451. 음성대조(난수 30 draw) q95 **+0.0537** 이하 → 사전등록 F1 반증. 회수율 **−30.3%**.
- ★★**천장은 실재한다**: 같은 커버 집합에서 사후 최악 1종만 정확히 빼면 ΔIR **+0.4153**(사전 측정 +0.4139 재현). 커버 종목 안에 큰 분산이 있는데 w_ratio 가 그것을 못 짚는다.
- 기전 정합: rank-IC 는 순위라 이상치에 둔감하고 PORT_t/IR 은 평균이라 꼬리가 지배 — **1.1절 R31/R32 와 동형**.

**`L-AR-20260809_234500`** · grade C · `metric_type=canonical_screen` (FQ-193)

위 천장(+0.4153)을 **w_amt(12M 절대 계약금액)** 로 겨냥: **살아 있으나 확립되지 않았다**.
79개월 실측 — 기준선 book IR 1.0950 / PORT_t 2.768 → 하위3분위 제외 IR 1.2108(**ΔIR +0.1158**) / PORT_t **3.020**(+0.251).
- F1 통과(음성대조 q95 +0.0537 초과) · F2 통과(회수율 **27.9%**) · F5 통과(w_amt vs book rank rho −0.096 / weight +0.180 = size 교락 낮음) · 양성대조 완전예지 +0.4153 재현.
- ★★**F3 반증 — 전반 −0.0634 / 후반 +0.2556 부호 갈림**. 사전등록이 "단일 판정 금지"로 못박아 둔 축이 정확히 발화.
- 기전 판별도 막혔다: 커버가 2020년 11% → 2026년 36% 로 추세라 **커버-시대가 구조적 교락**. 회귀 diff~n_cov+era 에서 둘 다 비유의(p 0.320 / 0.342), 2원 표는 셀 표본이 (2,6)까지 떨어져 분리 불가.

**next_probe**: ① 커버-시대 교락을 끊는 설계 — 커버율 고정 서브샘플(matched-coverage) 또는 커버 진입 시점 기준 이벤트-시간 정렬 ② w_amt 를 **랭킹이 아니라 분위 평균 스프레드**(1.1절 통계량)로 재선별 ③ 천장 +0.4153 을 낸 "사후 최악 1종"의 사전 식별자 탐색 — 계약 메타(계약 상대·기간·취소 이력)로 표면 확장.

**`L-AR-20260809_214500`** · grade F · `metric_type=unavailable` (FQ-198)

★**"재빌드로 해금된 신규 재료 4종"은 실제로 0종이었다.** 2026-08-09 factor_db 전면 재빌드(440개월)가 4종을 "25년치 실림"으로 기록했으나 값으로 재보니:
1. **C10 ≡ C01_SUE · C13 ≡ C04_ESBR 비트-동일** — 표본월 8건(2003-06~2026-07) 전건 완전동일 비율 **1.0000** · **최대절대차 0.000e+00** · spearman/pearson **+1.000000**(z·raw 양쪽). 커버리지까지 바이트 동일(299월/216,073 종목-월 · 302월/328,778).
2. **C15 는 factor_db 에 존재하지 않는다** — 커넥터 전량 로드 4개 표본월(2005/2012/2019/2026)에서 C-계열 16종 중 부재.
3. **C18 은 이벤트-CAR 가 아니다**.

⇒ 라운드 산출은 알파가 아니라 **재료 인벤토리의 정정**이다.
**next_probe**: ① 레지스트리 등재 시점에 **값-동일성 검사**(신규 팩터 vs 기존 전수 상관 1.0 스캔)를 게이트로 신설 ② "실림" 판정을 행 수가 아니라 **고유값 존재**로 판독하도록 재빌드 리포터 수정.

### 1.4 FQ-168 오버레이 ΔIR 아크 — **L-code 미적립분, 본 세션에서 발행**

산출물 `stage_artifacts/fq168_overlay_deltair_20260810/` (16 probe result JSON) 은 존재하는데 **L-code 가 발행되지 않아** corpus(492건)·`hypothesis_index`(1,213건) 어디에도 없었다. 본 증류에서 `L-AR-20260810_FQ168` 로 적립(§3).

핵심 실측 (전부 `p*_result.json` 인용):

| probe | verdict | 실측 |
|---|---|---|
| p0 검정력 | `D1_PASS_UNAVAILABLE` | ΔIR 게이트 0.05 가 se **0.0478** 의 **1.047배** · 최소검출 ΔIR **0.0955** · 2se 도달에 **970개월** 필요 |
| p3b 전제 | `B1_PREMISE_HOLDS` | 유니버스 하위25% 상대 연 **−5.136%**(t **−3.224**) / 상위 +2.208%(t 1.528), 335개월 |
| p14 기전 | `K3_OVERWEIGHT` | PG2 가 q1 을 **29.73%** 보유 (t **7.619**, p 4.53e-13) |
| p2 소비 | `J2_FIRES_NO_EFFECT` | PG2 내부 flagged **15.880%/yr** vs unflagged **11.585%/yr** (diff +4.295, t 1.082) — 발화 충분(월중앙 7종), **부호가 반대** |
| p9b 창 | `H1_GAPPY` | 공통창 **235/335**, 결측 **100**, 내부 gap **12곳** |
| p6 격자 | `F3_NONE` | 공통창 제한 시 유효 **0/…**, 비연속, control −2.406 |
| p24 지속성 | `J1_PERSISTENT` | q1 비중 홀/짝 rho **0.9808** · Jaccard **0.800** (밴드 예측자 rel14 참조값 **0.182**) |
| p20 일반화 | `Q2_PARTIAL` | hi_mean 0.7123 vs lo_mean 0.9223 · rho_secondary −0.230 |
| p23b 예측자 | `H3_NO_SIGNAL` | 홀→짝 diff 1.961(p_perm 0.113, mde 2.430) · 짝→홀 −0.061(p 0.973) · **all→all −5.897(p 0.000) = 공유항 오염** |

세 줄 요약:
1. **ΔIR 은 이 설계에서 결과량이 될 수 없다** — 게이트 0.05 가 표준오차와 같은 크기(1.047배)라 통과 여부가 정보를 담지 않는다. 결과량을 ΔIR → **패널 산술**로 바꾼 것이 라운드를 성립시켰다.
2. **유니버스 효과는 실재하나 PG2 소비면에서 부호가 뒤집힌다** — 하위25% 는 −5.136%/yr 인데 PG2 top-25 **내부**에선 flagged 가 더 좋다(15.880 vs 11.585). 기전은 "자를 게 없다"가 아니라 **"자르면 안 된다"** — PG2 가 q1 을 29.73% 로 초과 보유(t 7.619).
3. **예측자는 평균-비중이지 위치가 아니다** — q1 평균비중은 홀/짝 Jaccard **0.800** 으로 지속적인데, 밴드(argmax/위치) 예측자는 **0.182**. `all→all` 의 rho p=0.000 은 공유항 오염이라 교차분할 없이 인용 불가.

**next_probe**: ① 소비면 부호 반전을 **다른 base 로 재현** — PG2 이외 캐리어(FAM_CR q1 0.150 / FAM_L 0.1479 = GO 군)에서 같은 필터가 양으로 가는지 ② **일별 축**에서 q1 초과보유의 시점 구조 측정(월간으로 접으면 초과보유 타이밍이 소멸) ③ 공통창 게이트를 계약화 — 교집합 산출 시 **개수 + 내부 gap 을 이론 개월수와 대조**하고 어느 셀이 좁혔는지 명시(본 아크에서 창 오귀속 2회 자기 철회의 직접 원인).

---

## 2. method_frontier 진단 10건 — 측정 규약 계열 (08-08~09)

전부 `metric_type=unavailable`, grade `N/A_*_diagnostic` (성과 주장 아님, 측정 방법 판정).

| L-code | 핵심 실측 |
|---|---|
| `WALL_IS_WINDOW_DEPENDENT` | 벤치-측 핸디캡 d 는 상수가 아니라 **창 의존**. 439개월 5년 블록 −0.0448~+0.3743, 2025+ 제외 420개월 **−0.0222**, 18m 롤링 422창 중앙값 −0.0183 ⇒ **평시엔 top-25 EW 가 순풍**. ★**269m 창(저장소 표준·PG2 baseline)은 종료연도 무관 전부 음수** ⇒ 그 창에서 수집된 기각은 **유효하며 보이는 것보다 강한 판정**. ★**24m 이하 라벨은 점추정으로 쓰지 말 것**(사분위 스프레드 36m 0.0279 vs 269m 0.0039) |
| `DUALBASIS_IS_BENCH_NOT_EXPOSURE` | dual-basis 진단은 포트폴리오가 아니라 **벤치마크만** 바꾼다(`canonical_screen_bt.R:97` ret_net 동일 객체 · L103-104 benchmark_id 만 교체). "EW basis 로는 2.86"은 옮겨올 알파가 아니라 **같은 포트를 더 쉬운 벤치로 채점한 값**. capw−EW 격차는 arm 무관 상수(n=167, d_alpha_ann sd 0.00106). ★오독이 challenge_note → NP-1 → layer_bottleneck_map v48 → FQ-141 로 **4단 전파** |
| `BREADTH_DOMINATES_TIER_BETA` | 유니버스 축소 실패의 지배 요인은 tier-beta 가 아니라 **breadth**: `cor(port_t, √N) 0.947` · `cor(ew_uni_t, √N) 0.989` (Grinold 정합). ★자기 정정 — "신호 열화 실재" 자동 판정이 **틀렸다**(breadth↓ 면 α→0 인데 drag 는 상수로 남아 port_t→−drag/se<0). ew_uni_t 는 전 변형 양수(1.526~3.030) ⇒ **신호 열화 미확립**. tier drag 도 시대 의존(전 구간 439개월 MID **+0.0006≈0**) ⇒ MID 를 접어둘 근거 없음 |
| `HANDICAP_AND_SIZE_ARE_ONE_AXIS` | 벤치 핸디캡 d 와 사이즈 효과는 **부호만 반대인 동일 축**: cor **−0.747**(439개월), 4시대 전부 통과(−0.812/−0.725/−0.764/−0.711). ⇒ layer_bottleneck_map ④construction 과 ⑤비중이 **같은 축을 두 언어로** 서술(자율 라운드 우선순위 왜곡). ★단 111-145 cap-rank 밴드는 **별개 축**(cor +0.069) — 발행 1시간 만의 검증이 "4게이트 제어" 주장에서 1건을 걷어냄 |
| `SHRINK_DIAL_IS_IDENTITY_ON_INCREMENT` | baseline 을 끝점으로 하는 혼합(shrink/blend) 계열에서 다이얼은 standalone 을 크게 움직이면서 **증분 t 는 원리적으로 못 바꾼다**(스칼라 배 → t 불변). 실측 λ∈{0,.25,.50,.75} 에서 paired t **소수 3자리까지 1.307 동일**(버그가 아니라 항등의 지문). ★`run_R4_bench_aware_weight.R:105` 가 `which.max(port_t)` 로 **다이얼에만 반응하는 양으로 선택**했다 ⇒ **교체·증분 판정은 paired 로 채점** |
| `SOURCE_AWARE_TTM_UNWIRED` | 재무 유량이 **TTM 정규화 없이 원시값으로** 팩터에 들어간다. `parse_fundamental_xlsx.R:274` 가 TTM 을 정확히 계산해 parquet(4,133,534행·non-NA 96.6%)에 쓰지만 빌더는 `fundamental_merged.parquet` 를 읽고 거기엔 `TTM_Value` 컬럼이 **없어** `compute_value.R:61` 조건이 **항상 거짓**. 결과 = 피드 이음매에서 스케일 4배 점프(Revenue **4.42** · OperatingProfit **4.72** · COGS **4.34**), 유니버스의 **약 31% 가 2014 분기 스케일로 얼어붙은 채** 연간 스케일과 같은 서열표에서 경쟁 |
| `WORD_BOUNDARY_SILENT_FALSE` | ★★**당일 전면 정정** — 원래 주장("R `\b` 가 한글 섞인 문자열에서 조용히 FALSE")은 **거짓**. 독립 재현에서 `\b` 정상 작동(fixed/TRE/perl 전 케이스 TRUE, 음성대조도 정확). 진짜 원인 = **도구 호출 heredoc 이 JSON 인코딩에서 백슬래시 한 겹을 소비**해 R 이 워드경계가 아니라 **백스페이스(0x08)** 를 받는 것. Write 도구로 쓴 파일엔 오염 없음. ★증상은 실재했다 — 스캐너가 "유량 의존 팩터 0건"을 **두 번** 반환(실제 51/373) |
| `BASE_DELTA_IR_NOT_INFORMATION` | ★base 대비 ΔIR 은 **정보의 척도가 아니다** — 슬롯 대체 비용이 지배. **정보 0 인 순열 M26** 도 개입 규모에 비례해 ΔIR 이 음으로 간다(w 0.05 −0.0066 / 0.20 −0.0413 / 0.50 −0.2164). 실측 arm 전부 그 placebo 밴드 안. 기전 = 북 top-20 슬롯 하나를 밀어내는 비용 연 **−13.7%**. ⇒ 정보를 재려면 **크기-정합 placebo 대조(real−placebo)** 필요. ★ΔIR≥0.05 게이트(연 +0.95%)가 이 설계의 paired 검출 바닥(연 +2.81%)의 **1/3** |
| `COUNT_RULE_UNINFORMATIVE_MAGNITUDE_DECIDES` | ★사전 고정한 계수 규칙(k/n)이 **무작위 귀무와 구별 불가**일 수 있다. "형태 ≥4/7 이면 공통" 규칙의 귀무분포 500 draw = **평균 3.47/7**(sd 1.38, 5~95% [1,6]) — 관측 계수 전부 귀무 90% 안. 판정을 **크기 축**으로 옮기니 명확: book 7종 pooled 연 **+2.61%**(NW t **+3.31**), 개별 유의 3건 전부 양수(M08 +6.10 · C06 +5.75 · C02 +5.02) ⇒ 혹(hump)은 **Q01-scoped** |
| `WALKING_SEAM_DATE_PINNED_REPAIR` | 도훈 적발("26년 수익률 이상"). 벤치 2026 연간 **−81.8%**(참값 **+60.85%**). 결함 = 리베이스 체인과 생 KPI200 을 **레벨로 이어붙인 뒤** pct_change ⇒ 경계 하루가 스케일비를 통째로 삼킴(2026-07-29 −89.38%, 참값 −6.185%). 나머지 146/147일은 <1e-9 일치 = **딱 하루짜리 결함**. ★★재발 기전 = 호출부가 `--start_date "$(date -d '10 days ago')"` 라 **cutoff 가 매일 전진하고 이음매도 따라 걷는다** ⇒ **위치가 움직이는 결함에 날짜를 박으면 하루밖에 못 산다**. 정본 수리 = **수익률 접합**(스케일 불변 ⇒ 이음매가 구조적으로 불가능), 멱등 실측 1회차 healed 8행 / 2회차 0행 |

---

## 3. factor-rotation — FR_002 폐지 풀 배분정책

**`L-FR-20260809_143948`** · grade C · `metric_type=backtested` · Track2

등급 미달 모듈 **85개**(명목 195에서 corr≥0.999 dedup)를 무조건부 trailing 평균 top-10 EW 로 워크포워드 배분.
계약 실측: net_sharpe **0.786** · PORT_t(NW3) **1.242** · calmar 0.398 · dsr 0.034 · oos_retention **0.046** → **HARD 4/4 FAIL**, grade C. edge_vs_ew +0.073.

7 교훈 중 상위 3:
1. ★**분모 혼동(최대 수확)**: 폐지 풀 EW 대비 paired t_NW3 **2.598~2.856** 은 벤치마크 대비 PORT_t **1.242** 와 전혀 다른 양이다. "풀 내부 기준선을 이겼다"가 "시장 대비 자격"으로 전이되지 않는다 ⇒ **상대 기준선 t 를 졸업 지표로 인용 금지**.
2. ★**중복이 측정을 바꾼다**: 명목 195 중 유효 독립 **85**(축소 55.5%, 최대 중복그룹 49개). 중복 포함 EW 는 한 전략이 비중 **25.7%** 를 차지해 총계 알파를 부풀렸고, dedup 후 풀 active 는 월 **+0.021%(t 0.043)** = 사실상 0.
3. ★**국면조건부의 정체 = beta**: 상태-조건부 모듈 순위와 모듈 beta 의 spearman **DOWN −0.9751 / SURGE +0.9851**(rank R² 0.951/0.970), beta 잔차화 시 split-half 지속성 **−0.401/−0.716** 음수 붕괴. 국면 라벨 자체도 무판별(P(DOWN|DOWN_t−1)=0.133 vs base rate 0.122). ⇒ 이 축은 멤버십(FR Track2)이 아니라 **노출 스케일 소관**.

부수: 직교성 프레이밍 철회(PC1-잔차 직교 선택은 무조건부 선택에 열등, paired t 전 K 음수 −1.98~−3.14 — 잔차 알파 자체는 실재 16/85) · MDD 는 선택으로 안 잡힘(필요 ΔMDD 4.49%p > 전이 2.90%p, 탐색 산포 5.1%p 가 필요 효과 초과) · IS active SR 0.864 → OOS 0.039.

**next_probe**: ① 폐지 풀을 **노출 스케일**(beta 예산) 소비면으로 재라우팅 — 멤버십 선택이 beta 대리라면 beta 를 직접 다루는 편이 정보 손실이 적다 ② dedup 을 **발행 시점 게이트**로 이동(corr≥0.999 중복은 등재 단계에서 차단) ③ 잔차 알파 16/85 를 개별 소비면 7종 순회 대상으로 등재.

---

## 4. alpha-search — 7 run (08-09 6건 · 08-13 1건)

| L-code | 전략 | grade | metric_type | 실측 재측정 |
|---|---|---|---|---|
| `L-AS-20260809_123327_46908` | within_sector_reversal | F | proxy | CAGR 4.2% · SR 0.15 |
| `L-AS-20260809_141324_57032` | within_sector_reversal (재run) | F | proxy | CAGR 4.2% · SR 0.15 (벤치 대비 −6.3%p) |
| `L-AS-20260809_125231_31080` | FQ100_ipm_sector_neutral | B | backtested | essence **C**, PORT_t(NW) **0.69** |
| `L-AS-20260809_131451_21880` | FQ100_ipm_sector_neutral (동일) | B | backtested | essence **C**, PORT_t(NW) **0.69** |
| `L-AS-20260809_142224_57032` | FQ100_ipm_sector_neutral (3회차) | B | backtested | essence **F**, PORT_t(NW) **−0.13** |
| `L-AS-20260809_143328_35280` | SpectralPersistence_Hurst | B | backtested | essence **C**, PORT_t(NW) **0.42** |
| `L-AS-20260813_071419_38300` | STR_AS_CIRCUIT_UPPER_21D | F | proxy | CAGR 11.5% · SR 0.48 |

**자격 통과 0건** (문턱 PORT_t 2.95 대비 최고 0.69).

★**주의 표시 — 같은 전략의 3회 기록이 서로 다르다**: `FQ100_ipm_sector_neutral` 3건이 헤드라인은 동일(등급 B / CAGR 10.2% / SR 0.46)한데 벤치 대비가 **+10.6%p vs −0.3%p**, 실측 재측정 essence 가 **C(0.69) vs F(−0.13)** 로 갈린다. 헤드라인 등급 B 는 세 건 모두 같으므로 **등급만 보면 이 불일치가 안 보인다**. 원인 미규명 — 벤치 basis 차이 또는 run 파라미터 차이 후보.
**next_probe**: ① 세 run 의 `manifest`/벤치 id 를 직접 대조해 basis 를 특정 ② alpha-search 기록에 **벤치 id 를 등급과 같은 자리에** 병기하도록 emit 경로 수정(수치 옆에 basis 가 없으면 재측정이 갈릴 때 원인을 못 짚는다 — 08-13 `delta_ir_caveat` 규약과 동형).

---

## 5. Axiom 후보 현황 (의무 절)

**집계** (`axiom_candidates`, 스윕 step [3.5] 실측):

| 항목 | 값 |
|---|---|
| 후보 total / pending | 94 / 94 |
| promote crash | 0 |
| L-code 무결성 | clean (492 entries / 492 unique / 충돌 0) |
| near-miss | 3 |
| 도훈 confirm 플래그 | 18 |
| pending_5axis | **94** (최고령 2026-07-08 = **38일**) |
| quarantined_evidence | 6 (2026-07-04 이후 **42일 정체**) |

**실패 축 히스토그램** (어느 축 결측이 승격을 막는가):

| 축 | 미달 건수 |
|---|---|
| external | **88** |
| independence | **85** |
| falsification | 76 |
| mechanism | 48 |
| rigor | 4 |

★판독: 병목은 `rigor`(4건)가 아니라 **external(88) · independence(85)** 다. 즉 후보들이 "엄밀하지 않아서"가 아니라 **외부 재현·독립 확인이 붙지 않아서** 막힌다. 이건 emit 시점에 채울 수 있는 필드이므로 **L-code emit 지점 보강**이 승격률 레버다(후속 등재).

**near-miss 3건** (1축만 미달):

| 후보 | 미달 축 | weighted |
|---|---|---|
| `CAND_20260815_alpha_research_infra_process_mixed_L-AR-20260710_223505_…` | independence | **0.970** |
| `CAND_20260714_alpha_research_distress_smallcap_wall_…` | external | 0.800 |
| `CAND_20260718_qepm_legacy_value_conditional_L-132_L-135_L-142` | falsification | 0.774 |

→ 셋 다 **도훈 confirm 대상**(§9). 자동 활성화 금지.

**pending_5axis 백로그 드레인 — 본 세션 5건 처리** (우선순위 = supporting L-code 수 상위):

| dist_id | mode | family | pol | n_sup | 처리 |
|---|---|---|---|---|---|
| DIST-AR-051 | alpha_research | overlay_regime | mixed | 14 | → proposed |
| DIST-AR-026 | alpha_research | value | positive | 13 | → proposed |
| DIST-JG-005 | judge_gate | value | conditional | 13 | → proposed |
| DIST-RAMP-013 | ramp | overlay_regime | conditional | 11 | → proposed |
| DIST-QPM-034 | qepm_legacy | overlay_regime | mixed | 11 | → proposed |

잔량 **94 → 89**. (54건이 supporting 1건짜리 — 단일 L-code 후보는 independence 축이 구조적으로 안 차므로 별도 처리 경로 필요, 후속 등재.)

**proposed 대기 5건** (도훈 배치 승인 대기, 주입 안 됨): DIST-AR-041 · DIST-QPM-023 · DIST-QPM-035 · DIST-RAMP-014 · DIST-RAMP-018 (전부 expiry 2027-02-09). 본 세션 신규 5건 합쳐 **10건 대기**.

---

## 6. Continuity Firewall

`n_blocks_logged` **82** · `n_cases` 11 · `n_suppressions` 1 · `n_new_suppressions_learned` 0 · **`n_pending_novel` 4**.

pending 4건 전부 triage_hint = "FP성 가능 — NEG-토큰 인용만·종결어휘 무". 실제 span 확인 결과 4건 모두 **보고·브리핑에서 negative 결과를 인용한 것**이지 완곡 종결 신어가 아니다(예: `HARD FAIL`·`QUARANTINE` 판정 인용, "가격 축은 소진됐고 비-return 원천으로" 같은 **다음 방향을 동반한** 서술).

→ 판정: **4건 전부 dismiss 권고** (신어 승격 아님). `--append-case` 미실행. 도훈 확인 시 `continuity_gate.py --dismiss` 일괄.

---

## 7. 잔재 처리 (§4)

**기계 스윕 삭제 1건** (`.cache/hygiene_manifest.log` 기록):
- `/tmp/qvest_tg_skeleton_warn.log` (weekly_temp_logs_30d, OS temp 30일+)

**위생 경고 77건** (`hygiene_n_warnings`, 전주 32 → **77**, +45):
- `root_unauthorized`: `downloads` 외 다수 — 루트 13항목 고정 위반
- `infra_underscore`: `ops/_sched_failure_classify.sh`
- `misplaced_outputs`: `02_Infrastructure/ast/tests/parity_factor_db_result.json`
- `unindexed_top`: `ast`, `methods`

**세션 삭제 1건** (참조 0 검증 후 무아카이브 삭제, manifest `06_Registry/distill_manifest_20260815.json`):
- `printed` (79 bytes) — R 콘솔 진단 출력이 리다이렉션 사고로 파일화된 것. 전체 내용 3줄(`idx = 1 0` / `length(v[idx]) = 1` / `element class: NULL  - as: PIT(기본값)`), 2026-08-02 auto-commit `fac52cfc` 유입. W32 가 삭제한 `1+)`(2,104 bytes close_round 콘솔 출력)와 **동일 부류**.
- **참조 0 검증**: 경로형 검색(`"printed"` / `file.path(...printed)` / `source(...printed)`, 대상 `*.R *.py *.sh *.json *.bat`) 매치 **0건**. 단어 매치 다수는 전부 `stage_artifacts/paper_recharge/mcp_discovery_*.json` 의 **논문 초록 영문 산문**("the printed bid of a calendar-vertical basket") — 경로 참조 아님을 개별 확인.
- ★**형태 정정**: W32 manifest 는 이 항목을 `printed/`(디렉터리)로 기록해 "재배치 대상"으로 preserved_deferred 에 넣었으나 실측은 **79바이트 일반 파일**이다. 디렉터리 가정이 삭제 부류 판정을 막고 있었다.

**보존 5건** (재판정하지 않고 W32 결정 승계):
- 루트 R 실행기 4종(`run_as_queue_20260806.R` 21,800B · `run_fx_intensity.R` · `run_spec_lowfreq_mass.R` · `run_within_sector_reversal.R`) — **실행 참조 0건**이나(매치는 전부 manifest·hygiene_report·events.jsonl 등 **기록물**) W32 가 "실제 리서치 실행 코드, 삭제 시 재현 능력 소멸, 조치는 삭제가 아니라 **이동**"으로 사유를 남겼다. 이동은 참조 경로 영향이 있어 도훈 confirm 사안. ★`run_within_sector_reversal.R` 은 이번 주 alpha-search 2 run 의 실행기라 오히려 당주 산출물과 직결.
- `downloads/` (arXiv PDF 7건 ~16MB) — `06_Registry/alpha_frontier_queue.json` 이 참조하는 **실참조** 보유. 삭제 불가.

★**경고 32 → 77 증가 원인 규명 완료**(추정 아님): 분해 실측 = root_unauthorized 6 + infra_underscore 1 + misplaced_outputs 1 + **unindexed_top 69**(02_Infrastructure 2 + **06_Registry 59** + 08_Tests 8) = 77 총계 정합. 증가분 지배 원인은 **`alpha_frontier_queue.json.bak_*` 30개** — 08-08/08-09 세션이 공유 큐를 쓸 때마다 백업을 남긴 결과다. `06_Registry` 는 절대보존 존이라 삭제 대상이 아니며, 누적을 줄이려면 `frontier_queue_io.R` 의 **백업 회전·상한 정책**이 필요하다(후속 등재).

### 7b. distilled ↔ settled-negative 대조 (SKILL §③-③)

`status=distilled` 15건(= **현재 주입 스트림이 실제 소비 중**)을 최신 settled-negative 목록과 대조한 결과 **4건이 이미 판정 끝난 레인을 '미검증 레버'로 광고** 중이다. 본 증류는 **등재만** 하고 재정제는 실행하지 않았다(주입 내용 변경 = 도훈 확인 사안, §9-4).

| dist_id | 정제일 | stale 항목 | 사유 |
|---|---|---|---|
| DIST-AR-003 | 07-04 | frontier "C23/C27 flow catalyst를 **DPL 입력 피처로**" + statement 의 `DPL_FEATURE` screen-route | DPL 은 06-26 settled-negative(재제안 금지) · `DPL_FEATURE` 발급은 v8.3(07-10) 중단. **카드 정제일이 두 결정보다 앞선다** |
| DIST-AS-008 | 07-04 | frontier "감쇠 견디는 후보를 overlay/**DPL feature**로 소비" | 동일 |
| DIST-AR-009 | 07-10 | frontier "비-return 원천(DART exec-insider·**공매도잔고 — 데이터 게이트 FQ-001/003**)" | 공매도/대차 게이트는 **도훈이 08-09 에 닫았고** insider 는 3-프레임 삼각-null. 카드는 대기 중 게이트로 서술 |
| DIST-QPM-005 | 07-04 | frontier "**DART insider** 등 … 진짜 신규 비-return 정보원으로 재설계" | insider 레인 실측 negative 이후 미갱신 |
| DIST-RAMP-006 | 07-18 | frontier 라벨 "(v8.3 **주력** 프론티어, FQ-001~005)" | **라벨만 낙후**(v8.4 가 08-13 주력 해제). severity=label_only |

★**키워드 적중을 그대로 판정으로 쓰면 안 된다는 반례가 같은 스캔 안에 있었다**: DPL 키워드는 6건에 걸렸는데 DIST-RAMP-006 의 DPL 언급은 **정확하다**(statement 가 "DPL은 06-26 settled-negative … 재제안 금지"로 올바르게 표기하고 금지 목록에도 명시). `DIST-RAMP-003` 의 "신규 비-return 정보원" 도 특정 폐쇄 레인을 지목하지 않은 일반 서술이라 stale 아님 — 문맥 판독 후 6건 중 **4건만** stale 로 확정했다.

---

## 8. 이번 주 계통 관찰 — 세 개의 같은 뿌리

주간 25 L-code 를 가로질러 **같은 구조의 오류가 세 층에서 반복**됐다. 개별 라운드 결론과 별개로 기록한다.

1. **결과량이 자기 척도를 못 가진다** — `BASE_DELTA_IR_NOT_INFORMATION`(순열도 ΔIR 음) · FQ-168 p0(게이트 0.05 = se 의 1.047배) · `COUNT_RULE_UNINFORMATIVE`(k/n 규칙이 귀무와 구별 불가). 셋 다 **판정 규칙 자체의 판별력을 재기 전에는 판정이 무의미**하다는 같은 말이다. ⇒ 규약: 사전등록 시 **규칙의 귀무분포 또는 최소검출크기를 함께 고정**.
2. **basis 를 안 적으면 같은 수가 다른 뜻이 된다** — `DUALBASIS_IS_BENCH_NOT_EXPOSURE`(4단 전파) · FR_002 교훈 1(풀 내부 t vs 벤치 PORT_t) · alpha-search FQ100 3회 불일치. ⇒ 규약: **수치 옆에 basis 를 같은 자리에**.
3. **평균과 순위는 꼬리에서 체계적으로 갈린다** — R31/R32/R33(320종 전반) · FQ-002b(rank-IC t 1.99 인데 PORT_t 0.51) · WT005(선별 통계량 교체). ⇒ v8.4 Lane A 의 전제가 이번 주에 **세 독립 경로로 확인**됐다.

---

## 9. 도훈 결정 대기 (자동 진행 금지)

1. ★**stale distilled 카드 4건 재정제** (§7b) — 우선순위 1위인 이유는 이 4건이 `status=distilled` 라 **지금 이 순간 주입 스트림이 소비 중**이기 때문이다. 에이전트가 DPL·공매도 게이트를 "열린 레버"로 안내받는다. 반영 내용은 도훈이 이미 내린 결정(DPL 재제안 금지 06-26 · `DPL_FEATURE` 중단 v8.3 · 공매도 게이트 폐쇄 08-09 · v8.4 주력 해제)이며, 주입 내용 변경이라 세션이 임의 실행하지 않았다.
   `Rscript -e 'source("02_Infrastructure/axiom/distilled.R"); refine_distilled("DIST-AR-003", <정제문>)'` (대상 4 + 라벨만 갱신 1)
2. **DIST proposed 10건 배치 승인** — 기존 5 + 본 세션 5. 승인 시에만 주입 스트림 개방.
   `Rscript -e 'source("02_Infrastructure/axiom/distilled.R"); approve_proposed(c("DIST-AR-051","DIST-AR-026","DIST-JG-005","DIST-RAMP-013","DIST-QPM-034"))'`
3. **axiom confirm 플래그 18건** — `conditional direction_consistency` 재정의(`within_condition_axis`, 2026-07-04) 적용 여부.
4. **continuity pending_novel 4건 dismiss** — 본 세션 판정은 "전부 FP, 신어 아님".
5. **루트 실행기 4종 재배치** — W32·W33 연속 보존. 삭제가 아니라 이동이며 이동은 참조 경로 영향이 있어 confirm 필요.

---

## 10. 후속 등재 (본 세션이 만든 다음 사이클 재료)

| # | 항목 | 근거 |
|---|---|---|
| 1 | L-code emit 지점에 `external`·`independence` 축 필드 보강 | §5 히스토그램 — 병목이 rigor 아닌 external(88)/independence(85) |
| 2 | supporting 1건짜리 pending_5axis 54건의 별도 처리 경로 | independence 축이 구조적으로 안 참 |
| 3 | 위생 경고 32 → 77 증가 원인 규명 | §7 |
| 4 | 팩터 등재 시 **값-동일성 게이트**(신규 vs 기존 전수 상관 1.0 스캔) | FQ-198 — C10≡C01, C13≡C04 비트 동일 |
| 5 | alpha-search emit 에 벤치 id 병기 | §4 FQ100 3회 불일치 |
| 6 | 공통창 산출 시 **개수 + 내부 gap 을 이론 개월수와 대조** 계약화 | FQ-168 p9b(235/335, gap 12) |
| 7 | 착수 전 검정력 선판정 관문(`required_effect_size.R` 호출 강제) | WT003 404년 벽 |
| 8 | `frontier_queue_io.R` 백업 회전·상한 정책 | §7 — `alpha_frontier_queue.json.bak_*` 30개가 위생 경고 증가분을 지배 |
| 9 | distilled 카드의 **settled-negative 자동 대조** 배선 | §7b — 4건이 정제일 이후의 판정을 반영 못한 채 주입 중. 주기 대조를 사람 눈이 아니라 기계로(카드 frontier ↔ settled 목록 교집합 경보) |
| 10 | 미적립 학습 탐지 자동화 | §1.4 — FQ-168 은 산출물 16건이 있는데 L-code 가 없어 5주간 안 보였다. `stage_artifacts/<round>/` 에 result JSON 이 N건 이상인데 대응 L-code 가 없으면 스윕이 경보 |

---

**증류 산출물**: 본 digest · `06_Registry/distill_manifest_20260815.json` · 신규 L-code 1건(`L-AR-20260810_FQ168`) · DIST proposed 5건
**claim**: `distill_status=in_progress` → `done` (owner `session_main`)
