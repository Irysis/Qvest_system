#!/usr/bin/env Rscript
suppressMessages({library(data.table); library(jsonlite)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260714_001")
CH   <- file.path(OUT, "charts"); dir.create(CH, showWarnings=FALSE, recursive=TRUE)
source(file.path(ROOT, "02_Infrastructure/telegram/tg_chart_pack.R"))
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

# Chart 1: cap-w authoritative PORT_t per surface (deployable basis)
c1 <- tg_chart_sweep(
  labels = c("S1 비적정","S2 강조사항","S3 계속기업","S4 KAM수","S5 정정횟수"),
  values = c(0, -0.73, 0.91, -0.36, -0.53),
  out_dir = CH, title = "감사신호 cap-w PORT_t (배포 기준·권위) — 全 |t|<1",
  value_label = "PORT_t (NW lag-3)", hline = 2.95, hline_label = "졸업컷",
  filename = "c1_capw_portt.png")

# Chart 2: size-tier spread_t (EW basis) — SMALL이 全 신호 구동 = size 아티팩트
c2 <- tg_chart_sweep(
  labels = c("S2 강조 MEGA","S2 강조 SMALL","S3 계속 MEGA","S3 계속 SMALL",
             "S4 KAM MEGA","S4 KAM SMALL","S5 정정 MEGA","S5 정정 SMALL"),
  values = c(-0.20, 5.90, -0.41, 2.87, -0.69, 2.25, -1.78, 3.83),
  out_dir = CH, title = "size-tier spread_t: SMALL만 양(+)=size 아티팩트 (MEGA 死)",
  value_label = "flagged-unflagged spread t", hline = 2.0, hline_label = "유의",
  filename = "c2_size_tier.png")

# Chart 3: flagged firm count by FY (going-concern + non-clean) — sparsity + 2019 jump
c3 <- tg_chart_sweep(
  labels = c("2015","2016","2017","2018","2019","2020","2021","2022","2023","2024","2025"),
  values = c(2,2,3,2,13,44,52,28,17,16,17),
  out_dir = CH, title = "going-concern 플래그 종목수/FY (비적정은 11년 2건뿐)",
  value_label = "flagged 종목수 (going-concern)",
  filename = "c3_flag_by_year.png")

sections <- list(
  list(type="text", title="쉬운 설명",
       body="감사보고서 '경고 신호'로 나쁜 종목을 미리 빼면(exclusion) 좋아지는지 실측했습니다. 배포 대형주에선 통하지 않았습니다. 경고 종목이 실제 더 나쁘지 않았고(권위 지표 全 무의미), 유일한 효과는 소형주 규모효과였으며 방향도 반대(경고 종목이 오히려 초과수익)였습니다. 진짜 부실(비적정)은 11년 2곳뿐이라 뺄 종목이 없었습니다."),
  list(type="text", title="판정",
       body="CONFIG_SCOPED_NEGATIVE (프론티어 열림). 성립 조건=부실 종목 사전 제거로 위험 감소이나 미충족. 자본 적용 불가 — 배포 top-25 PORT_t가 exclusion으로 사실상 안 움직임(계속기업 +0.024, 비적정 0.000)."),
  list(type="kv", title="핵심 실측", kv=list(
    "시총가중 권위지표"="포트t 全 1미만(무의미)",
    "시총계층 분해"="소형만 유의(+)·초대형/중형 소멸",
    "부호"="반전 — 경고종목이 오히려 초과수익(규모효과)",
    "비적정 희소성"="11년 2사·상위25 편입 0회",
    "강조사항 흔함"="상위25중 14.3 해당(제외 불가)",
    "계약 제외효과"="계속기업 +0.024·비적정 +0.000(영)",
    "실측 표본"="4.4만행·125개월·702종목"
  )),
  list(type="bullet", title="유의사항", items=c(
    "생존편향은 보수 방향이나 대형주 무의미는 불변",
    "정정신호는 빈도-인접만 측정(진짜 크기는 파서 필요)",
    "핵심감사사항은 2019년 이후만·레짐 편중 유의")),
  list(type="bullet", title="다음 탐침 (프론티어 열림)", items=c(
    "소형주 포함 유니버스에서 부실신호 재측정(위험감시 소비면)",
    "복합 부실신호 결합(계속기업 x 관리/거래정지/불성실공시)",
    "정정 진짜 크기 추출은 파서 관문(현재 미정당화)")),
  list(type="text", title="소비 배선",
       body="계속기업/비적정 신호 = monitoring tripwire로 배선(편입 종목에서 발생 시 alert·risk guard, alpha 아님).")
)

res <- tg_agent_brief(
  agent="Alpha",
  title="WT-D20260714_001 R25 감사-메타데이터 exclusion — CONFIG_SCOPED_NEGATIVE",
  sections=sections,
  charts=c(c1,c2,c3),
  as_of="2026-07-14")
cat("telegram sent. ok=", isTRUE(res$ok), "\n")
cat("charts:", c1, c2, c3, sep="\n")
