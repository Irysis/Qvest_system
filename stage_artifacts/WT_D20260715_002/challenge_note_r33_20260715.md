# R33 insider 소비면 전환 — Self-Adversarial Challenge (FQ-049, 2026-07-15)

**대상**: exclusion 필터(A) + monitoring 경보(B) 판정. 규약 v8.2 Opus 4.8 자체 적대검증(외부 Codex 없음). 약점 ≥3 자가제기 → ACCEPT/PARTIAL/REBUTTAL.
**측정 요약**: A paired t=−0.09(KILL) / B net-buy 클러스터 gap t=+3.36→size-neutral +5.22(large-cap t=+2.57) / B net-sell t=−0.01(무효). base=production clean T-1(§7b). pin=R9 rawdata pin.

---

## C1 [task ①] 배제 필터가 소수 종목만 건드려 "무영향"으로 나온 것 아닌가 — **REBUTTAL**
- **claim**: A paired t=−0.09는 배제가 top-25에서 월평균 2.4종목(영향월 164/268)만 건드려 통계적으로 안 보이는 것일 수 있다.
- **반박 근거**: 영향월 185/268(69%)·총 393 배제·5,009 후보 = 표본 충분. 게다가 **paired가 0-근방일 뿐 아니라 미세 음(−0.0006 ann)이고 위험 3축 전부 불개선**(MDD −0.368→−0.370, active-SR 0.78→0.75, active-vol 0.134→0.139). "underpowered toward 0"이면 위험지표는 랜덤 방향이어야 하나 전부 일관되게 (미세) 악화 → 배제가 미세하게 **손해**라는 방향성 신호. Branch B net-sell t=−0.01(232m, 무구분)이 독립 확증: net-sell은 forward 위험 정보 없음.
- **판정 REBUTTAL**: 소표본 아티팩트 아님. net-seller 배제 무효는 robust(3축 일관 + net-sell tripwire 독립 확증).

## C2 [task ②] 클러스터 경보 +3.36이 기저율/표본/size 아티팩트 아닌가 — **REBUTTAL(size) / PARTIAL(coverage)**
- **claim**: net-buy 클러스터 gap +3.36은 (a) 임원이 소형주를 사서 size 프리미엄이 새거나 (b) 126m coverage(전체의 47%)라 국소적일 수 있다.
- **(a) size**: **REBUTTAL** — size-잔차 gap t=+5.22(raw 3.36에서 **강화**), tercile: mid t=5.17·**large t=2.57**·small t=1.34(약). flag 분포는 large 2204 > mid 984 > small 365 = 소형 집중 아님. 즉 소형주 아티팩트의 정반대(size 통제 시 강화, 배포-관련 large tier 유의). 선별-면 cap-tier 국소화 벽(R9: large/mega 死)과 **다른 방향** — monitoring-면 large tier 生.
- **(b) coverage**: **PARTIAL 인정** — 126m(net-buy breadth 클러스터가 존재하는 월만). standalone 자본 신호로 쓰기엔 커버리지 성기고, R9가 pool-선별서 이미 KILL. 그래서 **자본 아닌 monitoring tripwire로만 라우팅**(task 프레이밍 정합). coverage 확장·안정성 재검정을 next_probe #2로 등재.
- **판정 REBUTTAL(size 아티팩트 기각) + PARTIAL(coverage → 자본 아닌 monitoring 한정)**.

## C3 [task ③] insider 커버리지 편중(이벤트 팩터, 오너경영 종목군) — **PARTIAL**
- **claim**: insider 팩터는 이벤트 기반(월 ~84종목 활동)이라 특정 섹터/지배구조(오너경영·지주사)에 편중 — 배포 유니버스(top-25 대형주) 일반화 제한.
- **자가검증**: size 편중은 C2에서 기각(large 최다·large tier 유의). 그러나 **섹터/지배구조 편중은 미측정** — net-buy 클러스터가 오너경영 종목군에 몰려 forward-gap이 그 종목군의 별도 프리미엄일 잔여 가능성 남음.
- **판정 PARTIAL**: size confound는 통제 통과(핵심 편중 기각), 섹터/지배구조 잔여 confound는 미격리 → next_probe #3(sector-neutral)로 전개. 현 판정(monitoring capability)은 size-robust + large-tier 유의로 지지되나, 배선 전 sector-neutral 확인 권고 라벨.

## C4 [자가] base parity 3.478 ≠ production 3.058 — **ACCEPT (paired robust)**
- **사실**: 재구성 cap-w 벤치 base PORT_t=3.478 vs production-meta 3.058(Δ+0.42). Size-가중 rawdata 재빌드 벤치 ≠ production 벤치 구성.
- **판정 ACCEPT**: 절대치는 "재구성-벤치" 라벨로 강등. 그러나 **Branch A 판정=paired(filtered−base)로 벤치·vintage canceling** → parity 차이에 불변. Branch B는 cross-sectional gap(벤치 상수 canceling) → 불변. 결론 3면 모두 벤치-재구성에 무관.

## C5 [자가] gap_exc_t == gap_ret_t 축퇴 = dual-basis 미구현 아닌가 — **ACCEPT (지표-dual로 대체)**
- **사실**: cross-sectional 월별 그룹평균 gap에서 market-excess는 BM이 상수라 raw와 동일(축퇴). "dual-basis" 문자 요건이 return 축에선 무의미.
- **판정 ACCEPT**: monitoring의 실질 dual-basis = **위험지표 다축**(downside/vol/tail — 병기 완료) + size-basis(raw vs size-resid — 병기 완료). return의 raw/excess 축퇴는 수학적 필연이지 누락 아님.

---

## 종합
- **자기합리화 detect 스캔**: "미미/관행/보수적이면" 등 미사용. 핵심 positive(net-buy)는 확증편향 방어를 위해 **역방향 가설(size 아티팩트)을 능동 검정 → 강화**로 확인. negative(A·net-sell)는 3축 일관 + 독립 확증으로 "무측정 음성" 배제.
- **분류 집계**: REBUTTAL 2(C1·C2-size) · PARTIAL 2(C2-coverage·C3) · ACCEPT 2(C4·C5). 약점 5 ≥ 3 충족.
- **escalate 판정**: HIGH severity <5, AX axiom hard FAIL 0, PIT C1(lockbox/lookahead) 위반 0 (§7b production base + C5 홀딩월-전 신호 + insider 재빌드 X) → Q-Lead 자동 escalate 미해당.
- **최종**: capability_established(net-buy monitoring tripwire, non-capital) + 3면 config_scoped_negative. next_probe 3 도출. 종결 어휘 미사용.
