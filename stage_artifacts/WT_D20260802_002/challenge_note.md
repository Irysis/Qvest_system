# challenge_note.md — WT-D20260802_002 / FQ-084 Self-Adversarial Challenge

**규약**: v8.2 Self-Adversarial Challenge (Codex Round 대체). finalize 직전 자기 산출물을 적대적으로 검증하고, 각 concern 을 ACCEPT / PARTIAL / REBUTTAL 로 분류해 근거와 함께 기록한다 (Charter §8 No Silent Override). AX-008 3-source 중 1개.
**대상**: `qepm/mailbox/worktask/WT-D20260802_002/alpha_package.json` (게이트 A/B 판정 = config-scoped negative)
**실측 근거 파일**: `stage_artifacts/WT_D20260802_002/adversarial.json` · `arms_results.json` · `diagnostics.json`

---

## 자기 비평 제기 (7건) 및 처리

### C1. 분모 컨벤션 오염 — Close(수정주가) × Vol(원 거래량)
**비평**: 게이트 `FA_share = Σ|Foreign_KRW| / Σ(Close×Vol)` 의 분자는 실제 거래대금(원)이고 분모는 *수정주가* × 거래량이다. 액면분할·병합 종목에서 분모가 체계적으로 틀어져 게이트 순위가 오염될 수 있다.
**분류: PARTIAL (인정, 결론 불변)**
**보완 실측**: `fa_share` 를 `adv`(정본 20d 평균거래대금, liqf) 에 대해 월별 횡단 잔차화한 게이트를 재측정 → PORT_t **2.645** (원판 게이트 2.198 / base 3.478). 분모 편향을 제거하면 손해가 다소 완화되나 base 대비 열위는 유지. sanity: 2026-03 표본에서 `tv/20` vs `adv` 상관 0.983.
**남는 한계**: 분할-이벤트 종목의 개별 오염은 제거되지 않았다. 다만 결론(개선 없음)은 두 분모 모두에서 동일.

### C2. 구성타당도 — |순매수| 는 '참여'가 아니라 '순불균형'
**비평**: 가설은 "정보를 옮길 거래주체가 *존재*하는가"를 묻는데, 측정한 것은 순매수 불균형의 크기다. 외국인이 대량 매매하되 매수·매도가 상쇄되는 종목은 '활동 없음'으로 잘못 분류된다. `investor_wide` 에는 gross 매수/매도가 없고 net 만 있다.
**분류: ACCEPT — 그리고 이 인정이 가설의 전제 자체를 무너뜨린다**
**보완 실측**: 참여의 직접 지표인 `fa_breadth`(직전 3개월 중 외국인 순매수 ≠ 0 인 거래일 비율)를 산출 → **94.3% 의 종목-월에서 정확히 1.000**, 5분위수 0.984. 즉 **배포 유니버스(K200∪KQ150 ∩ 유동성 2e8)에는 '외국인이 거래하지 않는 종목'이 사실상 존재하지 않는다.**
**귀결**: 가설의 전제("외국인 활동이 희박한 종목에서는 신호가 실현되지 않는다")는 이 유니버스에서 **공집합 위에 서 있다**. 본 라운드가 실제로 검정한 것은 '참여 유무'가 아니라 '순불균형 강도'이며, 패키지의 `factor_specs[1].proxy` 명칭과 hypothesis statement 는 이 정정을 반영해 읽어야 한다.
**자기합리화 점검**: "그래도 강도가 참여의 대리변수니 괜찮다" 로 넘어가려는 충동이 있었다 — 금칙 패턴("보수적이면 OK")에 해당하므로 기각하고, 전제 무효를 verdict 본문(`alpha_validation.json::adversarial.C2`)에 명기했다.

### C3. 음성 결과가 우연 아닌가 (단일 경로 268개월, holdout 없음)
**분류: REBUTTAL (근거 제시)**
**근거**: 무작위 50% 축소 20 draw 귀무분포 — mean 3.481 / sd 0.546 / **min 2.488**. B_gate = **2.198 은 20개 draw 전부보다 낮다** (n≤ = 0/20, 단측 p ≤ 0.048). 즉 '유니버스를 절반으로 줄이면 무엇이든 나빠진다'로 설명되지 않는 능동적 손상. 추가로 paired 월간 차분 NW lag-3 t = **-1.95**, dual-basis(cap-w 3.478→2.198 / EW-uni 4.218→2.175) 가 동일 방향.
**학술 인용**: 다중검정 하 hurdle 은 Harvey-Liu-Zhu(2016). 본 건은 양성 주장이 아니라 사전등록 필요조건의 반증이므로 hurdle 초과 요구 대상이 아니며, DSR 은 n_trials=1 에서 1.0 으로 축퇴(정보량 0)임을 정직 표기했다.

### C4. ★ IC 사분위 기울기가 cap-tier(size) 효과의 재표현 아닌가
**비평**: 내가 제시한 기전("알파는 외국인 소외 구간에 국소화")의 유일한 근거는 활동 사분위별 rank-IC 단조 감소(Q1 0.0518 → Q4 0.0370)다. 그런데 게이트 변수는 Size 와 Spearman +0.328 이고, 이 시스템에는 **알파가 소형 tier 에 국소화된다는 기존 실측(cap-tier 트랩)** 이 이미 있다. 그렇다면 이 기울기는 size 를 다시 그린 것에 불과할 수 있다.
**분류: ACCEPT — 기전 주장 강등**
**보완 실측**: size 5분위 × 활동 반분 이중정렬. 월별 (저활동 IC − 고활동 IC) gap = **+0.0087, NW lag-3 t = +1.11 (비유의)**, 그리고 최소 size 분위(sz_q=1)에서는 gap 이 **-0.0073 으로 부호 역전**.
**귀결**: 원시 사분위 기울기의 상당분은 size 효과이며, **"알파가 외국인 소외 구간에 국소화된다"는 나의 기전 설명은 size 통제 후 지지되지 않는다.** 패키지에서 이 주장을 서술적 관찰로 강등하고, 기전 귀속은 **미해결(open)** 로 표기했다.
**남는 사실**: 포트폴리오 수준의 손해는 견고하다 — size 5분위 내 게이트(E_gate_sizeneut) 도 2.425 로 placebo min 2.488 아래. 즉 *손해는 실재하나 그 원인은 아직 설명되지 않았다*. 이 둘을 섞어 쓰지 않도록 분리 서술했다.

### C5. 역-게이트(저활동 국소화)를 성과로 보고하려는 유혹
**비평**: B_gate_low 가 3.869 로 base 3.478 보다 높다. 이걸 "역방향으로는 개선"이라 쓰면 라운드가 양성으로 보인다.
**분류: ACCEPT (자기 차단)**
**근거**: 3.869 는 placebo 분포의 q50 3.576 ~ q95 4.315 **사이** — 무작위 절반 축소와 구분 불가. paired NW t = +1.44 (비유의). 사전등록에도 없던 방향이므로 채택 시 사후선택(argmax)이 되어 selection_type 이 chain→sweep 으로 재분류되고 DSR HARD 가 걸린다. **개선 아님으로 확정 보고**하고, 별도 사전등록 WT 로만 재도전 가능하도록 `next_probe` NP-1 에 조건을 명시했다.

### C6. 역할 카드 위반 은폐 위험 — discovery WT 인데 상속 상관 1.0
**분류: ACCEPT (선제 신고)**
**근거**: request 가 "base 신호를 새로 만들지 말 것"을 명시했으므로 `alpha_inheritance_cor = 1.0` 은 설계 준수의 결과다. 그러나 role card 상 discovery 는 `<0.95` 를 certificate 요건으로 하므로 **alpha_discovery_certificate 발급 자격 없음**. 숨기지 않고 `challenge_flags CF-02` + `governance_log` 의 `reclassify_proposal` 로 명시 신고했다. `alpha_discovery_count = 0` 으로 정직 표기.

### C7. 범위 과대 인용 위험 — 논문 원안의 절반만 검정
**분류: ACCEPT**
**근거**: 논문(Jeong-Eo-Kang, Pacific-Basin Finance Journal)의 net arbitrage 는 **외국인 ∧ 공매도** 결합이다. `F1_short_interest_lending` 실파일 0건(KRX OPEN API 404 / MDC 로그인 게이트)이라 공매도 축은 미검정. 본 결과를 "논문 반증"으로 승계하지 못하도록 `scope_limitation` + FQ-084 `scope_note` 양쪽에 기록했다.

---

## 자기합리화 auto-detection (금칙어 자가검사)

금칙 표현의 정본 목록은 `.claude/rules/pit.md` 「금지 표현」절 + `.claude/rules/answer-principles.md` 「회피 표현 grep」절에 있다. 아래는 **번호로만 지칭**한다 — 문자열을 여기 재현하면 `rationalization_detector` 훅이 인용과 실사용을 구분하지 못해 오탐이 발생함을 실측했다(본 파일 1차 저장 시 발화).

| 금칙 항목 | 사용 여부 | 처리 |
|---|---|---|
| pit.md 금지표현 #1 (규모 축소형) | 미사용 | — |
| pit.md 금지표현 #2 (관례 원용형) | 미사용 | — |
| pit.md 금지표현 #3 (하방 안전 원용형) | **C2 서술에서 쓰려던 충동 포착** | 기각 → 전제 무효를 정면 기록 |
| pit.md 금지표현 #5 (결과 동질 주장형) | 미사용 — C1 은 두 분모의 수치를 모두 명기(2.645 / 2.198) | — |
| pit.md 금지표현 #6 (사전 반영 단정형) | **C4 기전 서술에서 쓰려던 표현** | 정량 이중정렬로 대체, gap NW t = +1.11 비유의 명기 |

---

## 판정 요약

- **HIGH severity concern**: 2건 (C2 전제 무효 / C4 기전 강등) — 둘 다 **ACCEPT 하여 산출물을 수정**했다. 결론(게이트 = 손해)은 두 수정 후에도 불변.
- **AX 공리 hard FAIL**: 0건. **PIT C1 (lockbox·lookahead) 위반**: 0건 (파일 vintage 3종 일치, 게이트 창이 홀딩월 이전 종료, lag1 스트레스 병행).
- **Q-Lead 자동 escalate trigger**: 미발화 (HIGH ≥ 5 아님 / AX hard FAIL ≥ 3 아님 / PIT C1 위반 없음). 단 C2 는 **가설 전제가 유니버스에서 공집합**이라는 성질상 Q-Lead 인지 필요 — 최종 보고 본문에 최상단 배치.
- **AX-008 triangulation**: self-adversarial = 1 source (본 문서). 나머지 2 source(forge 실측 / architect 진단)는 downstream 단계 소관 — 본 라운드는 forge 진입 없음(negative).

## 산출물 수정 이력 (이 challenge 의 결과)

1. `alpha_package.json::hypothesis.statement` 에 "실측 결과 방향까지 반증" 명기
2. `alpha_validation.json::adversarial.C2` 신설 — breadth 94.3% 포화로 전제 무효 기록
3. `alpha_validation.json::adversarial.C7` 신설 — 기전 주장 ACCEPTED_MECHANISM_CLAIM_DOWNGRADED
4. `ab_test_results.ic_by_foreign_activity_quartile.interpretation` 의 기전 단정을 서술적 관찰로 강등 + size 통제 결과 병기
5. `challenge_flags` CF-02(role card) · CF-05(parity false) · CF-07(AST 경계차) 선제 신고
6. AST 정본을 const-free 표현으로 교체 (verifier 갭 발견 → 회피가 아니라 더 단순한 등가 표현으로 이동 + 갭 별도 보고)
