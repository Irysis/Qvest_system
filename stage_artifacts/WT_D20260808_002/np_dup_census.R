## C14/M26 중복 등재 + compute_consensus 침묵 스킵 범위 census (부수 산출 — 제안서 근거)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) { cat(sprintf(paste0("[dup] ",fmt,"\n"),...)); flush.console() }
`%||%` <- function(a,b) if (is.null(a) || length(a)==0L || (length(a)==1L && is.na(a))) b else a

## --- 1. registry 등재 상태 ---------------------------------------------------
rj <- fromJSON(".cache/factor_db/factor_registry.json", simplifyVector = FALSE)
fl <- if (!is.null(rj$factors)) rj$factors else rj
say("registry 최상위 키: %s", paste(head(names(rj),8), collapse=","))
say("registry 항목 수: %d", length(fl))
getid <- function(e, nm) {
  for (k in c("factor_id","id","name","Factor_Name")) if (!is.null(e[[k]])) return(as.character(e[[k]]))
  nm
}
ids <- vapply(seq_along(fl), function(i) getid(fl[[i]], names(fl)[i] %||% ""), character(1))
say("C 계열 등재: %s", paste(sort(grep("^C[0-9]", ids, value=TRUE)), collapse=" "))
for (tgt in c("C14_Revenue_Surprise","M26_Revenue_Mom")) {
  i <- which(ids == tgt)
  if (!length(i)) { say("★%s registry 미등재", tgt); next }
  say("=== registry[%s] ===", tgt)
  cat(toJSON(fl[[i[1]]], auto_unbox=TRUE, pretty=TRUE), "\n")
}

## --- 2. factor_db 실산출 census (C 계열 전수, 3개 vintage) -------------------
for (m in c("200506","201506","202507")) {
  f <- sprintf(".cache/factor_db/factor_db_%s.parquet", m)
  if (!file.exists(f)) next
  d <- as.data.table(read_parquet(f, col_select=c("Factor_Name")))
  fc <- sort(unique(d$Factor_Name))
  cser <- grep("^C[0-9]", fc, value=TRUE)
  say("factor_db_%s: 총 %d종 · C계열 산출 %d종 = %s", m, length(fc), length(cser), paste(cser, collapse=" "))
  reg_c <- sort(grep("^C[0-9]", ids, value=TRUE))
  say("   ★등재O 산출X: %s", paste(setdiff(reg_c, cser), collapse=" "))
}

## --- 3. 전 442월 C14/M26 산출 여부 (침묵 스킵의 상시성 확인) ------------------
fp <- sort(Sys.glob(".cache/factor_db/factor_db_*.parquet"))
chk <- rbindlist(lapply(fp, function(p) {
  d <- as.data.table(read_parquet(p, col_select=c("Factor_Name")))
  data.table(ym=substr(basename(p),11,16),
             C14=sum(d$Factor_Name=="C14_Revenue_Surprise"),
             M26=sum(d$Factor_Name=="M26_Revenue_Mom"),
             C10=sum(d$Factor_Name=="C10_SUE_Persistence"),
             C11=sum(d$Factor_Name=="C11_Earnings_Streak"),
             C13=sum(d$Factor_Name=="C13_Revision_Breadth_3m"),
             C15=sum(d$Factor_Name=="C15_Forecast_Error_Trend"),
             C17=sum(d$Factor_Name=="C17_OP_Revision"),
             C18=sum(d$Factor_Name=="C18_Earnings_CAR_3d"))
}))
say("--- 전 %d개 월 파일 전수 (cons-게이트 블록 7종 + M26 대조) ---", nrow(chk))
for (k in c("C10","C11","C13","C14","C15","C17","C18","M26")) {
  v <- chk[[k]]
  say("  %-4s 산출월 %3d/%d · 총 %8d행 · 최근값 %d", k, sum(v>0), length(v), sum(v), tail(v,1))
}
## ★양성 대조: 0 이 결론이 아니라 정지 신호 — 같은 스캔이 산출 팩터를 잡는지 확인
say("  ★양성 대조 M26 산출월 %d ⇒ 스캐너 자체는 살아있음(0 은 진짜 부재)", sum(chk$M26>0))
fwrite(chk, "stage_artifacts/WT_D20260808_002/consensus_silent_skip_census.csv")
say("저장: stage_artifacts/WT_D20260808_002/consensus_silent_skip_census.csv")
