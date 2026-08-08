# p15_residual_j1b.R — J1b: 문턱 정의 축 마저 분리
# p14 잔여 패턴: z_prod 0.18~0.29 인 초기 달들이 실제로는 '문턱 이하'로 처리됐고(actual 0.85),
#   2022-10 은 z 0.177 < 0.1817 인데 처리 안 됨 → 문턱이 **정적 전체분포 q20 이 아니라 expanding**임을 시사.
# 4 조합 대조: z 원천(내 재계산 vs production 저장) × 문턱(expanding vs 정적 전체분포)
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
M <- fread("stage_artifacts/tilt_realign_20260808/p14_residual_detail.csv")
M[, eval_date := as.Date(eval_date)]
setorder(M, eval_date)
expq <- function(x, p=0.20, mn=36L) sapply(seq_along(x), function(i) if (i<=mn) NA_real_ else quantile(x[1:(i-1)], p, names=FALSE, na.rm=TRUE))
q_static <- quantile(M$z_prod[is.finite(M$z_prod)], 0.20, names=FALSE)
M[, `:=`(q_exp_mine = expq(z_mine), q_exp_prod = expq(z_prod))]
beta_of <- function(flag) fcase(M$regime=="CRISIS" & flag, 0.30, M$regime=="CRISIS", 0.50,
                                M$regime=="CAUTION" & flag, 0.50, M$regime=="CAUTION", 0.70,
                                M$regime %in% c("BULL","NORMAL") & flag, 0.85, default=1.00)
combos <- list(
  "내 z × expanding q20"        = is.finite(M$q_exp_mine) & M$z_mine < M$q_exp_mine,
  "내 z × 정적 전체 q20"        = M$z_mine < quantile(M$z_mine[is.finite(M$z_mine)],0.20,names=FALSE),
  "production z × expanding q20"= is.finite(M$q_exp_prod) & M$z_prod < M$q_exp_prod,
  "production z × 정적 전체 q20"= M$z_prod < q_static)
rows <- lapply(names(combos), function(nm) {
  fl <- combos[[nm]]; fl[is.na(fl)] <- FALSE
  rc <- M$m4w * beta_of(fl)
  data.table(조합=nm, 발화=sum(fl), 일치율=round(100*mean(abs(M$invested-rc)<1e-6),1),
             `max|Δ|`=round(max(abs(M$invested-rc)),4), cor=round(suppressWarnings(cor(M$invested,rc)),4))
})
out <- rbindlist(rows); setorder(out, -일치율)
cat(sprintf("[표본] %d개월 | 정적 q20(production z) = %.4f\n\n", nrow(M), q_static))
cat("===== 재현 조합 대조 =====\n"); print(out)
best <- out[1]
cat(sprintf("\n[최선] %s → 일치 %.1f%% (cor %.4f)\n", best$조합, best$일치율, best$cor))
cat(sprintf("[z 원천 효과] production z 평균 일치율 %.1f%% vs 내 재계산 %.1f%%\n",
            mean(out[grepl("production", 조합), 일치율]), mean(out[grepl("내 z", 조합), 일치율])))
cat(sprintf("[문턱 효과] expanding 평균 %.1f%% vs 정적 %.1f%%\n",
            mean(out[grepl("expanding", 조합), 일치율]), mean(out[grepl("정적", 조합), 일치율])))
fl <- combos[[best$조합]]; fl[is.na(fl)] <- FALSE
rc <- M$m4w * beta_of(fl)
cat("\n[최선 조합의 잔여 불일치]\n")
print(M[abs(M$invested-rc) > 1e-6][order(-abs(invested-rc))][1:8,
  .(ym=key, regime, m4w=round(m4w,3), z_prod=round(z_prod,3), actual=round(invested,3))])
cat(sprintf("\n[결론] 재현 상한 %.1f%% — I1(β 매핑 재설계) 재개 가능 여부: %s\n", best$일치율,
            ifelse(best$일치율 >= 98, "가능(≥98%)", "아직 보류 — 잔여 성분 미설명")))
