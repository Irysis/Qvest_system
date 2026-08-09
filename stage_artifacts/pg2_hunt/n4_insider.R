## n4 — ★DART 임원·주요주주 매매(insider) 사전 확인
## 왜 이것인가: n3 이 확인했듯 **수급 축은 이미 331 에 20건 포함돼 전부 미달**이다
##   (INV01~INV13 = foreign/inst netbuy 20d·60d·momentum·concentration 등).
##   raw flow 12개 중 실질 신규는 5d 버전과 foreign_own_chg 정도이고, 20d/60d 가 전부 떨어진 뒤라
##   기대가 낮다. 반면 **insider 는 331 에 한 건도 없다** = 진짜 미측정 원천.
## ★이 스크립트는 **측정이 아니라 측정 가능성** 확인이다. 커버리지·PIT·신호화 가능성만 본다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[n4] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
say("=== 기준 창 === PG2 %d개월 · 파킹 %d개월", nrow(inc), nrow(Mru))

## 가장 큰 insider 자산들 전부 확인 (하나만 보고 판단하지 않는다)
cand <- list.files(".", pattern="insider.*\\.(parquet|rds|csv)$", recursive=TRUE, full.names=TRUE)
cand <- cand[file.size(cand) > 10000]
cand <- cand[order(-file.size(cand))]
say("=== insider 자산 %d개 ===", length(cand))
best <- NULL
for (f in head(cand, 10)) {
  d <- tryCatch({
    if (grepl("parquet$", f)) as.data.table(read_parquet(f))
    else if (grepl("rds$", f)) { x <- readRDS(f); if (is.data.frame(x)) as.data.table(x) else NULL }
    else fread(f)
  }, error = function(e) NULL)
  if (is.null(d) || !nrow(d)) next
  dc <- names(d)[which(tolower(names(d)) %in% c("date","rcept_dt","usable_date","sig_date"))[1]]
  if (is.na(dc)) next
  dv <- suppressWarnings(as.Date(as.character(d[[dc]])))
  dv <- dv[!is.na(dv)]
  if (!length(dv)) next
  ms <- unique(mi(dv))
  ov_pg <- length(intersect(ms, inc$m)); ov_pk <- length(intersect(ms, mi(Mru$date)))
  say("  %-44s %7d행 %s~%s · %3d개월 · PG2겹침 %3d · 파킹겹침 %2d",
      substr(basename(f),1,44), nrow(d), min(dv), max(dv), length(ms), ov_pg, ov_pk)
  if (is.null(best) || ov_pg > best$ov_pg) best <- list(f=f, d=d, dv=dv, ov_pg=ov_pg, ov_pk=ov_pk, dc=dc)
}
if (is.null(best)) { say("★날짜 있는 insider 자산 0건 — 정지"); quit(status=0) }

say("=== ★최장 커버리지 자산: %s ===", basename(best$f))
I <- best$d
say("  %d행 · %s ~ %s · PG2 겹침 **%d/269** · 파킹 겹침 **%d/73**",
    nrow(I), min(best$dv), max(best$dv), best$ov_pg, best$ov_pk)
say("  판정: 무조건부 arm %s (요구 60) · 파킹 arm %s",
    if (best$ov_pg >= 60L) "가능" else "★불가", if (best$ov_pk >= 60L) "가능" else "★불가")

say("=== 신호화 가능성 ===")
say("  컬럼: %s", paste(names(I), collapse=", "))
tc <- names(I)[which(tolower(names(I)) %in% c("ticker","code"))[1]]
say("  종목 %s · 고유 %s", tc, if (!is.na(tc)) uniqueN(I[[tc]]) else "?")
if ("trade_type" %in% names(I)) { say("  trade_type 분포:"); print(sort(table(I$trade_type), decreasing=TRUE)) }
## 수량 컬럼이 문자로 저장됐는지 (n2 에서 수치 0개였다)
qc <- grep("cnt|rate|irds", names(I), value=TRUE)
for (c0 in head(qc, 5)) {
  v <- I[[c0]]
  nn <- suppressWarnings(as.numeric(gsub("[, ]", "", as.character(v))))
  say("  %-26s cls=%-9s 수치변환 성공률 %.1f%% · 예시 %s", c0, class(v)[1],
      100*mean(!is.na(nn)), paste(head(as.character(v[!is.na(v)]),2), collapse=" | "))
}

say("=== ★월별 발생 밀도 (신호를 매달 만들 수 있는가) ===")
I2 <- data.table(m = mi(best$dv))
if (!is.na(tc)) I2[, tk := as.character(I[[tc]])]
den <- I2[, .(n_event = .N, n_ticker = if ("tk" %in% names(I2)) uniqueN(tk) else NA_integer_), by = m][order(m)]
say("  월평균 사건 %.1f · 월평균 종목 %.1f · 사건 0인 달 %d",
    mean(den$n_event), mean(den$n_ticker, na.rm=TRUE),
    length(setdiff(inc$m, den$m)))
say("  분포: 최소 %d · 중앙 %d · 최대 %d 사건/월",
    min(den$n_event), median(den$n_event), max(den$n_event))
say("  ★월 종목수 중앙 %.0f — top-25 슬리브를 만들려면 최소 25 이상 필요",
    median(den$n_ticker, na.rm=TRUE))
say("  25종목 이상인 달 **%d/%d (%.1f%%)**",
    sum(den$n_ticker >= 25, na.rm=TRUE), nrow(den), 100*mean(den$n_ticker >= 25, na.rm=TRUE))

say("=== ★착수 판정 ===")
feasible <- best$ov_pg >= 60L && median(den$n_ticker, na.rm=TRUE) >= 25
say("  %s", if (feasible) "★insider 축 착수 가능 — 다음 단계: 신호 정의 사전등록 → 2-arm 측정" else
  sprintf("★착수 조건 미충족 — PG2겹침 %d(요구60) · 월중앙종목 %.0f(요구25). 데이터 확보가 선행",
          best$ov_pg, median(den$n_ticker, na.rm=TRUE)))
fwrite(den, file.path(OUT,"n4_insider_density.csv"))
say("=== n4 완료 ===")
