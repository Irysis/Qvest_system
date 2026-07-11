# Self-Adversarial Challenge — RAMP R5 선별-규율 계열 폐쇄 (Branch B)

- **작성**: 2026-07-11 Q-Lead (RAMP orchestrator, Opus 4.8 native adversarial round — v8.2 Codex Round 대체)
- **대상 산출**: `outputs/ramp/r5_selection_{gates,paired,summary,prereg}_20260711.*` · L-code(R5) · 판정 "선별-규율 계열(Boruta+StabSel+mRMR) config-scoped 소진"
- **사전등록**: `outputs/ramp/r5_selection_prereg_20260711.json` (config_hash `30b6165dcccfab51`, 측정 전 동결) · 스펙 `04_Research/factor_selection_program/r5_selection_comparison_spec.md`
- **판정 요약**: R5 6 config 전부 base 대비 paired NW-t < 2.0 (max +0.18), 0/6 graduation. R4(Boruta) max paired −2.02와 합산 → 계열 폐쇄 TRUE. **pin identity OK**(fresh base == R4 stored, Δ=0.0000).

## 스스로 제기한 약점 (≥3) — ACCEPT / PARTIAL / REBUTTAL

### W1. "선별 목적함수 불일치" — 계열 폐쇄가 *relevance-objective* selection에 한정되는가? **[PARTIAL]**
- 제기: 세 규율이 최적화하는 목적은 전부 **통계적 관련성**이다 — Boruta=RF importance(shadow-null 초과), StabSel=LASSO 계수 안정성, mRMR=상호정보(여기선 부호 rank-IC)−중복. **어느 것도 게이트인 realized long-only top-25 net-active PORT_t를 직접 최적화하지 않는다.** 따라서 폐쇄는 "관련성-목적 선별-규율" 계열에 한정된다.
- 검증: 사실이다. 셋 다 IC/importance 계열 목적. measurement-graduation §3에 따르면 rank-IC 계열은 advisory(거짓통과·거짓탈락 유발) — 세 규율 모두 그 축에 앉아 있다.
- 분류 **PARTIAL**: 폐쇄 판정은 관련성-목적 계열에 대해 확정(3개 mechanistically-distinct 규율 × 10 config 전멸)이나, **PORT_t-정렬 선별**(trailing 창에서 각 팩터의 realized paired-PORT_t 기여로 greedy 선택)은 미검증. 이를 **부활신호**로 명시 등록 → 계열을 "구조 판결"이 아니라 "config-scoped 소진"(INV-7)으로 표기.

### W2. "base 자체가 문턱 미달 → 개선 천장이 낮다" **[ACCEPT]**
- 제기: all-11 EW base가 이미 HARD 전멸(pt 1.02/0.40, oos 음, post17SR −0.56)이다. 완벽한 선별이라도 죽은 base 위에서 얻을 수 있는 상방이 좁다 → "선별이 base를 못 이긴다"는 부분적으로 substrate(2005+ return-파생 11군, 2017+ 감쇠)의 낮은 headroom 반영.
- 검증: 옳다. 단 **paired NW-t는 정확히 "선별의 한계 부가가치"를 격리**하는 올바른 검정 — base의 절대 수준과 무관하게 "선별이 breadth 대비 +를 만드는가"를 본다. 그 답이 null(심지어 defensive-tilt는 유의 음).
- 분류 **ACCEPT**: base 취약은 이미 문서화(R4/R5 게이트표)이고, 한계 검정(paired)이 주 질문이며 답이 나왔다. 보고에 "base 취약 = 상방 제약" 병기.

### W3. "서브샘플-레짐 confound" (스펙 요구 자가점검) **[REBUTTAL(부분)]**
- 제기: StabSel의 complementary-pairs가 **행(row)-단위** 서브샘플이라 각 half가 모든 월을 대표 → 레짐 혼합이 서브샘플 간 ~일정. 이는 **횡단면 계수 안정성**을 검정하지 실제 **시간/레짐 안정성**을 검정하지 않는다.
- 검증: 맞다. 그러나 이는 "레짐 confound가 결과를 왜곡했다"는 반대 방향 — 행-단위 subsampling은 레짐을 **혼입시키지 않는다**(일정 유지). 즉 결과는 레짐-혼입 아티팩트가 아니다.
- 분류 **REBUTTAL(부분) + 잔여**: confound가 결과를 만든 게 아님(반증). 다만 **블록(월)-단위 subsampling StabSel**은 미실행 config로 남는다 — 그러나 이는 동일 계열 내 또 하나의 config이며, mechanistically-distinct 3규율 × 10 config 전멸이 이미 있어 한계 EV 낮음. 잔여로만 기록.

### W4. "mRMR 관련성=부호 rank-IC(상관 근사), 진짜 MI 아님" **[ACCEPT]**
- 제기: praznik/infotheo 부재로 관련성=trailing signed rank-IC, 중복=|pearson cor|. 진짜 MI-mRMR은 비선형 의존을 잡아 다른 집합을 고를 수 있다.
- 검증: 스펙이 명시 허용한 근사(라벨됨). mRMR ≈ base(paired +0.14/−0.33/+0.18, 중립)라 근사 정밀도가 판정을 뒤집을 여지 낮음. 게다가 mRMR이 **가장 덜 나쁜**(중립) 규율인데도 base를 못 넘음 → 근사가 mRMR을 부당히 깎았을 가능성은 판정에 유리하지 않다.
- 분류 **ACCEPT**: 라벨된 한계, 판정 영향 미미.

## 스펙 필수 자가점검 3종 결론
1. **방법간 수렴?** — 아니오(결정적). 세 규율의 팩터별 선택빈도 프로파일이 **상반**(Boruta→defensive LowRisk0.95, StabSel→growth Growth0.73, mRMR→momentum Momentum1.00/Consensus1.00) + 방법쌍 평균 Jaccard 0.18~0.39(低). **"같은 팩터로 수렴 → 규율 무관"이 아니라, 서로 다른 원리적 부분집합을 골라도 셋 다 all-11을 못 이김** → 벽=breadth-loss/신호 내용, 선별-규율 축 아님. (수렴했다면 "신호 내용 벽"의 약한 버전이었을 것 — 실제는 더 강한 버전: 어떤 부분집합도 무용.)
2. **서브샘플-레짐 confound?** — W3 반증. 행-단위 subsampling은 레짐 일정 유지 → 아티팩트 아님. 블록-단위 변형은 잔여.
3. **config-scoped 한계 + 부활신호?** — 명시. **부활신호 = 선별 기준을 relevance→realized-PORT_t로 교체**(각 팩터의 trailing 창 realized paired net-active 기여로 greedy 선택). 세 규율 모두 이 축을 안 건드림 = frontier crack. INV-7 재도전 조건.

## 자기합리화 detect
- 문턱 이동 없음: kill(paired≥2.0)은 sha256 동결(측정 전), 10 config 전부 그 문턱 미달로 판정 = 사전등록 그대로. 
- 반대방향(거짓 생존) 점검: mrmr_W36_k4(pt 1.14>base 1.02, DSR 0.76)를 "near-miss 생존"으로 승격할 유인 차단 — paired +0.14(base와 구분불가)·pt≪2.95·oos 음·calmar 0.30 → base-복제일 뿐, 사전등록 kill이 정확히 기각. 정직.
- 과대 판결 점검: "구조 판결"이 아니라 "config-scoped 소진"으로 표기(INV-7) + 부활신호 등록 → 지식 손실 아닌 탐색지도.

## 최종 분류
**PARTIAL ACCEPT** — 판정(선별-규율 계열 config-scoped 소진)은 사전등록·pin-clean·3규율 독립 전멸로 견고. 단 (a) "relevance-objective" 한정 스코프, (b) base-취약 상방제약 병기, (c) PORT_t-정렬 선별 부활신호 + 블록-subsampling 잔여를 반드시 동반 기록. 적대 라운드가 판정을 뒤집지 못했고 스코프를 정밀화했다.
