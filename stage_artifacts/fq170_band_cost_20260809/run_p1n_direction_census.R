## P1n — ret 패널 방향 규약 census (세션 간 수치 비교 가능성)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P1q: 내 ret 패널은 forward(cor 1.0000). 다른 라운드도 같은 규약인가?
##  ★다르면 세션 간 PORT_t 비교가 깨진다(같은 문턱을 다른 자로 재는 것).
##  대상: stage_artifacts 의 최근 WT ret/alpha 패널 중 Ret_1m 컬럼을 가진 parquet/rds.
##  판별: 각 패널의 Ret_1m 을 RAWDATA 월말 Close 로 검산 — forward vs contemporaneous.
##   T1 일관: 전 패널 forward → 세션 간 비교 안전
##   T2 혼재: 하나라도 contemporaneous → 방향 라벨 병기 의무 + 비교 전 정합 확인
##  ★성과 측정 없음. 규약 진단만.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- ".claude/worktrees/jovial-mcnulty-f7d018/stage_artifacts/fq170_band_cost_20260809"

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Close")))
RAW[, Date := as.Date(Date)][, ym := format(Date, "%Y-%m")]
ME <- RAW[, .SD[which.max(Date)], by=.(Ticker, ym)][, .(Ticker, ym, Close)]
setorder(ME, Ticker, ym)
ME[, `:=`(r_ct = Close/shift(Close) - 1, r_fw = shift(Close,-1L)/Close - 1), by=Ticker]
KEY <- ME[, .(Ticker, ym, r_ct, r_fw)]

cands <- c("stage_artifacts/WT_D20260808_001/alpha_scores.parquet",
           "stage_artifacts/WT_D20260808_002/alpha_scores.parquet",
           "stage_artifacts/WT_D20260808_003/alpha_scores.parquet",
           "stage_artifacts/WT_D20260425_010/alpha_scores.parquet",
           "stage_artifacts/WT_D20260802_009/base_panel.parquet")
rows <- list()
for (p in cands) {
  if (!file.exists(p)) { rows[[length(rows)+1L]] <- data.table(panel=basename(dirname(p)), status="파일없음"); next }
  d <- tryCatch(as.data.table(read_parquet(p)), error=function(e) NULL)
  if (is.null(d) || !("Ret_1m" %in% names(d)) || !("Date" %in% names(d)) || !("Ticker" %in% names(d))) {
    rows[[length(rows)+1L]] <- data.table(panel=basename(dirname(p)), status="Ret_1m 없음"); next }
  d[, Date := as.Date(Date)][, ym := format(Date, "%Y-%m")]
  m <- merge(d[!is.na(Ret_1m), .(Ticker, ym, Ret_1m)], KEY, by=c("Ticker","ym"))
  m <- m[is.finite(Ret_1m) & is.finite(r_ct) & is.finite(r_fw)]
  if (nrow(m) < 500L) { rows[[length(rows)+1L]] <- data.table(panel=basename(dirname(p)), status=sprintf("대조 부족 %d", nrow(m))); next }
  cc <- cor(m$Ret_1m, m$r_ct, use="complete.obs"); cf <- cor(m$Ret_1m, m$r_fw, use="complete.obs")
  rows[[length(rows)+1L]] <- data.table(panel=basename(dirname(p)), status="OK", n=nrow(m),
    cor_contemp=round(cc,4), cor_forward=round(cf,4),
    direction = if (abs(cf-cc) < 0.10) "불명" else if (cf > cc) "forward" else "contemporaneous")
}
R <- rbindlist(rows, fill=TRUE); print(R[])
ok <- R[status=="OK"]
verdict <- { if (!nrow(ok)) "T3_NO_DATA"
             else if (all(ok$direction == "forward")) "T1_CONSISTENT_FORWARD"
             else "T2_MIXED_DIRECTIONS" }
cat(sprintf("\n판정: %s (판별 성공 %d/%d)\n", verdict, nrow(ok), nrow(R)))
if (verdict == "T2_MIXED_DIRECTIONS")
  cat("★★세션 간 PORT_t 비교 시 방향 라벨 병기 의무 — 같은 문턱을 다른 자로 재고 있다\n")
write_json(list(verdict=verdict, results=R), file.path(OUT,"p1n_result.json"),
           pretty=TRUE, auto_unbox=TRUE, digits=NA)
