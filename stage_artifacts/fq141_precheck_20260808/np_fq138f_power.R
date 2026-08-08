## FQ-138f — DiD 검정력 사전 계산: n=28 조건부 표본에서 t=2.0 에 필요한 효과크기
## 목적: 측정 후 미달일 때 '검정력 부족'과 '효과 부재'를 구별해 보고하기 위함(사전 고정).
## 방법: (SIG - NEU) 스프레드의 월 변동성을 **무작위 바스켓 쌍**으로 실측 → 필요 평균 역산.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[138f] ",fmt,"\n"),...))
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
ME <- sort(RAW[, .(Date=max(Date)), by=ym]$Date); RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
U <- RAWME[(K200==TRUE|KQ150==TRUE) & !is.na(Size)&Size>0, .(Date,Ticker)]
P <- merge(U, ret, by=c("Date","Ticker"))
P <- P[Date>=as.Date("2019-12-01") & Date<=as.Date("2026-07-31")]   # panelx_A 창
say("창 %d개월", uniqueN(P$Date))

## 무작위 25종 바스켓 2개의 수익차 = (SIG - NEU) 의 귀무 변동성
sp <- function(seed){ set.seed(seed)
  S <- P[, { i <- sample(.N); a <- head(i,25); b <- i[26:50]
            .(diff = mean(Ret_1m[a]) - mean(Ret_1m[b])) }, by=Date]
  S$diff }
sds <- sapply(1:120, function(s) sd(sp(s)))
sd_m <- median(sds)
say("(SIG-NEU) 월 변동성 귀무 실측: 중앙 %.4f · 5%%~95%% %.4f~%.4f (120 draw)",
    sd_m, quantile(sds,.05), quantile(sds,.95))

## DiD 는 두 국면 그룹의 차 — 분산이 대략 2배(독립 근사)
say("--- t=2.0 도달에 필요한 DiD 평균 (NW 팽창 k=1.25 가정) ---")
for (n in c(28L, 34L, 40L, 80L)) {
  for (lab in c("스프레드 단일","DiD(2군 차)")) {
    s <- if (lab=="스프레드 단일") sd_m else sd_m*sqrt(2)
    need_m <- 2.0 * (s/sqrt(n)) * 1.25
    say("  n=%2d %-14s 필요 월평균 %+.4f = 연 %+.2f%%", n, lab, need_m, need_m*12*100)
  }
}
say("--- 참고: 원 보고 조건부 IC 격차 +0.1337 · 조건부 PORT_t 2.198(무조건 0.511) ---")
say("  ★사전 고정: 측정 DiD 가 문턱 미달이고 |DiD 평균| 이 위 필요치보다 작으면")
say("    '효과 부재'가 아니라 '검정력 부족'으로 보고한다.")
