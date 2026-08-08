## run_08 — 원장 ret_net 이 manifest 앵커에서 왔는지 실측 검증
## 목적: "동결 z 패널이 북 기록을 오염시켰다"는 내 진단이 맞는지 판별.
##   가설 H0(내 기존 진단): 북 ret_net 은 동결 패널 β=0.50 산물 → 기록 오염
##   가설 H1(원장 열 관찰): ret_net 은 manifest invested(배포 실측) 산물 → 기록 정상
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
R <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
SER <- file.path(R, "06_Registry/live_track/STR_1715_on_M4gAE_R05_noLayer4_PG2/live_book_series.csv")
NAV <- file.path(R, "06_Registry/live_track/STR_1715_on_M4gAE_R05_noLayer4_PG2/paper_nav.csv")
COST <- 0.0015

s <- fread(SER)
cat(sprintf("[원장] %s | %d행 | %s ~ %s\n", basename(SER), nrow(s), min(s$date), max(s$date)))

## 검증 대상 = manifest 앵커가 붙은 행 전부 (하드코딩 대신 원장에서 추출)
tgt <- s[grepl("^manifest_anchor", ret_net_source)]
cat(sprintf("[대상] manifest_anchor 행 %d건 · panel_recompute 행 %d건 · rds_anchor %d건\n\n",
            nrow(tgt), sum(s$ret_net_source == "panel_recompute"),
            sum(grepl("^rds_anchor", s$ret_net_source))))
if (!nrow(tgt)) { cat("[중단] manifest 앵커 행 없음 — H1 검증 불가\n"); quit(status = 0) }

res <- rbindlist(lapply(seq_len(nrow(tgt)), function(k) {
  r  <- tgt[k]
  mfn <- sub("^manifest_anchor\\((.*)\\)$", "\\1", r$ret_net_source)
  hit <- list.files(R, pattern = paste0("^", mfn, "$"), recursive = TRUE, full.names = TRUE)
  inv <- if (length(hit)) as.numeric(fromJSON(hit[1])[["invested"]]) else NA_real_
  ## 직전 행 노출 (코드 152행 규약: 직전 행 β×m4)
  j <- which(s$date == r$date) - 1L
  prev_inv <- if (j >= 1L) s$beta_R05[j] * s$m4[j] else inv
  ## H1 재계산: inv × ret_orig − |Δinv| × COST
  h1 <- inv * r$ret_orig - abs(inv - prev_inv) * COST
  ## H0 재계산: 원장 β_R05 × m4 × ret_orig  (동결 패널 산물)
  h0 <- r$beta_R05 * r$m4 * r$ret_orig
  data.table(realized_ym = r$realized_ym, regime = r$regime,
             ret_orig = r$ret_orig, beta_col = r$beta_R05, manifest_inv = inv,
             ledger_ret_net = r$ret_net, recompute_panel = r$ret_recompute_panel,
             H1_manifest = h1, H0_frozen_beta = h0,
             d_H1 = abs(h1 - r$ret_net), d_H0 = abs(h0 - r$ret_net))
}))

cat("=== 가설 대조 (원장 ret_net 을 어느 산식이 재현하나) ===\n")
print(res[, .(realized_ym, regime, ret_orig = round(ret_orig, 6),
              beta_col, manifest_inv,
              ledger = round(ledger_ret_net, 6),
              H1_manifest = round(H1_manifest, 6), d_H1 = signif(d_H1, 3),
              H0_frozen = round(H0_frozen_beta, 6), d_H0 = signif(d_H0, 3))])

cat("\n=== 판정 ===\n")
for (k in seq_len(nrow(res))) with(res[k], {
  v <- if (d_H1 < 1e-9 && d_H0 > 1e-9) "H1 확정 — 기록은 배포 실측(manifest)에서 옴 = 기록 정상"
  else if (d_H0 < 1e-9 && d_H1 > 1e-9) "H0 확정 — 기록이 동결 β 산물 = 기록 오염"
  else if (d_H1 < 1e-9 && d_H0 < 1e-9) "구분 불가 (두 산식 동값)"
  else "둘 다 불일치 — 제3 산식"
  cat(sprintf("  %s: %s\n", realized_ym, v))
  cat(sprintf("      β열 %.2f vs manifest invested %.2f → %s\n", beta_col, manifest_inv,
              if (abs(beta_col - manifest_inv) > 1e-9) "★열 불일치(원장 β 오독 위험)" else "일치"))
  cat(sprintf("      폴백 위험: manifest 부재 시 기록될 값 %.6f vs 실제 %.6f (차 %+.2f%%pt)\n",
              recompute_panel, ledger_ret_net, 100 * (recompute_panel - ledger_ret_net)))
})

## paper_nav 정합 (실제 성과 보고면)
nv <- fread(NAV)
mg <- merge(res[, .(realized_ym, ledger_ret_net)],
            nv[event == "REALIZED", .(realized_ym, paper_ret_net)], by = "realized_ym")
cat(sprintf("\n[paper_nav 정합] %d건 중 일치 %d건 (max|Δ| %.2e)\n",
            nrow(mg), sum(abs(mg$ledger_ret_net - mg$paper_ret_net) < 1e-12),
            if (nrow(mg)) max(abs(mg$ledger_ret_net - mg$paper_ret_net)) else NA_real_))

fwrite(res, file.path(R, "stage_artifacts/beta_z_source_20260808/manifest_anchor_verify.csv"))
cat("\n[저장] manifest_anchor_verify.csv\n")
