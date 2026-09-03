# R11 — detect_lookahead 양성 대조 2단.
#  (A) 검출기가 **실제로 선언한 idiom** 을 주입해 발화를 실증한다(계기 생존 확인).
#  (B) risk 레인 고유 위반(full-sample cov)을 주입해 **미검출 축**을 실증한다 — 이건 계기의 한계다.
#  ★"경고 0" 을 통과로 읽지 않기 위한 절차(memory: 검사기는 양방향으로 재라).
suppressWarnings(suppressMessages({library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
source(file.path(ROOT,"02_Infrastructure/validation/lookahead_detector.R"))
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004")
base <- file.path(OUT,"r4_regime.R"); src <- readLines(base, warn=FALSE)
z0 <- detect_lookahead(base, verbose=FALSE)

mk <- function(extra, nm){ p <- file.path(OUT,nm); writeLines(c(src, extra), p)
  z <- detect_lookahead(p, verbose=FALSE); unlink(p); z }

# (A) 검출기 선언 idiom — C1(full-sample vol) / C5_VT / C5_DDshort
zA <- mk(c('vol_ann <- sd(port_ret) * sqrt(252)',
           'after_vt <- ret_series * vt_scale',
           'window_ret <- nav[(i-19):i]   # drawdown window'), "_probe_A.R")
# (B) risk 고유 위반 — 전 표본 공분산 / 국면 라벨 미래 shift
zB <- mk(c('Om_full <- cov(Xfull)',
           'Sig_full <- cov(as.matrix(RET_ALL))',
           'lab[, panic_future := shift(panic, -1L)]'), "_probe_B.R")

f <- function(z) sapply(z$violations, function(v) v$check)
cat(sprintf("[대조] baseline violations=%d\n", length(z0$violations)))
cat(sprintf("[대조 A] 선언 idiom 주입 → violations=%d (%s) · clean=%s\n",
            length(zA$violations), paste(f(zA), collapse=","), as.character(zA$clean)))
cat(sprintf("[대조 B] risk 고유 위반 주입 → violations=%d (%s) · clean=%s\n",
            length(zB$violations), paste(f(zB), collapse=","), as.character(zB$clean)))
firedA <- length(zA$violations) > length(z0$violations)
firedB <- length(zB$violations) > length(z0$violations)
cat("[대조] A 발화:", firedA, " / B 발화:", firedB, "\n")
write_json(list(
  control="detect_lookahead_two_sided",
  baseline=list(file="r4_regime.R", clean=z0$clean, n=length(z0$violations)),
  probeA=list(purpose="검출기가 선언한 idiom(C1 full-sample vol / C5_VT / C5_DDshort)",
              n=length(zA$violations), checks=as.list(f(zA)), fired=firedA),
  probeB=list(purpose="risk 레인 고유 위반(full-sample cov · 국면라벨 shift(-1))",
              n=length(zB$violations), checks=as.list(f(zB)), fired=firedB),
  interpretation=paste0(
    "A 가 발화하면 계기는 살아 있다. B 가 발화하지 않으면 detect_lookahead 의 R 경로에는 ",
    "**전 표본 cov() 에 대한 일반 검사가 없다** 는 뜻이며, 그 축의 PIT 는 검출기가 아니라 ",
    "설계·산출물 기록(Omega 추정창 선언 · ex_ante_knowability walk-forward)이 담보한다. ",
    "risk_package.pit.C1 은 그 근거로 읽어야 하고, detect_lookahead PASS 를 C1 통과의 증거로 인용하면 안 된다."),
  risk_c1_evidence=c("Omega = 직전 504영업일 EWMA(rolling)",
                     "D = 직전 24개월 EWMA(rolling)",
                     "beta = 252일 rolling(Blume)",
                     "국면 Omega 는 as-of 진단 전용 + consumption_restriction 명시",
                     "사전 인지가능성은 시점별 재추정(walk-forward)으로 별도 실증")),
  file.path(OUT,"pit_gate_positive_control.json"), pretty=TRUE, auto_unbox=TRUE, na="null")
