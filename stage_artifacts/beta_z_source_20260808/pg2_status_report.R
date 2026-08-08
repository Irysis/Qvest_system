## PG2 현황 보고 — 실제 파일/코드 실행 실측만 (도훈 mandate)
suppressPackageStartupMessages({library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics)})
R <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(R)
line <- function() cat(strrep("─", 66), "\n")

## ── 1. 정체성 (book_state)
bs_cand <- c("qepm/registry/book_state.json", "06_Registry/book_state.json",
             "qepm/memory/book_state.json", ".cache/book_state.json")
bs_p <- bs_cand[file.exists(bs_cand)][1]
cat("■ 1. PG2 정체성\n"); line()
if (!is.na(bs_p)) {
  bs <- fromJSON(bs_p, simplifyDataFrame = FALSE)
  cat(sprintf("  book_state      : %s\n", bs_p))
  for (k in c("admitted_ids","current_pg2_official_name","incumbent_book_ir","ir_convention","updated")) {
    v <- bs[[k]]; if (!is.null(v)) cat(sprintf("  %-16s: %s\n", k, paste(unlist(v), collapse=", ")))
  }
} else cat("  ★book_state.json 미발견 (후보 4경로 모두 부재)\n")

## ── 2. 배포 생성기 핀 (미러 ↔ sha1 짝)
cat("\n■ 2. 배포 생성기 핀\n"); line()
gp <- "02_Infrastructure/ops/generator_pins.json"
if (file.exists(gp)) {
  p <- fromJSON(gp, simplifyDataFrame = FALSE)
  ent <- if (!is.null(p$pins)) p$pins else p
  for (nm in names(ent)) {
    e <- ent[[nm]]
    if (is.list(e) && !is.null(e$mirror)) {
      mp <- file.path(R, e$mirror)
      sha <- if (file.exists(mp)) substr(system2("sha1sum", shQuote(mp), stdout=TRUE), 1, 40) else NA
      ok <- !is.na(sha) && identical(sha, unlist(e$sha1)[1])
      cat(sprintf("  %s\n    mirror : %s\n    sha1   : %s (%s)\n", nm, e$mirror,
                  substr(unlist(e$sha1)[1], 1, 16), if (ok) "일치 ✓" else "★불일치/미확인"))
    }
  }
} else cat("  ★generator_pins.json 부재\n")

## ── 3. 북 시리즈 (원장 실측)
cat("\n■ 3. 북 성과 시리즈 (live_book_series)\n"); line()
LP <- "06_Registry/live_track/STR_1715_on_M4gAE_R05_noLayer4_PG2/live_book_series.csv"
L <- fread(LP); L[, date := as.Date(date)]; setorder(L, date)
x <- xts(L$ret_net, order.by = L$date)
ann <- table.AnnualizedReturns(x, scale = 12, Rf = 0)
cagr <- as.numeric(ann[1,1]); mdd <- as.numeric(maxDrawdown(x))
cat(sprintf("  기간            : %s ~ %s (n=%d)\n", min(L$date), max(L$date), nrow(L)))
cat(sprintf("  CAGR            : %.2f%%\n", 100*cagr))
cat(sprintf("  SR (geo, 월12)  : %.4f\n", as.numeric(ann[3,1])))
cat(sprintf("  MDD             : %.2f%%   (제약 <25%% → %s)\n", 100*mdd, if (mdd < 0.25) "충족" else "★위반"))
cat(sprintf("  Calmar          : %.3f\n", cagr/mdd))
cat(sprintf("  누적            : %.1f배\n", as.numeric(Return.cumulative(x))))
cat(sprintf("  최근 3개월 ret_net: %s\n", paste(sprintf("%s %+.2f%%", tail(L$realized_ym,3), 100*tail(L$ret_net,3)), collapse=" · ")))

## ── 4. 오늘 수리분 반영 상태
cat("\n■ 4. 오늘(08-08) 수리 반영 상태\n"); line()
newcols <- c("invested_eff","beta_R05_panel","beta_matches_ret_net")
cat(sprintf("  신설 열 존재    : %s\n", paste(sprintf("%s=%s", newcols, newcols %in% names(L)), collapse=" · ")))
if ("beta_matches_ret_net" %in% names(L))
  cat(sprintf("  β↔ret_net 대응  : 일치 %d / 불일치 %d (불일치 = 앵커가 다른 기준 값을 기록)\n",
              sum(L$beta_matches_ret_net), sum(!L$beta_matches_ret_net)))
cat(sprintf("  앵커 구성       : %s\n", paste(sprintf("%s×%d", names(table(L$ret_net_source)), table(L$ret_net_source)), collapse=" · ")))
last <- L[.N]
cat(sprintf("  최신월 %s   : ret_net %+.4f · β %.2f · invested_eff %.2f · src %s\n",
            last$realized_ym, last$ret_net, last$beta_R05,
            if ("invested_eff" %in% names(L)) last$invested_eff else NA, substr(last$ret_net_source,1,34)))

## ── 5. 배포 비중 (실제 주문 대상)
cat("\n■ 5. 최신 배포 비중\n"); line()
hd <- "05_Production/2.Factor_Model/2-4.STR_1715_on_M4gAE_R05_noLayer4_PG2/02_holdings_universe"
if (dir.exists(hd)) {
  w <- sort(list.files(hd, pattern="_weights_cap_0p20\\.csv$", full.names=TRUE))
  m <- sort(list.files(hd, pattern="_manifest\\.json$", full.names=TRUE))
  if (length(w)) {
    wf <- tail(w,1); W <- fread(wf)
    cat(sprintf("  비중 파일       : %s\n", basename(wf)))
    wc <- grep("^w|weight", names(W), value=TRUE, ignore.case=TRUE)[1]
    ## ★2026-08-08 오탐 수리: 비중 파일 첫 행은 CASH(단기예금/MMF)다.
    ##   초판은 CASH 를 종목으로 세어 max w 0.70 → "★위반"을 찍었다(실제로는 현금 70%).
    ##   종목 제약은 **주식 행에만**, 그리고 bound 0.20 은 **노출(invested) 정규화 후** 값에 적용된다
    ##   (배포 비중 = 전략비중 × invested 이므로 원장부 값은 invested 배만큼 축소돼 있다).
    if (!is.na(wc)) {
      E <- W[!(toupper(as.character(Ticker)) %chin% c("CASH"))]
      cash <- sum(W[toupper(as.character(Ticker)) %chin% c("CASH")][[wc]], na.rm=TRUE)
      inv  <- sum(E[[wc]], na.rm=TRUE)
      mx_n <- if (inv > 0) max(E[[wc]], na.rm=TRUE) / inv else NA_real_
      ok <- nrow(E) <= 25 && is.finite(mx_n) && mx_n <= 0.2001 &&
            all(E[[wc]] >= -1e-12, na.rm=TRUE) && abs(inv + cash - 1) < 1e-9
      cat(sprintf("  종목 %d (CASH 제외) · invested %.4f · CASH %.4f · Σ %.6f\n", nrow(E), inv, cash, inv+cash))
      cat(sprintf("  max w 원장부 %.4f → 노출정규화 %.4f (제약 ≤25종·≤0.20·long-only·Σ=1 → %s)\n",
                  max(E[[wc]], na.rm=TRUE), mx_n, if (ok) "충족" else "★위반"))
    }
  } else cat("  ★비중 CSV 없음\n")
  if (length(m)) {
    mj <- fromJSON(tail(m,1), simplifyDataFrame=FALSE)
    cat(sprintf("  manifest        : %s (as_of %s)\n", basename(tail(m,1)), paste(unlist(mj$as_of), collapse="")))
    cat(sprintf("  invested        : %s · regime %s\n",
        paste(unlist(mj$invested), collapse=""),
        paste(unlist(mj$overlay$beta_R05_V5$regime), collapse="")))
  }
} else cat("  (배포 슬롯 디렉터리 미확인)\n")

## ── 6. 페이퍼 NAV
cat("\n■ 6. 페이퍼 트래킹 NAV\n"); line()
np <- "06_Registry/live_track/STR_1715_on_M4gAE_R05_noLayer4_PG2/paper_nav.csv"
if (file.exists(np)) { N <- fread(np); cat(sprintf("  행 %d · 최신 %s · NAV %.6f\n", nrow(N), tail(N$date,1), tail(N$paper_nav,1))) }
cat("\n[라벨] 전 수치 = 원장/산출물 실측 (metric_type: backtested / 계약 rds 앵커)\n")
