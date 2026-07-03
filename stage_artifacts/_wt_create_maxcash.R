## QEPM WT 생성 — Max-Cash 비-compounding 오버레이 결합 (sizing_only, parent STR_1715)
ROOT <- Sys.getenv("QM_ROOT", getwd()); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure", "worktask", "worktask_manager.R"))

desc <- paste0(
 "[동기] 현 book STR_1715 오버레이 결합은 곱셈(risk_weight = beta_AR * beta_R05; 부트 admit baseline 0.70*1.00=0.70). ",
 "문서화된 결함(architecture audit B2): M4<->AR overlap 91% — 상관 높은 두 오버레이가 동시 발화 시 곱셈이 디리스크를 이중계상(compound)해 중간밴드 과방어 드래그 유발. ",
 "[가설] 비-compounding 결합 max-cash = risk_weight = min(beta_AR, beta_R05) (= 더 깊은 단일 디리스크만 채택, 곱셈 compound 회피). ",
 "상관 높은 오버레이의 과방어를 줄이되 깊은 크래시 방어는 유지한다. ",
 "[출처] arxiv 2606.09025 'Continuous Cash-Overlay Filters' max-cash 결합 연산자(메커니즘 동기 only — 논문 성과수치는 판정근거 아님, 실측 forge로만 보고). ",
 "[접근] A/B: incumbent 곱셈 vs max-cash(min) on STR_1715 AR/R05 오버레이. base sleeve/alpha/Sigma는 STR_1715 inherit(신규 알파 없음 = sizing_only). ",
 "fresh regime_daily_v2(06-26 refresh 완료), 15bps delta cost(v2.4), PIT 유지(AR/R05 모두 lag-1, max는 PIT 보존). ",
 "[게이트] book-marginal ΔIR>=0.05 + MDD 비악화. 가설주도 단일 A/B(chain, not sweep) → DSR 부적용. governor 정지(자본 수동+도훈). ",
 "[정직 기대] 오버레이는 SR~1.95로 다년 튜닝됨 — SR 2.5 천장 돌파 아님. 기대값 = 중간밴드 과방어 드래그 소폭 감소 / MDD 개선.")

wt_id <- wt_create(
  hypothesis_title = "Max-Cash 비-compounding 오버레이 결합 (AR x R05 과방어 완화)",
  hypothesis_description = desc,
  wt_type = "sizing_only",
  discovery_of = "STR_1715_WT016_Iter31_GridBestProd",
  universe = "KOSPI200_KOSDAQ150_intersection",
  benchmark = "KOSPI200_total_return"
)
cat("\nWT_CREATED:", wt_id, "\n")
