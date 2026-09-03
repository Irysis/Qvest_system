# Self-Adversarial Challenge — alpha 구간 (WT-R20260829_005)

작성: alpha-research · 2026-08-29 · 축 = combination (5/20) · 규율 = **단일 실투형 후보 1건**(도훈 지시 2026-08-29)
분류 규약: ACCEPT(명백한 위반 → 스펙 수정) / PARTIAL(부분 인정 → 보완) / REBUTTAL(학술 1+ · L-code 1+ · 정량 3축)

| ID | 축 | 제기 | 분류 |
|---|---|---|---|
| AC-1 | FAL-1 판정의 자기무결성 | price-lagged ME 자체가 별개 팩터라 상관 소멸이 당연한 것 아닌가 | **REBUTTAL** |
| AC-2 | 재포장 | 좌표가 선행 2건보다 낮다 — 진전이 아니라 열화 아닌가 | **ACCEPT** |
| AC-3 | 교란 미분리 | cap-tier OTHER 92.7% 인데 무신호 대조가 없다 | **ACCEPT** |
| AC-4 | 검정력 | ratio 0.166 · 검정력 6.8% 에서 어떤 성과 서술도 가능한가 | **ACCEPT** |
| AC-5 | PIT 계기 | detect_lookahead 가 clean 이 아니다 | **PARTIAL** |
| AC-6 | 논문 미준수 | 논문은 3분위 시총가중 + 랭크가중 zero-cost 인데 우리는 pct-rank top-25 EW | **PARTIAL** |
| AC-7 | 배포성 | as_of 2026-07-31 — 최신월(2026-08)이 아니다 | **PARTIAL** |
| AC-8 | 설계 승계 | axis_A/axis_B 를 실행하지 않고 패키지를 냈다 | **PARTIAL** |

---

## AC-1 — REBUTTAL (FAL-1 판정은 자기무결적이다)

**제기**: `bm_b = BE/ME_{t-14}` 는 14개월 묵은 시가총액을 쓰므로 `bm_a` 와 다른 팩터다. 다른 팩터가 momentum 과
다른 상관을 갖는 건 당연하고, 그걸 "구성 아티팩트" 판정 근거로 쓰는 건 순환 아닌가.

**반박 근거 3축**:
1. **학술**: AMP2013 p.936 원문이 이 대조를 스스로 제시한다 — *"When using more recent prices in the value measure,
   the negative correlation between value and momentum is more negative and the value premium is slightly reduced."*
   즉 두 사양의 차이가 곧 음상관의 가격-공유 성분이라는 것이 **저자의 진술**이고, 본 검정은 그 진술의 KR 실측이다.
   원문 PDF 직접 판독으로 재확인했다(§I.B, 본 라운드 step0_A).
2. **L-code**: `L-AR-20260822_215840`(FQ-234 통제 사양) — 전 구간 상관이 0 이어도 절단면에서 되살아나는 전례가 있어
   **절단면 병기**를 의무화했다. 본 검정은 그 규약을 지켰고(연도별 20행 + 분위 양끝 6절단면), 절단면에서 부호가
   **더 강하게** 뒤집힌다(value D1 rho_b +0.413 · D10 +0.343 · 중간 D4~D7 +0.419). 전 구간 하나로 접지 않았다.
3. **정량 3축**: ①시점 비공유 실증 — `ME_{t-14}` 는 t-14 종가까지만 담고 momentum 6-1 형성창은 t-2..t-7 이라
   **공유 가격관측치 0**이다(12-1 사양도 t-2..t-13 로 1개월 여유). ②자체계산 `bm_a` 가 권위 경로 `V01_BM` 을
   재현한다 — 월별 순위상관 **중앙값 1.0000 · 평균 0.9992 · p10 1.0000(259개월)**. 즉 분해 대상이 실제 생산 팩터다.
   ③`bm_b` 는 무력한 잔재가 아니라 **더 강한 standalone 팩터**다 — 랭크가중 zero-cost gross SR
   `bm_b 0.380 > bm_a 0.197`. 논문의 "value premium is slightly reduced [with recent prices]" 와 방향이 같다.
   죽은 변수라서 상관이 사라진 게 아니다.

⇒ 순환 아님. **다만 완화 불가 잔여**: 14개월이라는 lag 길이는 "두 신호가 가격을 공유하지 않는 최소 거리" 로 고른
선언값이며 논문에 크기 근거가 없다(설계 SAC-3 과 같은 계열의 약점). 사후에 옮기지 않았다.

## AC-2 — ACCEPT (열화를 열화로 신고한다)

본 후보의 좌표는 선행 2건보다 **낮다**: CAGR 13.42% vs 20.1~20.8% · SR(총수익) 0.619 vs 0.799~0.825 ·
Calmar 0.253 vs 0.331~0.344 · OOS retention 중앙값 **−0.561** vs 0.757. `mandatory_prior_run_disclosure` 에
그대로 실었고 `self_report_repackaging.verdict` 에 "성과 축에서 새 발견 없음"을 명시했다.
**결합이 기저를 개선했다는 주장을 하지 않는다.** 본 라운드의 산출 가치는 FAL-1 과 권위 경로 좌표뿐이다.

## AC-3 — ACCEPT (분리 실패를 결과에 못박는다)

보유 비중의 **92.7% 가 OTHER tier**(MEGA top-10·MID 11-30 외)다. 2/20 의 91.2% 와 같은 자리다.
무신호 대조는 지시로 취소돼 이번엔 **소형주 노출과 신호를 분리하지 못했다**. 이를 challenge_flags 에 HIGH 로 올렸고,
어떤 양(+) 좌표도 "신호 기여"로 서술하지 않았다. β-통제 α +5.78%/yr(t 1.792)는 시장 노출만 통제한 값이며
size 노출은 통제되지 않았다 — 이 구분을 하류가 놓치지 않도록 diagnostics 에 라벨했다.

## AC-4 — ACCEPT (성과 축은 '미결'로만 처분한다)

Step 0 (C): ratio 0.166 · 기대 t 0.466 · **검정력 6.75%**. 착수금지선(0.15)은 넘겼으나 조건부 구간이고
미결이 최빈 결말이다. **미결일 때 이 라운드가 남기는 것**을 사전에 적어 둔다:
①FAL-1 전제 기각(결정적) ②재사용 가능한 259개월 결합 패널 + α̂ 벡터 ③선행 2건에 없던 권위 경로 좌표
④도달가능성 갱신(PORT_t 1.196 · 활성 net +4.25%/yr · 이 창에서 PORT_t 2.95 에 필요한 활성 = +10.47%/yr) ⑤6/20 표적(C5 잔차화)의 근거.

## AC-5 — PARTIAL (계기를 피해 쓰지 않았다)

`detect_lookahead` 가 `s4_candidate.R` 2건(C1)을 잡았다. 실체는 **실현 net 수익의 사후 보고 통계**
(총수익 SR·연변동성·활성 SR)이고 신호·선택·비중 어디에도 되먹임되지 않는다 — 신호 경로(`s1_panel.R`·`s5_alpha.R`)는
둘 다 clean 이다. **양성 대조**: 같은 패턴이 권위 계약 파일 자신에서도 발화한다
(`canonical_screen_bt.R` 1건 = line 376 `net_sr <- mean(active)/stats::sd(active)*sqrt(...)` ·
`backtest_result_contract.R` 2건). 즉 정규식이 '사후 보고 SR' 과 '전표본 변동성으로 신호를 만든 것' 을 구분 못 한다.
**패턴을 회피하도록 코드를 고치지 않았다** — 계기를 피해 쓰는 것이 계기를 죽이는 방법이기 때문이다.
사실 그대로 기록하고 하네스 수리 대상으로 넘긴다.

★같은 계열의 두 번째 건: `ast_verify.py` 초판이 K200/KQ150 멤버십을 FAIL_LOOKAHEAD 로 잡았다. 원인은 코드가 아니라
`decision_ts` 라벨이 실제 편성시점보다 하루 일렀던 것이다(점수 = 월말 t, 편성 = 홀딩월 t+1 시작).
`decision_ts = t+1` 로 정정했고 그로써 허용되는 자료는 여전히 t 이하뿐이다. **정정 사실과 초판 판정을 함께 기록**했다 —
게이트를 통과시키려고 라벨을 옮긴 것으로 읽히지 않게.

## AC-6 — PARTIAL (형태 차를 숨기지 않는다)

논문은 ①3분위 정렬 후 시총가중 ②랭크가중 zero-cost 롱숏 ③수익수준 50/50 블렌드다. 본 후보는
①시장-내 pct-rank ②pooled top-25 ③EW ④점수수준 결합이다. 형태 차가 4곳이고 그 이유는 고정 축(롱온리·≤25종·Σw=1)이다.
**논문 준수라고 주장하지 않는다** — 패키지는 이를 "AMP2013 의 KR 이식"이 아니라 "두 팩터의 동일가중 랭크결합"으로
서술하도록 challenge_flags 에 못박았다. 논문 basis(랭크가중 zero-cost)는 FAL-1 전제검정에서만 쓰였고
그 층은 성과 판정에 입력되지 않는다.

## AC-7 — PARTIAL (as_of 한 달 stale)

`as_of = 2026-07-31` 이다. forward 수익 패널의 종점이 그달이라 유동성 자(20일 평균 거래대금 t-1)의 앵커가 거기서 끝난다.
2026-08 신호는 팩터 DB(2026-08)에 존재하나 본 라운드는 **측정 창과 배포 벡터의 as_of 를 일치**시켰다.
하류가 최신월 벡터를 필요로 하면 `alpha_scores.parquet` 재산출로 1개월 전진 가능하다(스펙 변경 불요).

## AC-8 — PARTIAL (미실행을 미실행으로 기록했다)

설계의 `preregistered_primary.axis_A/axis_B` 는 **대조 arm 을 전제로 정의된 검정**이라 단일 후보 규율 아래서는
정의 자체가 성립하지 않는다. 문구를 고치지 않고(No Silent Override)
`status = "NOT_TESTABLE_UNDER_SINGLE_CANDIDATE_DISCIPLINE"` 로 남겼다 — 사후 축 교체가 아니라 **미실행 신고**다.
설계에 결함이 있다고 주장하지 않는다. 규율이 바뀌었을 뿐이고, 그 사실은 `discipline_change_2026_08_29` 에 있다.

---

## 합리화 어휘 자기검증

"미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일 / 이미 반영되어 있었을 것 /
백테스트 기간이 충분히 길어서 상쇄" — 사용 **0건**. auto RE-VIEW 미발동.

## Q-Lead escalate 판정

- HIGH severity: **4건**(FAL-1 전제 붕괴 · 검정력 6.8% · OOS retention 음수 · cap-tier 미분리) < 5 → 자동 escalate 미발동
- AX axiom hard FAIL: 0
- PIT C1(lookahead) 위반: **0** (계기 발화 2건은 사후 보고 통계이며 신호 경로 clean · ast_verify LOOKAHEAD 0)

⇒ 자동 escalate 불발동. 단 **체인 완주 의무**(도훈 2026-08-29)에 따라 음성 판정과 무관하게
risk → optimizer → forge 로 넘긴다. 패키지는 결측 없이 완결돼 있다.

---

## 부기 — 본 에이전트 밖 파일 변경 1건 (자기신고)

`06_Registry/ast_structure_log.jsonl` 에 6행이 추가됐다. 본 에이전트가 쓴 것이 아니라
`canonical_screen_bt()` 의 AST Step 4 사이드카가 호출 시 append 하는 계약 내부 동작이다(append-only 원장).
그 외 005 mailbox 와 `stage_artifacts/WT_R20260829_005/` 밖 쓰기는 없다 —
`.claude/skills/reinforce/SKILL.md` · WT-R20260829_004/006/007 산출물은 병렬 세션의 것이며 본 에이전트는 접근하지 않았다.
