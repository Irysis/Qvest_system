## FQ-037 (R24) 사전확인 — 라운드 착수 전 '전제'를 잰다
##
## 사전등록 유효성 게이트(큐 wall_check): **독립 지각 에피소드 < 30 이면 POWER_INSUFFICIENT**.
## R23 의 벽은 신호 부재가 아니라 표본력(배포 유니버스 내 독립 지각제출 6개사).
## ⇒ 착수 전 질문: **전시장(KOSPI+KOSDAQ 필러)으로 넓히면 30개가 나오는가?**
##    안 나오면 라운드는 시작 전에 끝난다(FQ-024/025/026 가 캐시 부재로 죽어 있던 것과 같은 종류의 절약).
## 본 스크립트는 **읽기 전용 coverage 실측**이다 — 가설 검정 아님.
suppressPackageStartupMessages({library(data.table); library(arrow)})
R <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(R)
OUT <- "stage_artifacts/fq037_precheck_20260808"; dir.create(OUT, showWarnings=FALSE, recursive=TRUE)

cat("=== [1] RAWDATA 사건 플래그 존재 여부 ===\n")
sc <- schema(open_dataset(".cache/RAWDATA.parquet"))
nm <- names(sc)
pat <- c("Unfaithful","UnfaithfulDisc","AdminStock","TradingHalt","Delist")
found <- unlist(lapply(pat, function(p) grep(p, nm, value=TRUE, fixed=TRUE)))
found <- unique(found)
cat(sprintf("  RAWDATA 총 열 %d\n", length(nm)))
cat(sprintf("  사건 플래그 발견: %s\n", if (length(found)) paste(found, collapse=", ") else "**없음**"))
if (!length(found)) {
  cat("\n[중단] 사건 플래그 부재 — 큐의 data_gate('RAWDATA 전시장 플래그')가 성립하지 않는다.\n")
  cat("       ⇒ FQ-037 은 착수 불가. 큐에 blocked 표기 필요.\n")
  quit(status = 0)
}

cat("\n=== [2] 플래그 커버리지 (전시장) ===\n")
cols <- unique(c("Date","Ticker", found))
raw <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select = cols))
raw[, Date := as.Date(Date)]
cat(sprintf("  행 %s · 티커 %d · 기간 %s ~ %s\n", format(nrow(raw), big.mark=","),
            uniqueN(raw$Ticker), min(raw$Date), max(raw$Date)))
for (f in found) {
  v <- raw[[f]]
  tv <- sum(v %in% c(TRUE, 1, "Y", "1"), na.rm = TRUE)
  cat(sprintf("  %-16s : 참 %s행 · 해당 티커 %d\n", f, format(tv, big.mark=","),
              uniqueN(raw[v %in% c(TRUE,1,"Y","1")]$Ticker)))
}

cat("\n=== [3] 심각사건 = 상폐 ∪ 관리 ∪ 불성실 (단기정지 제외) ===\n")
sev <- setdiff(found, grep("Halt", found, value=TRUE))
cat(sprintf("  심각사건 열: %s (단기정지 %s 제외)\n",
            paste(sev, collapse=", "), paste(setdiff(found, sev), collapse=",")))
if (!length(sev)) { cat("  ★심각사건 열 없음 — 과녁 정의 불가\n"); quit(status=0) }
raw[, sev_any := Reduce(`|`, lapply(.SD, function(v) v %in% c(TRUE,1,"Y","1"))), .SDcols = sev]
## 에피소드 = 티커별 사건 onset (직전월 FALSE → 당월 TRUE)
setorder(raw, Ticker, Date)
raw[, prev := shift(sev_any, 1L, fill = FALSE), by = Ticker]
onset <- raw[sev_any & !prev]
cat(sprintf("  심각사건 **onset 에피소드** %s건 · 회사 %d개 · %s ~ %s\n",
            format(nrow(onset), big.mark=","), uniqueN(onset$Ticker),
            if (nrow(onset)) min(onset$Date) else NA, if (nrow(onset)) max(onset$Date) else NA))

cat("\n=== [4] DART 제출지연 원천 (지각 에피소드의 다른 축) ===\n")
cand <- c(list.files(".cache", pattern="dart.*list.*\\.parquet$", full.names=TRUE, ignore.case=TRUE),
          list.files(".cache", pattern="dart.*\\.parquet$", full.names=TRUE, ignore.case=TRUE))
cand <- unique(cand)
if (!length(cand)) {
  cat("  ★로컬 DART list 아카이브(.cache/*dart*.parquet) **없음**\n")
  cat("  ⇒ 큐 data_gate '로컬 DART list 아카이브(50.7만행) rcept_dt' 미충족 — 경로 재확인 또는 착수 불가\n")
} else {
  for (f in head(cand, 6)) {
    n <- tryCatch(nrow(open_dataset(f)), error=function(e) NA)
    cat(sprintf("  %-52s %s행\n", basename(f), format(n, big.mark=",")))
  }
}

cat("\n[사전확인 판정]\n")
cat(sprintf("  심각사건 onset %d건 (회사 %d) — 이것만으로 지각×사건 교차 표본의 **상한**이다.\n",
            nrow(onset), uniqueN(onset$Ticker)))
cat("  ★교차(지각제출 ∧ 사건) 에피소드는 이보다 작다. 사전등록 게이트 30건 대비 여유가 없으면\n")
cat("    라운드는 POWER_INSUFFICIENT 로 끝날 가능성이 높다 — 착수 전에 알 수 있는 정보.\n")
fwrite(onset[, .(Ticker, Date)], file.path(OUT, "severe_event_onsets.csv"))
cat(sprintf("\n[저장] %s/severe_event_onsets.csv\n", OUT))
