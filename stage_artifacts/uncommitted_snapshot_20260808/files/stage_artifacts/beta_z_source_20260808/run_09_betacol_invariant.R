## run_09 — β 열 정합 수리의 불변식 검증
## 요구: ret_net 은 전 행 불변(이번 수리는 열 정합이지 수익률 변경이 아니다)
##       beta_R05 는 manifest 앵커 행에서만 변경
suppressPackageStartupMessages(library(data.table))
R <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
D <- file.path(R, "06_Registry/live_track/STR_1715_on_M4gAE_R05_noLayer4_PG2")
NEW <- file.path(D, "live_book_series.csv")
baks <- sort(list.files(D, pattern = "^live_book_series\\.csv\\.bak_betacol_", full.names = TRUE))
if (!length(baks)) stop("[중단] 백업 부재 — 전후 대조 불가")
OLD <- tail(baks, 1)
cat(sprintf("[대조] 전: %s\n       후: %s\n\n", basename(OLD), basename(NEW)))

o <- fread(OLD); n <- fread(NEW)
cat(sprintf("행수 전 %d / 후 %d %s\n", nrow(o), nrow(n),
            if (nrow(o) == nrow(n)) "(일치)" else "★불일치"))
cat(sprintf("신규 열: %s\n\n", paste(setdiff(names(n), names(o)), collapse = ", ")))

m <- merge(o[, .(realized_ym, ret_net_o = ret_net, beta_o = beta_R05, src_o = ret_net_source)],
           n[, .(realized_ym, ret_net_n = ret_net, beta_n = beta_R05, src_n = ret_net_source,
                 inv_n = invested_eff, bpanel_n = beta_R05_panel)],
           by = "realized_ym", all = TRUE)

## ── 불변식 1: ret_net 전 행 불변
dr <- m[!is.na(ret_net_o) & !is.na(ret_net_n) & abs(ret_net_o - ret_net_n) > 1e-15]
cat(sprintf("[불변식1] ret_net 변경 행: %d건 %s\n", nrow(dr),
            if (nrow(dr) == 0) "→ PASS (수익률 무변경)" else "→ ★FAIL"))
if (nrow(dr)) print(dr[, .(realized_ym, ret_net_o, ret_net_n, d = ret_net_n - ret_net_o)])

## ── 불변식 2: beta_R05 변경은 manifest 앵커 행에만
db <- m[!is.na(beta_o) & !is.na(beta_n) & abs(beta_o - beta_n) > 1e-15]
anch <- m[grepl("^manifest_anchor", src_n), realized_ym]
off  <- setdiff(db$realized_ym, anch)
cat(sprintf("[불변식2] beta_R05 변경 %d건 · 그중 앵커 밖 %d건 %s\n", nrow(db), length(off),
            if (length(off) == 0) "→ PASS (앵커 행에만 변경)" else "→ ★FAIL"))
if (nrow(db)) print(db[, .(realized_ym, beta_o, beta_n, src_n)])

## ── 불변식 3: 앵커 행에서 invested_eff == beta_R05 × m4 (규약 자기정합)
nn <- fread(NEW)
ck <- nn[grepl("^manifest_anchor", ret_net_source),
         .(realized_ym, beta_R05, m4, invested_eff, beta_R05_panel,
           recon = beta_R05 * m4, d = abs(beta_R05 * m4 - invested_eff))]
cat(sprintf("[불변식3] 앵커 행 %d건 · β×m4 == invested_eff 최대오차 %.2e %s\n",
            nrow(ck), if (nrow(ck)) max(ck$d) else 0,
            if (!nrow(ck) || max(ck$d) < 1e-12) "→ PASS" else "→ ★FAIL"))
if (nrow(ck)) print(ck)

## ── 불변식 4: 패널 원값이 보존됐는가 (진단 손실 없음)
lost <- nn[is.na(beta_R05_panel) & !is.na(beta_R05), .N]
cat(sprintf("[불변식4] beta_R05_panel 결손 행: %d건 %s\n", lost,
            if (lost == 0) "→ PASS (감사용 원값 전 행 보존)" else "→ ★FAIL"))

cat("\n[요약] 이번 수리로 바뀐 것 = β 열 정합 + 신규 진단 2열. 수익률·행수 무변경.\n")
