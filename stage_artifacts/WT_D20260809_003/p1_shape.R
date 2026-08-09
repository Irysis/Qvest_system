## WT-D20260809_003 (FQ-166) P1 — 동일 프레임 분위 프로파일 + 형태 분류
## 사전등록: preregistration.json (측정 전 작성). 형태 규칙·처분 규칙 전부 고정됨.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260809_003")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p1] ", fmt, "\n"), ...)); flush.console() }

source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")   # .nw_t_mean

PRE <- fromJSON(file.path(OUT, "preregistration.json"), simplifyVector = FALSE)
say("사전등록 파싱 OK — 형태규칙 %d · 처분규칙 %d",
    length(PRE$shape_classification_rules_fixed_before_results),
    length(PRE$disposition_rules_fixed_before_results))

## ---- 입력 실측 + 선언 대조 --------------------------------------------------
B <- readRDS(file.path(OUT, "merged_panel.rds"))
say("=== 입력 실측 ===")
say("  merged %d행 · %d개월 · %s ~ %s · %d종목",
    nrow(B), uniqueN(B$Date), min(B$Date), max(B$Date), uniqueN(B$Ticker))
d <- PRE$input_declared
stopifnot(nrow(B) == d$expected_rows, uniqueN(B$Date) == d$expected_months)
say("  선언 대조 통과 (행 %d · 월 %d)", d$expected_rows, d$expected_months)

P <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260809_001/p0_panels.rds"))
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
say("  ret %d행 · liq %d행 (WT-D20260809_001 계약 산출 재사용)", nrow(ret), nrow(liq))

X <- merge(B, ret[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
X <- merge(X, liq[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
say("  +수익/유동성 병합 후 %d행 · %d개월 (수익 커버리지 %.4f)",
    nrow(X), uniqueN(X$Date), nrow(X)/nrow(B))

## ---- 프로파일 산출 ----------------------------------------------------------
profile <- function(D, scorecol, nq) {
  D <- D[!is.na(get(scorecol))]
  D[, nmo := .N, by = Date]; D <- D[nmo >= nq * 5L]
  D[, q := cut(frank(get(scorecol), ties.method = "first"),
               breaks = quantile(seq_len(.N), probs = seq(0, 1, length.out = nq + 1L)),
               include.lowest = TRUE, labels = FALSE), by = Date]
  D[, univ := mean(Ret_1m), by = Date]
  M <- D[, .(r = mean(Ret_1m), u = univ[1], n = .N), by = .(Date, q)]
  M[, ex := r - u]
  res <- M[, .(ann_ex_pct = mean(ex) * 12 * 100, t_nw3 = .nw_t_mean(ex, lag = 3L),
               n_months = .N, avg_n = mean(n)), by = q][order(q)]
  res
}

classify <- function(res, nq) {
  sp  <- suppressWarnings(cor(res$q, res$ann_ex_pct, method = "spearman"))
  am  <- res$q[which.max(res$ann_ex_pct)]
  top <- res[q == nq, ann_ex_pct]; bot <- res[q == 1, ann_ex_pct]
  med <- median(res$ann_ex_pct)
  mid <- if (nq == 5L) 2:4 else 4:8
  cls <- if (!is.na(sp) && sp >= 0.70 && am == nq) "MONOTONE_TOP"
         else if (am %in% mid && top < med) "HUMP"
         else if (!is.na(sp) && sp <= -0.70) "INVERTED"
         else "UNCLASSIFIED"
  list(spearman = sp, argmax = am, top = top, bot = bot, median_ex = med,
       long_side_share = abs(top) / (abs(top) + abs(bot)), class = cls)
}

arms <- list(
  list(tag = "M26_Revenue_Mom", col = "M26_Revenue_Mom", treat = "raw"),
  list(tag = "Q01_EB",          col = "Q01_EB",          treat = "raw"),
  list(tag = "Q01_neutral",     col = "z_neutral",       treat = "neutral"),
  list(tag = "D03_EWMA",        col = "D03_EWMA",        treat = "raw"),
  list(tag = "M01_PATHQ",       col = "M01_PATHQ",       treat = "raw"))

rows <- list(); prof <- list()
for (liqf in c(TRUE, FALSE)) {
  D0 <- if (liqf) X[is.na(adv) | adv >= 2e8] else X
  for (win in c("full_282m", "post2015")) {
    D1 <- if (win == "post2015") D0[Date >= as.Date("2015-01-01")] else D0
    for (nq in c(5L, 10L)) {
      for (a in arms) {
        res <- profile(D1, a$col, nq)
        if (nrow(res) < nq) next
        cl <- classify(res, nq)
        key <- sprintf("%s|%s|q%d|%s", a$tag, win, nq, if (liqf) "liq" else "noliq")
        prof[[key]] <- res
        rows[[length(rows) + 1L]] <- data.table(
          material = a$tag, treatment = a$treat, window = win, nq = nq,
          liq = liqf, n_months = res$n_months[1],
          spearman = cl$spearman, argmax = cl$argmax,
          top_ann = cl$top, bot_ann = cl$bot, median_ann = cl$median_ex,
          long_side_share = cl$long_side_share, shape = cl$class)
      }
    }
  }
}
S <- rbindlist(rows)

say("=== ★1급 프레임: 유동성필터 · 전표본 282m · decile ===")
print(S[liq == TRUE & window == "full_282m" & nq == 10L,
        .(material, treatment, spearman = round(spearman, 3), argmax,
          top_ann = round(top_ann, 3), median_ann = round(median_ann, 3),
          long_side_share = round(long_side_share, 3), shape)])

say("=== WT-003 대조 프레임: 유동성필터 · post2015 · 5분위 ===")
print(S[liq == TRUE & window == "post2015" & nq == 5L,
        .(material, treatment, n_months, spearman = round(spearman, 3), argmax,
          top_ann = round(top_ann, 3), median_ann = round(median_ann, 3), shape)])

say("=== 형태 교차표 (유동성필터 적용분) ===")
print(dcast(S[liq == TRUE], material + treatment ~ window + nq, value.var = "shape"))

say("=== Q01 프로파일 원문 (post2015 · 5분위 · liq) — WT-003 [-3.81 +1.37 +3.05 +1.78 -2.41] 대조 ===")
for (k in c("Q01_EB|post2015|q5|liq", "Q01_neutral|post2015|q5|liq",
            "M26_Revenue_Mom|post2015|q5|liq")) {
  if (!is.null(prof[[k]]))
    say("  %-28s [%s]", k,
        paste(sprintf("%+.2f", prof[[k]]$ann_ex_pct), collapse = " "))
}
say("=== 전표본 decile 원문 (liq) ===")
for (a in arms) {
  k <- sprintf("%s|full_282m|q10|liq", a$tag)
  if (!is.null(prof[[k]]))
    say("  %-18s [%s]", a$tag, paste(sprintf("%+.2f", prof[[k]]$ann_ex_pct), collapse = " "))
}

saveRDS(list(summary = S, profiles = prof), file.path(OUT, "p1_results.rds"))
fwrite(S, file.path(OUT, "p1_shape_summary.csv"))
say("=== P1 완료 — %d 셀 ===", nrow(S))
