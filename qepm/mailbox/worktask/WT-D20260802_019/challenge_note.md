# Challenge Note — WT-D20260802_019 (Self-Adversarial, v8.2)

**대상**: 실현-하락 nowcast 대체 라벨 (FQ-118) — DD_STATE(12M 고점 −10%, g=0.40) × 현행 M4×R05
**판정**: NEGATIVE — 라벨 품질 사전 검정 단계 결론 (recall 0.351 ≤ base 0.413, fisher p=0.795)
**작성**: finalize 직전 자체 적대검증 (Charter §8 No Silent Override)

## Concern 1 — "DD5가 primary보다 recall이 높은데(0.532 > base) primary 판정 유지가 맞나? 사후 재선택 유혹"
**분류: ACCEPT (설계대로 거부)**. 사전등록이 DD10을 primary로 고정했고 DD5는 진단 병기(선택 사용 금지)로 명시 등재됨. DD5조차 fisher p=0.259로 pass_line(p<0.05) 미달 — 재선택해도 결론 불변. DD5의 양(+) 방향 recall은 사실로 기록하되(challenge_flags ALL_VARIANTS_FAIL) 판정에 미사용. 사전등록 위반 없음.

## Concern 2 — "pretest FAIL인데 성과 '유해' 수치를 병기하는 것이 판정 계층을 흐리지 않나"
**분류: PARTIAL (계층 명시로 보완)**. 사전등록 fail_line: "recall ≤ base → 성과는 참고 병기로 강등". 산출물 전체(alpha_package verdict_empirical, alpha_validation, 보고)에 1차 결론 = 라벨 판별력 부재, 성과 = 참고(방향 유해)로 계층을 명시 표기했다. 참고 성과를 숨기는 것이 오히려 정보 손실 — WT-017 대비 더 나쁜 −3.77은 "무판별 라벨 소비는 발화 월수에 비례해 유해"(92개월 ON vs MSM 28개월)라는 기전 지식을 준다.

## Concern 3 — "벤치 단일 소스 의존 — benchmark.parquet 2소스 divergence 실사고(2026-08-02, 7월 8일 불일치)가 DD 상태 계산을 오염시켰을 가능성"
**분류: REBUTTAL (정량 3축 + 선례)**. ① 표본 경계: carrier 마지막 홀딩월 = 2026-05, 마지막 cutoff = 2026-05-04 직전 — divergence 창(2026-07)은 전 표본 밖. ② 프레임 정합: WT-017이 동일 소스로 판정했고 본 실행의 BARE/BOOK/ORACLE/BOOK_EW가 WT-017과 자리수까지 일치(6.40/6.18/7.87/5.33) = 승계 프레임 정확 재현. ③ 민감도 구조: DD_STATE는 누적지수 비율(고점 대비 −10%)이라 단일월 소폭 오차에 이진 tipping이 국소적 — ON 92개월의 dd 분포는 문턱에서 대체로 이격(−0.10 경계월 소수). 학술: 판별 실패의 크기(recall 격차 −0.06, p=0.795)는 데이터 오차로 뒤집힐 규모가 아님. (L-ref: project-benchmark-two-source-divergence — 정합 검사 부재 결함은 별도 수리 궤도)

## Concern 4 — "fisher 검정력 — n_on=92, 진짜 약한 농축(+0.05~0.10)을 놓쳤을 수 있다"
**분류: PARTIAL (한계 기록)**. primary는 recall이 base *아래*(0.351 < 0.413)라 놓칠 농축 자체가 없음. DD5(+0.12, p=0.259)는 약한 진짜 농축을 배제 못 한다 — 단 소비 검정이 상한을 제공: NOWCAST_ONLY paired −3.53, DD5보다 판별력 낮은 라벨이 아니라 *어떤* 트레일링 가격-상태로도 상승월 비용(−4.87 지배)을 못 넘는 구조가 실측됨. 약한 농축이 실재해도 g=0.40 소비로는 순손실. 이 한계는 next_probe(심도-조건부 완화 g)로 승계.

## Concern 5 — "회수율 −343%는 프레임 자체의 문제 아닌가 — 오라클 분모가 작아(+2.14) 증폭 왜곡"
**분류: REBUTTAL (정의 정직성)**. 회수율은 사전등록 mandate 산식 그대로 (CAND−BOOK)/(ORACLE−BOOK). 분모가 작은 것이 아니라 후보의 분자가 음수로 큰 것(−7.35%/yr)이 본질 — "상금의 3.4배를 파괴"가 정확한 서술. MDD축 +7.3%를 부분 성공으로 포장하지 않음(1.1pp는 return 비용 −7.35%/yr와 교환 불가).

## 합리화 자기검증
answer-principles 회피표현 grep 목록(축소·관행 정당화 계열) 전항 미사용 확인 — 본 노트의 전 주장은 실측 수치(recall/fisher/paired t/회수율)와 사전등록 조항 인용으로만 구성. MDD 1.1pp 개선을 성과로 포장하지 않았고, DD5 방향성을 채택 근거로 전용하지 않았다.

## Escalation 판정
HIGH severity 위반 0 / AX axiom hard FAIL 0 / PIT C1(lockbox·lookahead) 위반 0 — Q-Lead escalate 비발동. PIT: assert HARD PASS + 위반 주입 발화 + lag 스트레스 clean(leak 방향이 더 나쁨) + strict A/B 인플레 0.
