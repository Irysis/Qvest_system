## E2 — argmax(및 형태 분류)의 프레임 불변성 정량화
## 물음: 형태 분류를 **소비 규칙**으로 쓸 수 있는가? 밴드가 프레임을 따라 움직이면 기술통계다.
## 프레임 축 4개 x 재료 5종. 분류 규칙은 WT-D20260809_003 p1_shape.R::classify 와 동일(재작성 아님).
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

B   <- readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")
P   <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
X <- merge(as.data.table(B), ret[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
X <- merge(X, liq[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
cat(sprintf("[입력 실측] %d행 · %d개월\n", nrow(X), uniqueN(X$Date)))

profile <- function(D, sc, nq, nmo_min) {
  D <- D[!is.na(get(sc))]
  D[, nmo := .N, by = Date]; D <- D[nmo >= nmo_min]
  if (!nrow(D)) return(NULL)
  D[, q := cut(frank(get(sc), ties.method="first"),
               breaks = quantile(seq_len(.N), probs = seq(0,1,length.out=nq+1L)),
               include.lowest = TRUE, labels = FALSE), by = Date]
  D[, univ := mean(Ret_1m), by = Date]
  M <- D[, .(ex = mean(Ret_1m) - univ[1]), by = .(Date,q)]
  M[, .(ann = mean(ex)*12*100, nm = .N), by = q][order(q)]
}
# ★분류 규칙 = p1_shape.R 원문 그대로 (재작성 금지)
classify <- function(res, nq) {
  sp  <- suppressWarnings(cor(res$q, res$ann, method="spearman"))
  am  <- res$q[which.max(res$ann)]
  top <- res[q == nq, ann]; med <- median(res$ann)
  mid <- if (nq == 5L) 2:4 else 4:8
  if (!is.na(sp) && sp >= 0.70 && am == nq) "MONOTONE_TOP"
  else if (am %in% mid && top < med) "HUMP"
  else if (!is.na(sp) && sp <= -0.70) "INVERTED"
  else "UNCLASSIFIED"
}

mats <- c("M26_Revenue_Mom","M01_PATHQ","Q01_EB","D03_EWMA","z_neutral")
rows <- list()
for (sc in mats) for (lf in c(TRUE,FALSE)) for (win in c("full","post2015"))
  for (nq in c(5L,10L)) for (nm in c(50L,125L)) {
    D0 <- if (lf) X[is.na(adv) | adv >= 2e8] else X
    D1 <- if (win == "post2015") D0[Date >= as.Date("2015-01-01")] else D0
    r <- profile(D1, sc, nq, nm); if (is.null(r) || nrow(r) < nq) next
    a <- r$q[which.max(r$ann)]
    rows[[length(rows)+1L]] <- data.table(
      material = sc, liq = lf, window = win, nq = nq, nmo_min = nm,
      argmax = a, argmax_pctile = (a - 0.5)/nq,      # 해상도 무관 비교용
      shape = classify(r, nq))
  }
S <- rbindlist(rows)

cat("\n=== 재료별 argmax 백분위 이동 폭 (16 프레임) ===\n")
agg <- S[, .(n_frames = .N,
             pctile_min = round(min(argmax_pctile),2),
             pctile_max = round(max(argmax_pctile),2),
             pctile_range = round(max(argmax_pctile)-min(argmax_pctile),2),
             n_distinct_shape = uniqueN(shape),
             shapes = paste(sort(unique(shape)), collapse="/")), by = material]
print(agg[])

cat("\n=== 형태 분류 교차표 (재료 x 프레임) ===\n")
print(dcast(S, material ~ liq + window + nq + nmo_min, value.var = "shape"))

stable <- agg[pctile_range <= 0.20 & n_distinct_shape == 1L]
cat(sprintf("\n=== E2 판정 ===\n프레임-안정 재료(백분위 이동 <=0.20 ∧ 형태 단일): %d/%d\n",
            nrow(stable), nrow(agg)))
cat(sprintf("형태가 2종 이상으로 갈리는 재료: %d\n", sum(agg$n_distinct_shape > 1L)))
verdict <- {
  if (nrow(stable) >= 4L) "ARGMAX_FRAME_STABLE"
  else if (nrow(stable) == 0L) "ARGMAX_FRAME_UNSTABLE_ALL"
  else "ARGMAX_FRAME_MIXED"
}
cat(sprintf("판정: %s\n", verdict))

fwrite(S, file.path(OUT, "e2_argmax_frames.csv"))
write_json(list(verdict = verdict, n_stable = nrow(stable), agg = agg),
           file.path(OUT, "e2_result.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
