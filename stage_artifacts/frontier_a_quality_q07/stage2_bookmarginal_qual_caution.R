ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
suppressMessages({ library(data.table); library(xts) })

ppy <- 12
ir_of <- function(a) { a <- a[is.finite(a)]; if (length(a) < 3) return(NA_real_); mean(a)/stats::sd(a)*sqrt(ppy) }
ym <- function(d) format(as.Date(d), "%Y-%m")

# ---------------------------------------------------------------------------
# 1. BOOK ACTIVE (incumbent = STR_1715_on_M4_R05_noLayer4_PG2)
#    authoritative source: WT-D20260702_002 bt_result_C_noL4_CLEAN_ann12.rds
#    (contract build_benchmark_compare, IR=1.416, 269m, net-active vs KOSPI200)
#    book_active = ret_net - benchmark_ret (contract already merged clean IKS200)
# ---------------------------------------------------------------------------
bt <- readRDS("qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds")
pr <- as.data.table(bt$period_returns)[, .(date, ret_net)]
br <- as.data.table(bt$benchmark_returns)[, .(date, benchmark_ret)]
book <- merge(pr, br, by = "date")
setorder(book, date)
# window: Date <= 2026-06-30 (drop corrupted live 2026-07 if any)
book <- book[date <= as.Date("2026-06-30")]
book[, ym := ym(date)]
book[, book_active := ret_net - benchmark_ret]

# sanity: reproduce incumbent IR from this series
book_ir_recon <- ir_of(book$book_active)
cat(sprintf("[book] n=%d  net-active IR recon = %.4f  (book_state incumbent = 1.416)\n",
            nrow(book), book_ir_recon))
cat(sprintf("[book] Active_Return_Mean=%.6f  TE=%.6f\n",
            mean(book$book_active), stats::sd(book$book_active)))

INCUMBENT_IR <- 1.416   # book_state.json authoritative net_active_recon_v1

# ---------------------------------------------------------------------------
# 2. SLEEVE ACTIVE (qual_caution — regime-conditional, holds quality only in CAUTION)
#    qual_caution_active.rds = the 13 CAUTION-month active returns (net_active)
# ---------------------------------------------------------------------------
sl <- as.data.table(readRDS("stage_artifacts/frontier_a_quality_q07/qual_caution_active.rds"))
setnames(sl, "active", "sleeve_active")
sl[, ym := ym(Date)]
setorder(sl, Date)
cat(sprintf("\n[sleeve qual_caution] n=%d months, ym range %s .. %s\n",
            nrow(sl), min(sl$ym), max(sl$ym)))
cat(sprintf("[sleeve] Stage1: PORT_t=0.3797 IR=0.3108 (sleeve standalone over its 13 active months)\n"))

# ---------------------------------------------------------------------------
# 3. ALIGNMENT VERIFICATION — offset -3..+3 cor scan (MANDATORY, misalignment guard)
#    Align on year-month. Shift sleeve ym by k months, correlate with book_active
#    over the OVERLAPPING months (the 13 CAUTION months). Max cor must be at offset 0.
# ---------------------------------------------------------------------------
# Build a monthly index for book (sequential position by ym)
book_seq <- book[, .(ym, book_active)]
book_seq[, pos := .I]                      # sequential month position in book
ympos <- book_seq[, .(ym, pos)]

# map sleeve ym -> book pos
sl2 <- merge(sl[, .(ym, sleeve_active)], ympos, by = "ym", all.x = TRUE)
cat(sprintf("\n[align] sleeve months mapped into book index: %d of %d\n",
            sum(!is.na(sl2$pos)), nrow(sl2)))
if (any(is.na(sl2$pos))) {
  cat("[align] WARN sleeve months NOT in book index:\n")
  print(sl2[is.na(pos), ym])
}
sl2 <- sl2[!is.na(pos)]

offsets <- -3:3
cor_scan <- sapply(offsets, function(k) {
  # sleeve month at book pos p is compared to book_active at pos p+k
  tgt <- book_seq[match(sl2$pos + k, pos), book_active]
  ok <- is.finite(tgt) & is.finite(sl2$sleeve_active)
  if (sum(ok) < 4) return(NA_real_)
  stats::cor(sl2$sleeve_active[ok], tgt[ok])
})
names(cor_scan) <- as.character(offsets)
cat("\n[align] offset -3..+3 cor(sleeve, book_active):\n")
print(round(cor_scan, 4))
best_off <- offsets[which.max(abs(replace(cor_scan, is.na(cor_scan), -Inf)))]
best_off_cor <- cor_scan[as.character(best_off)]
cat(sprintf("[align] max|cor| at offset = %d  (cor = %.4f)\n", best_off, best_off_cor))

ALIGN_OK <- (best_off == 0L)
if (!ALIGN_OK) {
  cat(sprintf("\n*** FAIL LOUD: max-cor offset = %d != 0 — MISALIGNMENT. ABORT dIR. ***\n", best_off))
} else {
  cat("[align] PASS — max-cor at offset 0, alignment confirmed.\n")
}

# active_cor at offset 0 (over the 13 overlapping CAUTION months)
tgt0 <- book_seq[match(sl2$pos, pos), book_active]
active_cor <- stats::cor(sl2$sleeve_active, tgt0)
cat(sprintf("\n[cor] active_cor (offset 0, n=%d overlap) = %.4f\n", length(tgt0), active_cor))

# ---------------------------------------------------------------------------
# 4. dIR grid — combined_active = (1-w)*book_active + w*sleeve_active
#    Regime-conditional sleeve: contributes ONLY in its 13 CAUTION months;
#    elsewhere sleeve diverges 0 from book (flat -> sleeve_active=0 outside CAUTION).
#    So build sleeve_active_full over ALL book months (0 outside CAUTION).
# ---------------------------------------------------------------------------
if (ALIGN_OK) {
  sleeve_full <- merge(book_seq[, .(ym, pos, book_active)],
                       sl[, .(ym, sleeve_active)], by = "ym", all.x = TRUE)
  sleeve_full[is.na(sleeve_active), sleeve_active := 0]   # 0 outside CAUTION (sleeve flat = book)
  setorder(sleeve_full, pos)

  weights <- c(0.05, 0.10, 0.15, 0.20, 0.30)
  ir_grid <- sapply(weights, function(w) {
    comb <- (1 - w) * sleeve_full$book_active + w * sleeve_full$sleeve_active
    ir_of(comb)
  })
  names(ir_grid) <- sprintf("%.2f", weights)
  cat("\n[dIR] IR_combined grid over w:\n")
  print(round(ir_grid, 4))

  best_i <- which.max(ir_grid)
  best_w <- weights[best_i]
  best_new_ir <- ir_grid[best_i]
  delta_ir <- best_new_ir - INCUMBENT_IR
  cat(sprintf("\n[dIR] best_w=%.2f  best_new_book_ir=%.4f  incumbent=%.4f  dIR=%.4f\n",
              best_w, best_new_ir, INCUMBENT_IR, delta_ir))

  # ---- GATE ----
  gate_dir  <- delta_ir >= 0.05
  gate_cor  <- active_cor < 0.30
  cat(sprintf("\n[GATE] dIR>=0.05 : %s (dIR=%.4f)\n", gate_dir, delta_ir))
  cat(sprintf("[GATE] active_cor<0.30 : %s (cor=%.4f)\n", gate_cor, active_cor))
  cat(sprintf("[GATE] PASS(both) : %s\n", gate_dir && gate_cor))

  ir_grid_str <- paste(sprintf("%.2f=%.4f", weights, ir_grid), collapse="; ")
  cat("\n[EMIT] ir_grid_str: ", ir_grid_str, "\n")
  cat(sprintf("[EMIT] active_cor=%.4f best_w=%.2f best_new_ir=%.4f dIR=%.4f align_off=%d align_cor=%.4f\n",
              active_cor, best_w, best_new_ir, delta_ir, best_off, best_off_cor))

  saveRDS(list(book_ir_recon=book_ir_recon, incumbent_ir=INCUMBENT_IR,
               active_cor=active_cor, best_off=best_off, best_off_cor=best_off_cor,
               ir_grid=ir_grid, best_w=best_w, best_new_ir=best_new_ir, delta_ir=delta_ir,
               gate_dir=gate_dir, gate_cor=gate_cor),
          "stage_artifacts/frontier_a_quality_q07/qual_caution_stage2_result.rds")
}
