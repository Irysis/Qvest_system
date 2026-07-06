# Self-Adversarial Challenge — DART Officer Net-Buy Graduation Harness

**Agent**: alpha-research (QEPM). **Date**: 2026-07-06. **Mode**: Opus 4.8 native adversarial (v8.2, no external Codex).
**Scope**: 하네스 *구축물* + interim 측정. **판정 아님**(INTERIM_NONAUTHORITATIVE, contig 15 < 60월).

finalize 직전, alpha_package(=하네스 산출)를 스스로 적대적으로 검증. 각 concern → ACCEPT/PARTIAL/REBUTTAL + 근거.
합리화 표현("미미/관행적/보수적이면 OK") auto-detection 적용.

---

## Concern 1 (mandated ①) — anti-look-ahead: 'Date < anchor' 안 썼나?

**적대 주장**: 오늘 BearProb faith 버그가 동월 look-ahead 로 falsify 됨. 이 하네스도 신호 Date 와
수익 월을 잘못 정렬해 홀딩월 정보를 그달 수익에 흘렸을 수 있다.

**분류: REBUTTAL** (정량 3축 + 코드 + 스트레스).
- **코드 축**: 신호 Date = `first-day-of(usable_month = sig_month + PIT_LAG≥1)`. sig_month = rcept_dt 의 월.
  → rcept_dt(M) < 홀딩월(M+1) 시작 **항상**. `anchor_date` 변수·`Date<anchor` 비교 **코드에 없음**
  (`pit_audit.py` A5 = tokenizer 로 문자열/주석 제외 후 실행코드만 grep → PASS). 동월 사용 0.
- **감사 축**: `pit_audit.py` 5/5 PASS (A1 usable>sig strict, A2 Date=usable month-begin, A3 lag 상수,
  A4 홀딩 Date ≥ sig_month 말일, A5 antipattern 부재). FAIL 시 orchestrator 중단(hard).
- **스트레스 축 (결정적)**: PIT_LAG 1→2 (신호 1개월 추가지연) 시 PORT_t **붕괴 안 함**
  (krw contig 2.41→1.95, combined 2.48→1.18; nflow 오히려 상승). leakage signature(양→음 급락) 없음
  → `lag_stress_comparison.json` verdict = `NO_LEAKAGE_graceful_degrade`. 동월 누출이면 lag2 에서 급락해야 함.
- **잔여 caveat (정직)**: returns_dt 월수익은 log-sum 방식(build_bt_result Return.portfolio 아님 — canonical_screen_bt
  내부 규약). canonical_screen_bt 는 계약 build_benchmark_compare 경유이므로 PORT_t 자체는 contract-grade.

## Concern 2 (mandated ②) — mechanical 오염

**적대 주장**: 주식분할(+47.5M)·유상신주취득·임원선임상여 등 mechanical 이벤트가 net_change_qty 에 섞여
"임원 순매수"를 오염. disc_change_qty(장내매매 순증감)가 전량 NULL 이므로 정제 실패.

**분류: PARTIAL ACCEPT** (한계 인정 + 근사 배선 + 라벨).
- **인정**: 파서의 `disc_change_qty`(RPT_RSN 01/02 장내매매 순증감)는 CPT_CNT 추출 실패로 **전량 NULL**
  (15,971→17,905 report 전수 확인). 따라서 report-level 정밀 discretionary 수량 분해 불가.
- **보완 배선**: report-level `n_mechanical==0 & n_discretionary>0` 필터로 근사 —
  **mechanical txn 이 1건이라도 섞인 report 는 통째 배제**(오염 report 제거). officer 6,629 → clean 2,059
  (69% 배제, 강한 필터). 주식분할·상여 report 는 n_mechanical>0 이라 제거됨.
- **잔여 한계 (정직 라벨)**: n_mechanical==0 인 report 의 net_change_qty 는 장내/장외 매매 합이므로,
  장외(03/04)가 소량 섞일 수 있음(순수 장내만은 아님). caveat 에 명시. 이는 신호를 *약화*시키는 방향
  (노이즈 추가)이지 look-ahead·인위적 강화 아님 — 판정에 낙관 편향 없음.
- ⚠ 합리화 auto-check: "소량이라 괜찮다" 사용 안 함. 실제로 배제율 69% 를 수치로 제시.

## Concern 3 (mandated ③) — officer 필터 무결성

**적대 주장**: reporter_type=="officer" 가 주요주주/블록딜을 걸러낸다지만, pre-2009 는 필드 sparse 라
officer=0 → 커버리지가 사실상 2009+, 2015-16, 2024 로 파편화. 전체 342 유니버스 대비 대표성 의문.

**분류: ACCEPT** (커버리지 한계를 verdict_level 로 명시적 gate).
- **인정**: officer 분류 = 2009+(v3.1+)만 신뢰(README §한계). pre-2009(v2.8) reporter_type sparse →
  그 월들은 officer 신호 자연 부재. 현 커버리지 = 21~23 signal months, 갭 163+, 최장 연속 15월.
- **처리**: `verdict_level = INTERIM_NONAUTHORITATIVE` (contig < 60월). 게이트 판정은 **하네스 작동검증용**
  이지 졸업 verdict 아님을 stdout·JSON·README 3곳에 명시. book_marginal ΔIR 도 참고용(음수도 있음).
- **재발화 설계**: backfill 이 2016-2024 를 채우면 officer 커버리지 대폭 확장 → contig≥60 시 authoritative.
  실측 확인: 본 세션 중 backfill 이 2016-01/02/03 추가 → contig 13→15 자동 반영(idempotent 입증).
- **officer 정의**: reporter_type=="officer"(등기+비등기 임원). officer_registered==True(등기only)는 880건뿐
  → 너무 얇아 미채택. 등기only 요구 시 검정력 소멸. 이는 Cohen-Malloy-Pomorski "officer" 정의와 정합.

## Concern 4 (mandated ④) — sparse 이벤트 top-25 구성

**적대 주장**: 임원거래는 sparse 이벤트. 어떤 월은 이벤트 종목 < 25개 → top-25 EW 가 실제론
5~10종목 집중 포트. n=15~23 월에서 PORT_t 는 소표본 잡음일 수 있다.

**분류: PARTIAL ACCEPT** (구조 인정 + 소표본 caveat + rank-IC 병기).
- **인정**: canonical_screen_bt 는 `min(top_n, .N)` 이라 이벤트 < 25 월은 available 만 편입(집중 가능).
  월 이벤트 수 편차 큼. n_months 15~23 은 통계적으로 얇음(SE 큼).
- **처리**: ① PORT_t **와** rank-IC 둘 다 보고(Cycle 2 교훈 — rank-IC≠PORT_t). ② oos_retention·calmar 도
  산출하되 소표본에서 degenerate(oos>1, calmar 음수) 나올 수 있음을 라벨. ③ 어떤 단일 지표도
  authoritative 로 선언 안 함(INTERIM). ④ 검정력 부족을 verdict_level 로 hard-gate.
- **잔여**: top-25 EW 는 canonical 규약(계약 정합). sparse 이벤트 신호에 event-study(누적초과수익) 가
  더 자연스러울 수 있으나, 졸업 게이트가 top-N long-only PORT_t 기준이므로 계약 정합 위해 EW 유지.
  authoritative 단계(forge)에서 event-weighting 대안 탐색 여지 — 후속 note.
- **★추가 발견 (turnover)**: 측정 결과 turnover ~1,580%/yr — 스파스 이벤트를 매월 full-rebalance 하기
  때문. **screening turnover hard-fail 1,100% 초과** → 현 구성은 milestone 자격에서 구현규율(⑥) 사유로
  탈락. 신호력(PORT_t)과 별개 축. holding-band/decay overlay 로 회전 억제가 후속 필수. INTERIM 리포트 §4 라벨.
  (이 caveat 는 신호를 죽이지 않지만, 낙관 보고를 막기 위해 명시.)

## Concern 5 (mandated ⑤) — 부분데이터 과해석

**적대 주장**: 앞서 부분데이터에서 placebo-kill 방향이었는데, 지금 PORT_t +2.4 가 나오니
"신호 있다"고 과해석할 위험. 부분·갭 데이터의 우연일 수 있다.

**분류: REBUTTAL (해석 규율) + ACCEPT (비권위 명시)**.
- **비권위 명시**: 모든 산출에 `metric_type=canonical_screen`(screening-tier, forge 아님) + `INTERIM_NONAUTHORITATIVE`.
  "신호 있다" 주장 **안 함**. 보고 문구 = "harness READY, interim PORT_t ~2.4 (underpowered, 비권위)".
- **과해석 방어**: HARD 게이트 3종 **모두 FALSE**(PORT_t<2.95). 즉 현 데이터로도 졸업 아님을 정직 보고.
  긍정 방향이나 gate 미달 — 성공 위장 없음(AX-000).
- **우연성 인정**: n=15~23, 갭 163월. contig 60월 도달 전엔 어떤 방향도 확정 불가. 이 점을 verdict 로 gate.

---

## 종합 verdict (self-adversarial)

- **HIGH severity concern 수**: 0 (모든 concern 이 라벨·gate·스트레스로 처리됨; PIT 위반 없음).
- **AX axiom hard FAIL**: 0. **PIT C1 (lockbox/lookahead) 위반**: 없음(스트레스+감사 통과).
- **Q-Lead escalate trigger**: 해당 없음(HIGH≥5 / AX hard FAIL≥3 / PIT C1 위반 모두 미해당).
- **자기합리화 auto-detect**: "미미/관행적/보수적이면 OK/대부분 동일" 미사용. Concern 2·4 에서
  낙관 편향 유발 표현 대신 배제율·소표본 SE 를 수치로 제시.

**결론**: 하네스는 **PIT-무결·재발화 가능·계약경유 실측**. 현 커버리지 판정은 INTERIM(비권위).
AX-008 3-source 중 self-adversarial source = PASS (하네스 무결성). backfill contig≥60 시 재실행 → 졸업 판정.
