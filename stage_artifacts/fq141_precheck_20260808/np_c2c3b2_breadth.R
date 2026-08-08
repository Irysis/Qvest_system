## NP-c2c3b2 — mid 좁힘 악화가 breadth 축소인가 신호 열화인가
## 변형 정의(run_R4_mid_construction.R:87-101)로 실제 유니버스 크기를 재고 port_t 와 대조.
## Grinold: IR ∝ IC × sqrt(N). breadth 만이면 port_t 는 0 으로 수렴할 뿐 **부호가 뒤집히지 않는다**.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[b2] ",fmt,"\n"),...))
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
ME <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)
U <- RAW[Date %in% ME & (K200==TRUE|KQ150==TRUE) & !is.na(Size) & Size>0]
U <- U[Date >= as.Date("2012-12-01") & Date <= as.Date("2026-06-30")]   # R4 OOS 창
setorder(U, Date, -Size); U[, cap_rank := seq_len(.N), by=Date]

br <- function(f, lab) {
  n <- U[, .(n = f(.SD)), by=Date]$n
  data.table(variant=lab, breadth=round(mean(n),1))
}
B <- rbindlist(list(
  br(function(d) nrow(d), "full_univ"),
  br(function(d) sum(d$cap_rank>10), "mega_drop10"),
  br(function(d) sum(d$cap_rank>=11 & d$cap_rank<=50), "mid_band_11_50"),
  br(function(d) sum(d$cap_rank>=11 & d$cap_rank<=100), "mid_11_100"),
  br(function(d) sum(d$KQ150==TRUE), "kq150_focus"),
  br(function(d) sum(d$cap_rank>=11), "nonmega_all")))

R <- fread("04_Research/method_frontier/wt006_exog_forecast/R4_mid_construction_results.csv")
M <- merge(B, R[, .(variant, port_t, net_sr, turnover, ew_uni_t)], by="variant")
M[, sqrtN := sqrt(breadth)]
setorder(M, -breadth)
say("--- 유니버스 크기(R4 창 월평균) vs 성과 ---")
print(M[, .(variant, breadth, sqrtN=round(sqrtN,2), port_t, net_sr, turnover, ew_uni_t)])
say("cor(port_t, breadth) = %.3f · cor(port_t, sqrtN) = %.3f",
    cor(M$port_t, M$breadth), cor(M$port_t, M$sqrtN))
say("cor(net_sr, sqrtN)  = %.3f", cor(M$net_sr, M$sqrtN))
say("--- Grinold 검정: breadth 만이면 port_t 는 0 으로 수렴할 뿐 음수로 못 간다 ---")
neg <- M[port_t < 0]
say("  port_t < 0 인 변형: %s", if (nrow(neg)) paste(neg$variant, collapse=", ") else "없음")
if (nrow(neg)) say("  → breadth 축소만으로는 설명 불가. 신호 열화 성분 실재.")
say("--- EW-uni basis 에서도 같은 순서인가(벤치 제거 시 신호만 남음) ---")
say("  cor(ew_uni_t, sqrtN) = %.3f", cor(M$ew_uni_t, M$sqrtN))
print(M[order(-ew_uni_t), .(variant, breadth, ew_uni_t, port_t)])
