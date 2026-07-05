ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
suppressMessages({ library(data.table); library(xts) })

ppy <- 12
ir_of <- function(a) { a <- a[is.finite(a)]; if (length(a) < 3) return(NA_real_); mean(a)/stats::sd(a)*sqrt(ppy) }
ym <- function(d) format(as.Date(d), "%Y-%m")
INCUMBENT_IR <- 1.416   # book_state.json authoritative net_active_recon_v1 (STR_1715_on_M4_R05_noLayer4)

# ---------------------------------------------------------------------------
# 1. BOOK ACTIVE (incumbent = STR_1715_on_M4_R05_noLayer4_PG2)
#    Authoritative source: contract bt_result (build_benchmark_compare, IR=1.416).
#    Reconciles EXACTLY to 1.416 (net_active_recon_v1) — proven in qual_caution Stage 2.
#    book_active = ret_net - benchmark_ret (contract already merged clean IKS200 monthly).
#    NOTE: variant_returns_xts.rds holds the raw 9 core/defense/blend sleeves, NOT the
#          M4/R05-overlay noLayer4 book; incumbent 1.416 lives only in the contract file.
#          Using contract source keeps incumbent basis identical to book_state.
# ---------------------------------------------------------------------------
bt <- readRDS("qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds")
pr <- as.data.table(bt$period_returns)[, .(date, ret_net)]
br <- as.data.table(bt$benchmark_returns)[, .(date, benchmark_ret)]
book <- merge(pr, br, by = "date"); setorder(book, date)
book <- book[date <= as.Date("2026-06-30")]     # drop corrupted live 2026-07 row
book[, ym := ym(date)]
book[, book_active := ret_net - benchmark_ret]
book[, pos := .I]                                 # sequential month index
book_ir_recon <- ir_of(book$book_active)
cat(sprintf("[book] n=%d  net-active IR recon = %.4f  (incumbent target 1.416)\n",
            nrow(book), book_ir_recon))

# ---------------------------------------------------------------------------
# 2. SLEEVE ACTIVE (qual_q07 — full 258-month sleeve, net_active vs KOSPI200)
#    Stage 1: PORT_t=0.2747, IR=0.0707, 258m (canonical_screen, top-25 EW long-only).
# ---------------------------------------------------------------------------
sl <- as.data.table(readRDS("stage_artifacts/frontier_a_quality_q07/qual_q07_active.rds"))
setnames(sl, "active", "sleeve_active")
sl[, ym := ym(Date)]; setorder(sl, Date)
cat(sprintf("[sleeve qual_q07] n=%d  ym %s .. %s  (Stage1 PORT_t=0.2747 IR=0.0707)\n",
            nrow(sl), min(sl$ym), max(sl$ym)))

# ---------------------------------------------------------------------------
# 3. ALIGNMENT VERIFICATION (MANDATORY misalignment guard) — offset -3..+3 cor scan
#    Align on year-month string. Map sleeve ym -> book sequential pos; shift by k
#    book-positions; correlate over dense overlap. Max |cor| must be at offset 0.
# ---------------------------------------------------------------------------
m <- merge(book[, .(ym, pos, book_active)], sl[, .(ym, sleeve_active)], by = "ym", all.x = TRUE)
setorder(m, pos)
mm <- m[!is.na(sleeve_active)]
cat(sprintf("[align] book months=%d, sleeve dense overlap=%d\n", nrow(m), nrow(mm)))

offs <- -3:3
sc <- sapply(offs, function(k) {
  tgt <- book[match(mm$pos + k, pos), book_active]
  ok <- is.finite(tgt) & is.finite(mm$sleeve_active)
  if (sum(ok) < 20) return(NA_real_)
  stats::cor(mm$sleeve_active[ok], tgt[ok])
})
names(sc) <- as.character(offs)
cat("[align] offset -3..+3 cor(sleeve, book_active):\n"); print(round(sc, 4))
best_off <- offs[which.max(abs(replace(sc, is.na(sc), -Inf)))]
best_off_cor <- sc[as.character(best_off)]
cat(sprintf("[align] max|cor| at offset = %d  (cor=%.4f)\n", best_off, best_off_cor))

ALIGN_OK <- (best_off == 0L)
if (!ALIGN_OK) {
  cat(sprintf("\n*** FAIL LOUD: max-cor offset = %d != 0 — MISALIGNMENT. ABORT dIR. ***\n", best_off))
  saveRDS(list(status="FAILED_ALIGN", best_off=best_off, sc=sc),
          "stage_artifacts/frontier_a_quality_q07/qual_q07_stage2_result.rds")
  quit(status = 0)
}
cat("[align] PASS — max-cor at offset 0.\n")

# active_cor at offset 0 (over dense overlap)
tgt0 <- book[match(mm$pos, pos), book_active]
active_cor <- stats::cor(mm$sleeve_active, tgt0)
cat(sprintf("[cor] active_cor (offset 0, n=%d) = %.4f\n", length(tgt0), active_cor))

# ---------------------------------------------------------------------------
# 4. dIR grid — combined_active = (1-w)*book_active + w*sleeve_active
#    Full sleeve overlaps 258 of 269 book months; outside overlap sleeve=NA -> use
#    book-only months as-is (drop-to-book where sleeve absent, i.e. sleeve_active=0
#    contribution => combined=book_active there). This preserves book's full IR base.
# ---------------------------------------------------------------------------
m[is.na(sleeve_active), sleeve_active := 0]   # book-only months: sleeve contributes 0 delta
setorder(m, pos)
weights <- c(0.05, 0.10, 0.15, 0.20, 0.30)
ir_grid <- sapply(weights, function(w) {
  comb <- (1 - w) * m$book_active + w * m$sleeve_active
  ir_of(comb)
})
names(ir_grid) <- sprintf("%.2f", weights)
cat("\n[dIR] IR_combined grid over w:\n"); print(round(ir_grid, 4))

best_i <- which.max(ir_grid); best_w <- weights[best_i]
best_new_ir <- as.numeric(ir_grid[best_i])
delta_ir <- best_new_ir - INCUMBENT_IR
cat(sprintf("\n[dIR] best_w=%.2f  best_new_book_ir=%.4f  incumbent=%.4f  dIR=%.4f\n",
            best_w, best_new_ir, INCUMBENT_IR, delta_ir))

# ---- GATE (measurement-graduation §4) ----
gate_dir <- delta_ir >= 0.05
gate_cor <- active_cor < 0.30
cat(sprintf("\n[GATE] dIR>=0.05      : %s (dIR=%.4f)\n", gate_dir, delta_ir))
cat(sprintf("[GATE] active_cor<0.30 : %s (cor=%.4f)\n", gate_cor, active_cor))
cat(sprintf("[GATE] PASS(both)      : %s\n", gate_dir && gate_cor))

ir_grid_str <- paste(sprintf("%.2f=%.4f", weights, ir_grid), collapse = "; ")
cat("\n[EMIT] ir_grid_str: ", ir_grid_str, "\n")
cat(sprintf("[EMIT] active_cor=%.4f best_w=%.2f best_new_ir=%.4f dIR=%.4f align_off=%d align_cor=%.4f\n",
            active_cor, best_w, best_new_ir, delta_ir, best_off, best_off_cor))

saveRDS(list(status="MEASURED", book_ir_recon=book_ir_recon, incumbent_ir=INCUMBENT_IR,
             active_cor=active_cor, best_off=best_off, best_off_cor=best_off_cor,
             ir_grid=ir_grid, ir_grid_str=ir_grid_str, best_w=best_w,
             best_new_ir=best_new_ir, delta_ir=delta_ir,
             gate_dir=gate_dir, gate_cor=gate_cor, n_overlap=nrow(mm)),
        "stage_artifacts/frontier_a_quality_q07/qual_q07_stage2_result.rds")
cat("\n[saved] qual_q07_stage2_result.rds\n")
