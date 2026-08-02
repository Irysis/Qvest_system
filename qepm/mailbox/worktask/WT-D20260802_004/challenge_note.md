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
- answer-principles 회피표현 조항의 금칙 어구(합리화 계열 5종) 본문 사용 없음 확인 — 본 절은 어구를 인용하지 않고 조항 참조로 대체(grep 오탐 방지).
- "직교 ≠ 수익" 기존 확증(§6)과 일관 — 직교성(D55)은 조합 정당화의 필요조건일 뿐, 판정은 조건부 실측으로만.

## 3. Escalation 판정
- HIGH severity 2건(C-2, C-6)이나 모두 한계 명시/경계 준수로 처리 — **escalate 불요** (AX hard FAIL 0, PIT C1 위반 0).

---

## 4. AX-001 v2 조건부 3축 실측 (eval 확정 — metric_type=canonical_screen, 258개월, top-25 EW, 15bps, liq 2e8)

### 4-1. crisis_alpha (CRISIS 16월 / 5에피소드)

| 구성 (def lane) | crisis α %/월 (NW t) | 에피소드 +/전체 | 하락형 위기(BM<0) 누적 active |
|---|---|---|---|
| D03_RealVol_def | −4.94 (−1.03) | 4/5 | **+24.4%** |
| D41_Vol_of_Vol_def | −4.08 (−1.04) | 3/5 | +19.0% |
| D55_Vol_Trend_def | −2.88 (−1.02) | 3/5 | +11.4% |
| **C_ORTH_def (조합)** | **−5.26 (−1.26)** | 2/5 | **+8.4%** |
| C_ALL5_def (조합) | −5.70 (−1.09) | 3/5 | +23.7% |
| CORE_M01 (참조) | −5.10 (−2.02) | 1/5 | −13.2% |

**에피소드 분해가 판정의 열쇠**: 하락형 위기 4건(GFC 2008-10~2009-03 · 2011-09 · COVID 2020-03/04 · 2025-11)에선 방어 lane 전 구성이 누적 양(+) active — **episodic 방어는 실재**. 그러나 5번째 에피소드 2026-02~07은 **CRISIS 라벨인데 벤치 누적 +33.7%(초대형주 반도체 멜트업)** — 여기서 C_ORTH_def −92.5% cum active로 평균이 지배됨. C_ALL5≈D03(ρ 0.96 수준축 지배)이므로 C_ALL5의 +23.7%는 조합 효과가 아니라 D03 복제.

### 4-2. Core 대비 MDD (full-period, PerformanceAnalytics::maxDrawdown)

def lane MDD 60.4~80.4% vs Core(M01 top-25) 59.5% / BM 47.1% → **complement 전 구성 음수(−0.8~−20.8pp) FAIL**. 원인은 크래시가 아니라 **만성 음(−) drift 누적**(def lane netSR −0.20~−0.32) — 방어 팩터를 standalone 슬리브로 상시 보유하는 구조 자체가 위기 보호분을 압도하는 비용.

### 4-3. bad/normal IC ratio

방어 배향 IC: 전기간 −0.047~−0.053, **bad(BM_Ret<0) 월 IC −0.108~−0.139 (더 음수)** → 축 방향 자체 FAIL (ratio 산술은 부호 혼합으로 무의미 — 수치 인용 금지, 두 IC 별도 보고). KR 하락월 횡단면에서 저변동 종목이 더 못함 — "저변동 = 방어" 직관이 이 유니버스에선 성립하지 않음의 직접 실측.

### 4-4. 판정 (config-scoped, 사유 명시)

1. **(가설 본체) 조합 > 단일 crisis_alpha: 기각** — regime-라벨 축에서도(−5.26 vs −2.88), 하락형-위기 한정 축에서도(+8.4% vs +24.4%) 조합이 단일 최선을 넘지 못함.
2. **(재평가) 선례 FAIL의 AX-001 위반 채점: 확정** (§0-1) — 단 올바른 조건부 채점으로도 승격 불가 판정은 동일하며 **사유가 다름**(구: 전기간 MDD hard / 신: 만성 drift + 조합 무개선 + bad-IC 역방향). 채점 위반 판별과 팩터 실격은 독립 명제 — 둘 다 성립.
3. **실재하는 것**: 하락형 위기 episodic 방어(+5~10%/에피소드, 4/4 에피소드 D03 양수). 소비처는 standalone 아닌 **overlay/국면-조건부 입력** — "방어는 오버레이만"(07-03 방어팩터 DB 전수) 확증과 정합, 반증 아님.
4. **현 config 수렴** (config = K200∪KQ150 · top-25 EW · 월간 · 15bps · regime-라벨 조건부): 이 측정틀에서 변동성 조합의 방어 승격 경로 없음 + 부활 조건 명시 — ① 위기 정의를 실현-하락 기반으로 교체한 재판정에서 MDD-complement 축이 뒤집히는 실측 ② overlay-게이트 결합(위기 게이트 발화 시에만 tilt)에서 book-marginal 기여 실측 ③ KR 저변동 이상현상의 구조 변화 신호(vol IC 부호 반전 지속).

## 5. next_probe (≥2) + 소비면 7종 순회

**next_probe**:
1. **AX-001 hook family 오분류 수리** (governance): hurdle `detected_family="other"`가 defense 계열을 AX-001 enforcement 우회시킴 (§0-1 실측). family 탐지를 hypothesis_signature 우선으로 보강 — 별도 배관 태스크로 등재.
2. **위기 정의 이원화 표준**: 2026-02~07(CRISIS 라벨 ∧ BM +33.7%) 실사례가 crisis_alpha 축을 구조 오염 — AX-001 절차에 regime-라벨 축과 실현-하락(BM_Ret<0 / drawdown-state) 축 병기 의무를 제안. 본 라운드는 이미 이원 보고로 선례 제공.
3. **falsification 미측정분 실측**: CRISIS 월 고변동 quintile 개인 순매수 강도(investor_wide) — 복권 수요 기전의 agent 성분 직접 검증 (본 패키지 falsification[1] 사전 지목).
4. **(조건부) overlay-입력화**: D03 저변동 tilt × 기존 위기 게이트 결합의 book-marginal 실측 — optimizer/FR 소비면 (FQ 등재 후보, alpha 역할 밖).

**소비면 7종**: ① 팩터 랭킹 — 부적합(만성 음 drift) ② 유니버스 필터 — 미측정(저변동 필터는 역효과 방향) ③ **오버레이/국면 입력 — 후보** (하락형 위기 episodic 방어 실측) ④ **위험모델 — 유용**: 수준축 3종(D03/D01/D45) ρ 0.91~0.97 실측은 risk agent의 vol-축 중복 처리 근거 ⑤ **monitoring — 후보**: regime-라벨 vs 실현시장 괴리(2026-02~07형) tripwire ⑥ 선별 라벨 — screen_route=OVERLAY_CANDIDATE ⑦ 타 모드 이식 — FR-RCMA 방어 specialist 요건(만성 drift) 미충족.

## 6. (h) 77건 선례 대비 차별점 (정직 평가)

- **최초**: 조건부 3축(crisis_alpha/MDD-complement/bad-normal IC) 실측 — 선례 88건 매칭 중 0건이 이 축을 계산.
- **최초**: 에피소드 분해로 "하락형 위기 방어 실재"와 "멜트업-라벨 오염"을 분리 — 선례의 단일 평균 채점으론 불가한 구분.
- **최초**: 방향정렬의 고변동-롱 실측 문서화(expanding IC +0.11~0.14) + 양 lane 병행 — 선례 LowVol류가 "왜" 전기간에서 죽는지의 기전(저변동 롱 = KR에서 만성 역풍) 특정.
- **한계 정직**: standalone 승격 관점의 결론은 선례와 동일(불가). 새 지식은 판정 사유의 교체(채점 위반 → 기전 실측)와 소비처 특정(overlay 입력)이지, 새 배포 가능 alpha가 아님.

## 7. 검증 무결성

- parity: defensive AST 5축 max|diff| 0.0e0 / combo 4종 ≤1.8e-15 — 전부 PASS (컴파일러 대조 검증 완료).
- selection_type=chain (전 설계 사전등록, argmax 0회) / n_trials=15 기록 / DSR 게이트 비적용(비-sweep).
- live_with_ast: 33 (본 WT +15, VOLC 접두 — Step 5 조건 30 초과 달성).
- Rule 1 (failure_rules) 발동 명시: 기대 alpha 음수 → Risk 단계 진행 비권고, status ABORTED 기록.

