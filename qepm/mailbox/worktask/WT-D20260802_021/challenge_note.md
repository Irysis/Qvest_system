# Challenge Note — WT-D20260802_021 (FQ-116 다팩터 합성 손실 기전 분해)

Self-Adversarial Challenge (v8.2, finalize 직전). Concern 5건: ACCEPT 2 / PARTIAL 1 / REBUTTAL 1 / ACCEPT(부분) 1.

## C1. advocate 귀속 규칙(argmax z)의 임의성 — **PARTIAL**
- 제기: IN-종목을 "그 달 z 최대 팩터"로 귀속하는 규칙은 여러 가능한 귀속 중 하나. Shapley류 반사실 제거 귀속에서 NEG share 75%가 무너질 수 있다.
- 처리: 강건성 probe 실행(`probe_robustness.R`) — 양의 z 비례 배분 귀속으로 교체 시 NEG share **75% → 78%** (결론 불변). 잔여 한계: 완전 반사실(2^5 canonical) 미수행 — 비용 대비 판별 이득 낮아 next_probe 선택지로만 기록.
- 판정 영향: 없음 (두 귀속 규칙 모두 사전 기준 ≥50% 충족).

## C2. NEG 집합에 V06_EB(+0.315, 약양성) 포함 — **ACCEPT(부분)**
- 제기: 사전등록 문턱(PORT_t<0.5)이 V06_EB를 "음-전이"로 분류했으나 실제 부호는 약양성 — NEG share 75%가 분류 관대함의 산물일 수 있다.
- 처리: V06을 POS로 재분류한 엄격판 병기 — NEG share(D03_EWMA+Q01_EB만) = **63%(argmax) / 59%(비례)**. 여전히 사전 기준 ≥50% 충족. alpha_validation에 4개 판 전부 기록.
- 판정 영향: M1 SUPPORTED 유지. 서술은 "강건 범위 59~78%"로 보고.

## C3. M2 판별 문턱 근접 미달 (t=1.31 vs 사전 1.5) — **ACCEPT**
- 제기: M01 꼬리 기울기 b1−b2 t=1.31은 사전 문턱 1.5 미달이나 기각 문턱 1.0 초과 — 사후에 "지지"로 올리고 싶은 유혹이 있는 구간.
- 처리: 사전등록 그대로 **NOT_CONFIRMED**(방향 일치·문턱 미달) 판정. 추가로 합성 픽의 M01 상위 decile(0.9,1] 실현 active가 −0.06%로 오히려 음(구간 (0.5,0.8]은 +0.64%)이어서 "꼬리 소실이 곧 손실" 서사를 지지하지 않음. POS2 검정(사전 예측: M2 독립 기여면 paired t ≤ −1.0)이 +0.37로 나와 **M2 독립 기여는 기각** — 이것이 더 강한 판별.
- 판정 영향: M2 = 현상(중앙값 0.639로 꼬리 이탈)은 실재하나 손실 기전으로는 기각.

## C4. POS2 회복률 126%의 in-sample 편향 — **ACCEPT**
- 제기: POS2 성분(M01_PATHQ·V01_SECREL)은 동일 표본 WT-009 PORT_t로 선별된 뒤 동일 표본에서 회복률을 잰 것 — 126%는 in-sample 상한이지 OOS 보장이 아니다.
- 처리: (i) POS2는 사전등록대로 **기전 probe이지 후보 아님** — 자본/채택 주장 0, paired vs single t=+0.37 비유의, PORT_t 2.49 < HARD 2.95, EW-uni oos 근사 0.61 < 0.7. (ii) 설계 원칙에 "성분 게이트는 IS-only canonical PORT_t + 조합은 OOS 확인" 명문화(NP-1). 회복률 판별 자체(M1 지배 여부, 사전 문턱 60%)는 이 편향 방향과 무관하게 M1·M2 판별에 정합 — 편향이 있어도 "양-전이만 섞으면 손실이 사라진다"는 부호 결론은 attribution 분해(75%)와 독립 경로로 재확인됨.
- 판정 영향: 회복률 수치는 in-sample 라벨 병기. 기전 판정 불변.

## C5. "overlap 4.4/25면 아예 다른 포트 — slot 잠식 프레임은 동어반복" — **REBUTTAL**
- 제기: 합성과 단일의 overlap이 4.4/25뿐이면 성과 격차는 당연히 IN/OUT 격차이고, "잠식"은 항등식의 재서술 아니냐.
- 반박 (근거 3축):
  1. **학술**: Clarke–de Silva–Thorley (2002, FAJ) "Portfolio Constraints and the Fundamental Law of Active Management" — IR = IC·√BR·**TC**. 본 라운드는 그 TC 항이 *팩터별로 부호가 다르다*는 것을 top-25 구현에서 분해로 특정한 것. 항등식은 출발점이고, 판별 내용은 "어느 팩터의 대변(advocacy)이 얼마를 파괴하는가"의 귀속(사전 기준 포함)이다.
  2. **L-code**: L-AR-20260802_204803 (WT-015 단일 지배 3회 정합) — 본 라운드는 그 next_probe의 기전 판별 완결이며, 동어반복이면 M3 기각·M2 기각 같은 차등 판정이 나올 수 없다.
  3. **정량 3축**: (a) overlap 4.4/25 + 잠식 slot 20.6/월 (b) NEG advocate 기여 −6.22%/yr = gap의 75%(강건 59~78%) (c) 반증 가능 대조 — 양-전이 2팩터 조합은 동일 항등식 하에서 손실이 소멸(+1.06%/yr, t +0.37). 잠식이 동어반복이면 (c)에서도 손실이 나야 했다.
- 판정 영향: 없음.

## 합리화 자기검증
answer-principles 회피표현 목록(축소·관행 정당화 계열) 전수 grep — 본문 사용 0건. M2·M3는 문턱 근접 구간에서 사전등록 문턱 그대로 기각/미확증 처리(사후 완화 없음). PIT C1 계열 위반 0. HIGH severity 0건 → Q-Lead escalate 비발동.
