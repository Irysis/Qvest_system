# Textbook Summaries — Qvest 시스템 흡수 reference

> **작성일**: 2026-04-30 (Phase 1-3, textbook 흡수 plan, plan file: `~/.claude/plans/fizzy-tinkering-cocke.md`)

## 인덱스

| 책 | 우선순위 | 적용 |
|---|---|---|
| **[FRM (Pfaff R-based)](FRM_Pfaff_summary.md)** | **HIGH** ⭐ | Risk + Optimizer agent. EVT/Copula/GARCH/Robust opt/Min CVaR/Min CDaR |
| [FRM R Packages](FRM_R_packages_required.md) | — | Phase 5 PoC 진행 시 설치 가이드 |
| **[NMF (Gilli-Maringer Matlab)](NMF_Gilli_summary.md)** | **MED** | Optimizer agent. Heuristics (PSO/DE/GA/SA/TA) — 추후 cross-family blender 시점 |
| [FER (한글 금융공학)](FER_한글_금융공학_excluded.md) | LOW | **적용 제외** (derivatives 위주, 본 시스템 long-only equity와 dimension 다름) |

## Agent별 적용 우선순위

### Risk-research agent (FRM 우선)
- **Ch4** Measuring Risks: VaR / CVaR / ES (이미 사용 중)
- **Ch7** EVT: GPD threshold (POT) / Hill α — **PoC 1순위**
- **Ch8** GARCH: regime-conditional vol — 추가 활용 가능
- **Ch9** Copula: Student-t / Clayton (TDC 정밀화)

### Optimizer-research agent (FRM + NMF)
- **FRM Ch10** Robust opt: MCD / Stahel-Donoho — **PoC 2순위**
- **FRM Ch11** MDP / ERC: HRP 외 alternative
- **FRM Ch12** Min CVaR / Min CDaR: drawdown control
- **NMF Ch12** Heuristics: PSO / DE / GA — **PoC 3순위**

### Alpha-research agent
- 변경 없음 — FRM/NMF/FER 모두 alpha discovery 직접 도움 작음
- (Alpha의 literature anchor는 SSRN/arXiv 학술 paper에서 직접)

## Phase 4 적용 (예정)

`02_Infrastructure/prompts/` 안의 agent init prompt에 textbook reference 섹션 추가:
- `risk_research_init.md` ← FRM Ch4/7/8/9
- `optimizer_research_init.md` ← FRM Ch10-12 + NMF Ch12-13

## Phase 5 PoC 후보 (별도 시간)

| 순위 | 모듈 | 챕터 |
|---|---|---|
| 1 | `02_Infrastructure/risk/textbook_methods/evt_engine.R` | FRM Ch7 |
| 2 | `02_Infrastructure/portfolio/textbook_methods/robust_opt.R` | FRM Ch10 |
| 3 | `02_Infrastructure/portfolio/textbook_methods/heuristic_opt.R` | NMF Ch12 |

## 추출 도구

- **Hancom OpenDataLoader v2.4.0** (Apache 2.0): FER + NMF 성공
- **pdftools fallback**: FRM (PDFBox NPE bug 우회)

각 책 평균 추출 시간 ~10초 (FER 한글 OCR 포함).
