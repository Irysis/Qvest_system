# Runner — ReSGA 2606.04576 size×tail-risk interaction (alpha-search 모드 가동)
suppressWarnings(suppressMessages(library(data.table)))
try(setDTthreads(1L), silent = TRUE)   # 세그폴트 회피(잔류 프로세스+멀티스레드, project-r-segfault)
Sys.setenv(RESGA_DIRECTION = Sys.getenv("RESGA_DIRECTION", "POS"))

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(ROOT, "02_Infrastructure/alpha_search/run_alpha_search.R"))

ENGINE <- file.path(ROOT, "02_Infrastructure/alpha_search/factor_engine_resga_2606_04576.R")
NAME <- sprintf("ReSGA_SizeTail_%s", Sys.getenv("RESGA_DIRECTION", "POS"))
IDEA <- paste0(
  "ReSGA(arXiv 2606.04576) Eq.(11) size×tail-risk 상호작용: ",
  "alpha = (logCap - 단면평균logCap) × (1 - exp(ES_hat)), ",
  "ES_hat=직전252d 일별수익 하위5% 평균(historical CVaR_95). ",
  "P1(대형주×고꼬리위험, too-big-to-fail 매수측) long-only top-25 EW. ",
  "방향=", Sys.getenv("RESGA_DIRECTION", "POS"), " (논문 부호 시장의존 KR 재검증)."
)

res <- run_alpha_search(NAME, IDEA, ENGINE,
                        n_holdings = 25L, weight_method = "ew",
                        send_telegram = FALSE, factor_analysis = TRUE)

cat("\n==== RESGA RESULT ====\n")
cat(sprintf("strategy_id=%s grade=%s score=%s excess=%s out_dir=%s\n",
            res$strategy_id, res$grade, as.character(res$score),
            as.character(res$excess_cagr), res$out_dir))
auth <- res$authoritative
if (!is.null(auth)) {
  cat(sprintf("AUTH status=%s essence_grade=%s\n",
              auth$status %||% "NA", auth$essence_grade %||% "NA"))
}
saveRDS(res, file.path(ROOT, "stage_artifacts/paper_recharge/_resga_2606_04576_result.rds"))
