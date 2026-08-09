## 실패 판정의 오염 기인 스크린 — P0 census
## 근거: 2026-08-09 FQ-187 실측 — 내가 '실패' 로 버린 tail_asym 이 오염에 눌려 있었다(0.996 -> 1.132).
##   ⇒ **문턱 근방 실패 판정**은 데이터 오염 기인일 수 있다. 되살아나는 후보가 있으면 그게 알파다.
## P0 = 착수 전 census. 후보가 없으면 라운드 자체가 없어진다(사전 확인이 설계를 바꾼 5/5 선례).
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/revive_scan")
say  <- function(fmt, ...) { cat(sprintf(paste0("[c] ", fmt, "\n"), ...)); flush.console() }

## ---- 1. 오염 창 확정 (언제부터 벤치가 오염됐나) ------------------------------
say("=== 1. ★오염 창 실측 — 언제부터 벤치-종목 괴리가 벌어졌나 ===")
G <- fread(file.path(ROOT, "stage_artifacts/FQ182/p5_bench_stock_gap.csv"))
G[, Date := as.Date(Date)][, yr := as.integer(format(Date, "%Y"))]
Y <- G[, .(n = .N, gap_med = median(gap, na.rm=TRUE), gap_p95 = quantile(gap, .95, na.rm=TRUE),
           n_over_p99 = sum(gap > quantile(G$gap, .99, na.rm=TRUE), na.rm=TRUE)), by = yr][order(yr)]
print(tail(Y, 10))
base_med <- median(G[yr < 2025]$gap, na.rm = TRUE)
say("  기준(2025 이전) gap 중앙 %.5f", base_med)
for (y in 2023:2026) {
  m <- Y[yr == y]
  if (!nrow(m)) next
  say("  %d : gap 중앙 %.5f (기준 대비 %.2f배) · p99 초과일 %d/%d",
      y, m$gap_med, m$gap_med/base_med, m$n_over_p99, m$n)
}
say("  ★오염이 2026 에 국한되는가, 2025 부터인가가 재검 범위를 정한다.")

## ---- 2. 원장에서 '문턱 근방 실패' 후보 추출 ----------------------------------
say("=== 2. 원장 census — 문턱 근방 실패 판정 ===")
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
blob <- vapply(Q$entries, function(e) paste(unlist(e), collapse = " "), character(1))
st   <- vapply(Q$entries, function(e) if (is.null(e$status)) "" else as.character(e$status)[1], character(1))
ti   <- vapply(Q$entries, function(e) gsub("[\r\n]+"," ", as.character(e$title)[1]), character(1))
say("  원장 %d 항목", length(ids))

## PORT_t 수치를 본문에서 추출 (2.0~2.95 = 문턱 근방 실패)
extract_num <- function(s, pat) {
  m <- regmatches(s, gregexpr(pat, s, perl = TRUE))[[1]]
  if (!length(m)) return(numeric(0))
  as.numeric(gsub("[^0-9.+-]", "", m))
}
cand <- list()
for (i in seq_along(ids)) {
  v <- extract_num(blob[i], "PORT_t[^0-9+-]{0,12}[+-]?[0-9]+\\.[0-9]+")
  v <- v[is.finite(v) & v > 0 & v < 10]
  near <- v[v >= 2.0 & v < 2.95]
  if (length(near))
    cand[[length(cand)+1L]] <- data.table(id = ids[i], status = substr(st[i],1,30),
                                          title = substr(ti[i],1,58),
                                          port_t_near = paste(sprintf("%.3f", near), collapse=","),
                                          max_near = max(near))
}
C <- if (length(cand)) rbindlist(cand) else data.table()
say("  ★PORT_t 2.0~2.95 (HARD 문턱 근방 실패) 언급 항목: **%d건**", nrow(C))
if (nrow(C)) print(C[order(-max_near)][, .(id, status, port_t_near, title)])

## ratio / t 문턱 근방도
cand2 <- list()
for (i in seq_along(ids)) {
  v <- extract_num(blob[i], "ratio[^0-9+-]{0,10}[0-9]+\\.[0-9]+")
  v <- v[is.finite(v) & v > 0 & v < 5]
  near <- v[v >= 0.80 & v < 1.00]
  if (length(near))
    cand2[[length(cand2)+1L]] <- data.table(id = ids[i], status = substr(st[i],1,30),
                                            title = substr(ti[i],1,58),
                                            ratio_near = paste(sprintf("%.3f", near), collapse=","))
}
C2 <- if (length(cand2)) rbindlist(cand2) else data.table()
say("  ★ratio 0.80~1.00 (검출 문턱 근방) 언급 항목: **%d건**", nrow(C2))
if (nrow(C2)) print(C2)

## ---- 3. 오염 노출 판정 — 그 라운드가 최근 데이터를 썼나 ----------------------
say("=== 3. 오염 노출 — 후보 라운드가 2025~2026 구간을 포함했나 ===")
say("  ★판정 규칙: 측정 창 종점이 2025-01 이후면 오염 노출 가능. 그 이전이면 무관.")
say("  (창 정보는 각 result_ref 산출물에서 확인 필요 — P1 과제)")

fwrite(Y, file.path(OUT, "gap_by_year.csv"))
if (nrow(C))  fwrite(C,  file.path(OUT, "cand_port_t.csv"))
if (nrow(C2)) fwrite(C2, file.path(OUT, "cand_ratio.csv"))
say("=== 판정 ===")
tot <- nrow(C) + nrow(C2)
say("  후보 총 %d건 ⇒ %s", tot,
    if (tot == 0) "★후보 0 — 라운드 불성립, 그 사실 자체를 기록" else "라운드 성립 — P1 에서 창·오염 노출 판정")
saveRDS(list(year_gap = Y, cand_port = C, cand_ratio = C2), file.path(OUT, "p0.rds"))
say("=== P0 완료 ===")
