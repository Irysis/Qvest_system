## run_07_ast_constfree.R — const-free 등가 표현 검증
##   SUB(CS_RANK(x), 0.5)  ≡  CS_DEMEAN(CS_RANK(x))    [CS_RANK 횡단 평균 = 0.5]
##   동기: ast_verify.py 가 const 노드를 미지원(op=None → FAIL_CONTRACT)함을 발견.
##         회피가 아니라 — 노드 1개·자유 파라미터 1개가 줄어드는 더 단순한 등가 표현이라
##         정본을 이쪽으로 옮기고, verifier 갭은 별도 보고한다.
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setDTthreads(2); QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
TD <- "stage_artifacts/WT_D20260802_002"
source("02_Infrastructure/ast/ast_compile.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

astj <- fromJSON(file.path(TD, "ast_F1_gated_score.json"), simplifyVector = FALSE)
## const-free 판: SIGN(SUB(CS_RANK(g), 0.5)) → SIGN(CS_DEMEAN(CS_RANK(g)))
cs_rank_node <- astj$args[[2]]$args[[1]]$args[[1]]
ast_cf <- astj
ast_cf$args[[2]]$args[[1]] <- list(type = "op", op = "CS_DEMEAN", args = list(cs_rank_node))
write_json(ast_cf, file.path(TD, "ast_F1_gated_score_constfree.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")

AIN <- as.data.table(read_parquet(file.path(TD, "ast_input_panel.parquet"))); AIN[, Date := as.Date(Date)]
eval_dates <- sort(unique(AIN$Date)); U <- AIN[, .(Date, Ticker)]

c1 <- ast_compile(astj,   eval_dates = eval_dates, universe = U)
c2 <- ast_compile(ast_cf, eval_dates = eval_dates, universe = U,
                  manifest_out = file.path(TD, "ast_manifest_F1_constfree.json"))
p1 <- c1$panel[is.finite(value)]; p2 <- c2$panel[is.finite(value)]
mm <- merge(p1[, .(Date, Ticker, v1 = value)], p2[, .(Date, Ticker, v2 = value)], by = c("Date", "Ticker"), all = TRUE)
cat(sprintf("[등가검증] n1=%d n2=%d both=%d only1=%d only2=%d max|d|=%.3e\n",
            nrow(p1), nrow(p2), mm[is.finite(v1) & is.finite(v2), .N],
            mm[is.finite(v1) & is.na(v2), .N], mm[is.na(v1) & is.finite(v2), .N],
            mm[is.finite(v1) & is.finite(v2), max(abs(v1 - v2))]))
cat("[const-free features]\n"); print(c2$manifest$ast_features)
cat("[const-free op_counts]\n"); print(c2$manifest$operator_counts)

SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
r <- canonical_screen_bt(p2[, .(Date, Ticker, score = value)], as.data.table(SI$fwd_ret), as.data.table(SI$bench),
                         top_n = 25L, cost_bps_oneway = 15, liq_dt = as.data.table(SI$liqf), liq_min = 2e8,
                         size_dt = as.data.table(SI$SIZE), run_id = "fq084_B_gate_AST_constfree",
                         strategy_id = "FQ084_B_gate_AST_constfree", ast_features = c2$manifest$ast_features)
cat(sprintf("[const-free 실측] PORT_t=%+.3f n=%d\n", r$portfolio_alpha_t_nw_lag3, r$n_months))
saveRDS(list(equiv_max_abs_diff = mm[is.finite(v1) & is.finite(v2), max(abs(v1 - v2))],
             n1 = nrow(p1), n2 = nrow(p2), port_t = r$portfolio_alpha_t_nw_lag3,
             features = c2$manifest$ast_features), file.path(TD, "ast_constfree.rds"))
cat("[DONE]\n")
