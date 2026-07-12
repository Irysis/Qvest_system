## _r8_charts_telegram.R — R8 실측 시각화(원칙 9) + 텔레그램 v7 판정 보고
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT=QM); setwd(QM)
source("02_Infrastructure/telegram/tg_chart_pack.R")
source("02_Infrastructure/telegram/telegram_notify.R")
r8 <- fromJSON("outputs/ramp/r8_band_escalation_20260712.json")
r7 <- readRDS(".cache/_ramp_r7_20260712.rds"); prc <- as.data.table(r7$PR[["capwrepro_W36_K20"]])[order(date)]
OUTD <- "stage_artifacts/ramp_R8_20260712"; if(!dir.exists(OUTD)) dir.create(OUTD, recursive=TRUE)
LCODE <- Sys.getenv("R8_LCODE","L-RAMP-20260712_R8")

## ── Chart 1: 보강증거 3종 (통일 '판정문턱(0) 대비 여유 — 양수=충족' 대시보드) ──
e1t <- 1.4647; e2m <- 3.919 - (-1.369); e3a <- -0.0052*100; e3b <- (0.30-0.3241)*10
p1 <- tg_chart_sweep(
  labels = c("①추세 trailing PORT_t (>0)", "②플라시보 real−null(95%) (>0⇔p<.05)",
             "③a 북기여 ΔIR×100 (>0)", "③b 탈상관 (0.30−|cor|)×10 (>0)"),
  values = c(e1t, e2m, e3a, e3b),
  out_dir = OUTD, title = "R8 보강증거 3종 (양수=충족) — 2/3 band_escalated",
  value_label = "판정문턱(0) 대비 여유", hline = 0, hline_label = "문턱",
  filename = "r8_evidence_bars.png")

## ── Chart 2: EW-active vs cap-w active 누적 초과수익 (왜 EW는 실재하나 cap-w는 미달인가) ──
f2 <- file.path(OUTD, "r8_ew_active_cumulative.png")
grDevices::png(f2, width=1000, height=560, res=110)
graphics::par(mar=c(4,4.4,3.2,1.2), family="")
ew_w <- cumprod(1+ifelse(is.na(prc$act),0,prc$act)); cw_w <- cumprod(1+ifelse(is.na(prc$act_bm),0,prc$act_bm))
dt <- as.Date(prc$date); yl <- range(c(ew_w, cw_w))
plot(dt, ew_w, type="l", lwd=2.4, col="#2ca02c", ylim=yl, xlab="", ylab="누적 초과수익 (배수)",
     main="R6-best Ppure W36_K20 — 벤치 대비 누적 초과수익")
lines(dt, cw_w, lwd=2.2, col="#7f7f7f")
abline(v=as.Date("2017-01-01"), col="#d62728", lty=3, lwd=1.4); abline(h=1, col="#333333", lty=2)
legend("topleft", bty="n", lwd=c(2.4,2.2), col=c("#2ca02c","#7f7f7f"),
       legend=c("EW 진단 basis (PORT_t 3.92·oos 0.51 band_escalated)", "cap-w authoritative (PORT_t 2.61·oos −0.08 자본게이트 FAIL)"), cex=0.78)
text(as.Date("2017-01-01"), yl[2]*0.96, "2017", col="#d62728", cex=0.7, pos=4)
grDevices::dev.off()
p2 <- normalizePath(f2, winslash="/")
cat("charts:\n", p1, "\n", p2, "\n")

## ── Telegram v7 (판정 평문 1줄 + 쉬운 설명 + 자동 용어풀이) ──
tg_agent_brief(
  agent = "Q-Lead",
  title = "RAMP R8 — 표본외 성적 보강심사(band escalation) 2/3 통과: 배포성 결정 재료 자격 회복(자본 아님)",
  sections = list(
    list(type="summary", emoji="📌",
      body="R6 최선 팩터전략의 표본외 성적(0.51)을 보강심사에 부쳐 2/3 통과 — 배포성 결정 재료 자격은 회복, 단 실제 자본 기준(cap-w)은 미달."),
    list(type="bullet", emoji="📖", heading="쉬운 설명",
      items=c(
        "시도: R7이 표본외 0.51을 문턱 하나로 '탈락' 종결했으나 규칙상 0.5~0.7은 보강심사 대상 — 그 절차 실행",
        "방법: EW 기준 ①최근도 초과수익 양수? ②가짜검사(플라시보) 통과? ③현 운용북에 섞어 도움? 3종 실측",
        "결과: ①통과·②통과(가짜검사 완승·우연확률 0)·③미달 → 2/3 = 조건부 배포성 재료 자격 회복",
        "의미: 신호는 진짜지만 자본 기준(대형주가중 cap-w)엔 미달 — 소형주 몰린 알파라 현 북엔 못 담음")),
    list(type="kv", emoji="📊", heading="보강증거 3종 (EW 진단 basis)",
      kv=list("표본외유지율"="0.51 (밴드 [0.5,0.7))",
              "①추세 PORT_t"="1.46 (>0 충족)",
              "②플라시보 p"="0.000 (real 3.92 vs null −2.38)",
              "③북기여 ΔIR"="−0.005 · |상관| 0.32 (미달)",
              "종합"="2/3 → band_escalated")),
    list(type="bullet", emoji="🚩", heading="주의 (정직 caveat)",
      items=c(
        "자본 게이트(cap-w) 3종 전부 미달 불변 — PORT_t 2.61 · 표본외 −0.08 · Calmar 0.45",
        "③북기여는 ΔIR 음수라 미달 — 후보↔북 월-정합 상관 0.94 caveat이나 판정 비-결정적",
        "①추세 신호 감쇠 중(3분할 4.20→1.72→1.46) — 규칙상 통과이나 약화")),
    list(type="bullet", emoji="➡️", heading="다음 / 돈에 뭐가 달라지나",
      items=c(
        "이번 판정으로 실제 자본은 배정 안 함 — cap-w 미달로 '참고용 배포성 재료(D3)'로만 보관",
        "메타: 신호는 진짜인데(플라시보 완승) 현 대형주-가중 북엔 못 담김 = 소형주 국소화 벽",
        "잔존 개척지 = 비-수익 신규 원천(임원 지분거래 공시 등)",
        "교훈코드 적립 완료 · 개척지 큐 종결"))
  ),
  charts = c(p1, p2),
  footer = paste0("📚 산출: outputs/ramp/r8_band_escalation_20260712.json · ", LCODE)
)
cat("TG_DONE\n")
