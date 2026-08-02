# Self-Adversarial Challenge — WT-D20260802_005 (Alpha Agent)

**규약**: v8.2 (Codex Round 대체 — 메인 세션 모델 자체 적대검증, AX-008 3-source 중 1개). finalize 직전 작성.
**대상**: quarantine·skip 재고 4분류 + canonical 재실측 10런 + RD-to-Market alpha_package 승격.

---

## C1 [HIGH — ACCEPT] "회수 확정"의 선택 구조는 chain이 아니라 재고-스윕에 가깝다

- 제기: 고정된 재고 집합(등록 25건, 재실측 10런)에서 threshold를 넘는 1건을 골라 승격 — 이는 measurement-graduation §3의 sweep 정의("열거된 trial 집합에서 argmax/threshold-pick으로 최종안 선택")에 부분 부합한다. 최초 method_shopping_log에 selection_type을 chain으로 서술한 것은 관대했다.
- 완화 사실(면죄 아님): RD-to-Market은 오늘 스캔으로 발굴된 것이 아니라 **07-09에 이미 Grade A + 계약 PORT_t 2.584로 기록된 후보의 배관 유실(STANDALONE_TRACK 소비자 0건) 복구**다. 재실측은 확인 측정이지 탐색이 아니다.
- **처리 (ACCEPT)**: alpha_package `challenge_flags`에 sweep-분류 가능성 + judge의 DSR 게이트 적용 판단 요청을 명시 플래그로 추가했다. n_trials = 10(재실측 전수) 기록. 최종 판단 권위 = judge.

## C2 [MEDIUM — REBUTTAL(근거 명시)] EW-uni 3.61은 자기-유사 벤치 낙관일 수 있다

- 제기: 보유 96%가 OTHER tier(시총 31위+)인 포트를 유동성필터 前 패널 동일가중 벤치와 비교하면, 벤치 구성이 포트와 유사해져 우위가 과장될 수 있다. 결측수익 종목 처리도 포트(0-fill)와 벤치(제외)가 비대칭.
- **반박 근거 (3축)**: ① 학술 — Harvey-Liu-Zhu(2016) 문헌-레벨 다중검정 hurdle은 cap-w 게이트 문턱(2.95) 자체에 포함된 보정이고, EW는 진단만. ② L-code/제도 — v8.3 SOT dual-basis mandate가 EW를 **비바인딩 진단**으로만 규정(canonical_screen_bt.R 주석: "HARD 게이트 basis는 cap-w 단일 권위 불변"), 본 WT의 모든 서술이 이를 준수("회수 확정" = screening-tier 라벨이지 자본 아님, cap-w 2.537 < 2.95 명기). ③ 정량 — 결측 비대칭은 진단에 하방(보수) 방향(계약 주석 실측), 그리고 cap-w basis 자체로도 p=.011로 재고 중 유일 2.5+.
- 잔여 리스크는 후속 forge(authoritative)가 흡수한다.

## C3 [MEDIUM — PARTIAL] IN03 커버리지 편향 — 월평균 221종목, 섹터 쏠림 미통제

- 제기: R&D 보고 기업만 신호 보유(월평균 221/유니버스 ~340) → 바이오/테크 쏠림 개연. 섹터 중립화 미실시 상태의 PORT_t는 섹터 베팅 혼입일 수 있다.
- **처리 (PARTIAL)**: 보완 — 07-09 원 run의 FMB/multifactor 분석이 존재(계약 산출물), 완전 분해는 risk 단계 위임이 역할 경계 정합. next_probe에 sector-neutral 재실측을 명시 등재. alpha_package `factor_specs.neutralization = "none"` 정직 기록.

## C4 [HIGH — PARTIAL] 재무 리프 vintage 리스크 — C4 xlsx Q4 경로 + restatement

- 제기: IN03은 분기 재무 파생(restatement_prone=TRUE). pit.md C4 주석의 "xlsx 경로 Q4 일률 +45d(≈익년 2/14)는 3/31 대비 공격적 — 수리 항목"에 노출될 수 있고, 07-26 메모리의 REPRT_MAP 뒤집힘 look-ahead 혐의(피해 0 판정 대기)와 동일 데이터 계통이다.
- **처리 (PARTIAL)**: self_pit_check verdict = `warn_restatement` + challenge_flags에 judge WARN_RESTATEMENT 입력 명시. lag1 스트레스/vintage-swap 통제는 forge 단계 실측 항목으로 지목(저장패널 동월 look-ahead 실사고 07-14의 검거 도구 = vintage-swap, placebo 아님).

## C5 [MEDIUM — 정직 라벨] 최근 구간 감쇠 — 2020-2026 IC 0.0082

- subperiod IC: 0.0242 / 0.0290 / 0.0082 — 부호는 전 구간 양수(stab 1.0)이나 최근 구간 크기 약화. EW post2017 t +1.615는 양수-비유의. "최근 유효성 확립"을 주장하지 않는다 — challenge_flags 기재 완료. cap-w oos_retention 원기록 -0.052는 decay-pattern이며 EW 근사 0.563과의 간극 = 벤치 미스매치 *개연*(확정 아님).

## C6 [기록] AX-001 mechanical rule 한계 자백

- ax001_conditional.R의 2/3 기계 판정이 3건에 DEFENSIVE_QUALIFIED를 발화했으나, 축별 실질 검토(crisis_alpha 부호·relief 물질성)에서 전부 기각했다. **기계 규칙과 최종 판정이 다른 3건 모두 근거를 alpha_validation.json `ax001_judgment_note`에 남겼다** — 판정 뒤집기가 아니라 규칙의 관대함(relief 0.3%p를 통과로 침) 교정. miscored 최종 0건.

## 자기합리화 자동검사

- 금칙 패턴(영향-미미류 / 관행-허용류 / 보수-면책류 / 결과-동일류 — pit.md 목록) 사용처 스캔 — 본문·산출물에서 판정 근거로 사용한 곳 없음. "보수(하방) 방향" 1회는 계약 주석의 실측 인용(비대칭 방향 명시)으로 합리화 아님.
- 종결 어휘 검사 — 산출물에 "소진/종결/dead-end/끝" 미사용. negative는 전부 config-scoped + next_probe 병기.

## Escalation 판정

- HIGH 2건(C1/C4) < 5, AX axiom hard FAIL 0, PIT C1(lockbox/lookahead) 위반 0 → **Q-Lead 자동 escalate 비발동**. 단 C1(sweep-DSR)·C4(vintage)는 judge 심사 필수 입력으로 플래그.

## 이 노트가 바꾼 것

1. alpha_package `challenge_flags`에 sweep-분류/DSR judge 판단 요청 플래그 추가 (C1 ACCEPT).
2. next_probe에 sector-neutral 재실측 추가 (C3).
3. forge 단계 vintage-swap/lag1 스트레스 실측 의무 지목 (C4).
