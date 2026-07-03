## Factor deep-recheck (tier-2) telegram brief — 20260619 (single tg_agent_brief call)
suppressWarnings(suppressMessages({ library(jsonlite) }))
ROOT <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", getwd()))
if (!nzchar(ROOT)) ROOT <- getwd()
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure", "telegram", "telegram_notify.R"))

TODAY <- "20260619"
base  <- file.path("stage_artifacts", "paper_recharge")
res_j <- fromJSON(file.path(base, sprintf("factor_recheck_result_%s.json", TODAY)), simplifyVector = FALSE)

n_in   <- res_j$n_input
n_prom <- length(res_j$promoted)
n_inf  <- length(res_j$confirmed_infeasible)
n_unc  <- length(res_j$still_uncertain)

b_prom <- if (n_prom == 0) "없음 — 재현율 회복 대상 0건 (두 후보 모두 전문 정독 후 기각)" else
  paste(sapply(res_j$promoted, function(x) sprintf("%s [%s]", x$factor_name, x$paper_id)), collapse=" / ")

b_inf <- c(
  "price_network_centrality [2606.07450] — 논문에 종목 수익신호 부재(섹터 AMI·쌍단위 ΔI만, centrality 수익검증 없음). centrality alpha 합성=batch_434 날조 가드. registry엔 novel이나 논문 미지원.",
  "resga_predicted_ES_sort [2606.04576] — 신호가 수백만 파라미터 ReSGA 모델에 종속(경량 ES 대체=non-faithful). long-short(롱온리 위배) + tail/VaR/CVaR 13종 중복(D08/D25/D47-49/R01-05). long leg=방어 tilt(AX-005).")

b_unc <- if (n_unc == 0) "없음 — 보류 0건. 두 후보 전문 접근·정독 완료, 추가 정보 대기 항목 없음." else paste(sapply(res_j$still_uncertain, function(x) sprintf("%s — %s", x$paper_id, x$need)), collapse=" / ")

sections <- list(
  list(emoji = "✅", heading = sprintf("승격(testable) %d건", n_prom), type = "text", body = b_prom),
  list(emoji = "⛔", heading = sprintf("확정 기각 %d건", n_inf), type = "bullet", items = b_inf),
  list(emoji = "❓", heading = sprintf("still_uncertain %d건", n_unc), type = "text", body = paste(b_unc, collapse=" / "))
)

res <- tg_agent_brief(
  agent = "AlphaSearch",
  title = "팩터 심층 재검 (tier-2)",
  as_of = "2026-06-19",
  relaxed = TRUE,
  force = TRUE,
  lock_scope = sprintf("factor_recheck_%s", TODAY),
  sections = sections,
  footer = sprintf("입력 uncertain %d건 심층(논문당) 재검 → 승격 %d / 확정기각 %d / 보류 %d. alpha_search_queue 추가 0. 산출: factor_recheck_result_%s.json",
                   n_in, n_prom, n_inf, n_unc, TODAY))

cat("TG_OK:", isTRUE(res$ok), " bytes:", res$bytes %||% NA, " err:", res$error %||% "NULL", "\n")
