# 실패 지식 아키텍처 재설계 계획 — 제약 방화벽 + 탐색 지도 (2026-07-04)

**배경**: 도훈 mandate — "실패를 구조적으로 틀어막으면 리서치가 죽는다. 좋은 아이디어는 실패를 딛고 나온다. value/quality에 '낙인'을 찍으면 Qvest가 창의적 발견자가 아닌 교조적 보수파가 된다. 특히 '기본 제약조건(long-only·≤25종) 하에서 실패' 식 기록은, LLM인 Q가 '제약 해지가 유일한 레버'라고 반복하게 만든다."

**핵심 원리 (합의)**: 실패 지식은 *금지*가 아니라 *탐색 지도*여야 한다. 그리고 고정 제약은 *변수*가 아니라 *문제의 축*이다.

---

## Ⅰ. 5대 원리 (설계 대전제)

1. **경로(path)를 기록하되 방향(direction)을 판결하지 않는다.** value는 실패한 적 없다 — "EP-단독-long-only라는 특정 경로가 이 시기에 F"일 뿐. 지식 단위 = 구성+측정+메커니즘+무엇이 바뀌면.
2. **실패는 생성적(generative)이다.** "EP-단독이 value premium 약화+quality mix 부재로 F" → "그럼 value+quality composite / regime-conditional / spread-reversion을 해봐라"를 **가리킨다**. 실패 지식의 1차 산출 = 다음 가설.
3. **제약 방화벽.** 고정 제약(long-only·≤25종·K200∪KQ150)은 문제의 고정 축. 실패를 제약에 *귀속*하거나 제약 *완화*를 레버로 제시하는 것 = 금지. AX-000 따름정리("한계는 방법의 한계" → 제약은 게임의 법칙, 창의 부담은 방법에).
4. **영구 판결 없음 — live 트리거로 자동 부활.** 시장은 순환(value 死→生). 실패 지식은 만료일 필수 + 국면/spread/데이터 트리거 감시로 휴면 실패를 **시스템이 먼저** 재부상.
5. **기록은 싸게, 주입은 엄선.** 모든 실패는 corpus에 기록(검색 가능 역사). 단 *모든 미래 리서치를 편향*시키는 주입은 강한 증거(backtested/clean-재확인 + N≥2 + 방화벽 통과)만. 약한 실패의 주입 = 교조화, 자격 바 = 교조화 예방.

---

## Ⅱ. 아키텍처 매핑 (원리 → 실제 파일/함수)

### A. INV-7 재정의 [keystone, 도훈 confirm] — `docs/rules/axiom-engine.md:38`
현: "negative = provisional failure-ledger. construction≥3 + expiry + 재도전 트리거."
신 INV-7 (제안):
> negative 지식은 Law가 아니라 **Distilled 탐색-지도(exploration-map)**다. 5축 승격 게이트를 거치지 않는다. **단위 = 경로(구성-scoped), 방향(family) 판결 금지.** **제약 방화벽**: 고정 제약은 문제의 축 — 실패를 제약에 귀속하거나 제약 완화를 레버로 제시 금지(위반 = 초안 REJECT). 산출 = {탐색됨, 프론티어(미탐색 인접), 부활 트리거} — "금지" 아님. **필수 필드**: expiry + live_trigger + frontier. **주입 자격 바**: backtested OR clean-재확인 + N≥2 + 방화벽 통과분만 주입(기록은 무조건). positive용 축(External oos≥0.5·Independence≥3구성)은 negative에 부적용. process 규칙(polarity 없음, 예 AX-001)만 Law 잔존.

### B. 제약 = 문제-축 격상 [도훈 confirm] — `CLAUDE.md:123` Production Constraints
현: "제약" 표(지켜야 할 규칙).
신: 표 상단에 1줄 — "**이것은 배포 현실이 정의한 문제의 고정 축이다. 최적화로 없앨 변수가 아니다. AX-000 따름정리: 이 봉투 *안에서* 풀어라 — 제약 완화를 레버로 제시하는 것은 게임을 이기는 게 아니라 바꾸는 것.**" + 이 프레이밍을 주입(아래 F).

### C. DIST 스키마 확장 [mechanical] — `02_Infrastructure/axiom/distilled.R`
신규 필드: `frontier`(미탐색 인접 경로 list, 원리2) · `constraint_firewall`(pass/fail+note, 원리3) · `expiry`(필수, 원리4) · `live_trigger`({type:regime|spread|data|time, condition, monitored_source}, 원리4). `draft_proposed`/`approve_proposed`/rebuild가 신필드 저장·검증.

### D. 자동초안 적대검증 확장 [mechanical] — `/cleaner` SKILL + 초안 에이전트
현 3체크: 과장 / 근거 / AX-000. 추가:
- **(d) 제약 방화벽**: 초안이 고정 제약을 원인 귀속하거나 제약 완화를 레버로 제시하는가? → REJECT, envelope-상대로 재작성.
- **(e) 프론티어 생성**: 초안이 미탐색 인접(frontier)을 담는가? 없으면 생성(실패는 앞을 가리켜야). frontier는 근거 있는 hypothesis(구성-인접+메커니즘 동기), 창작 금지.
→ 자동초안이 "요약"이 아니라 **탐색-지도**를 산출.

### E. 검색 프레이밍 전환 [mechanical] — `tools/hypothesis_index.R:289`
현: negative lookup → "재시도 금지(INV-7 provisional)".
신: → "**탐색됨: [경로=F, 증거]; 프론티어(미탐색): [frontier]; 부활 트리거: [live_trigger]; 봉투 안 차별점 명시 시 진행 가능.**" 금지가 아니라 지도.

### F. 주입 프레이밍 전환 [mechanical] — `hooks/axiom_context_inject.sh`
① negative 주입을 "이건 실패"가 아니라 "**탐색됨 + 봉투 안 프론티어**"로 프레임. ② Production Constraints를 **불가침 문제-축**으로 주입(B) — Q가 제약을 레버 후보에서 애초 제외하게. (2500자 상한 내 우선순위 재배치.)

### G. Live 트리거 모니터 [신규 capability] — `02_Infrastructure/ops/` 신규 + 주간/일간 배선
distilled negative의 `live_trigger`를 현 상태와 대조: 국면(`unified_regime_signal`)·value spread·신규 데이터원(DART insider 등). 트리거 발화 시 모닝브리핑/다이제스트에 "**X 재도전 시점 — [트리거] 충족**" 능동 노출. 반ossification 엔진(휴면 실패를 시스템이 먼저 un-bury). 신호원: §5 실측(`macro_regime`·`unified_regime_signal_daily`·`portfolio_gap_vector`).

### H. 기존 오염 기록 감사 [신규 audit] — corpus/DIST/메모리/strategic_truths 전수
제약-귀속/제약-완화-레버 오염 색출·재작성. **확증 오염 1건**: 메모리 "SR 천장 ~1.1, 돌파는 overlay 또는 **>25종 분산**뿐" — ">25종"은 제약-완화-레버. envelope-안 레버(overlay·잔차sleeve·비-return·DPL)만 유지, ">25종"·"short 허용"은 out-of-scope 격리. + 현 proposed 11건을 신 방화벽으로 재초안 후에만 승인.

---

## Ⅲ. 단계 (confirm 게이트 명시)

- **Phase 1 [도훈 confirm]**: A(INV-7 재정의 문안) + B(제약 문제-축 격상). 거버넌스/불변조항 — 문안 승인 필수.
- **Phase 2 [mechanical, confirm 후]**: C(스키마) + D(방화벽·프론티어 초안) + E(검색) + F(주입). 원리를 코드로.
- **Phase 3 [신규]**: G(live 트리거 모니터). 반ossification 엔진 가동.
- **Phase 4 [cleanup]**: H(기존 오염 감사 + 11건 방화벽 재초안). 재초안·재검증분만 승인 후보로.

---

## Ⅳ. 자기반증 (어디서 과교정될 수 있나)

1. **방화벽이 정직한 binding-constraint 발견을 억압?** — 아니오. "이 봉투 안에서 이 방법은 천장"은 **허용**(envelope-상대 사실). 금지되는 건 "**그러니 제약을 풀어라**"의 결론뿐. 모든 방법 소진해도 안 되면 "미해결로 열어둠"(AX-000), 제약 완화 아님.
2. **프론티어 환각?** — frontier는 근거 있는 인접 가설(구성-인접+메커니즘)이고 적대검증 대상. claim이 아니라 hypothesis.
3. **live 트리거 노이즈?** — 트리거는 구체·측정 기반(spread 극단 백분위·국면전환 확인)만. 모호 조건 금지.
4. **복잡도 대비 가치?** — 이게 없으면 지식 엔진이 Q를 "제약 해지 반복 LLM"으로 만듦(도훈 실측 지적). 복잡도가 사는 것 = 반ossification = 고정 봉투 안 공격적 탐색(시스템 코어 가치).

---

## Ⅴ. 진행 조건
Phase 1의 A(INV-7 문안)·B(제약 격상) 도훈 confirm 후 Phase 2~4 실행. active AX 자동변경 없음. INV-1~6·AX-008·5축 hurdle·process(AX-001) 불변.
