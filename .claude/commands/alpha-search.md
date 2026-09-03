---
description: 알파 서칭 — 논문/가설 빠른 백테스트 검증 + 2차트·성과요약 텔레그램 + 조건부 L-code 적립 (QEPM 이행 없음)
---

# /alpha-search <논문URL | 가설>

Qvest 초기 모델 스타일의 **가벼운 독립 검증 루프**. 논문/가설을 빠르게 백테스트로
검증하고 전략별로 (1) 전기간 Equity Curve(vs BM) + (2) 연간 수익률 막대그래프(vs BM)
2차트, (3) 전략명+아이디어, (4) 성과요약(스코어링 지표)을 텔레그램으로 보낸다.
얻은 교훈은 **모드별 L-code**로 적립되어 Axiom 엔진이 자가발전한다.

**사용법**:
```
/alpha-search https://arxiv.org/abs/2401.xxxxx
/alpha-search "잔차 모멘텀 12-1 가설을 코스피200에서 검증"
```

**동작**:
1. 논문/가설 intake (arXiv/SSRN/jina로 검색 가능) → 핵심 시그널 추출
2. `factor_engine.R` 작성 (가설 → FACTORS, PIT 준수)
3. `run_paper_replication(name, idea, engine, portfolio_spec=<논문값>, source_paper=list(url=))` 실행 → 논문 그대로 복제(롱숏·종목수·비중·리밸) + bt_result 계약 + 2차트 + **권위 등급(essence)** 산출
4. 텔레그램 발송 1회 — 표제 `[1계층] 알파 서칭 — …`(§5.6b, 러너 자동)
5. 판정 인용은 `authoritative_remeasure.json::essence_grade` **만**(hurdle 등급 = proxy 진단, 판정 인용 금지)
6. 의미있는 실패(탈락축이 잡힌 clean-PIT F)만 L-code 적립(`stage_artifacts/l_code/paper_replication/`, `next_probes`≥2 + `live_trigger`) → harvester/cluster 비동기
7. **Grade A → `judge_request.json` 발행 → Judge(PIT 6축) → PASS 시 BOOK 등록 후보(도훈 confirm)**. **미달(B/C/F) → `Skill(reinforce)`** 로 강화 원장(`reinforce_ledger_l1.json`) open — 논문당 최대 25회.

**충실구현 단계 QEPM 미이행**(강화부터 QEPM): Risk/Optimizer/Forge 미호출,
WorkTask status 전이 없음, certificate 의존 없음, WT-id 사용 금지. Judge 는 Grade A 한정.

**PIT 주의**: 외부 parquet 의존 팩터(fe_ml 등)는 정적 PIT 검사(`detect_lookahead`) 사각 —
생성 `.py`가 forward-label sanity(`bear_date_audit`/`validate_label_direction` 동등)를 통과했는지 별도 보증 필수(python-policy.md, Cycle 50).

**실행 방식**: `Skill(alpha-search)` 또는 `Agent(subagent_type="alpha-search", prompt=...)`

상세: `.claude/skills/alpha-search/SKILL.md` 참조.
