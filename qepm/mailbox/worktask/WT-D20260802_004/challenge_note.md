# Challenge Note — WT-D20260802_004 (Self-Adversarial Challenge, v8.2)

**작성**: alpha-research agent, 2026-08-02 (초안 — eval 확정 수치는 §하단 추가분에 기입)
**대상**: 변동성 팩터 조합 — 단일 대비 crisis_alpha 개선 여부 (AX-001 v2 조건부 평가)

---

## 0. 확정 사실 (eval 前 실측 — 판정과 독립)

### 0-1. (a) 기존 FAIL의 채점 방식 판별 — AX-001 위반 채점 확정

`hypothesis_index` 변동성 계열 88건 매칭 전수 + 원문 hurdle_result 확인:

| 선례 | verdict | 채점 축 (원문 실측) | AX-001 위반 여부 |
|---|---|---|---|
| `LowVol` (STR_AS_20260605_200252) | FAIL | **hard_fail "MDD 54.9% > 45%"** + 전기간 sharpe(0.294)/ir/cagr/calmar/mdd 축. 조건부 축 0개 | **위반 채점** (defense\|low_volatility 시그니처) |
| `AS_LowVol_BlitzVanVliet2007` (3건) | FAIL F | 전기간 sharpe 0.116/cagr 1.39/mdd 50.75, score 0 | **위반 채점** (defense 시그니처) |
| `Defense + quality base` (STR_AS_20260612_154048) | FAIL F | 전기간 축 + portfolio_alpha_t −0.565 | **위반 채점** (방어 역할 주장 전략) |
| `VOL_RANK_STABILITY_v1` (07-26) | FAIL F | 전기간 축 (sharpe 0.167, mdd 55.4) | 경계 사례 — 시그니처는 defense\|volatility이나 **알파(수익) 주장**으로 제출됨. 수익 주장엔 전기간 채점이 정당. 단 방어 역할 재평가는 미수행 상태 |
| `C_VolRankStability_3M` (08-02) | FAIL F | 전기간 축 (mdd 62.1) | 상동 (other\|volatility) |

**핵심 발견 (governance)**: `LowVol`의 hurdle 원문에서 `detected_family: "other"` — **방어 계열 오분류로 AX-001 enforcement hook(defense regex 트리거)이 발화 자체를 못 했다.** AX-001 hook은 파일 내 "defense" 문자열+grade F에 조건부 요구("crisis|stress|conditional")를 걸지만, family 탐지가 "other"로 빠지면 우회된다. → 소비면/후속 과제로 등재 예정 (next_probe).

**결론 (a)**: 예 — 최소 5건(LowVol 계열 4 + Defense+quality)이 **전기간 SR/CAGR/MDD 채점으로 FAIL 처리**됐고 조건부 축(crisis_alpha / Core 대비 MDD / bad-normal IC)은 어떤 선례에서도 계산된 적 없음. 본 라운드가 그 재평가를 최초 수행.

### 0-2. 방향정렬 실측 — "저변동 롱"은 connector 정본 배향이 아니다

`factor_ic_monthly.parquet` expanding IC (2005~2026 연말 스냅샷 전수):
- D03_RealVol +0.11~0.14 / D01_IdioVol +0.11~0.14 / D41_Vol_of_Vol +0.07~0.08 / D45_Downside_Dev +0.11~0.14 / D55_Vol_Trend +0.04~0.05 — **전 구간 양(+), 부호 반전 없음**.
- 즉 C13 Z_Score_Aligned(IC-정렬)는 이들 팩터를 **"고변동 롱"**으로 배향한다. KR 전기간 횡단면에서 고변동이 이긴다는 구조 실측 (KOSDAQ 소형 고변동 랠리 + 공매도 제약).
- 방어 배향(저변동 롱)은 **AST에 `MUL(leaf, const −1)`로 구조 선언** (ad-hoc 소비시점 flip 아님 — 스펙 파일·manifest·사이드카에 노출). canonical/defensive 두 lane 전부 측정·보고.
- parity 실측: defensive AST 컴파일 vs −1×canonical 패널, 5축 × 4 probe월, **max|차이| = 0.00e+00 전부 PASS** (`compile_meta.rds` 11:05).

### 0-3. (b) 상관·직교성 실측 (259개월 월별 횡단면 Spearman 평균±sd)

- D03~D01 **+0.965** / D03~D45 **+0.955** / D01~D45 +0.909 → **저변동 수준 3축(RealVol/IVOL/semivol)은 사실상 동일 축** — "5축 조합"의 실질은 3축 이하.
- D03~D41 +0.796 / D01~D41 +0.784 (경계 — 규칙 0.8 미만으로 D41 잔존)
- D55(vol trend) vs 나머지: **−0.06~−0.10 (직교)** — 유일하게 독립인 축.
- 사전등록 규칙(|ρ̄|≥0.8 → 일반→특수 우선순위 후순위 제거, 성과 무참조): **C_ORTH = {D03_RealVol, D41_Vol_of_Vol, D55_Vol_Trend}** (제거: D01, D45).

---

## 1. 자기 비평 (devil's advocate — concern ≥3)

### C-1. 국면 라벨의 사후성 (severity: MEDIUM)
`unified_regime_signal.parquet` Category(CRISIS 16월/2005+)는 MSM/FRED/KTRI 합성 — 위기 월 식별이 사실상 실현 결과를 조건으로 한다(위기는 정의상 하락 후 라벨링). 이는 **AX-001 조건부 평가 자체가 요구하는 attribution slicing**이며 포트폴리오 구성에 라벨을 쓰지 않으므로 PIT 위반은 아니다(신호 미사용 → C5 비발동). 그러나 crisis_alpha의 표본 선택이 라벨 엔진에 의존하는 것은 사실.
**처리: PARTIAL** — 라벨 독립 정의(BM_Ret<0 bad months)를 병행 측정해 3축 중 bad/normal IC ratio는 라벨-비의존 축으로 확보. 두 정의 결과를 모두 보고.

### C-2. crisis 표본 극소 + 최근 국면 편중 (severity: HIGH)
2005+ CRISIS = 16월/5에피소드, 그중 **7월이 2025-11~2026-07 현재 진행 국면** (GFC 6월, 2011-09 1월, COVID 2월). NW t는 n=16에서 저검정력이고, 현재 진행 국면이 표본의 44%를 차지 — crisis_alpha가 사실상 "2025-26 폭락 1개 사건 + GFC"로 결정될 수 있다.
**처리: ACCEPT(한계 명시)** — 에피소드별 분해를 의무 보고하고, 판정문에 "에피소드 수준 재현성(5개 중 양수 개수)"을 t값보다 앞세운다. crisis_alpha 단일 수치로 강한 주장 금지.

### C-3. C13 방향정렬과의 긴장 (severity: MEDIUM)
방어 배향은 connector 정본(Z_Score_Aligned)이 아니라 AST 선언 변환이다. "Z_Score_Aligned only" 룰의 자구와 긴장. 반론 근거: ① AST v1.1은 리프 위 연산을 스펙으로 선언하는 체계 자체가 정본 경로(FQ073 SUB/LOG 선례) ② C13의 입법 취지는 성과-추종 ad-hoc 부호 뒤집기 금지 — 본 건은 **기전(방어)에서 도출된 사전등록 배향**이고 canonical lane도 전량 병행 측정·공개 ③ align_factor_direction의 registry-only 모드(공식 문서화된 "PIT-safe default")가 주는 배향과 동일함을 0-2에서 실측(IC 부호가 전 구간 안정 양수 → defensive = registry lower_better 배향과 일치, 시점별 flip 없음).
**처리: REBUTTAL** (학술: Blitz-van Vliet 2007 저변동 이상현상 — 방어 팩터의 정의 자체가 저변동 롱 / L-code: L-132~140 계열 defense 평가 선례 + AX-001 axes 정의 / 정량 3축: 0-2 IC 히스토리 + parity 0.0e0 + 두 lane 전량 병행 보고). judge가 자구 우선으로 판단하면 defensive lane을 advisory로 강등 수용.

### C-4. "조합" 가설의 실질 축소 (severity: MEDIUM — 정직 보고)
(b) 실측이 보여주듯 5축 중 3축이 동일 축. "조합이 단일보다 낫다"는 가설의 검정 대상이 실질적으로 {수준, vol-of-vol, 추세} 3축 결합으로 축소된다. 이는 negative가 아니라 **가설 정밀화**다(서로 같은 것을 재는 축의 조합은 의미 없음 — 요청서의 첫 판별점 그대로).
**처리: ACCEPT** — C_ALL5는 참조로만, C_ORTH가 본 검정.

### C-5. 다중검정 (severity: LOW-MEDIUM)
측정 구성 15개(단일 5×2 lane + 조합 2×2 + Core). 선택은 사전등록(C_ORTH primary, 상관 규칙)이고 argmax 없음 → selection_type=chain, DSR 게이트 비적용. 단 n_trials=15는 기록하고, harvey-t 인용 시 다중검정 주의 병기.
**처리: ACCEPT(기록)**.

### C-6. MDD 무료레버 확증과의 경계 (severity: HIGH — 경계 준수 확인)
"MDD 무료레버 = overlay/timing 뿐, WEIGHTING·SELECTION 비유의" 3라운드 확증과 충돌 금지. 본 라운드는 SELECTION으로 MDD를 잡겠다는 주장을 **하지 않는다** — AX-001 축의 mdd_complement는 방어 팩터의 조건부 성과 서술이지 배포 레버 주장이 아니다. 산출물이 소비될 곳도 overlay/FR-RCMA 후보 라벨이지 standalone 승격이 아님.
**처리: ACCEPT(경계 명시)** — 보고서·패키지에 "전기간 SR 승격 주장 아님 + MDD 레버 주장 아님" 이중 명시.

## 2. Self-rationalization 자기검증
- 금지 표현("미미/관행적/보수적이면 OK/대부분 결과 동일") 사용 없음 확인.
- "직교 ≠ 수익" 기존 확증(§6)과 일관 — 직교성(D55)은 조합 정당화의 필요조건일 뿐, 판정은 조건부 실측으로만.

## 3. Escalation 판정
- HIGH severity 2건(C-2, C-6)이나 모두 한계 명시/경계 준수로 처리 — **escalate 불요** (AX hard FAIL 0, PIT C1 위반 0).

---

*(이하 eval 확정 후 추가: AX-001 3축 실측표 + 판정 + next_probe)*
