## P1q — Ret_1m@T 는 T월 중 실현인가 T→T+1 forward 인가 (아크 전체를 가르는 단일 잔여)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P1p: load_month_factors(T) 는 T월 파일을 그대로 열고 Usable_Date 필터가 없다.
##  ⇒ 남은 질문 = Ret_1m 방향. RAWDATA Close 로 검산한다.
##   S1 forward(clean): cor(Ret_1m@T, Close@(T+1)/Close@T - 1) 가 최대 → 월말 T 팩터로 다음달 예측 = PIT clean
##   S2 contemporaneous(오염): cor(Ret_1m@T, Close@T/Close@(T-1) - 1) 가 최대 → same-month look-ahead
##   S3 불명: 두 상관 차이 < 0.10
##  ★판정 기준은 **어느 쪽이 1.0 에 가까운가** (동일 계산이면 ~1.0 이어야 한다).
suppressPackageStartupMessages({ library(data.table); library(arrow) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
R <- as.data.table(P$ret)[!is.na(Ret_1m)]; R[, Date := as.Date(Date)]
cat(sprintf("[내 ret 패널] %d행 · %d개월 · %s ~ %s\n", nrow(R), uniqueN(R$Date), min(R$Date), max(R$Date)))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Close")))
RAW[, Date := as.Date(Date)][, ym := format(Date, "%Y-%m")]
ME <- RAW[, .SD[which.max(Date)], by = .(Ticker, ym)][, .(Ticker, ym, Date_me = Date, Close)]
setorder(ME, Ticker, ym)
ME[, `:=`(Close_prev = shift(Close), Close_next = shift(Close, -1L),
          ym_prev = shift(ym), ym_next = shift(ym, -1L)), by = Ticker]
ME[, `:=`(r_contemp = Close/Close_prev - 1, r_forward = Close_next/Close - 1)]

R[, ym := format(Date, "%Y-%m")]
M <- merge(R[, .(Ticker, ym, Ret_1m)], ME[, .(Ticker, ym, r_contemp, r_forward)], by = c("Ticker","ym"))
M <- M[is.finite(Ret_1m) & is.finite(r_contemp) & is.finite(r_forward)]
cat(sprintf("[대조 쌍] %d행 · %d개월\n", nrow(M), uniqueN(M$ym)))

c_ct <- cor(M$Ret_1m, M$r_contemp, use="complete.obs")
c_fw <- cor(M$Ret_1m, M$r_forward, use="complete.obs")
d_ct <- median(abs(M$Ret_1m - M$r_contemp), na.rm=TRUE)
d_fw <- median(abs(M$Ret_1m - M$r_forward), na.rm=TRUE)
cat(sprintf("\ncor(Ret_1m, **동월 실현**  Close@T/Close@(T-1)-1) = **%.4f** · 중앙절대차 %.5f\n", c_ct, d_ct))
cat(sprintf("cor(Ret_1m, **익월 forward** Close@(T+1)/Close@T-1) = **%.4f** · 중앙절대차 %.5f\n", c_fw, d_fw))
verdict <- {
  if (abs(c_fw - c_ct) < 0.10) "S3_INDETERMINATE"
  else if (c_fw > c_ct) "S1_FORWARD_PIT_CLEAN"
  else "S2_CONTEMPORANEOUS_LOOKAHEAD_RISK"
}
cat(sprintf("\n판정: %s\n", verdict))
if (verdict == "S1_FORWARD_PIT_CLEAN")
  cat("★월말 T 팩터로 **다음달** 수익을 예측 = PIT clean. 아크 정본 2.137 유효.\n")
if (verdict == "S2_CONTEMPORANEOUS_LOOKAHEAD_RISK")
  cat("★★월말 T 팩터가 **T월 수익**을 설명 = same-month look-ahead. 정본 재산출 필요(FQ-044 2.08~2.18x).\n")
jsonlite::write_json(list(verdict=verdict, cor_contemp=c_ct, cor_forward=c_fw,
                          mad_contemp=d_ct, mad_forward=d_fw, n=nrow(M)),
                     file.path(OUT,"p1q_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
