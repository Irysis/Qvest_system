setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/meta/axiom_replay")
source("R/wp1_promotion.R")
led <- ar_load_ledger(1); att <- ar_attempts_df(led); ent <- ar_entries_df(led, att)
cache <- new.env(parent = emptyenv())
ent$base_port_t <- vapply(ent$base_artifacts, .wp1_base_port_t, numeric(1), cache = cache)

cat("=== 기저 관문 현황 ===\n")
cat("  파킹(skipped_base_quality 사유):", sum(grepl("기저|base", ent$parked_reason %||% "", ignore.case=TRUE), na.rm=TRUE),
    " / 전체 파킹", sum(ent$status == "parked"), "\n")
cat("  파킹 entry 의 시도 칸 합계:", sum(ent$n_cells[ent$status == "parked"]), "\n")
cat("  기저 PORT_t 회수:", sum(is.finite(ent$base_port_t)), "/", nrow(ent), "\n")

# 착수한 entry = 측정 칸이 있는 것. 원본(root/rescued/combo) 만 — 승격은 기저가 부모다.
run <- ent[ent$n_measured > 0 & ent$kind != "promo" & is.finite(ent$base_port_t), ]
cat("\n=== (1) 기저 PORT_t 가 최종 최고 PORT_t 를 예측하는가 (착수분 n=", nrow(run), ") ===\n", sep="")
set.seed(20260918)
x <- run$base_port_t; y <- run$best_port_t
rho <- suppressWarnings(cor(x, y, method = "spearman"))
bs <- replicate(4000, { i <- sample(seq_along(x), length(x), TRUE)
  if (length(unique(x[i])) < 2 || length(unique(y[i])) < 2) NA_real_ else suppressWarnings(cor(x[i], y[i], method="spearman")) })
ci <- quantile(bs, c(.025,.975), na.rm=TRUE)
cat(sprintf("  Spearman rho = %+.3f  95%%CI [%+.3f, %+.3f]  -> %s\n", rho, ci[1], ci[2],
            if (ci[1] > 0) "유의하게 양수" else if (ci[2] < 0) "유의하게 음수" else "0 포함 — 예측력 근거 없음"))
q <- quantile(x, c(0,.25,.5,.75,1)); run$qb <- cut(x, q, include.lowest=TRUE, labels=c("Q1","Q2","Q3","Q4"))
cat("\n  기저 사분위별 최종 최고 PORT_t:\n")
for (l in levels(run$qb)) { s <- run[run$qb == l, ]
  cat(sprintf("    %s  기저[%+.2f,%+.2f]  n=%d  최고 중앙 %.3f  최대 %.3f\n", l,
      min(s$base_port_t), max(s$base_port_t), nrow(s), median(s$best_port_t), max(s$best_port_t))) }
topq <- quantile(run$best_port_t, .75)
low  <- run[run$base_port_t >= 0 & run$base_port_t <= 0.5, ]
cat(sprintf("\n  기저가 [0, 0.5] 인 entry %d건 중 최종 최고가 상위 사분위(>=%.3f)에 든 건수: %d\n",
            nrow(low), topq, sum(low$best_port_t >= topq)))
cat("\n=== (2) 구제 우회 2건 (n=2 — 판정 근거 아님) ===\n")
r2 <- ent[ent$kind == "rescued" | grepl("rescued", ent$base_id), ]
for (i in seq_len(nrow(r2))) cat(sprintf("  %-46s 기저 %+.3f(%s) -> 최고 %.3f (%s) · 칸 %d\n",
    sub("^RP_2026","",r2$base_id[i]), r2$base_port_t[i], r2$base_grade[i], r2$best_port_t[i], r2$best_grade[i], r2$n_cells[i]))
