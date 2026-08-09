## FQ-169 P2 — 평균/순위 괴리 전수 스크린 (분류 규칙은 preregistration.json 에 측정 전 고정)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ169")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")   # .nw_t_mean

PRE <- fromJSON(file.path(OUT, "preregistration.json"), simplifyVector = FALSE)
say("사전등록 파싱 OK — 예측 %d · 분류 %d",
    length(PRE$predictions_fixed_before_measurement), length(PRE$classification_fixed_before_results))

W <- readRDS(file.path(OUT, "panel.rds"))
W <- W[is.na(adv) | adv >= 2e8]
say("=== 입력 실측 === %d행 · %d개월 · %s ~ %s · %d종목",
    nrow(W), uniqueN(W$Date), min(W$Date), max(W$Date), uniqueN(W$Ticker))
say("  월별 종목수 중앙 %.0f (decile 당 %.0f)", median(W[, .N, by=Date]$N), median(W[, .N, by=Date]$N)/10)

TARG <- c("D34_RealVol_21d","D35_RealVol_63d","D36_RealVol_126d","D41_Vol_of_Vol",
          "D42_EWMA_Vol","D45_Downside_Dev","D47_CVaR_5pct","D50_MaxDrawdown")
POS  <- "D03_RealVol"; NEG <- c("M26_Revenue_Mom","M01_Mom_12_1")

skew1 <- function(v){ v<-v[is.finite(v)]; n<-length(v); if(n<3) return(NA_real_)
  s<-sd(v); if(!is.finite(s)||s==0) return(NA_real_); sum((v-mean(v))^3)/n/s^3 }

one <- function(k) {
  D <- W[!is.na(get(k))]
  D[, nmo := .N, by = Date]; D <- D[nmo >= 50L]
  D[, dec := cut(frank(get(k), ties.method="first"),
                 breaks = quantile(seq_len(.N), probs = seq(0,1,0.1)),
                 include.lowest = TRUE, labels = FALSE), by = Date]
  D[, `:=`(um = mean(Ret_1m), ud = median(Ret_1m)), by = Date]
  M <- D[, .(mn = mean(Ret_1m) - um[1], md = median(Ret_1m) - ud[1]), by = .(Date, dec)]
  G <- D[, .(skew = skew1(Ret_1m), sdv = sd(Ret_1m)), by = dec]
  R <- M[, .(mean_ann = mean(mn)*12*100, med_ann = mean(md)*12*100,
             mean_t = .nw_t_mean(mn, lag=3L), med_t = .nw_t_mean(md, lag=3L)), by = dec]
  R <- merge(R, G, by="dec")[order(dec)]; R[, gap := mean_ann - med_ann]
  ic <- D[, .(ic = suppressWarnings(cor(get(k), Ret_1m, method="spearman"))), by=Date][!is.na(ic)]
  sp <- function(a,b) suppressWarnings(cor(a,b,method="spearman"))
  list(tab = R, row = data.table(
    factor = k, n_months = uniqueN(D$Date),
    sp_mean = sp(R$dec, R$mean_ann), sp_med = sp(R$dec, R$med_ann),
    sp_gap = sp(R$dec, R$gap), sp_skew = sp(R$dec, R$skew),
    rank_ic = mean(ic$ic), rank_ic_t = .nw_t_mean(ic$ic, lag=3L),
    top_mean = R[dec==10, mean_ann], top_med = R[dec==10, med_ann],
    sd_D1 = R[dec==1, sdv], sd_D10 = R[dec==10, sdv]))
}

res <- list(); rows <- list()
for (k in c(TARG, POS, NEG)) { o <- one(k); res[[k]] <- o$tab; rows[[k]] <- o$row
  say("  %-18s sp_mean %+.3f | sp_med %+.3f | gap %+.3f | skew %+.3f | rIC %+.4f (t %+.2f)",
      k, o$row$sp_mean, o$row$sp_med, o$row$sp_gap, o$row$sp_skew, o$row$rank_ic, o$row$rank_ic_t) }
S <- rbindlist(rows)

## 사전등록 분류 규칙 적용
S[, cls := fifelse(sign(sp_mean) != sign(sp_med) & abs(sp_mean) >= 0.30 & abs(sp_med) >= 0.30, "DIVERGENT",
            fifelse(abs(sp_mean) < 0.30 & abs(sp_med) < 0.30, "WEAK",
            fifelse(abs(sp_mean - sp_med) >= 0.80, "PARTIAL", "ALIGNED")))]
S[, role := fifelse(factor %in% TARG, "target", fifelse(factor == POS, "pos_control", "neg_control"))]
say("=== 분류 결과 ===")
print(S[, .(factor, role, sp_mean = round(sp_mean,3), sp_med = round(sp_med,3),
            sp_gap = round(sp_gap,3), sd_ratio = round(sd_D1/sd_D10,2),
            rank_ic_t = round(rank_ic_t,2), cls)])

nd <- S[role=="target" & cls=="DIVERGENT", .N]
say("=== ★예측 판정 ===")
say("  대상 8종 중 DIVERGENT = %d", nd)
say("  G1 (>=4 -> FAMILY_WIDE)  : %s", nd >= 4)
say("  G2 (<=1 -> D03_SPECIFIC) : %s", nd <= 1)
say("  중간(2~3) -> PARTIAL_FAMILY : %s", nd %in% 2:3)
say("  G3 음성대조 ALIGNED?      : %s",
    paste(sprintf("%s=%s", S[role=="neg_control", factor], S[role=="neg_control", cls]), collapse=" · "))
say("  G4 양성대조 D03_RealVol   : %s", S[role=="pos_control", cls])
verdict <- if (S[role=="neg_control", any(cls == "DIVERGENT")]) "HOLD_DESIGN_SUSPECT" else
           if (nd >= 4) "FAMILY_WIDE" else if (nd <= 1) "D03_SPECIFIC" else "PARTIAL_FAMILY"
say("  ★판정: %s", verdict)

## 상관(선언한 교락 — 8종은 독립 8검정이 아니다)
say("=== 대상 8종 + D03 횡단면 상관(월평균 spearman) ===")
CC <- W[, {m <- .SD[, c(TARG, POS), with=FALSE]
           as.data.table(as.table(suppressWarnings(cor(m, method="spearman", use="pairwise.complete.obs"))))},
        by = Date][, .(rho = mean(N, na.rm=TRUE)), by = .(V1, V2)]
print(dcast(CC, V1 ~ V2, value.var="rho")[, lapply(.SD, function(x) if(is.numeric(x)) round(x,2) else x)])

saveRDS(list(summary = S, tables = res, verdict = verdict, cor = CC), file.path(OUT, "p2_results.rds"))
fwrite(S, file.path(OUT, "p2_divergence_summary.csv"))
fwrite(rbindlist(lapply(names(res), function(k) cbind(factor=k, res[[k]]))), file.path(OUT, "p2_decile_detail.csv"))
say("=== P2 완료 ===")
