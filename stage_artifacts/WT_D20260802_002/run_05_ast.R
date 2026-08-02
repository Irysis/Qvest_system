## run_05_ast.R — AST v1.1 컴파일 + 손빌드 게이트 대조(검증) + 사이드카 배선
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite); library(digest)})
setDTthreads(2); try(arrow::set_io_thread_count(2), silent = TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
TD <- "stage_artifacts/WT_D20260802_002"
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ast/ast_compile.R")

SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
fwd <- as.data.table(SI$fwd_ret); bench <- as.data.table(SI$bench)
liqf <- as.data.table(SI$liqf); SIZE <- as.data.table(SI$SIZE)
S <- as.data.table(read_parquet(file.path(TD, "gate_panel.parquet"))); S[, Date := as.Date(Date)]

LIQ_MIN <- 2e8
BASE <- merge(S, liqf[, .(Date, Ticker, adv2 = adv)], by = c("Date", "Ticker"), all.x = TRUE)
BASE <- BASE[is.na(adv2) | adv2 >= LIQ_MIN][is.finite(score) & is.finite(fa_share_l0)]; BASE[, adv2 := NULL]

## AST 리프 입력 패널 (BASE 와 동일 그리드 — CS_RANK 모집단을 손빌드와 일치시킴)
AIN <- BASE[, .(Date, Ticker, alpha_score_base = score, fa_share_l0)]
write_parquet(AIN, file.path(TD, "ast_input_panel.parquet"))
h <- digest::digest(file = file.path(TD, "ast_input_panel.parquet"), algo = "sha1")
cat(sprintf("[ast_input_panel] rows=%d sha1=%s\n", nrow(AIN), h))

## 실제 해시를 AST 계약에 주입 (placeholder 제거)
astj <- fromJSON(file.path(TD, "ast_F1_gated_score.json"), simplifyVector = FALSE)
astj$args[[1]]$contract$store_build_hash <- h
astj$args[[2]]$args[[1]]$args[[1]]$args[[1]]$contract$store_build_hash <- h
astj$args[[2]]$args[[1]]$args[[1]]$args[[1]]$args <- NULL   # 이전 오주입 잔재 제거
write_json(astj, file.path(TD, "ast_F1_gated_score.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")

eval_dates <- sort(unique(BASE$Date))
cmp <- ast_compile(astj, eval_dates = eval_dates,
                   universe = BASE[, .(Date, Ticker)],
                   manifest_out = file.path(TD, "ast_manifest_F1.json"))
pan <- cmp$panel[is.finite(value)]
cat(sprintf("[ast_compile] 산출 non-NA 셀=%d (그리드 %d)  월수=%d\n",
            nrow(pan), nrow(cmp$panel), uniqueN(pan$Date)))
cat("[ast_features]\n"); print(cmp$manifest$ast_features)
cat("[operator_counts]\n"); print(cmp$manifest$operator_counts)

## ── 검증: 컴파일러 게이트 vs 손빌드 B_gate 일치 ────────────────────────────────
hand <- copy(BASE); hand[, gate := frank(-fa_share_l0, ties.method = "first") <= ceiling(.N / 2), by = Date]
hand_g <- hand[gate == TRUE, .(Date, Ticker, score_hand = score)]
mm <- merge(pan[, .(Date, Ticker, score_ast = value)], hand_g, by = c("Date", "Ticker"), all = TRUE)
n_both <- mm[is.finite(score_ast) & is.finite(score_hand), .N]
n_ast_only <- mm[is.finite(score_ast) & is.na(score_hand), .N]
n_hand_only <- mm[is.na(score_ast) & is.finite(score_hand), .N]
maxd <- if (n_both > 0) mm[is.finite(score_ast) & is.finite(score_hand), max(abs(score_ast - score_hand))] else NA_real_
cat(sprintf("[검증 컴파일러 vs 손빌드] both=%d ast_only=%d hand_only=%d max|d|=%.3e\n",
            n_both, n_ast_only, n_hand_only, maxd))
jaccard <- n_both / (n_both + n_ast_only + n_hand_only)
cat(sprintf("[검증] 멤버십 Jaccard=%.6f  (1.0 = 완전일치)\n", jaccard))

## ── 사이드카 배선: ast_features 를 실제로 전달해 재측정 ─────────────────────────
AF <- cmp$manifest$ast_features
r_gate <- canonical_screen_bt(pan[, .(Date, Ticker, score = value)], fwd, bench,
                              top_n = 25L, cost_bps_oneway = 15, liq_dt = liqf, liq_min = LIQ_MIN,
                              size_dt = SIZE, run_id = "fq084_B_gate_AST",
                              strategy_id = "FQ084_B_gate_AST", ast_features = AF)
## base arm 도 AST(리프 단독) 로 컴파일해 동일 사이드카 경로 통과
ast_base <- astj$args[[1]]
cmpb <- ast_compile(ast_base, eval_dates = eval_dates, universe = BASE[, .(Date, Ticker)],
                    manifest_out = file.path(TD, "ast_manifest_F0_base.json"))
panb <- cmpb$panel[is.finite(value)]
r_base <- canonical_screen_bt(panb[, .(Date, Ticker, score = value)], fwd, bench,
                              top_n = 25L, cost_bps_oneway = 15, liq_dt = liqf, liq_min = LIQ_MIN,
                              size_dt = SIZE, run_id = "fq084_A_base_AST",
                              strategy_id = "FQ084_A_base_AST",
                              ast_features = cmpb$manifest$ast_features)
cat(sprintf("\n[AST 경로 실측] A_base PORT_t=%+.3f (n=%d) / B_gate PORT_t=%+.3f (n=%d)\n",
            r_base$portfolio_alpha_t_nw_lag3, r_base$n_months,
            r_gate$portfolio_alpha_t_nw_lag3, r_gate$n_months))

saveRDS(list(sha1 = h, features = AF, op_counts = cmp$manifest$operator_counts,
             verify = list(n_both = n_both, n_ast_only = n_ast_only, n_hand_only = n_hand_only,
                           max_abs_diff = maxd, jaccard = jaccard),
             ast_port_t_base = r_base$portfolio_alpha_t_nw_lag3,
             ast_port_t_gate = r_gate$portfolio_alpha_t_nw_lag3),
        file.path(TD, "ast_run.rds"))
cat("[DONE]\n")
