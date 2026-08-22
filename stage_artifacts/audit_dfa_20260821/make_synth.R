## make_synth.R — 감사 전용 합성 지수 parquet 생성 (audit_dfa_20260821)
## A: 기본 (seed 11). B1/B2: t* 이후 난수 치환 (P5). P8: Value 열만 무국면 노이즈 치환. M0D: 단일일 교란 (P6-M0).
## 구조: Market + 6팩터 총수익. 팩터 active = 2-상태 마코프 국면 드리프트(±6bp/d) + 노이즈 → SJM이 학습할 신호 실재.
suppressPackageStartupMessages({library(data.table); library(arrow)})
OUTD <- "stage_artifacts/audit_dfa_20260821"
FACN <- c("Value","Size","Momentum","Quality","LowVol","Growth")

biz_days <- function(from, to){ d <- seq(as.Date(from), as.Date(to), by="day"); d[!(format(d,"%u") %in% c("6","7"))] }
D <- biz_days("2005-01-03","2012-12-31"); n <- length(D)

gen_path <- function(seed, n){
  set.seed(seed)
  mkt <- rnorm(n, 0.0002, 0.010)
  act <- matrix(NA_real_, n, 6)
  for(f in 1:6){
    st <- integer(n); st[1] <- sample(1:2,1)
    for(t in 2:n) st[t] <- if(runif(1) < 0.985) st[t-1] else 3L-st[t-1]
    mu <- c(-6e-4, 6e-4)[st]
    act[,f] <- mu + rnorm(n, 0, 0.003)
  }
  list(mkt=mkt, act=act)
}

mk_dt <- function(p){
  dt <- data.table(Date=D, Market=p$mkt)
  for(f in 1:6) dt[[FACN[f]]] <- p$mkt + p$act[,f]
  dt
}

A  <- gen_path(11, n)
B1n<- gen_path(21, n)   # 치환용 독립 경로
B2n<- gen_path(31, n)
P8n<- gen_path(41, n)   # Value 치환용 (무국면: active=순수 노이즈)
set.seed(41); p8_act <- rnorm(n, 0, 0.003)   # 국면 구조 없는 Value active

dtA <- mk_dt(A)

t1 <- as.Date("2010-06-30"); t2 <- as.Date("2012-03-30"); tm <- as.Date("2010-05-14")
stopifnot(t1 %in% D, tm %in% D)  # t2는 거래일 아니면 직전 거래일로
if(!(t2 %in% D)) t2 <- max(D[D<=t2])

## B1: Date > t1 이후 전 열 치환
dtB1 <- copy(dtA); i1 <- which(D > t1)
dtB1[i1, Market := B1n$mkt[i1]]
for(f in 1:6) dtB1[[FACN[f]]][i1] <- B1n$mkt[i1] + B1n$act[i1,f]

## B2: Date > t2
dtB2 <- copy(dtA); i2 <- which(D > t2)
dtB2[i2, Market := B2n$mkt[i2]]
for(f in 1:6) dtB2[[FACN[f]]][i2] <- B2n$mkt[i2] + B2n$act[i2,f]

## P8: Value 열만 전 기간 치환 (Market + 무국면 노이즈) — 나머지 열 불변
dtP8 <- copy(dtA); dtP8[, Value := Market + p8_act]

## M0D: 단일일 tm 교란 (전 열) — market -6%, 팩터 active ±8% 교대
dtM0D <- copy(dtA); im <- which(D == tm)
dtM0D[im, Market := -0.06]
for(f in 1:6) dtM0D[[FACN[f]]][im] <- -0.06 + c(0.08,-0.08)[1+(f %% 2)]

for(nm in c("A","B1","B2","P8","M0D")){
  dt <- get(paste0("dt", ifelse(nm=="A","A",nm)))
  write_parquet(dt, file.path(OUTD, sprintf("synth_%s.parquet", nm)))
}
cat(sprintf("synth written: n=%d days %s..%s | t1=%s t2=%s tm=%s\n", n, min(D), max(D), t1, t2, tm))
cat("SYNTH_DONE\n")
