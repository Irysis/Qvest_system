# Challenge Note — WT-D20260822_005 · alpha-hypothesis 구간 (v8.2 Self-Adversarial)

- **작성**: alpha-hypothesis (model: fable), 2026-08-22, finalize 직전
- **범위**: 설계 축만 (①메커니즘 사후서술 여부 / ②반증조건 위장 여부 / ③국면 경계 도출 여부 / ④settled-negative 재포장 여부)
- **후속**: alpha-research는 본 파일에 자기 구간 섹션을 **append** (overwrite 금지)

## 자가 제기 약점 5건 + 분류

### W1. 성분 귀속이 비통제 형제-대조 추론이다 — **PARTIAL**
"모멘텀 축이 드라이버"의 근거는 형제 run 2건(1055313 port_t 0.539 / 1055314 port_t 0.597)과 풀 복합(2.523)의 대조인데, 형제들은 성분 구성·개수가 달라 **통제 비교가 아니다**. 모멘텀 축이 아니라 "6축이라는 특정 결합 자체" 또는 ladder-선택 아티팩트일 가능성이 남는다.
**처분**: 수용하되 설계 안에 흡수 — F4(정제 3축 IS canonical PORT_t < 2.0 시 귀속 기각)를 반증 조건으로 명문화했고, ablation 실측을 alpha-research 선결 과제(open question ①)로 이관. 가설은 이 추론이 틀리면 기각되도록 짜여 있다.

### W2. 국면 경계가 사후 데이터 관찰이다 — **PARTIAL (가장 약한 가정)**
regime_scope의 RISK_ON/CRISIS 경계는 ip_20260817 국면별 실측(RISK_ON IR +0.958 / CRISIS −0.879)을 **열람한 후** 서술됐다. "기전에서 도출했다"고 쓰지만 실측이 서술을 유도했을 사후성 리스크가 실재한다.
**반론 일부**: 모멘텀 크래시·위기 청산-압도는 이 실측과 독립적으로 문헌·선행 라운드(DFA 아크, momentum crash)에서 예측되는 경계다 — 실측은 경계의 확인이지 발생기가 아니다.
**처분**: 부분 수용 — 사후성 리스크를 alpha_hypothesis.json challenge_flags에 명시했고, F3(회복 전환 월 junk-rally 패턴이라는 **독립 부수 관측**)를 반증 조건으로 걸어 경계 논리가 실측 동어반복이 되지 않게 했다. F3가 기각되면 경계 도출 논리 자체를 재설계한다.

### W3. 반증 조건 F4는 성과 동어반복에 가깝다 — **ACCEPT (완화 조치 포함)**
F4(canonical PORT_t < 2.0 기각)는 성과 지표 기반이라 AST v1.1 "성과 동어반복 금지"의 경계선에 있다.
**처분**: 수용 — F4를 단독 무효로 명시 라벨하고("단독으로는 무효, F1~F3와 병용"), 기전 반증의 본체는 field_dictionary 리프 기반 부수 관측 3건(F1 개인-마찰/A6, F2 실적-경유/FDB-B3, F3 크래시 귀속/A1·E3)에 둔다. F4는 성능 반증이 아니라 **성분-귀속 주장**의 반증으로 한정 서술했다.

### W4. settled-negative 재포장 아닌가 — **REBUTTAL**
quality/momentum long-only는 DIST-QPM-003/006 실패 계열이고, factor DB 331 전수 book-marginal 통과 0이며, "신규 standalone 평균-표적 팩터 사냥"은 최후순위다.
**반론**: ① DIST-QPM-003/006의 실패 scope는 **single-signal** long-only — multi-axis composite는 그 카드들의 명시 EXCLUSION lane이다. ② 본 라운드는 신규 팩터 사냥이 아니라 screen 통과 실측(2.523)이 있는 재료의 **paper_promotion + 비-ML 결합 정제**로, v8.4가 2026-08-22 재분류한 "결합 마디 = 측정된 적 없는 축"의 재진입 순서 ①(비-ML 결합 사전등록 비교)과 정합한다. ③ hypothesis_index lookup에서 동일 config의 settled-negative 부재 확인(형제 F는 **다른** 구성의 실패로, 오히려 본 가설의 대조군). 재포장 아님.

### W5. oos_retention −0.191의 원인 진단이 브리핑과 다르다 — **REBUTTAL + 정직 기록**
과제 브리핑은 "6요소 계수가 IS에서 최적화됨"을 과적합 원인으로 제시했으나, **equal-weight 복합엔 적합 계수가 없다**. 실측 가능한 원인은 (a) ladder 형제 중 IS-성과 생존 선택(selection-level), (b) cohort-wide post-2017 decay(FMT-07: active SR pre-2017 +1.10 → post-2017 −0.18). (b)가 주원인이면 6→3 정제로 oos는 회복되지 않는다 — dual-basis(EW-유니버스) 재판정을 선결로 걸었다(open question ②).
동일 계통 정정: 브리핑의 "stress outperform 3/3 → defense의 국면 조건부 기여" 서술은 월간 국면 해상도 실측(CRISIS active IR −0.879)과 상반 — episode-창 누적(4/4 TRUE)은 회복월 포함 + β<1 완충의 산술이다. 두 수치 모두 실측이고 측정 대상이 다르다. 설계는 후자(월간)를 경계에 반영했다.

## 합리화 어휘 자가검사
answer-principles 회피표현 목록 전 항목에 대해 본문 검사 — 해당 어휘 부재 확인 (목록 리터럴은 검출기 오발화 방지를 위해 여기 재기입하지 않음). 검증 안 된 추론(성분 귀속·개인 거래비중 채널)은 전부 "추론/미실측" 명시 라벨.

## 결론
verdict = **designed** 유지. 가장 약한 가정 = W2(국면 경계 사후성) — F3 독립 관측으로 반증 가능하게 설계했으므로 finalize 진행.

---

# Challenge Note — WT-D20260822_005 · alpha-research 구간 (v8.2 Self-Adversarial) — APPENDED

- **작성**: alpha-research (model: opus), 2026-08-22, finalize 직전
- **범위**: 실측 산출 축 (①ablation 성분귀속 / ②dual-basis / ③KQ150 / ④redundancy / ⑤regime / ⑥창-도달가능성 / PIT)
- **승계 규약 준수**: mechanism/falsification/regime_scope 재작성 안 함 — 게이트 스키마 재포장만. 결함 미발견(재설계 요청 없음).

## 실측 요약 (measure 결과, metric_type=canonical_screen_diag, tier=screen_diagnostic)
- **IS(2005~2018) ablation**: A(M08+Q01) 2.193 → **B(M08+Q01+C03) 2.841** → H(+M01) 2.983(redundant). G(Q01 단독) 1.154. F4 반증조건 PASS(유지축 조합 IS PORT_t > 2.0 — 성분귀속 IS 확정).
- **선택 B 다중창(cap-w IKS200)**: IS 2.841 / **OOS(2019~) −1.285** / full(259m) 0.866 / clean(2015-07~) −1.643.
- **oos_retention(canonical, 2019 split) = −0.666 → HARD FAIL(<0.5 무조건)**.
- **④ redundancy**: M08~M01 xsec cor **0.813**(H의 +M01 = 잉여, 배제 정당). M08~M07 0.225 / M08~Q01 0.008(직교).
- **② dual-basis**: EW-universe diag도 OOS 0.146 / clean −0.095 / post2017_t 0.18 → post-2017 감쇠는 cap-w 아티팩트 아님(진짜 cohort decay). OVERLAY_CANDIDATE 재분류 근거 부재.
- **⑥ 창-도달가능성 상한**: perfect-foresight top-25 = **31.01** → 이 창에서 2.95 원리적 도달 가능 ⇒ 실패는 '창 짧음'이 아니라 '신호 약함'(효과없음 아니라 decay).
- **⑤ regime arm(advisory)**: RISK_ON active +10.9%/yr(SR 0.61) vs RISK_OFF −2.3%/yr(SR −0.11) — 승계 regime_scope 실측 정합.

## 자가 제기 약점 3건 + 분류

### AW1. C17 dead → C03 대체가 silent override 아닌가 — **REBUTTAL + 정직 라벨**
C17_OP_Revision 은 전기간 커버리지 0(dead — registry 등록됐으나 미배출, 74개월 표본 전부 0). 대체 = C03_EPS_Chg_3m(3m EPS revision, 2005~ live). 기전 intent(이익수정/컨센서스 실현 경로, F2)를 보존하는 최근접 live emitter이며, 대체 사실·근거를 본 노트·alpha_package factors 층에 명시 기록. 특정 dead ID를 live 동류로 교체한 것은 데이터 게이트 대응이지 가설 재해석 아님(Charter §8 정합 — 승계 mechanism 불변). ⚠ 단 C03이 C17과 동일 통계량이 아니므로 "C17 arm 그 자체"는 미측정으로 남는다(정직 라벨).

### AW2. B가 IS 우수인데 OOS 붕괴 = IS-선택 아티팩트 아닌가 — **ACCEPT (이것이 핵심 판정)**
B는 IS-only 선택 라운드의 승자이고 OOS(−1.285)·clean(−1.643)에서 부호 반전. oos_retention −0.666은 HARD FAIL. **이것은 결함이 아니라 판정 결과다** — chain 자격 ②(IS-only 선택)를 지켰기에 OOS가 순정 검증으로 남았고, 그 검증이 자본 부적격을 확정했다. W5(alpha-hypothesis)가 예고한 이중성 중 (b)cohort-wide post-2017 decay(FMT-07)가 주원인임이 dual-basis로 확인 — 6→3 정제로 회복 안 됨. 성분귀속(F4)은 IS에서 참이나, 그 참인 귀속이 자본 자격을 주지 않는다(measurement-graduation §3: HARD는 forge-authoritative, screening은 라벨일 뿐).

### AW3. regime arm이 CRISIS 방어를 입증했다고 과대해석 위험 — **PARTIAL**
RISK_ON/RISK_OFF median split은 Macro_Risk_Score 기준 근사이며 E3의 정식 RISK_ON/CRISIS 4-라벨이 아니다. RISK_OFF active 음수는 승계 regime_scope와 방향 정합이나, 이는 advisory diag이고 OOS 붕괴를 구제하지 못한다. "국면 조건부화하면 자본 자격"이라는 결론으로 비약 금지 — 외부 overlay는 OVERLAY_INFERIOR 실측(2026-08-17). 국면 소비는 next_probe로 이관(FR 모드).

## 합리화 어휘 자가검사
answer-principles 회피표현 목록 전 항목 본문 검사 — "미미/관행/보수적이면/대부분 동일" 등 부재 확인. 모든 추론(성분귀속 IS-한정, regime 근사)에 "IS-only/advisory/미측정" 명시 라벨. self-rationalization auto-detection: 해당 어휘 미사용.

## Q-Lead escalate trigger 점검
HIGH severity concern < 5, AX axiom hard FAIL 없음, PIT C1(lockbox·lookahead) 위반 없음(macro regime Date<=sig_date 진행중월 배제 확인) → 자동 escalate 미발화. 단 oos_retention HARD FAIL은 자본 tier 부적격이므로 governor 미진행(정상 — screening tier 라운드).

## 결론
verdict = **measured → config_scoped_negative_capital_tier + IS_driver_attribution_confirmed**. 가장 약한 가정 = AW2(수용, 판정 그 자체). Self-Adversarial 통과 — finalize 진행. next_probe ≥ 2 (alpha_package).
