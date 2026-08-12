## AZ1c — INVERTED 형태 census (329 팩터, C15 loader 경유)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  Z_Score_Aligned 는 **IC 기반 방향 정렬**을 거쳤다 → rank-IC 는 양수 방향으로 맞춰져 있다.
##  ⇒ 찾는 것은 **rank-IC 양수인데 decile 평균 프로파일은 역전**인 재료 = D03 패턴
##     (오늘 실측: D03 rank-IC +0.0322 t 3.00 ↔ decile 평균 기울기 -0.685).
##  형태 규칙 = p1_shape.R::classify 원문 승계(재작성 금지).
##  표본: 전 기간에서 6개월 간격 샘플(계산량 관리 — census 목적이라 전월 불요), 유동성 adv>=2e8.
##   BA1 표본 확보: INVERTED >= 2건(D03 외) → AE3 를 FQ-171 대기 없이 착수
##   BA2 희소: 0~1건 → INVERTED 는 드물고 'D03 고유' 증거 강화
##  ★census 만. 성과 측정·결합은 별도 사전등록.
suppressPackageStartupMessages({ library(data.table) ; library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
ds_all <- sort(unique(ret$Date))
ds <- ds_all[seq(1, length(ds_all), by = 6L)]
ds <- ds[ds >= as.Date("2005-01-01")]
cat(sprintf("[표본] %d개월 (6개월 간격) · %s ~ %s\n", length(ds), min(ds), max(ds)))

acc <- list()
for (dt in ds) {
  z <- try(load_month_factors(as.Date(dt)), silent = TRUE)
  if (inherits(z, "try-error")) next
  z <- as.data.table(z)
  R <- ret[Date == dt, .(Ticker, Ret_1m)]
  L <- liq[Date == dt, .(Ticker, adv)]
  M <- merge(z, R, by = "Ticker")
  M <- merge(M, L, by = "Ticker", all.x = TRUE)
  M <- M[(is.na(adv) | adv >= 2e8) & !is.na(Z_Score_Aligned)]
  if (!nrow(M)) next
  M[, n_f := .N, by = Factor_Name]
  M <- M[n_f >= 60L]
  if (!nrow(M)) next
  M[, q := cut(frank(Z_Score_Aligned, ties.method="first"),
               breaks = quantile(seq_len(.N), probs = seq(0,1,length.out=11L)),
               include.lowest = TRUE, labels = FALSE), by = Factor_Name]
  u <- mean(M[!duplicated(Ticker)]$Ret_1m)
  acc[[length(acc)+1L]] <- M[, .(ex = mean(Ret_1m) - u, ic = cor(Z_Score_Aligned, Ret_1m, method="spearman")),
                             by = .(Factor_Name, q)]
}
A <- rbindlist(acc)
cat(sprintf("[누적] %d 셀 · 팩터 %d종\n", nrow(A), uniqueN(A$Factor_Name)))
PR <- A[, .(ann = mean(ex)*12*100), by = .(Factor_Name, q)]
IC <- A[, .(ic = mean(ic, na.rm=TRUE)), by = Factor_Name]

classify <- function(d) {
  d <- d[order(q)]
  sp <- suppressWarnings(cor(d$q, d$ann, method="spearman"))
  am <- d$q[which.max(d$ann)]; top <- d[q==10, ann]; med <- median(d$ann)
  if (!is.na(sp) && sp >= 0.70 && am == 10L) "MONOTONE_TOP"
  else if (am %in% 4:8 && length(top) && top < med) "HUMP"
  else if (!is.na(sp) && sp <= -0.70) "INVERTED"
  else "UNCLASSIFIED"
}
S <- PR[, .(shape = classify(.SD), sp = round(suppressWarnings(cor(q, ann, method="spearman")),3),
            argmax = q[which.max(ann)]), by = Factor_Name]
S <- merge(S, IC, by = "Factor_Name")
print(S[, .N, by = shape][order(-N)])
INV <- S[shape == "INVERTED"][order(-ic)]
cat(sprintf("\n=== INVERTED %d종 (rank-IC 내림차순, 상위 15) ===\n", nrow(INV)))
print(head(INV[, .(Factor_Name, sp, argmax, ic = round(ic,4))], 15))
verdict <- if (nrow(INV) >= 2L) "BA1_SAMPLE_AVAILABLE" else "BA2_INVERTED_RARE"
cat(sprintf("\n판정: %s\n★census 전용 — 성과 측정 없음\n", verdict))
fwrite(S, file.path(OUT,"az1_shape_census.csv"))
write_json(list(verdict=verdict, n_factors=nrow(S), n_inverted=nrow(INV),
                shape_counts=as.list(table(S$shape)), top_inverted=head(INV$Factor_Name, 20)),
           file.path(OUT,"az1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
