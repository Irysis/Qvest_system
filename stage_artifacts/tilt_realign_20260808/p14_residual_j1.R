# p14_residual_j1.R — J1: 재현 잔여 7.7% 원인 특정
# 후보 ① 내가 factor DB 에서 z 를 **재계산**했는데 production 은 저장된 R05_z_avg 를 쓴다
#        (§7b: production 코드가 base 권위 — 파생 재계산은 parity 검증 전엔 base 아님)
#      ② q20 문턱: production 은 period_returns_layer5.csv 의 R05_z_avg 전체 분포 q20 사용,
#        나는 expanding q20 사용 → 문턱 정의 자체가 다름
#      ③ β_faith 잔재 / D3 게이트 전환기
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
V <- fread("stage_artifacts/tilt_realign_20260808/p12_beta_recon_detail.csv")
V[, eval_date := as.Date(eval_date)]
prl <- fread("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
cat(sprintf("[prl] %d행 | 컬럼 %s\n", nrow(prl), paste(head(names(prl),12), collapse=",")))
stopifnot("R05_z_avg" %in% names(prl))
dcol <- intersect(c("date","Date","eval_date","realized_ym","return_ym"), names(prl))[1]
cat(sprintf("[prl] 날짜열 = %s | R05_z_avg 유효 %d개 | q20(전체분포) = %.4f\n",
            dcol, sum(is.finite(prl$R05_z_avg)),
            quantile(prl$R05_z_avg[is.finite(prl$R05_z_avg)], 0.20, names=FALSE)))

P <- prl[is.finite(R05_z_avg)]
P[, key := format(as.Date(if (dcol %in% c("realized_ym","return_ym")) paste0(get(dcol),"-01") else get(dcol)), "%Y-%m")]
V[, key := format(eval_date, "%Y-%m")]
M <- merge(V[, .(key, eval_date, regime, z_mine = z_port, zlt_mine = zlt, invested, beta_hat)],
           P[, .(key, z_prod = R05_z_avg)], by="key")
cat(sprintf("\n[매칭] %d개월 | 내 재계산 z vs production 저장 z: cor %.4f · max|Δ| %.4f · 평균|Δ| %.4f\n",
            nrow(M), suppressWarnings(cor(M$z_mine, M$z_prod, use="complete.obs")),
            max(abs(M$z_mine - M$z_prod), na.rm=TRUE), mean(abs(M$z_mine - M$z_prod), na.rm=TRUE)))

q20_full <- quantile(P$R05_z_avg, 0.20, names=FALSE)
M[, zlt_prod := is.finite(z_prod) & z_prod < q20_full]
cat(sprintf("[문턱 판정 일치] 내 expanding-q20 vs production 전체분포-q20: %.1f%% (%d/%d 불일치)\n",
            100*mean(M$zlt_mine == M$zlt_prod, na.rm=TRUE),
            sum(M$zlt_mine != M$zlt_prod, na.rm=TRUE), nrow(M)))
M[, beta_prod := fcase(regime=="CRISIS" & zlt_prod, 0.30, regime=="CRISIS", 0.50,
                       regime=="CAUTION" & zlt_prod, 0.50, regime=="CAUTION", 0.70,
                       regime %in% c("BULL","NORMAL") & zlt_prod, 0.85, default=1.00)]
m4 <- as.data.table(read_parquet("qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet"))
m4[, Date := as.Date(Date)]; m4[, ym := format(Date, "%Y-%m")]
mm <- m4[, .(m4w = weight_str1715[which.max(Date)]), by=ym]
M[, dec_ym := format(as.Date(cut(eval_date, "month")) - 1, "%Y-%m")]
M <- merge(M, mm, by.x="dec_ym", by.y="ym", all.x=TRUE)
M <- M[is.finite(m4w)]
M[, `:=`(recon_mine = m4w*beta_hat, recon_prod = m4w*beta_prod)]
f <- function(x) sprintf("일치 %.1f%% · max|Δ| %.4f · cor %.4f",
        100*mean(abs(M$invested - x) < 1e-6), max(abs(M$invested - x)), suppressWarnings(cor(M$invested, x)))
cat(sprintf("\n[재현 비교, n=%d]\n  m4 × β(내 z·expanding q20)      : %s\n  m4 × β(production z·전체 q20)  : %s\n",
            nrow(M), f(M$recon_mine), f(M$recon_prod)))
cat("\n[잔여 불일치 상위 — production z 판 기준]\n")
print(M[abs(invested-recon_prod) > 1e-6][order(-abs(invested-recon_prod))][1:8,
  .(ym=key, regime, m4w=round(m4w,3), z_prod=round(z_prod,3), zlt_prod,
    recon=round(recon_prod,3), actual=round(invested,3), 잔차=round(invested-recon_prod,3))])
cat(sprintf("\n[판정] z 원천 교체로 재현 %s → 잔여의 주원인은 %s\n",
  ifelse(mean(abs(M$invested-M$recon_prod)<1e-6) > mean(abs(M$invested-M$recon_mine)<1e-6), "개선", "미개선"),
  ifelse(mean(abs(M$invested-M$recon_prod)<1e-6) > mean(abs(M$invested-M$recon_mine)<1e-6),
         "z 재계산/문턱 정의 차이 (§7b — production 저장값이 base 권위)", "다른 성분(β_faith·게이트 전환기 등)")))
fwrite(M, "stage_artifacts/tilt_realign_20260808/p14_residual_detail.csv")
