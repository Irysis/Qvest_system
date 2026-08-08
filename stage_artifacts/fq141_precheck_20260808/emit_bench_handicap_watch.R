## 벤치 핸디캡 감시 상태 1회 산출 (관례: qepm/observability/*_latest.json)
## ★이 파일을 쓰는 것은 **배선이 아니다** — 월간 자동 실행은 미배선(칩 분리).
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq141_precheck_20260808")
D <- fread(file.path(OUT,"np157c2a1_d_extended.csv")); D[, Date := as.Date(Date)]; setorder(D, Date)
n <- nrow(D)
r6 <- sapply(6:n, function(i) mean(D$d[(i-5):i])*12)
dates6 <- D$Date[6:n]
THR <- 0.0314   # 역사 18m-롤링 75 백분위 (NP-157c2a1)
cur <- tail(r6,1)
below <- rev(r6 <= THR); streak <- 0
for (b in below) { if (isTRUE(b)) streak <- streak + 1 else break }
pct <- mean(r6 <= cur)*100
J <- list(
  watch_id = "bench_handicap_d",
  generated_at = format(max(D$Date)),
  metric_type = "canonical_screen_diag",
  wired = FALSE,
  wiring_note = "월간 자동 실행 미배선 — 이 파일의 존재는 감시가 돌고 있음을 뜻하지 않는다(칩 분리). 재산출은 stage_artifacts/fq141_precheck_20260808/emit_bench_handicap_watch.R",
  definition = "d = cap-w 유니버스 벤치 − EW 유니버스 벤치(월). 6개월 롤링 연율.",
  series_months = n, series_range = c(format(min(D$Date)), format(max(D$Date))),
  current = list(as_of = format(max(dates6)), rolling6m_d_ann = round(cur,4),
                 historical_percentile = round(pct,1)),
  prereg_threshold = list(value = THR,
    basis = "역사 18m-롤링 d_ann 75 백분위 (NP-157c2a1, 422창)",
    rule = "6m 롤링 d_ann 이 문턱 아래로 3개월 연속 유지되면 '핸디캡 정상화' 판정. 단일 월 반등으로 번복 금지.",
    months_below_now = streak, months_required = 3L,
    verdict = if (streak >= 3L) "NORMALIZED" else if (cur <= THR) "BELOW_THRESHOLD_PENDING" else "ELEVATED"),
  gates_this_watch_controls = c(
    "MID/OTHER 구성 라운드 착수 타이밍 (NP-c2c3)",
    "최근 창 수집분의 고-핸디캡 라벨 부착 여부 (NP-c5)",
    "111-145 밴드 재활성 관찰 (NP-b2b3a)",
    "사이즈 효과 부호 복귀 관찰 (NP-b2b)"),
  recent_6m_rolling = as.list(round(tail(r6,8),4)),
  source_round = "NPC5_20260808_ENDPOINT_ARITHMETIC_AND_REVERSAL_WATCH")
p <- "qepm/observability/bench_handicap_watch_latest.json"
write(toJSON(J, auto_unbox=TRUE, pretty=TRUE), p)
cat(sprintf("[watch] 현재 6m 롤링 d_ann = %+.4f (백분위 %.1f%%) · 문턱 %.4f · 연속 %d/3 개월 · 판정 %s\n",
            cur, pct, THR, streak, J$prereg_threshold$verdict))
cat(sprintf("[watch] 저장: %s (wired=FALSE)\n", p))
