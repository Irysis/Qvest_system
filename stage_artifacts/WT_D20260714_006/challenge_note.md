# R30 (FQ-045) Self-Adversarial Challenge — challenge_note

**규약**: v8.2 자체 적대검증(Opus 4.8, 외부 Codex 없음). finalize 직전 약점 ≥3 자가제기 → ACCEPT/PARTIAL/REBUTTAL 분류 + 근거 + 합리화 자기검증. Charter §8 No Silent Override.

**맥락**: Branch B2(non-mega value slotting)가 R29 unconditional(paired 1.243, FAIL)을 넘어 cap-w screening AND-게이트를 관통(paired 2.378·ΔIR 0.232). **positive 결과는 적대검증을 더 엄격히 받는다** — cap-tier 국소화 prior가 "cap-w 탈출 불가"를 양측증명한 상태에서 게이트 관통 주장이므로.

---

## Concern 1 [ACCEPT] — B2 게이트 관통은 IS/pre-2017 견인, holdout marginal은 flat/negative
**제기**: paired_full 2.378은 통과이나 (a) **holdout dIR = −0.022**(2024-07+), (b) paired_HO 1.170 < 2.0, (c) post2017_t 1.734 < 2.0, (d) variant 절대 cap-w oos_v2 0.452 < 0.5. 즉 full-period 관통이 pre-2017 + mid-period에 실려 있고, 가장 최근 2년의 value marginal은 사실상 사라졌다. "AND-게이트 PASS"를 헤드라인으로 쓰면 recency 감쇠를 은폐한다.

**분류: ACCEPT (framing 교정).** graduation HARD(oos_retention 0.7·holdout falsification)는 forge-authoritative 값에만 적용되는 자본 게이트이고, B2는 그 계층에 도달하지 못한다. → 판정을 **"screening-tier config-scoped positive (full-period), 단 최근 marginal 감쇠"**로 명시하고 자본 NO-GO를 못박음. verdict/validation 전면에 dIR_ho −0.022 병기. **자본 주장 금지**.
**합리화 자기검증**: "관행적/보수적이면 OK" 미사용. paired-diff oos_v2 2.326을 근거로 "OOS robust"라 주장하고 싶은 유혹 → **거부**: 그 지표의 마지막 split(~2021)은 강한 2021-22를 포함하므로 명시적 2024-26 holdout(dIR −0.022)과 다르다. 두 지표 병기하고 recency 감쇠를 실재로 인정.

## Concern 2 [PARTIAL] — value_quality_spread 압축(0.175 pct) = holdout 양성이 소진된 되돌림의 후행 관측일 가능성
**제기**: 스프레드가 06-24 '사상최대'에서 백분위 0.175로 크게 압축 = value reversion 상당분이 이미 실현됨. B2/pure-value의 clean holdout 양성이 그 되돌림의 *꼬리*(후행 관측)라면, forward value 기대는 하향이고 지금 게이트 관통을 자본 신호로 읽으면 늦은-사이클에 진입하는 것.

**분류: PARTIAL.** 인정: 스프레드 압축은 forward 하향 리스크이고 Concern 1의 holdout 감쇠(dIR −0.022)·pure-value post17 1.39와 방향 정합 — 강화 증거. 부분 반박: placebo p=0.000·lag1 2.473은 신호가 *과거에 실재*했음을 입증(우연/look-ahead 아님); 스프레드는 forward EV를 낮추나 신호 존재 자체를 반증하지 않는다. → 판정은 "신호 실재하되 forward EV 하향(늦은-사이클)"로 이중 라벨. next_probe P3(recency 감쇠 판별 + monitoring tripwire)로 배관.
**합리화 자기검증**: 스프레드를 타이밍 신호로 쓰고 싶은 유혹(활성화 조건) → **금지 준수**(factor-of-factors NULL·regime FALSIFIED·시장타이밍 4중부정). 스프레드는 리스크 맥락으로만 사용, 사전동결 준수.

## Concern 3 [ACCEPT] — Branch A EW-상대 트랙의 실투자 불가능성 + pure-value redundancy
**제기**: (a) EW-유니버스 벤치 상대 트랙은 실투자 mandate 벤치가 EW가 아니므로 프레임 전용 채점 — "3호 후보 자격"이 실계좌 트랙을 정당화하지 못함(D3 §3 동일). (b) pure-value EW active-corr 0.50 with 기존 P-pure track > V02_EP 0.34(D3서 redundancy로 독립 불채택) → 독립 트랙 근거 더 약함.

**분류: ACCEPT.** → Branch A 판정 = "pure-value EW = band-조건부 신호 확인이나 **독립 페이퍼트래킹 3호 부적격(P-pure 중복)**". Z6 blend EW는 book-duplicate로 standalone 무의미 명시. active-corr 0.50은 basis-mixed proxy(EW-uni active vs cap-wBM P-pure active)임을 정직 라벨 — 정밀치는 아니나 redundancy 방향은 견고(overlap 19.5% + corr 0.50 둘 다 V02_EP 초과).
**합리화 자기검증**: "EWuni 6.39 강하니 트랙 열자" 유혹 → **거부**: 6.39는 Z6=book+value(book-duplicate)이고, 순수 value 기여는 3.75이며 그마저 P-pure 중복. 강한 헤드라인 수치로 약한 독립성을 덮지 않음.

## Concern 4 [PARTIAL] — B2 marginal이 OTHER(소형) tier·소가중(wMID 0.062) tail 선택변화의 증폭
**제기**: B1(MID-only) FAIL·B2(OTHER 포함) PASS = 게이트 관통을 OTHER(31+, 소형가치)가 견인. 그러나 cap-w top-25에서 non-mega 명목가중은 작다(wMID 0.062). marginal이 top-25 경계의 소가중 종목 교체에서 나온다면 (a)capacity/구현성 취약 (b)소가중 tail의 통계적 불안정 우려.

**분류: PARTIAL.** 인정: 소가중 tail 증폭은 구현·강건성 리스크 — next_probe P2(OTHER liq/capacity 필터 + tier-cut 민감도)로 정면 검증 배관. 부분 반박: 배포 유니버스 제약(liq 2e8·top-25)은 mk_capw에 이미 적용되어 OTHER 종목도 유동성 통과분만 선택; placebo가 소가중에도 신호 실재 확인(null max 1.10). → "실재하나 구현성 미검증"으로 라벨.
**합리화 자기검증**: 제약을 실패의 원인으로 귀속하지 않음(AX-000 따름정리·INV-7). 소가중은 cap-w 구조의 고정 축이지 레버 아님 — 봉투 안 검증(P2)으로.

## Concern 5 [REBUTTAL] — B2가 R29 unconditional과 사실상 같은데 base=off0 clean이 맞나(vintage 재발 우려)
**제기**: R29에서 look-ahead base가 value marginal을 ~2배 증폭했다. B2 2.378이 또 vintage 아티팩트면?

**분류: REBUTTAL (명시 근거).** (1) **base = 0_stored_S7 = production_parity_verified**(clean panel meta: score_vs_recon max_abs_diff 0·cor 1·prod code spearman 0.975~0.997, off0 T-1). §7b 준수. (2) **value = vz_off0**(R29 확정 T-1 clean, factor_db cor 1.0). (3) **lag1 = 2.473**(value 1개월 shift에도 생존) = 동월 look-ahead 부재(R29/faith 사건의 판별기 통과). (4) base cap-w PORT_t 3.058 = R28/R29 clean 재현치 정확 일치. → B2의 base·value 양측 clean 확정, vintage 아티팩트 아님. R29 unconditional(1.243)과의 차이는 vintage가 아니라 **tier-조건부 구성**(mega value 미적용)에서 온다.
**합리화 자기검증**: parity 라벨을 신뢰하되 lag1 스트레스로 독립 확인 — "이미 검증됨" 단정 대신 실측 판별기 통과 명시.

---

## Q-Lead escalate trigger 점검
- HIGH severity ≥5? → 아니오(ACCEPT 2·PARTIAL 2·REBUTTAL 1, 자본 주장 없음).
- AX axiom hard FAIL ≥3? → 아니오.
- PIT C1(lockbox·lookahead) 위반? → 아니오(base·value clean 확정, lag1 통과).
→ **자동 escalate 미발동.** 단 B2 positive는 도훈 결정 재료로 상신(forge dossier 착수 여부 = 도훈 우선순위).

## AX-008 Verification Triangulation
self-adversarial(본 note) = 3-source 중 1. Branch B2 positive는 **forge(build_bt_result authoritative) + architect(구현성/tier-cut) 중 1개 추가 PASS 필요**(2/3) — 현재 screening만이므로 자본 판정 미성립. next_probe P1이 그 배관.
