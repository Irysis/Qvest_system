## FQ-181 P5 — ④ 과거 판정 영향: **뒤집힘 후보 목록만** (재판정 여부 = 도훈 결정)
##
## 판정 기준 (추측 아닌 실측 앵커):
##   P4(B) 실측에서 자 교정의 PORT_t 이동폭 = **-0.1285** (자A 2.1969 → 자B 2.0684),
##   선별 변화 = 295개월 중 103개월(34.9%) · 평균 0.61 종목/월.
##   ⇒ HARD 게이트 2.95 에서 |PORT_t - 2.95| 가 이 이동폭 규모 안에 있는 기록은
##     자 교정만으로 판정이 갈릴 수 있다. 보수적으로 **밴드 = 0.30 (실측 이동폭의 ~2.3배)**.
##   ⇒ 밴드 **밖**은 자 교정으로 뒤집히지 않는다 — 이 축으로는 재판정 불요.
##
## ★이 목록은 "뒤집혔다"가 아니라 "뒤집힐 수 있다"의 목록이다. 확정하려면 재실행이
##   필요하고 재실행은 도훈 결정 사항이다. 소급 재작성 없음.
##
## 산출: p5_flip_candidates.json / .csv

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
QM <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
QM <- gsub("\\\\", "/", QM); setwd(QM)
OUT <- file.path(QM, "stage_artifacts/FQ181_liquidity_ruler")

GATE <- 2.95; BAND <- 0.30; OBSERVED_SHIFT <- 0.1285

## ── 기록된 PORT_t 를 담은 원장들 ────────────────────────────────────────────
SRC <- c("06_Registry/module_catalog.json",
         "06_Registry/hypothesis_index.json",
         "06_Registry/alpha_frontier_queue.json")
PORT_KEYS <- c("portfolio_alpha_t_nw","portfolio_alpha_t_nw_lag3","portfolio_alpha_t",
               "port_t","canonical_port_t_nw_lag3","PORT_t","portfolio_alpha_t_nw_lag3_capw")

rows <- list()
harvest <- function(o, path, src) {
  if (is.list(o)) {
    nm <- names(o)
    if (!is.null(nm)) {
      for (k in intersect(nm, PORT_KEYS)) {
        v <- suppressWarnings(as.numeric(o[[k]][1]))
        if (length(v) == 1L && !is.na(v)) {
          lbl <- NA_character_
          for (idk in c("id","strategy_id","module_id","factor_id","wt_id","name","title","hypothesis_id"))
            if (!is.na(idk) && idk %in% nm && is.character(o[[idk]][1])) { lbl <- o[[idk]][1]; break }
          rows[[length(rows)+1L]] <<- data.table(source = src, path = path, metric_key = k,
                                                 port_t = v, label = lbl)
        }
      }
      for (i in seq_along(o)) harvest(o[[i]], paste0(path, "/", nm[i]), src)
    } else for (i in seq_along(o)) harvest(o[[i]], paste0(path, "[", i, "]"), src)
  }
}
for (s in SRC) {
  if (!file.exists(s)) { cat(sprintf("[skip] %s 부재\n", s)); next }
  j <- tryCatch(fromJSON(s, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(j)) { cat(sprintf("[skip] %s 파싱 실패\n", s)); next }
  n0 <- length(rows); harvest(j, "", basename(s))
  cat(sprintf("[scan] %-32s PORT_t 기록 %d 건\n", basename(s), length(rows) - n0))
}
## backtest_registry.csv
brf <- "qepm/registry/backtest_registry.csv"
if (file.exists(brf)) {
  B <- fread(brf)
  hit <- intersect(names(B), PORT_KEYS)
  cat(sprintf("[scan] %-32s PORT_t 컬럼 %s\n", basename(brf),
              if (length(hit)) paste(hit, collapse=",") else "(없음)"))
  for (k in hit) {
    v <- suppressWarnings(as.numeric(B[[k]]))
    idc <- intersect(names(B), c("strategy_id","run_id","id"))[1]
    ok <- !is.na(v)
    if (any(ok)) rows[[length(rows)+1L]] <- data.table(
      source = basename(brf), path = k, metric_key = k, port_t = v[ok],
      label = if (!is.na(idc)) as.character(B[[idc]][ok]) else NA_character_)
  }
}

R <- if (length(rows)) rbindlist(rows, fill = TRUE) else data.table()
if (!nrow(R)) stop("PORT_t 기록 0건 — ★정지 신호(스캐너 사망 의심), 결론으로 읽지 말 것")

## ── 양성 대조: 스캐너가 알려진 값을 잡는가 ──────────────────────────────────
cat(sprintf("\n[positive-control] 총 %s 건 수확 · 범위 %.3f .. %.3f · 중앙 %.3f\n",
            format(nrow(R), big.mark=","), min(R$port_t), max(R$port_t), median(R$port_t)))
if (nrow(R) < 5) stop("수확 건수가 비정상적으로 적음 — 정지 신호")

R <- unique(R, by = c("source","path","metric_key","port_t","label"))
R[, dist := abs(port_t - GATE)]
R[, side := fifelse(port_t >= GATE, "PASS(현재)", "FAIL(현재)")]
CAND <- R[dist <= BAND][order(dist)]

cat(sprintf("\n=== ④ 뒤집힘 후보 (|PORT_t - %.2f| <= %.2f) ===\n", GATE, BAND))
cat(sprintf("총 기록 %s 건 중 후보 %d 건 (%.2f%%) — 나머지 %s 건은 자 교정으로 뒤집히지 않는다\n",
            format(nrow(R), big.mark=","), nrow(CAND), 100*nrow(CAND)/nrow(R),
            format(nrow(R)-nrow(CAND), big.mark=",")))
if (nrow(CAND)) print(CAND[, .(source, label, metric_key, port_t, dist, side)], nrows = 60)

fwrite(CAND, file.path(OUT, "p5_flip_candidates.csv"))
write_json(list(
  method = "기록된 PORT_t 원장 스캔 → HARD 게이트 2.95 근방 밴드",
  anchor = list(observed_port_t_shift_from_ruler_correction = OBSERVED_SHIFT,
                measured_on = "WT_D20260808_001 미필터 패널 295개월 top-25 A/B (canonical_screen_bt 실측)",
                band_used = BAND, band_rationale = "실측 이동폭의 약 2.3배 — 보수적"),
  gate = GATE, n_port_t_records = nrow(R), n_candidates = nrow(CAND),
  candidates = CAND,
  disclaimer = paste("이 목록은 '뒤집혔다'가 아니라 '뒤집힐 수 있다'이다.",
                     "확정은 재실행이 필요하며 재실행 여부는 도훈 결정이다. 소급 재작성 없음.")
), file.path(OUT, "p5_flip_candidates.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)
cat("\n[done] p5_flip_candidates.{json,csv}\n")
