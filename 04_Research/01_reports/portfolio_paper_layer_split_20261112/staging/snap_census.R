# 기저 캐시 전수에 달 스냅을 걸어 엔진별로 무엇이 달라지는지 센다 — 날짜 · 개수만(성과 없음).
suppressMessages({ library(data.table) })
root <- "G:/OneDrive/Quant_Module_Moltbot"
source(file.path(root, "02_Infrastructure/reinforcement/rf_base_align.R"))
cal <- sort(unique(as.Date(arrow::read_parquet(file.path(root, ".cache/rawdata.parquet"), col_select = "Date")$Date)))
me <- cal[!duplicated(format(cal, "%Y%m"), fromLast = TRUE)]
sig <- me[me >= as.Date("2000-01-01")]
eng <- list.files(file.path(root, "04_Research/strategies"), pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
eng <- eng[grepl("/RP_AUTO[^/]*/(engine[^/]*\\.R)$", eng)]
emd <- data.table(path = eng, md5 = unname(tools::md5sum(eng)))
emd[, pre := substr(md5, 1, 12)][, name := paste0(basename(dirname(path)), "/", basename(path))]
fs <- list.files(file.path(root, ".cache/rf_base_signal"), pattern = "^base_v2_[0-9a-f]{12}_.*\\.rds$", full.names = TRUE)
fi <- data.table(f = fs, pre = substr(basename(fs), 9, 20), mt = file.info(fs)$mtime)
setorder(fi, pre, -mt); fi <- fi[!duplicated(pre)]                       # 엔진 md5 접두마다 가장 새 캐시
res <- rbindlist(lapply(seq_len(nrow(fi)), function(i) {
  b <- tryCatch(as.data.table(readRDS(fi$f[i])), error = function(e) NULL)
  if (is.null(b) || !all(c("Date", "Ticker", ".base_sig") %in% names(b))) return(NULL)
  b <- b[, .(Date = as.Date(Date), Ticker, .base_sig)]
  E <- sort(unique(b$Date)); r <- rf_base_month_snap(b, cal)
  nm <- emd[pre == fi$pre[i], name]; nm <- if (length(nm)) nm[1] else "(지금 엔진과 md5 다름)"
  gap <- if (length(E) > 1) as.numeric(median(diff(match(E[E %in% cal], cal)))) else NA_real_
  data.table(md5 = fi$pre[i], engine = nm, cache = format(fi$mt[i], "%m-%d"), n_dates = length(E), first = format(min(E)), last = format(max(E)),
             gap_td = gap, legacy_me = sum(E %in% sig), snap_me = sum(unique(r$panel$Date) %in% sig),
             ident = r$diag$n_identity, moved = r$diag$n_moved, superseded = r$diag$n_superseded, tail = r$diag$n_dropped_tail,
             max_lag = as.integer(r$diag$max_lag_td), n_off_cal = sum(!E %in% cal))
}))
setorder(res, -moved, engine)
options(width = 250)
print(res, nrows = 200)
cat(sprintf("\n캐시 %d개(엔진 md5 접두 기준) · 달 스냅으로 달라지는 것(옮김 > 0 또는 덮임 > 0) %d개 · 항등 %d개 · 지금 엔진 md5 와 일치 %d개\n",
            nrow(res), sum(res$moved > 0 | res$superseded > 0), sum(res$moved == 0 & res$superseded == 0), sum(res$engine != "(지금 엔진과 md5 다름)")))
fwrite(res, file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "snap_census.csv"))
