---
name: qvest-attribution-style
description: judge(PIT 전담)·BOOK 등록 판단 참고용 QEPM 스타일 — Attribution & Feedback Loop (factor/selection/cost/residual 분해, Brinson + Carhart 4). research_philosophy ⑦ operationalize. Judge PIT 검증 및 BOOK 등록 후보 검토 시 적용.
---

# Attribution & Feedback Style (research_philosophy ⑦)

**SOT**: `02_Infrastructure/docs/qvest_research_philosophy.md`. 위반 = AX-002 동급.

## ⑦ Attribution & Feedback Loop
- 수익 분해 4축: **factor + selection + cost + residual** (Brinson + Carhart 4-factor). (사실 정정 11-10: '분기별 자동' 훅 `attribution_quarterly_trigger.sh` 는 `.claude/settings.json` 미등록 — 자동 분해는 돌지 않는다. 살아 있는 귀속 = 등급 v3.3 팩터 조정 알파(FF3 · Carhart4 · FF5 · FF6 · `data/build_kr_factor_returns.R`) + 행동 카드 MC8 귀속(선택 · 크기 · 노출 방어) + 15bps 판 대 논문 기준판 병기(비용).)
- BOOK 등록 후보 검토 시(참고 — 판정 축 아님) alpha가 어디서 오는지(factor exposure vs 순수 selection) 분해 확인 — factor-driven이면 기존 factor와 redundant 위험.

## 판정 원칙 (Judge · BOOK) — ★등급은 essence_score 소관, Judge 는 재채점하지 않는다
- **AX-000 reframe 정합**: 실증·PIT·수리로 입증된 한계는 **정직히 FAIL 판정**. PASS로 합리화 금지(자기합리화 grep: 미미/관행적/보수적이면OK/대부분동일).
- **portfolio-alpha t-stat이 authoritative** (rank-IC t 아님). Harvey-Liu-Zhu hurdle(t≥2.95)은 realized portfolio alpha 회귀에 적용.
- **AX-008 v2.0 (2026-09-23 도훈 AX-D5 개정)**: 결정에 영향을 주는 수치(등급·PORT_t·Calmar 등)는 R 계약 산출만 인용한다 — 손계산·재구성·추정 금지. 독립 검증 = Judge(PIT 전담, essence Grade A 확정 후 — 표결 adjudicator 아님, `.claude/agents/judge.md`). 구 v1.1 3자 교차검증 2-of-3 은 `AX-008.json::history` 사료.
- **권위 등급 = 등급 v3 · 규칙 판 v3.4**(2026-11-10 사실 정정 — 구 'HARD 3종 AND' 서술은 동결된 WT 배포 훅 `discovery_graduation_gate.sh` 의 문턱으로만 남는다 · measurement-graduation.md §0): S = (Calmar/0.64)^0.6 × (PORT_t/2.95)^0.4 · A = S ≥ 1 ∧ 하한(PORT_t ≥ 2.0 · Calmar ≥ 같은 창 KOSPI200 · CAGR ≥ 16% · Sharpe ≥ 0.8) ∧ OOS 관문(τ_D 이후 시험 창 위기 복원력 약함 아님 ∧ 시험 창 Calmar ≥ 같은 창 KOSPI200) ∧ 스윕이면 선택 현실 점검(조정 p ≤ 0.05 · 미제출 = 경과 규정 DSR) · 팩터 조정 알파 노치(FF3 · Carhart4 · FF5 · FF6 알파 NW-t 최솟값) · 위기 복원력 노치(행동 카드 · MC8 귀속). MDD 직접 문턱 없음. 정본 = CLAUDE.md 등급 절 · `contracts/grade_v3.R` · `06_Registry/grade_v3.json` — 이 문서는 요약이고 인용은 `authoritative_remeasure.json::essence_grade` 만. **SR target 2.5**(목표 서술 · 게이트 아님).
- PIT C1~C15 독립 검증 + lookahead false-positive 판별. (v10: lockbox 폐지)

## ⚠️ Cycle 2 교훈
- discovery WT가 게이트 fail이면 **정직히 등급 미달(B/C/F) → Judge 미스폰·BOOK 미진입**(강화 프로세스 대상). incumbent retain. (D ML 30f 사례)
- single-cross-section 지표(beta 등)는 walk-forward로 재검 — single-snapshot 과대평가 금지.

## 경계
판정만. 전략 설계/구현/수정 금지.
