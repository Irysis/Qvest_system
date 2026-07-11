## _r6_telegram.R — R6 텔레그램 v7 판정 보고 (차트팩 + 쉬운 설명 + 판정 평문)
suppressPackageStartupMessages({library(data.table)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/telegram/tg_chart_pack.R")
source("02_Infrastructure/telegram/telegram_notify.R")
OUTD <- "stage_artifacts/r6_portt_boruta"; if(!dir.exists(OUTD)) dir.create(OUTD, recursive=TRUE)

## ── ① sweep: R4+R5+R6 통합 서열 (대조군-초과 paired NW-t, hline=2.0) ──
labels <- c("R4 Boruta W60ICW","R4 Boruta W36EW","R5 StabSel W36π70","R5 mRMR W36K4","R5 mRMR W60K6",
            "R6 P-pure W60K10","R6 P-pure W36K10","R6 P-pure W60K20","R6 P-pure W36K20","R6 P-boruta W36K20")
values <- c(-2.51,-2.30,-1.52,0.14,0.18, 1.26,1.57,2.12,2.25,-2.58)
sweep_png <- tg_chart_sweep(labels, values, out_dir=OUTD,
  title="RAMP 선별 방법별 대조군-초과 paired NW-t (R4→R6)",
  value_label="paired NW-t (lag3, vs 대조군)", hline=2.0, hline_label="kill 문턱",
  highlight="R6 P-pure W36K20", filename="01_sweep_r4_r6_paired.png")

## ── ② 최선 config(Ppure_W36_K20) 표준 3종 ──
x <- readRDS(".cache/_ramp_r6_20260711.rds"); PR <- x$PR
pr <- PR[["Ppure_W36_K20"]]   # date, act_bm, ret_net, benchmark_ret
pack <- tg_chart_pack(pr, out_dir=OUTD,
  title="R6 최선 P-pure W36K20",
  metrics_note="cap-w PORT_t 2.61 · oos -0.08 · calmar 0.45 (canonical, screen-tier)",
  prefix="02_ppure_")
charts <- c(sweep_png, pack)
cat("charts:\n"); cat(paste(charts, collapse="\n"), "\n")

## ── 텔레그램 v7 brief ──
tg_agent_brief(
  agent = "Q-Lead",
  title = "RAMP R6 팩터 선별 — '과거 실제 성과' 기질로 교체 (신호 실재·자본 미달)",
  sections = list(
    list(type="summary", emoji="📌",
      body="팩터를 '과거 실제 성과 상위'로 골라 배분하니 기존(전체·11군 배분)보다 확실히 나았지만, 자본 투입 기준에는 여전히 못 미쳐 참고용으로만 보관합니다."),
    list(type="bullet", emoji="📖", heading="쉬운 설명",
      items=c(
        "시도: 팩터를 '최근 실제 성과 상위' 순으로 뽑아 배분 (기존 상관성 기준은 실패했었음)",
        "방법: 102개 팩터 20년 백테스팅으로 성과 순위화, 그 시점 정보로만 상위 선택(미래참조 차단)",
        "결과: 기존보다 확실히 개선(다중검정 t값 +2.25/+3.01). 단 2017년 이후엔 효과 대부분 소멸",
        "의미: 방법은 진짜 효과나 재료(수익률 팩터)가 2017년 후 약해져 자본 기준 미달, 참고용 보관")),
    list(type="kv", emoji="📊", heading="핵심 수치 (시총가중 기준)",
      kv=list(
        "최고 다중검정 t값"="2.61 (기준 2.95 미달)",
        "기존 11군 대비 개선"="+2.25 (짝지은 t값)",
        "전체 102개 대비 개선"="+3.01 (순수 선별효과)",
        "표본외 유지율"="-0.08 (기준 0.7 미달)")),
    list(type="bullet", emoji="🚩", heading="주의 / 한계",
      items=c(
        "개선은 2017년 이전 집중 — 이후 초과수익은 여전히 음(-0.11), 재료 감쇠 벽",
        "선별이 저평가(Value) 팩터에 집중(31~35%) — 사실상 고정형 밸류 틸트",
        "보루타(Boruta)는 앞 라운드에 이어 또 손해(과선별) — 이 풀에서도 음(-2.58)")),
    list(type="bullet", emoji="➡️", heading="판정 / 다음",
      items=c(
        "판정 참고용 등급 — 방법은 효과 있으나 자본 기준(다중검정 t값 2.95·유지율 0.7) 미달, 실제 돈 미투입",
        "선별 축은 소진 아님 — 기존 상관성 선별과 달리 대조군을 유의하게 이김",
        "벽은 선별 아닌 재료(수익률 팩터)의 2017년 후 감쇠 — 비-수익 원천이 잔여 경로",
        "교훈코드 적립 및 프론티어 큐 갱신 완료")),
    list(type="code", emoji="📁", heading="산출",
      body="outputs/ramp/r6_portt_boruta_{gates,paired,summary}_20260711 · r6_factor_deployzone_active.parquet · challenge_note_r6_portt_boruta_20260711.md")
  ),
  charts = charts
)
cat("TG_DONE\n")
