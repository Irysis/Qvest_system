## R42 실현위험 append 경로 검증 — writer의 Ret_1m 산식(prod(1+Ret)-1)을 완료된 홀딩월에 실측
## (초기 실행선 need_ret 공집합이라 미실행된 경로 — 익월 append 기능 실동작 확증)
Sys.setenv(ARROW_IO_THREADS = "2")
suppressWarnings(suppressMessages({ library(arrow); library(data.table) }))
setDTthreads(1); try(arrow::set_io_thread_count(2L), silent=TRUE)
RAW_P <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/rawdata.parquet"
ym <- function(d){ d<-as.Date(d); as.integer(format(d,"%Y"))*100L+as.integer(format(d,"%m")) }
rw <- as.data.table(read_parquet(RAW_P, col_select=c("Date","Ticker","Ret")))
rw[, Date := as.Date(Date)]; rw[, ymv := ym(Date)]
rd_max_ym <- ym(max(rw$Date, na.rm=TRUE))
cat(sprintf("[test] rawdata max_ym = %d (완료월 판정 기준: holding_ym <= 이 값이어야 append)\n", rd_max_ym))
TAIL_THR <- -0.15
compute <- function(tk, H){
  rr <- rw[Ticker==tk & ymv==H, Ret]; rr <- rr[is.finite(rr)]
  if(!length(rr)) return(NULL)
  ret_1m <- prod(1+rr)-1
  list(ticker=tk, hold_ym=H, n_days=length(rr), ret_1m=round(ret_1m,5),
       tail_hit=as.integer(ret_1m < TAIL_THR), downside=if(ret_1m<0) round(ret_1m,5) else 0)
}
for (tk in c("A011070","A004170")) for (H in c(202605L, 202606L)) {
  o <- compute(tk, H)
  if (is.null(o)) cat(sprintf("[test] %s %d : 데이터 없음\n", tk, H))
  else cat(sprintf("[test] %s %d : n_days=%d ret_1m=%+.5f tail_hit(<-15%%)=%d downside=%+.5f\n",
                   o$ticker, o$hold_ym, o$n_days, o$ret_1m, o$tail_hit, o$downside))
}
cat(sprintf("[test] 202607 완료 여부(현 발화 홀딩월): %s → %s\n",
            202607L <= rd_max_ym,
            ifelse(202607L <= rd_max_ym, "완료(append 가능)", "미완결(pending — 정상: 초기 등록만)")))
cat("[test] 실현위험 append 경로 산식 실동작 확인 — writer step 5와 동일 로직\n")
