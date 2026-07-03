## Factor deep-recheck (tier-2) telegram brief — 20260620 (single tg_agent_brief call)
suppressWarnings(suppressMessages({ library(jsonlite) }))
ROOT <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", getwd()))
if (!nzchar(ROOT)) ROOT <- getwd()
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure", "telegram", "telegram_notify.R"))

TODAY <- "20260620"
base  <- file.path("stage_artifacts", "paper_recharge")
res_j <- fromJSON(file.path(base, sprintf("factor_recheck_result_%s.json", TODAY)), simplifyVector = FALSE)

n_in   <- res_j$n_input
n_prom <- length(res_j$promoted)
n_inf  <- length(res_j$confirmed_infeasible)
n_red  <- length(res_j$redundant)
n_unc  <- length(res_j$still_uncertain)

b_prom <- if (n_prom == 0) "없음 — 승격 0건 (신규 처리 0; 입력 2건은 전일 재검 완료분 중복 재유입)" else
  paste(sapply(res_j$promoted, function(x) sprintf("%s [%s]", x$factor_name, x$paper_id)), collapse=" / ")

b_rej <- c(
  "price_network_centrality [2606.07450] — 확정기각(infeasible). abstract 재대조: 논문 목적=섹터 taxonomy 복원, 종목 수익신호 부재 → centrality alpha 합성=batch_434 날조 가드.",
  "resga_predicted_ES_sort [2606.04576] — redundant(전일 infeasible→정밀화). long leg(저ES decile)=방어 tilt이나 tail/VaR/CVaR 13종(D08/D25/D47-49/R01-05) 중복. novel분=ReSGA 모델품질 종속이라 충실재현 불가.")

sections <- list(
  list(emoji = "✅", heading = sprintf("승격(testable) %d건", n_prom), type = "text", body = b_prom),
  list(emoji = "⛔", heading = sprintf("기각 %d건 (확정기각 %d + 중복 %d)", n_inf + n_red, n_inf, n_red), type = "bullet", items = b_rej),
  list(emoji = "🐞", heading = "runner 버그(surface)", type = "text",
       body = "오늘 큐 = 어제 큐와 동일(같은 2 paper_id). 둘 다 이미 done(20260619/infeasible)인데 재유입 — 큐빌더 done-제외(dedup) 미작동. 정상 신규입력은 0건이었어야 함. abstract 직접 대조로 재검증(verdict 불변, 1건 정밀화). 후속: 큐생성 시 factor_recheck_done 대조 제외 필요.")
)

res <- tg_agent_brief(
  agent = "AlphaSearch",
  title = "팩터 심층 재검 (tier-2)",
  as_of = "2026-06-20",
  relaxed = TRUE,
  force = TRUE,
  lock_scope = sprintf("factor_recheck_%s", TODAY),
  sections = sections,
  footer = sprintf("입력 %d건 모두 전일 재검 완료분 중복(runner dedup 버그). 신규승격 0 / 확정기각 %d / 중복 %d / 보류 %d. alpha_search_queue·done 변경 0. 산출: factor_recheck_result_%s.json",
                   n_in, n_inf, n_red, n_unc, TODAY))

cat("TG_OK:", isTRUE(res$ok), " bytes:", res$bytes %||% NA, " err:", res$error %||% "NULL", "\n")
