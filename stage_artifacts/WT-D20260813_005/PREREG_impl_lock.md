# 구현 사전등록 봉인 — WT-D20260813_005 (FQ-237 선별 목적함수 교체)

작성: 2026-08-13 · **측정 착수 전** 작성 · alpha-research (Step 1~7)
승계 정본: `qepm/mailbox/worktask/WT-D20260813_005/alpha_hypothesis.json` (재작성 금지 — 아래는 그 `preregistration_lock` 이 alpha-research 에 위임한 구현 자유도 6항의 **확정값**)

## §0 승계분 (변경 없음 — 가설 에이전트 고정)

- primary = **OBJ-MEAN** 1개: trailing top-분위(Q5) EW 평균 활성의 NW lag-3 t
- negative control = **OBJ-MED** 1개 (중앙값 스프레드) — 개선되면 **기전 기각**
- base = **OBJ-RANK** (rank-IC 선별), 동일 K·동일 구성
- primary endpoint = paired 월별 active 차이 (OBJ-MEAN − OBJ-RANK) NW lag-3 t, **문턱 +2.0**
- 비-성과 반증축 3종: ①Jaccard(S_mean,S_rank) 중앙값 > 0.8 → 기전 부재 기각 ②왜도 프로파일 분기 방향 불일치 → 기각 ③negative control paired t ≥ +2.0 → 특이성 기각
- selection_type = **chain** (primary 1개, 가설주도 paired 단일 검정). DSR 은 진단 산출·기록.

## §1 착수 전 확정한 구현 자유도 (전부 단일값 — 스윕 금지)

| 항목 | 확정값 | 확정 근거 (측정 전에 쓴다) |
|---|---|---|
| **K** (선별 팩터 수) | **5** | 가설 권고값 + method shopping 상한 5 정합. 단일 고정, 스윕 시 sweep 재선언 의무이므로 스윕하지 않는다. |
| **trailing 창 W** | **36개월** | RAMP R6 가 쓴 W36 과 동일 — 인접 선행 라운드와 창 규약을 맞춰 비교 가능성을 남긴다. NW lag-3 t 산출에 n=36 은 계약 하한(lag+2=5) 충족. |
| **선별 통계량 정규화** | **3 arm 전부 NW lag-3 t** | ★교란 차단: primary 가 t-형인데 base 를 원시 평균 IC 로 두면 "평균 vs 순위"(가설 축)와 "t vs 원시"(무관 축)가 섞인다. 정규화를 상수로 고정해야 **함수형 축만** 격리된다. OBJ-MED 정의가 이미 "NW lag-3 t"이므로 승계분과도 정합. |
| **분위** | **5분위, Q5 = 최고 z** | 승계 (`top-분위(5분위 Q5)`) |
| **재료(팩터 집합)** | **320종** = `master_panel_FIXED` 팩터 집합 (= lane_a 패널 331종 − alias 11종) | 가설이 "동일 재료(master_panel_FIXED 320종)" 로 지목. alias 11종 제외는 재료 정의의 승계이지 선택이 아님. |
| **결합** | **z_score_aligned_equal_weight** (선별된 K개 `Z_Score_Aligned` 의 종목별 단순평균, 유효 팩터 ≥1 요구) | 3 arm 동일. 결합에 자유 파라미터를 두지 않는다(자유도 최소화). |
| **구성** | top-25 EW long-only · 15bps one-way · 월간 리밸 | 고정 축 (Production Constraints) |
| **벤치마크** | `.cache/benchmark.parquet` (IKS200) 일별 → `apply.monthly(Return.cumulative)` 월간, **ym 키** 조인 | armA 가 밟은 함정(일별 벤치를 월간처럼 사용 → 199→101개월)의 수리 경로 승계. `fq081_build_benchmark()` 는 자체합성이라 미사용. |
| **PIT 컷오프** | 홀딩월 T 의 선별은 **anchor < A_T** 인 월의 실현 통계만 사용 (직전 36개) | 앵커 A 의 forward 는 A 월 말에 완결 → A_T 시점에 A<A_T 는 전부 기지. |
| **m_\* 사용** | **선별 입력으로 사용 금지** | `master_panel_FIXED` 의 m_* 는 진단 전용. 선별 통계량은 lane_a 원자료에서 **매 시점 trailing 재산출**. |

## §2 판정 규칙 (착수 전 고정)

1. **supported**: paired NW3 t(OBJ-MEAN − OBJ-RANK) ≥ **+2.0** ∧ 반증축 3종 전부 미발화.
2. **not-supported**: t < +2.0 → "선별 통계량 교체는 이 프레임에서 레버 아님" 기록 + 재료 축(FQ-234) 라우팅. 계열 확대 금지(INV-7).
3. **기전 기각**: 반증축 ①②③ 중 발화 시 — 성과와 무관하게 기전 서사 기각.
4. **안정성 비용 상쇄** (승계 `stability_cost_test`): primary 문턱 통과여도 OBJ-MEAN arm 회전율이 OBJ-RANK arm 의 **1.5배 초과** ∧ net(15bps) paired 개선이 문턱 아래 → "불안정 비용이 이득 상쇄" 기록, **supported 선언 금지**.

## §3 basis 명시 (승계 handoff ⑤)

- 계약 `net_sr` = `mean(active)/sd(active)*sqrt(12)` = **active SR (= IR)**. total SR 아님. 인용 시 항상 `active_sr(=IR)` 로 라벨.
- 1급 축 = **paired 월별 active NW3 t** (primary) + **canonical PORT_t** (자본 축, cap-w 벤치) 병기.
- `canonical PORT_t` = `metric_type="canonical_screen"` — 자본 판정 아님(forge-authoritative).

## §4 검사 판별력 확인 의무 (착수 전 고정 — "통과했다"를 근거로 쓰기 전에)

PIT 검사기의 판별력이 0 이었던 사례(WT-004, 위반 주입도 PASS)를 재발시키지 않기 위해, **위반을 주입한 arm 을 실제로 만들어** 검사가 발화하는지 확인한다.

- **주입 arm (LOOKAHEAD-CTRL)**: 홀딩월 T 의 선별에 **T 월 자신의 실현 통계**를 포함(1개월 look-ahead). 그 외 전부 동일.
- **기대**: 주입 arm 의 canonical PORT_t / paired t 가 clean arm 대비 **크게** 상승해야 한다. 상승하지 않으면 **본 프레임의 성과 축이 1개월 누출에 둔감** = "clean arm 이 PIT 통과" 라는 진술이 근거로 못 쓰인다는 뜻이므로 그 사실을 정직 기록한다.
- 부수: lag1 스트레스(선별 입력을 T−2 까지로 한 칸 더 물림) 병기.

## §5 조인/축 감시 (승계 handoff ②)

개수 검문만으로는 키 오류를 못 잡는다(오늘 실측: 1행 손실이 5% 검문을 통과하면서 축이 1개월 어긋난 사례). 따라서 **개수 + 축 정합** 이중 검문:

- (a) 각 단계 개월수를 이론값과 대조, **5% 초과 손실 시 중단**.
- (b) **축 정합 검증**: 합성 스코어 → forward 수익 IC 부호가 **양수**여야 한다(앵커 규약 정상 지문). 음수 대폭이면 앵커 오정렬.
- (c) 벤치 축 덮개 ≥ 95%, 그리고 벤치 월과 포트 월의 ym 일치율 100%.
- (d) 패널 지문 3종 재확인: `M04_Mom_1` 평균 IC ≈ +0.0170 · `|평균IC|>0.10` 0종 · 최대 ≈ 0.0509 — **내가 계산한 IC 로** 재현되어야 프레임 승계가 성립.

## §6 산출물

- `qepm/mailbox/worktask/WT-D20260813_005/alpha_package.json` (AST v1.1 3층 + selection_objective 선언)
- `stage_artifacts/WT-D20260813_005/alpha_scores.parquet` (primary arm 합성 스코어)
- `stage_artifacts/WT-D20260813_005/alpha_validation.json`
- `qepm/mailbox/worktask/WT-D20260813_005/challenge_note.md` (self-adversarial)
