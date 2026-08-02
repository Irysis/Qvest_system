# Challenge Note — WT-D20260802_007 (Self-Adversarial Challenge, v8.2)

**작성**: alpha-research agent, finalize 직전 자체 적대검증 (Charter §8 No Silent Override).
**대상**: alpha_package.json (INS_MAGQ3 사전등록 primary + 대조 5축).

---

## C1 — "primary가 자기 대조축(NOFILT +1.59)보다 낮다 — 사전등록이 성과를 깎았다. 판정을 NOFILT 기준으로 바꿔야 하지 않나"

**분류: REBUTTAL** (근거 3축)

- 학술: Bailey–López de Prado (2014, DSR) — 사후 argmax는 다중검정 상향편의. 사전등록 primary를 실측 후 더 좋은 arm으로 교체하는 행위가 정확히 DSR이 벌하는 selection.
- L-code/규약: measurement-graduation §3 chain 자격요건 + preregistration.json no-flip/no-argmax 조항(측정 전 고정). WT-006 동일 프로토콜 선례.
- 정량: NOFILT−primary paired = +4.8bps/m (t=+1.45) — 유의 미달. 교체해도 HARD 2.95에 못 미침(+1.59). 교체의 이득은 없고 프로토콜 파괴 비용만 있음. **NOFILT 우위는 CF-04로 정직 공개 + NP-3(함수형 분해)로 승계** — 은폐도 채택도 아님.

## C2 — "placebo가 안 죽었다(최대 시드 +1.33 vs primary +1.37) — 'magnitude 정보' 주장 자체가 성립 안 하는 것 아닌가"

**분류: ACCEPT (부분 — 서사 강등 반영)**

- 인정: cr 셔플 후에도 PORT_t 0.45~1.33 — primary가 5/5 상회하나 여유가 통계적으로 무의미한 수준. "크기 정보가 알파의 원천"이라는 강한 주장은 **기각**이 맞다.
- 반영: alpha_package placebo_note와 CF-05에 "magnitude 고유 증분은 실재하되 얇다 — 개선의 상당분은 signed-cr 함수형(placebo 평균 +0.88 > base +0.55)"으로 서사를 강등해 기록했고, verdict도 "벽을 구부리나 뚫지 못함"으로 고정. economic_rationale에도 "기전의 '정보성' 서사는 미입증" 명기.
- 잔여 방어(왜 전면 무효는 아닌가): placebo는 참여·방향·건수 구조를 보존하므로 '참여 여부' 정보는 남는다 — placebo가 base3(+0.55)보다 높은 것 자체가 cr-함수형의 기여를 실측하는 통제였고, 이는 발견(함수형 개선)으로 NP-3에 승계된다.

## C3 — "flow 링크 t=+1.41을 '기각 아님'으로 넘기는 것은 자기합리화 아닌가 — WT-006은 +4.08이었다"

**분류: ACCEPT**

- 사전등록 기각선은 t<1이었고 1.41은 그 위이나, 지지선(t≥2)에 못 미친다. 패키지에 **MECHANISM_NOT_ESTABLISHED**로 라벨 — "지지"로 기록하지 않았다.
- 함의를 정직하게: "insider 매수 = 축적의 가장 직접적 공시 지문"이라는 본 WT의 착안은 **실측으로 약화**됐다. 가격-거래 경로 기하(WT-006)가 잡는 축적과 insider 공시가 잡는 것은 다른 대상이다(insider 매수 후 기관이 따라 사지 않는다). 이 사실 자체가 계열 간 비교 성과물이며 verdict_summary에 반영.

## C4 — "FQ-080은 '측정했다'고 할 수 없는 커버리지(월 2명)다 — PORT_t +0.96을 보고하는 것 자체가 오해 유발"

**분류: PARTIAL**

- 인정: portfolio-tier 판정 불성립. CF-06 + contrast_axes에 diagnostic-grade 라벨, rank-IC n_ic=8 명기. 자본 관련 주장 일절 없음.
- 보완 자료: 본 라운드의 FQ-080 기여는 성과가 아니라 **데이터 게이트 해소**(크롤 0으로 부정 이벤트 668건 census — 감자 242·영업양도 214·해산 95·영업정지 85·회생 57) + **커버리지 벽의 실측 확정**(이벤트×임원매수 교집합 428건/21년 = 월 2명). "신호 부재"가 아니라 "표본 부족"이 바인딩임을 분리 기록(NP-4).
- C6 생존 tilt(348 corp = 현행 유니버스 크롤)도 self_pit_check에 명기.

## C5 — "cap-tier UNRANKED 22.4% — tier 분해의 1/5이 미분류인데 'mid/small 국소' 결론을 내려도 되나"

**분류: PARTIAL**

- 인정: UNRANKED는 초기 연도 Size 결측 구간(2005~) 집중 — tier 결론은 Size 커버 구간 기준. dual_basis verdict에 UNRANKED 22.4% 사유 병기.
- 방어: 판정에 쓰인 것은 cap-w PORT_t(HARD)와 EW-uni 진단이며 둘 다 UNRANKED와 무관하게 산출. tier 분해는 비바인딩 진단(metric_type=canonical_screen_diag)이고, MID>MEGA 구조는 R33 독립 실측(mid-cap 강건 t 4.6~6.1)과 정합 — 단독 근거로 쓰지 않음.

## C6 — "SEQ12는 정수 스코어(-6..6) — top-25 선택이 동점 처리에 좌우된다. R33 재탕 판정의 rank-cor 0.805도 동점 왜곡 아닌가"

**분류: REBUTTAL (한정적)**

- 정량: rank-cor는 Spearman으로 동점을 mid-rank 처리 — 동점이 상관을 **하향** 편향시키는 방향(변별력 손실)이지 상향이 아니다. 0.805는 오히려 보수적 하한.
- 규약: 재탕 판정선(|rho|≥0.7)은 사전등록 — 사후 조정 없음.
- 인정 사항: SEQ12의 canonical PORT_t(+0.98)는 동점-임의 선택 노이즈를 포함 — 단 SEQ12는 대조축(판정 비대상)이라 바인딩 없음. 기록만.

## 자기합리화 스캔 (금지 표현 감사)

패키지·검증 파일에서 answer-principles 회피표현 조항의 금지 목록(pit.md 금지 표현 5종 계열) 전항목 grep — 미사용 확인. 판정 완화 시도 2곳을 스스로 적발해 강등: ① flow 링크를 "기각 아님"으로 쓰려던 초안 → MECHANISM_NOT_ESTABLISHED로 교체(C3) ② placebo "5/5 상회"를 지지 증거로 쓰려던 초안 → "여유 얇음 + 함수형 기여" 강등(C2).

## Escalation 판정

HIGH severity = 3건 (CF-01/02/03) < 5, AX axiom hard FAIL = 0, PIT C1 위반 = 0 (truncation-invariance 3/3 PASS, lag1 완만 감쇠, rcept월 규약) → **Q-Lead 자동 escalate 비발동**.

## AX-008 Triangulation 상태

Self-Adversarial(본 문서) = 1 source 완료. Forge/Architect는 후속 단계 소관 — 단 본 라운드는 capital-tier negative로 forge 승격 대상 아님(스크리닝 판정 종결, Q-Lead 수집 대기).
