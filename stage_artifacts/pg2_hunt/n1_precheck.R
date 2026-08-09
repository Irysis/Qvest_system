## n1 — ★P2 착수 전 사전 확인: 비-return 원천의 커버리지와 FQ-191 창 겹침
## 종합이 명시한 선행 조건. 이번 라운드에서 커버리지 부족으로 3건이 판정 불가였다.
## ★측정하기 전에 **측정 가능한지**를 먼저 잰다 — 10분 read-only 가 라운드 설계를 바꾼다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[n1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent()
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
say("=== 기준 창 ===")
say("  PG2 %d개월 (%s ~ %s)", nrow(inc), min(inc$date), max(inc$date))
say("  FQ-191 파킹 라벨 %d개월 (%s ~ %s) · ON %d", nrow(Mru), min(Mru$date), max(Mru$date), sum(Mru$regime))
say("  ★통과 요구(종합 산출): 상관 <= 0.277 ∧ IR >= need_ir(상관) · 계약 슬리브 실측 (0.140, 0.758)")

## 후보 데이터 자산 탐색 — 캐시/parquet/rds 중 비-return 원천
say("=== 1. 비-return 원천 자산 스캔 ===")
pats <- list(
  insider  = c("insider","exec"),
  contract = c("contract","수주"),
  short    = c("short","공매도","borrow","lend","대차"),
  consensus= c("consensus","estimate","revision"),
  flow     = c("investor","foreign","flow","institution"),
  pledge   = c("pledge"),
  disclosure=c("disclosure","filing","submission"))
roots <- c(".cache", "02_Infrastructure/data", "04_Research/method_frontier",
           "06_Registry", "02_Infrastructure/factor_db")
allf <- unlist(lapply(roots, function(r)
  if (dir.exists(r)) list.files(r, pattern="\\.(parquet|rds|csv)$", recursive=TRUE, full.names=TRUE) else character(0)))
say("  스캔 파일 %d개", length(allf))
found <- list()
for (k in names(pats)) {
  hit <- allf[grepl(paste(pats[[k]], collapse="|"), basename(allf), ignore.case=TRUE)]
  hit <- hit[file.size(hit) > 5000]
  say("  [%-10s] %d건%s", k, length(hit),
      if (length(hit)) paste0(" — ", paste(basename(head(hit,3)), collapse=", ")) else "")
  if (length(hit)) found[[k]] <- hit
}

say("=== 2. ★각 자산의 시간 커버리지 실측 (판정 가능성) ===")
say("  %-46s %8s %10s %10s %8s", "파일", "행", "시작", "끝", "겹침")
res <- list()
for (k in names(found)) {
  for (f in head(found[[k]], 4)) {
    d <- tryCatch({
      if (grepl("parquet$", f)) as.data.table(read_parquet(f))
      else if (grepl("rds$", f)) { x <- readRDS(f); if (is.data.frame(x)) as.data.table(x) else NULL }
      else fread(f, nrows = 200000)
    }, error = function(e) NULL)
    if (is.null(d) || !nrow(d)) next
    dc <- names(d)[which(tolower(names(d)) %in%
      c("date","ym","rcept_dt","usable_date","sig_date","trade_date","base_date"))[1]]
    if (is.na(dc)) next
    dv <- suppressWarnings(as.Date(as.character(d[[dc]]), tryFormats=c("%Y-%m-%d","%Y/%m/%d","%Y%m%d")))
    dv <- dv[!is.na(dv)]
    if (!length(dv)) next
    ov <- length(intersect(unique(mi(dv)), mi(Mru$date)))
    say("  %-46s %8d %10s %10s %8d", substr(basename(f),1,46), nrow(d),
        as.character(min(dv)), as.character(max(dv)), ov)
    res[[length(res)+1L]] <- data.table(family=k, file=basename(f), path=f, n=nrow(d),
      from=min(dv), to=max(dv), overlap_park=ov, n_months=uniqueN(mi(dv)))
  }
}
R <- rbindlist(res, fill=TRUE)
if (!nrow(R)) { say("★날짜 컬럼을 가진 자산 0건 — 스캔 패턴 재설계 필요(0을 결론으로 읽지 말 것)"); quit(status=0) }

say("=== 3. ★판정 가능성 (겹침 >= 60개월이어야 파킹 arm 측정 가능) ===")
R[, park_ok := overlap_park >= 60L]
R[, uncond_ok := n_months >= 60L]
print(R[order(-overlap_park), .(family, file=substr(file,1,34), n_months, overlap_park, park_ok, uncond_ok)][1:min(15,.N)])
say("  파킹 arm 측정 가능 **%d/%d** · 무조건부 arm 가능 %d/%d",
    sum(R$park_ok), nrow(R), sum(R$uncond_ok), nrow(R))
say("=== 4. 착수 판정 ===")
if (sum(R$park_ok) == 0L) {
  say("  ★파킹 arm 측정 가능한 비-return 자산 **0건** — 무조건부 arm 만 가능하거나 데이터 확보가 선행")
} else {
  say("  ★파킹 arm 착수 가능: %s", paste(unique(R[park_ok==TRUE, family]), collapse=", "))
}
fwrite(R, file.path(OUT,"n1_precheck.csv"))
say("=== n1 완료 → n1_precheck.csv ===")
