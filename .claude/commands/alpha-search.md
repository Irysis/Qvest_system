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
3. `run_alpha_search()` 실행 → 풀백테스트 + 차트 + `run_hurdle_gate` 점수·등급 + (factor_analysis 기본 ON) FF3/FF5/Carhart 알파·Fama-MacBeth
4. 텔레그램 발송 (헤더에 `🔭 AlphaSearch` 모드 배지 자동)
5. PASS/의미있는 실패만 L-code 적립(`stage_artifacts/l_code/alpha_search/`) → harvester/cluster
6. Grade A는 STR_AS_ 등록 + PG 편입 **권고**(book_state는 도훈 수동 승인)

**QEPM 이행 없음**: Risk/Optimizer/Forge/Judge/Governor 미호출, Codex Round 없음,
WorkTask status 전이 없음, certificate 의존 없음, WT-id 사용 금지.

**PIT 주의**: 외부 parquet 의존 팩터(fe_ml 등)는 정적 PIT 검사(`detect_lookahead`) 사각 —
생성 `.py`가 forward-label sanity(`bear_date_audit`/`validate_label_direction` 동등)를 통과했는지 별도 보증 필수(python-policy.md, Cycle 50).

**실행 방식**: `Skill(alpha-search)` 또는 `Agent(subagent_type="alpha-search", prompt=...)`

상세: `.claude/skills/alpha-search/SKILL.md` 참조.
