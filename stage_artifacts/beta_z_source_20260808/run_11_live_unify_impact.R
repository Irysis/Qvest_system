## run_11 — live 통일이 북 시리즈·IR 에 실제로 무엇을 바꿨나
## 질문 3개: ① 원장 수익률이 바뀌었나 ② IR 이 바뀌었나 ③ rds 앵커 162개월 불일치의 의미는
suppressPackageStartupMessages(library(data.table))
R <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
D <- file.path(R, "06_Registry/live_track/STR_1715_on_M4gAE_R05_noLayer4_PG2")
NEW <- file.path(D, "live_book_series.csv")
baks <- sort(list.files(D, pattern = "^live_book_series\\.csv\\.bak_frozen_", full.names = TRUE))
if (!length(baks)) stop("[중단] frozen 백업 부재")
OLD <- tail(baks, 1)
o <- fread(OLD); n <- fread(NEW)
cat(sprintf("[대조] 전(frozen z): %s · %d행\n       후(live z)  : %s · %d행\n\n",
            basename(OLD), nrow(o), basename(NEW), nrow(n)))

m <- merge(o[, .(realized_ym, ret_o = ret_net, b_o = beta_R05, rp_o = ret_recompute_panel, src_o = ret_net_source)],
           n[, .(realized_ym, ret_n = ret_net, b_n = beta_R05, rp_n = ret_recompute_panel, src_n = ret_net_source)],
           by = "realized_ym", all = TRUE)

## ① 원장 기록 수익률
dr <- m[abs(ret_o - ret_n) > 1e-15]
cat(sprintf("① 원장 ret_net 변경: %d/%d행\n", nrow(dr), nrow(m)))
if (nrow(dr)) print(dr[, .(realized_ym, ret_o = round(ret_o,6), ret_n = round(ret_n,6),
                           d_pp = round(100*(ret_n-ret_o),3), src_n)])

## ② β 열
db <- m[abs(b_o - b_n) > 1e-12]
cat(sprintf("\n② beta_R05 변경: %d/%d행\n", nrow(db), nrow(m)))
if (nrow(db)) print(db[, .(realized_ym, b_o, b_n, src_n)])

## ③ 재계산치(ret_recompute_panel) — 여기가 162개월 바뀐 곳
drp <- m[abs(rp_o - rp_n) > 1e-12]
cat(sprintf("\n③ ret_recompute_panel 변경: %d/%d행  ← z 원천 교체가 실제로 닿은 범위\n", nrow(drp), nrow(m)))
cat(sprintf("   그중 원장에 반영된 행: %d (나머지는 rds 앵커가 고정 → 진단 컬럼만 변화)\n",
            nrow(drp[abs(ret_o - ret_n) > 1e-15])))
cat(sprintf("   앵커 종류별: %s\n", paste(sprintf("%s=%d", names(table(m$src_n)), table(m$src_n)), collapse = " · ")))

## ★핵심 진단: 배포 실측(manifest)과 북 재계산의 일치도 — 통일의 목적
anc <- n[grepl("^manifest_anchor", ret_net_source)]
if (nrow(anc)) {
  cat(sprintf("\n★ manifest 앵커월 재계산 정합 (통일 목표 지표)\n"))
  for (k in seq_len(nrow(anc))) with(anc[k], {
    o_rp <- m[realized_ym == anc$realized_ym[k]]$rp_o
    cat(sprintf("   %s: 재계산 %.6f vs 원장(배포실측) %.6f → 괴리 %+.2f%%pt  (통일 전 재계산 %.6f = 괴리 %+.2f%%pt)\n",
                realized_ym, ret_recompute_panel, ret_net, 100*(ret_recompute_panel - ret_net),
                o_rp, 100*(o_rp - m[realized_ym == anc$realized_ym[k]]$ret_o)))
  })
}

## ② IR (net-active recon 규약 근사: 원장 ret_net 시계열의 mean/sd × sqrt(12))
ir <- function(x) { x <- x[is.finite(x)]; if (length(x) < 24) return(NA_real_); mean(x)/sd(x)*sqrt(12) }
cat(sprintf("\n[IR 근사 — 원장 ret_net 기준, metric_type=scaled_approx]\n"))
cat(sprintf("   전(frozen) %.4f · 후(live) %.4f · Δ %+.4f  (n=%d)\n",
            ir(o$ret_net), ir(n$ret_net), ir(n$ret_net) - ir(o$ret_net), nrow(n)))
cat("   ※ book_state incumbent_book_ir(1.416)는 recon NAV 기반 별도 규약 — 위 값은 방향 확인용.\n")

fwrite(m, file.path(R, "stage_artifacts/beta_z_source_20260808/live_unify_impact.csv"))
cat("\n[저장] live_unify_impact.csv\n")
