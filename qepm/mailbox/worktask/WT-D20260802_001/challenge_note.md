# challenge_note — WT-D20260802_001 **R2** (FQ-073 next_probe P1+P2)

> Self-Adversarial Challenge (v8.2 — 외부 Codex 없음, 본 에이전트 자체 적대검증).
> Charter §8 No Silent Override 이행 기록. R1 판은 `challenge_note_r1.md` 로 보존.
> **원칙**: 반론은 글로 적고 끝내지 않는다 — 데이터로 판별 가능한 반론은 실측한다
> (`stage_artifacts/WT_D20260802_001/fq073_r2_adversarial.json`).

---

## 0. 이 라운드가 실제로 산출한 것 (요약)

| 축 | R1 | R2 | 변화 |
|---|---|---|---|
| canonical PORT_t (PRIMARY) | −1.7078 | **−1.2005** (G1 materiality) | 음수 축소 |
| 최고 변형 PORT_t | −1.129 | **+0.137** (G5 mat×SUE 6M평활, p 0.891) | 음수 소멸, 알파는 아님 |
| EW-유니버스 PORT_t | −1.605 | −1.103 (G1) / **+1.446** (G5) | 부호 전환 |
| 회전율 | 1288%/yr (**제약 위반**) | 1252%(G1) / **712%(G4)** / **508%(G5)** | **P2 해소** |
| 보유 cap-tier OTHER | 0.889 | 0.915 (G1) | 대형 tier **이동 없음** |
| firm-level 해상도 distinct_ratio | 0.6439 | 0.6488 | **사실상 무변화** |
| 반증 링크1 t (컨센 영업이익) | 1.969 | **0.744** | **약화** |
| ast_verify | FAIL_CONTRACT 5건 (F1 leaf_count=0) | **WARN_RESTATEMENT 6/6**, leaf 5~9 | 실검증 도달 |

**판정: config-scoped negative.** 승격 후보 제출 없음.

---

## 1. 자기 비평 — 제기된 반론과 처리

### C1 [ACCEPT · HIGH] materiality 는 버킷 수준이라 P1 을 절반만 집행했다

**반론**: "수출 의존도 5%인 기업과 80%인 기업을 구분했다"고 주장하지만, 채택한 정규화
M_i = Σ_h w_ih·R_h 에서 R_h = Flow_h·FX / Σ_j(Rev_j·w_jh) 는 **버킷 수준 상수**이고
분자·분모의 Rev_i 가 소거된다. 따라서 같은 HS4 에 단일 매핑된 기업들은 **여전히 동일한 M**을 받는다.

**실측**: distinct_ratio 0.6439 → **0.6488** (+0.005). 크로스워크 구조상 315사 중 **180사가
단일-HS4 매핑**, 92 버킷 중 42 버킷이 1사 전용, 273사가 공유 버킷에 속한다
(`fq073_r2_adversarial.json::C1_bucket_tie_structure`).

**처리**: **ACCEPT**. 이 라운드의 재척도는 **버킷 간**에서만 작동했고 **버킷 내**에서는 작동하지 않았다.
alpha_package `R2-CF-02` 에 명시했고, verdict_summary 의 P1 답변도 이 한계를 포함해 서술했다.
넘으려면 정규화가 아니라 **기업별 수출비중 데이터**가 필요하다 → `NP-R2-1` (P1).

**왜 그럼에도 cap-tier 판별은 유효한가**: 보유 tier 구성을 결정하는 것은 *어떤 버킷이 선택되는가*이고
버킷 간 재척도는 실제로 일어났다(M 의 버킷 간 분산은 실재 — p10 0.093 / med 0.560 / p90 4.410).
따라서 "대형 tier 로 이동하지 않았다"는 결론 자체는 성립한다. 성립하지 않는 것은
"firm-level 노출로 재척도했다"는 **더 강한 주장**이며, 그 주장은 철회한다.

---

### C2 [REBUTTAL · 실측 근거] "대형주가 크로스워크에 없어서 못 움직인 것 아닌가"

**반론**: cap-tier 가 안 움직인 건 materiality 실패가 아니라, 스코어 부여 가능한 대형주가
애초에 없어 선택지가 없었기 때문일 수 있다. 그렇다면 P1 은 검정되지 않은 것이다.

**실측 반박** (`C2_tier_score_coverage`):

| tier | 유니버스 firm-month | 스코어 보유 | 커버리지 | 월평균 스코어 종목 |
|---|---|---|---|---|
| MEGA (1–10위) | 1,398 | 874 | **0.625** | **7.73 / 10** |
| MID (11–30위) | 2,796 | 979 | 0.350 | 8.66 / 20 |
| OTHER (31위+) | 45,161 | 18,487 | 0.409 | 163.6 |

MEGA 커버리지가 OTHER보다 **높다**. 매월 평균 7.73개 MEGA 종목이 스코어를 갖고, 포트는 25 슬롯이다.
**선택 여지가 실재했는데 선택되지 않았다.**

**처리**: **REBUTTAL**. 근거 = 정량 3축(커버리지 비율 / 월평균 후보 수 / 슬롯 대비 여유) + 실측 산출물.
추가로 대형주-제한 재측정에서도 알파 없음(G1 −0.779 p 0.436 / G5 −0.244 p 0.808) — R1 F5(−0.33)와 동일 결론.

---

### C3 [ACCEPT · HIGH] 반증 검정이 materiality 구성 자체를 반증했다

**반론**: 사전등록한 R2 강화 조건은 "materiality 가 실제 경제적 노출을 잡는다면 링크1
(수출 서프라이즈 → 후속 컨센서스 영업이익 상향)이 R1 대비 **강해져야 한다**"였다.
실측은 t 1.969 → **0.744** (Q5−Q1 +1.494% → +0.604% log). 반대로 갔다.

**처리**: **ACCEPT**. 이는 알파 부재와 별개로 **materiality 구성의 타당성에 대한 부정 증거**다.
가능한 독해 두 갈래를 모두 남긴다:
(a) R_h 가 경제적 노출이 아니라 버킷 매핑 품질의 잡음을 실어 링크를 희석했다,
(b) 5분위 구성이 바뀌며 검정력이 떨어졌다(가중이 저노출 기업을 중간 분위로 밀어넣음).
**어느 쪽인지 이 라운드는 판별하지 못했다** — 판별에는 firm-level 수출비중(NP-R2-1)이 필요하다.
무시 가능하다는 서술로 넘기지 않고 alpha_package `R2-CF-03` HIGH 로 등재했다.

---

### C4 [PARTIAL] 개선처럼 보이는 것이 창 길이 단축의 산물일 수 있다

**반론**: B0 n=112 → G5 n=95. TS_STD(12)+TS_MEAN(6)이 앞을 잘라내므로, PORT_t 개선이
구성 변화가 아니라 **2016–18 나쁜 구간 제거**의 산물일 수 있다.

**대응**: 공통창(96개월, 2018-08 ~ 2026-07) 전 변형 재측정을 병기했다.

| 변형 | 전창 PORT_t | 공통창 PORT_t |
|---|---|---|
| B0 (R1 F1) | −1.708 (112m) | −1.398 |
| G1 materiality | −1.200 (112m) | −1.197 |
| G2 SUE | −1.270 (100m) | −1.210 |
| G3 mat×SUE | −0.668 (100m) | −0.620 |
| G4 sm3 | −0.767 (98m) | −0.649 |
| G5 sm6 | +0.137 (95m) | +0.137 |

공통창에서도 방향은 유지된다(B0 −1.398 → G5 +0.137). **처리: PARTIAL** — 창 효과는 통제됐으나,
G5 의 p=0.891 은 "개선"이 아니라 "0 과 구분 불가"이므로 개선 서사를 부여하지 않는다.
부기간 분해에서 G5 는 2016-19 +1.738 / 2020-22 +2.536 / **2023-26 −1.373** 로,
저장소 전반의 post-2017(특히 2023+) 감쇠 패턴과 동형이다.

---

### C5 [ACCEPT · MEDIUM] 타이밍 주장이 데이터와 어긋난다

G4(3M 평활)의 lag1 스트레스가 base(−0.767)보다 **높다**(+0.443, 인플레 −1.210).
누출 방향은 아니다(누출이면 base ≫ lag1이어야 하며 전 변형 NO_INFLATION). 그러나 메커니즘이
선언한 "M+2 홀딩월에 반영"이라는 시점 주장은 데이터가 지지하지 않는다. **ACCEPT** — `R2-CF-05`.

---

### C6 [ACCEPT · MEDIUM] PIT 노출을 해소하지 않았고, 오히려 승계·확대했다

materiality 분모 Σ_j(Rev_j·w_jh) 는 **R1 과 동일한 static_current 크로스워크 가중치**를 쓴다.
즉 C1/C3 사업구성 look-ahead 가 이제 분자(노출)와 분모(귀속 상대) 양쪽에 들어간다.
C6 survivorship(현 상장사 기반 474사)도 그대로다. **ACCEPT** — `gate_eligible = FALSE` 승계,
graduation 판정 자격 없음을 verdict_summary 에 명시. 해소 경로 = `NP-R2-2` (P3 vintage 크로스워크).

*정직 보고*: 상한(upper-bound) 논증의 한계는 R1 CF-02 그대로 유효하다 — 매핑 vintage 오류는
favorable bias 가 아니라 attenuating noise 일 개연이 크므로, "상한이 음수/0 이니 clean lane 도 그렇다"는
**강한 신호만 배제**하고 약한 신호는 배제하지 못한다.

---

### C7 [PARTIAL] CLIP(0,1) 이 귀속 실패를 최대 materiality 로 saturate 시킨다

M > 1 은 "매핑된 상장사 매출로 그 수출 흐름을 설명할 수 없다"(비상장·해외·오매핑)는 뜻인데,
CLIP 은 이를 **최대 의존도 1** 로 만든다 — 방향이 반대일 수 있다. 실측 M>1 비중 = **40.0%**.

**대응**: 이 반론을 그대로 구현한 대조군을 사전 배치했다 — `G1c` = min(R_h, 1/R_h) 가중
(R=1 에서 최대, 양방향 감쇠 = 귀속 실패를 감쇠). 결과 **−1.190** (G1 −1.200 과 사실상 동일),
cap-tier 는 오히려 OTHER 0.933 로 더 쏠렸다. **PARTIAL** — 반론은 타당하나 결론을 바꾸지 않는다.
materiality 프로파일 실측: Spearman(M, −cap_rank) raw −0.210 / clip −0.194 / cred **+0.019**.
즉 credibility 보정만이 시총 중립이며, **어떤 정규화도 신호를 대형 tier 로 이동시키지 않는다.**

---

### C8 [ACCEPT · 방법론] 6 변형은 sweep 인가

argmax 로 최종안을 고르면 sweep 이고 DSR HARD 대상이다. 본 라운드는:
① 6 변형을 **사전선언 귀속설계**(materiality on/off × 변동성표준화 on/off 의 2×2 + 평활 사다리 2단)로 배치,
② 각 변형에 mechanism 진단 1줄 기록(`method_log[].mechanism_note`),
③ 선택은 IS 구간 canonical PORT_t 로만, holdout 미조회,
④ **결정적으로 — 어떤 변형도 승격 후보로 제출하지 않는다**(전 변형 PORT_t < 2.95, 최고치 p 0.891).
선택 편향이 개입할 판정 자체가 없다. `selection_type = "chain"`, `n_trials = 6` 사후 감사용 기록.
**ACCEPT(라벨 의무)** — 라벨을 정직히 달되 DSR 게이트는 부적용(measurement-graduation §3).

---

### C9 [ACCEPT · 전제 정정 · HIGH] 이 라운드의 출발 전제가 틀렸다

라운드 지시와 R1 보고는 "보유 cap-tier OTHER 88.9% = 직전 16후보를 죽인 소형주 국소화 재현"이라
읽었다. 그러나 **K200∪KQ150 에서 MEGA=10·MID=20 종목은 정의상 고정**이므로 OTHER 의
base rate 는 0.915(유니버스) / 0.909(스코어풀)다.

| | MEGA | MID | OTHER |
|---|---|---|---|
| 유니버스 base | 0.028 | 0.057 | 0.915 |
| 스코어풀 base | 0.043 | 0.048 | 0.909 |
| **R1 (B0)** 보유 | 0.0595 (lift_univ **2.097**) | 0.0513 (0.904) | 0.889 (0.972) |
| **R2 G1** 보유 | 0.0442 (lift_univ 1.560) | 0.0404 (0.711) | 0.915 (1.001) |

R1 은 소형주 국소화가 아니라 **약한 대형주 초과편입**(MEGA lift 2.1×)이었다.
**ACCEPT** — `R2-CF-01` HIGH 로 등재. 이 정정 때문에 이 라운드의 정확한 답은
"아티팩트냐 신호의 성질이냐"가 아니라 **"수출 신호에는 애초에 cap-tier 를 움직일 횡단면 선택력이 없다"** 가 된다.

---

## 2. 자기 합리화 auto-detection

금칙 표현 목록은 `.claude/rules/pit.md` 금지표현 절 + `.claude/rules/answer-principles.md`
회피표현 grep 절이 정본이다(본 문서는 목록을 복제하지 않는다 — 복제 자체가 탐지기를 오발화시킨다).
아래는 초안 단계에서 그 부류의 서술로 미끄러질 뻔한 지점과 대체 조치다.

| 위치 | 미끄러짐 유형 | 조치 |
|---|---|---|
| C3 반증 약화 | 검정력 탓으로 돌려 넘기려는 충동 | **RE-VIEW** → 판별 불가를 명시하고 HIGH 등재 + next_probe 이월 |
| C7 CLIP 40% | 관행 수준이라는 서술로 무마하려는 충동 | **RE-VIEW** → 대조군 G1c 실측 수치로 대체 |
| C4 창 길이 | 결과가 같다는 취지의 뭉뚱그림 | **RE-VIEW** → 공통창 7행 표로 대체 |
| C8 FX | 무시 가능하다는 단정 | **미측정으로 정직 라벨** (`R2-CF-08`, LOW) — 재지 않았으면 작다고 쓰지 않는다 |

R1 대비 개선 서사("음수가 사라졌다")를 알파 발견처럼 서술하려는 충동 → **차단**.
PORT_t +0.137 (p 0.891) 은 알파가 아니라 **0** 이며, verdict_summary·본 note 전체에서 그렇게만 쓴다.

---

## 3. Q-Lead escalate trigger 점검

| trigger | 임계 | 실측 | 발화 |
|---|---|---|---|
| HIGH severity concern | ≥ 5 | 4 (R2-CF-01/02/03 + C6) | 미발화 |
| AX axiom hard FAIL | ≥ 3 | 0 | 미발화 |
| PIT C1 (lockbox·lookahead) 위반 | 1건 | **신규 위반 0** — C1/C3 static mix 는 R1 이 사전 선언한 **기존** 노출이며 `gate_eligible=FALSE` 로 격리, graduation 주장 없음 | 미발화 (단 Q-Lead 인지 필요) |

**escalate 미발화**. 다만 아래 2건은 Q-Lead 판단 필요로 명시 상신한다:
1. C1/C3 노출이 R2 에서 분자·분모 양쪽으로 확대됐다 — P3(NP-R2-2) 착수 시점 결정.
2. `02_Infrastructure/worktask/lineage_utils.R` 의 `system("git rev-parse HEAD 2>/dev/null")` 가
   Windows 에서 `fatal: ambiguous argument '2>/dev/null'` 로 실패한다(git_sha 결손 + status 128).
   r-portability 금칙 계통(쉘 리다이렉션을 인자로 주입). **본 라운드 범위 밖 — 별건 태스크로 분리.**

---

## 4. AX-008 Verification Triangulation

| source | 상태 |
|---|---|
| Self-Adversarial (본 note) | 수행 — 반론 9건, ACCEPT 6 / PARTIAL 2 / REBUTTAL 1, 실측 3건 |
| Forge | 미수행 (승격 후보 없음 — canonical screen 단계에서 종료) |
| Architect | 미수행 |

3-source 중 1 PASS. **2/3 미충족 → 본 라운드 산출물은 graduation 판정에 사용할 수 없다**
(애초에 판정 자격 없음: `gate_eligible = FALSE`, 승격 후보 제출 0).

---

## 5. 연속성 (answer-principles §리서치 연속성)

본 라운드는 config-scoped negative + 프론티어 표시로 마감한다. 종결 어휘 사용 없음.

**next_probe (≥2)** — alpha_package `verdict_summary.next_probe` 정본:
- **NP-R2-1 [P1]** 버킷 내 해상도 — DART 사업보고서 '매출실적' 표의 수출/내수 행 파싱으로
  firm-level 수출비중 패널 구축. 현재 정규식 상한 18.4%(58/315, 중앙값 56.65%). **distinct_ratio 0.64 천장의 정체.**
- **NP-R2-2 [P1]** P3 vintage 크로스워크 — `pull_dart_products.py` 연도 파라미터(FQ073_BGN/END)로
  `effective_from` 다행 구조 재구축 → C1/C3 해소 → gate 자격 + attenuating-noise 반론 판별.
- **NP-R2-3 [P2]** 6M 평활이 음수를 제거한 기전 귀속 — (a) 비용 (b) 단기 반전 (c) 버킷 변동성.
  이 지식은 FQ-073 밖 **다른 월간 flow 신호에 이식 가능**.
- **NP-R2-4 [P2]** 소비면 이식 — 랭킹 팩터가 아니라 ①유니버스 필터 ②monitoring tripwire
  ③국면 입력(총수출 모멘텀)으로. 횡단면 선택력 부재가 시계열 정보 부재를 뜻하지 않는다.

**부활 조건 (INV-7)**: ① firm-level 수출비중 커버리지 ≥ 60% 달성 시 P1 재도전
② vintage 크로스워크로 gate_eligible 전환 시 전 변형 재측정 ③ NP-R2-3 이 (b)/(c)로 귀속되면
동일 처리(평활+표준화)를 다른 비-return 월간 원천에 이식 후 재평가.

**소비면 7종 순회**: ①팩터 랭킹 = 실패(본 라운드) ②유니버스 필터 = **미측정 → NP-R2-4**
③오버레이/국면 입력 = **미측정 → NP-R2-4** ④위험모델·β예산 = 해당 없음(신호 β 정보 없음)
⑤monitoring 신호 = **미측정 → NP-R2-4** ⑥선별 라벨 = screen_route 부적격(PORT_t 0 근방, 신호력 미달)
⑦타 모드 이식 = NP-R2-3 이 선행 조건(기전 귀속 후에야 이식 대상이 정해진다).

---

*작성: alpha-research agent / 2026-08-02 / WT-D20260802_001 R2*
