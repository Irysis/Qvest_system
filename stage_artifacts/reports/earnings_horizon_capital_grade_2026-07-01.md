# earnings-revision @ horizon LEAD — capital-grade 검증 종합 (2026-07-01, 자율세션)

## TL;DR
아침 discovery rounds(4-8)가 발견한 **earnings-revision @ 3-6M horizon LEAD**(1M死/3-6M生, placebo 100%ile, proxy book-marginal SR Δ+0.33)를 계약-grade(Round9-11)로 검증 → **두 자본 게이트 모두 FAIL, 메커니즘 규명.** 한 가지 양성 발견(총SR 개선=de-risking)은 도훈 거버넌스 결정으로 surface.

## 검증 결과 (계약-grade, metric_type=canonical_screen / contract NW3)

| 방법론 | 측정 | 결과 | 게이트 |
|---|---|---|---|
| **① selection sleeve** (broad earnings, H3, top25, +liq) | standalone 계약 PORT_t(NW3) | recent **+1.75**(p0.08) · full **+1.66** | ✗ HARD 2.95 |
| | 16-변형 sweep best (conviction) | +1.93 | ✗ ≪2.95 |
| | book-marginal 활성-IR (raw blend) | ΔactiveIR **−0.01~−0.044** | ✗ §4 (≥0.05) |
| **② 직교화 sleeve** (PIT 확장윈도 beta, book 잔차) | 잔차 IR recent | +0.17(EW)/+0.21(conv), full **음수** | — |
| | best ΔactiveIR @최적λ | **+0.000~0.003** | ✗ ≪0.05 → earnings⊂book |
| **③ breadth 시장 오버레이** (피벗, selection 회피) | breadth(t-1)→시장 IC recent | **~0** (raw +0.024·z −0.003) | ✗ 무신호 |
| | risk-on/off 활성 SR recent | **−0.53** (누적 −20%) | ✗ cheap-kill |

부수: value sleeve와 active corr **0.91**(earnings≈대형주 value/quality 포트 + 작은 revision 틸트), 24-26 집중(CAGR +81.6%·n28).

## 메커니즘 (왜 실패하나)
- **바인딩 제약 = book-redundancy.** sleeve 활성IR 0.34 < book 0.61 이고 active 상관 **0.60** → 개선조건 `IR>corr×book_IR=0.366` 간발 미달. book에 섞으면 활성알파 *희석*.
- **직교화가 이를 증명**: book이 못 가진 잔차만 추출해도 잔차 IR 0.17~0.21(< 임계 ~0.25), full-history 0/음수 → 직교 earnings-알파는 2024-26에만, 미미. **best-possible 추출도 ΔIR~0 → sizing/horizon/구성 변형으로 못 고침.** (추가 sweep 무의미 — 메커니즘이 변형-불변.)
- book 자체가 강함: 계약 full 활성 PORT_t **4.78**·IR 0.89 (recent 2.27/0.60).

## ★거버넌스 질문 (도훈 결정 — 연구로 못 정함)
earnings sleeve를 book에 25% 섞으면:
- **총 SR**(목표지표, gap_vector target 2.5): book **+1.92 → blend +2.22** (recent, Δ+0.31) ↑ — de-risking·calmar↑
- **활성 IR**(governor admission 게이트): book +0.60 → blend +0.58 (Δ−0.024) ↓ — 알파 희석
- **활성 PORT_t**: +2.27 → +2.40 (거의 불변) = 순수 de-risking, 새 알파 아님

→ **목표는 총SR인데 admission 게이트는 활성IR.** de-risking sleeve가 게이트에 막힘.
- 보수적 해석(게이트 정당): de-risking은 현금/지수로 이미 가능 → "알파 아님"을 게이트가 정확히 차단. earnings sleeve 비채택.
- 대안 해석: 목표-게이트 불일치 — 총SR/calmar/MDD 목표엔 de-risking sleeve도 기여.
- ※ blend는 ESTIMATED(0.75book+0.25sleeve self-synth) — 실제 admission은 forge+governor+도훈 수동. 본 수치는 결정-지원용.

## 함의 / 남은 프론티어
- earnings = KR long-only **마지막 live 횡단면 LEAD**. 두 직교 레버(selection·timing) capital-grade 완결 falsify → 기존 selection 천장 재확증(논문풀·327팩터·microstructure·value·momentum 소진 기록과 정합).
- 남은 미탐색(본 세션 범위 밖): **비-return 데이터**(DART 인사이더 백필 — 데이터 엔지니어링, 별도 세션 / 06-30 도훈 스코핑).
- 작동 레버는 여전히 book의 **가격/변동성 레짐 오버레이**(STR_1715, 총SR 1.95). 펀더멘털 오버레이·새 sleeve는 본 세션서 추가 falsify.

## 재현 (인프라·결과)
- 스크립트: `02_Infrastructure/discovery/round9_capital_gate.py` · `round9_contract.R` · `round10_orthogonalize.py` · `round10_contract.R` · `round11_overlay_firstcut.py`
- 결과: `.cache/discovery/round{9,10,11}_results.txt`
- 패널: `.cache/discovery/phase0_panel_2005-01_2026-04.parquet` (327팩터·256월, Phase0 PIT 검증)
- book: `05_Production/.../STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv`
- 메모리: [[project-earnings-horizon-capital-grade-falsified]]
