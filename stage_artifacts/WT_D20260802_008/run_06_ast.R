## run_06_ast.R — AST v1.1 표현 + 컴파일 + 사이드카(live_with_ast) 기록
##   정본 AST = WHERE(base, SIGN(CS_DEMEAN(CS_RANK(cov_l0)))) — WT-002 const-free 형과 동일 구조,
##   게이트 리프만 fa_share_l0 → cov_l0 교체. 컴파일 경로 vs 손빌드 경계 차이(정수 동률)를 실측 보고.
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setDTthreads(2); QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
TD <- "stage_artifacts/WT_D20260802_008"
source("02_Infrastructure/ast/ast_compile.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/ast_sidecar.R")

sc0 <- ast_sidecar_status()
cat(sprintf("[sidecar before] live=%d live_with_ast=%d\n", sc0$live, sc0$live_with_ast))

## [1] AST 입력 패널
BASE <- as.data.table(read_parquet(file.path(TD, "cov_panel.parquet")))
BASE[, Date := as.Date(Date)]
AIN <- BASE[, .(Date, Ticker, alpha_score_base = score, cov_l0)]
write_parquet(AIN, file.path(TD, "ast_input_panel.parquet"))
h <- digest::digest(file = file.path(TD, "ast_input_panel.parquet"), algo = "sha1")

leaf <- function(field, restat) list(
  type = "leaf", class = "STORED_SCORE", source = "stored_panel", field = field,
  avail_offset_days = 0, restatement_prone = restat,
  contract = list(path = file.path(TD, "ast_input_panel.parquet"), value_col = field,
                  avail_offset_days = 0, store_build_hash = h,
                  generator_code_path = "stage_artifacts/WT_D20260802_008/run_01_premise.R",
                  generated_at = "2026-08-02",
                  production_parity_verified = (field == "alpha_score_base"),
                  parity_note = if (field == "alpha_score_base")
                    "cleanT1 verbatim 상속 (WT-002 동일 base — parity 근거 cleanT1_meta.json spearman=1.0)"
                  else "본 라운드 신규 파생(coverage as-of) — production 경로 파생 아님. 정직 선언(false)."))
ast <- list(type = "op", op = "WHERE", args = list(
  leaf("alpha_score_base", TRUE),
  list(type = "op", op = "SIGN", args = list(
    list(type = "op", op = "CS_DEMEAN", args = list(
      list(type = "op", op = "CS_RANK", args = list(leaf("cov_l0", FALSE)))))))))
write_json(ast, file.path(TD, "ast_F1_cov_gated_score.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")

## [2] 컴파일 + 실측
eval_dates <- sort(unique(AIN$Date)); U <- AIN[, .(Date, Ticker)]
cc <- ast_compile(ast, eval_dates = eval_dates, universe = U,
                  manifest_out = file.path(TD, "ast_manifest_F1_cov.json"))
p <- cc$panel[is.finite(value)]
cat("[features]\n"); print(cc$manifest$ast_features)

## 손빌드 게이트와 대조 (동률 경계 차이 정량)
setorder(BASE, Date, Ticker)
BASE[, gate := frank(-cov_l0, ties.method = "first") <= ceiling(.N / 2), by = Date]
hb <- BASE[gate == TRUE, .(Date, Ticker)]
cp <- p[, .(Date, Ticker)]
inter <- nrow(merge(hb, cp, by = c("Date", "Ticker")))
jac <- inter / (nrow(hb) + nrow(cp) - inter)
cat(sprintf("[경계대조] 손빌드 %d vs 컴파일 %d cells  Jaccard=%.4f\n", nrow(hb), nrow(cp), jac))

SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
r <- canonical_screen_bt(p[, .(Date, Ticker, score = value)], as.data.table(SI$fwd_ret),
                         as.data.table(SI$bench), top_n = 25L, cost_bps_oneway = 15,
                         liq_dt = as.data.table(SI$liqf), liq_min = 2e8,
                         size_dt = as.data.table(SI$SIZE),
                         run_id = "fq084np2_B_cov_AST", strategy_id = "FQ084NP2_B_cov_AST",
                         ast_features = cc$manifest$ast_features)
cat(sprintf("[AST 경로 실측] PORT_t=%+.3f n=%d (손빌드 +3.922)\n", r$portfolio_alpha_t_nw_lag3, r$n_months))

sc1 <- ast_sidecar_status()
cat(sprintf("[sidecar after] live=%d live_with_ast=%d\n", sc1$live, sc1$live_with_ast))

saveRDS(list(features = cc$manifest$ast_features, op_counts = cc$manifest$operator_counts,
             jaccard_vs_handbuilt = jac, n_handbuilt = nrow(hb), n_compiled = nrow(cp),
             ast_port_t = r$portfolio_alpha_t_nw_lag3,
             sidecar = list(before = sc0[c("live", "live_with_ast")],
                            after  = sc1[c("live", "live_with_ast")]),
             panel_sha1 = h),
        file.path(TD, "ast_run.rds"))
cat("[SAVED] ast_run.rds / ast_F1_cov_gated_score.json / ast_manifest_F1_cov.json\n[DONE]\n")
