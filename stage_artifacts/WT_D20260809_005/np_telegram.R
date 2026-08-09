## FQ-198 텔레그램 — tg_agent_brief() 단일 진입점 + 차트(원칙 9)
## ★tg_agent_brief 에 summary 인자는 없다(실측: 시그니처 agent/title/sections/as_of/charts/...).
##   한줄 결론은 첫 섹션 type="summary" 로 넣는다.
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260809_005")
AV  <- fromJSON(file.path(OUT,"alpha_validation.json"), simplifyVector=FALSE)
RT  <- readRDS(file.path(OUT,"p1_results.rds"))$RT
OUTS<- readRDS(file.path(OUT,"p3b_results.rds"))$OUTS
cat(sprintf("[tg] 입력 실측: arm %d · 반전통제 spec %d · primary t %+.3f\n",
            nrow(RT), nrow(OUTS), AV$primary$fmb_nw3_t))

ord <- c("C18_Earnings_CAR_3d","C10s_SUE_Persist_step","C13s_RevBreadth_step","C15s_SUE_Trend_step")
c1 <- tg_chart_sweep(
  labels = c("C18 (원안 primary)","C10s (스텝보정)","C13s (스텝보정)","C15s (스텝보정)"),
  values = sapply(ord, function(a) as.numeric(RT[arm==a]$t_nw3)),
  out_dir = OUT, title = "FQ-198 신규 컨센서스 재료 — 증분 회귀 t값 (문턱 2.0)",
  hline = 2.0, highlight = 1L)

c2 <- tg_chart_sweep(
  labels = c("통제 없음","+1개월 반전","+6일 창","+1M+12M","+전체"),
  values = abs(OUTS$t_nw3),
  out_dir = OUT, title = "C18 증분 t값 — 단기반전 통제 시 붕괴 (문턱 2.0)",
  hline = 2.0, highlight = 3L)

charts <- c(unlist(c1), unlist(c2), file.path(OUT,"chart_fq198_summary.png"))
charts <- charts[file.exists(charts)]
cat(sprintf("[tg] 차트 %d장: %s\n", length(charts), paste(basename(charts), collapse=", ")))

res <- tg_agent_brief(
  agent = "Alpha",
  title = "FQ-198 · 해금됐다던 컨센서스 4종 — 실제 신규 재료는 0종",
  sections = list(
    ## ★summary body 는 [20, 100]자 제약 (실측: tg_format_summary). 상세는 text 섹션으로.
    list(type = "summary", emoji = "📌",
         body = "새로 채워졌다던 팩터 4종을 다 재봤더니 실제 신규 재료는 0종이었습니다."),

    list(type = "bullet", emoji = "🧭", heading = "무슨 일이었나",
      items = c(
        "어제 재빌드로 25년치가 새로 채워졌다던 애널리스트 추정치 팩터 4종을 실제로 재봤습니다",
        "둘은 이미 쓰고 있는 팩터와 소수점까지 똑같은 복제본이었습니다",
        "하나는 아예 만들어지지도 않았습니다",
        "나머지 하나는 실적 발표 반응이 아니라 월말 6일간 주가 등락이었습니다",
        "판정 — 이 4종에는 자본을 배정하지 않고 재료 목록의 잘못된 기록을 바로잡았습니다")),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
      items = c(
        "시도: 애널리스트 실적 추정치에서 나온 신규 팩터 4종이 이미 쓰는 3종보다 추가로 수익을 설명하는지 확인했습니다",
        "방법: 25년(283개월) 데이터로 기존 3종을 통제한 뒤 신규 팩터만의 기여를 회귀분석으로 쟀습니다",
        "결과: 2종은 기존 팩터와 값이 완전히 같았고, 1종은 값이 전부 0이라 만들어지지 않았고, 1종은 단기 주가 반전을 다시 포장한 것이었습니다",
        "의미: 실제 돈은 넣지 않습니다. 대신 신규 재료 4개 확보라고 적혀 있던 기록을 0개로 정정했습니다")),

    list(type = "bullet", emoji = "🔍", heading = "왜 이런 일이 생겼나",
      items = c(
        "추정치 원본은 매 영업일 기록되지만 값 자체는 분기에 한 번만 바뀝니다 (인접 영업일에 값이 바뀌는 비율 1.5%)",
        "빌더 코드가 최근 4개 관측의 평균을 계산하는데 이 4개가 4분기가 아니라 4영업일이었습니다",
        "4영업일 값이 전부 같으므로 평균이 원래 값과 같아집니다 (전부 같은 종목 비율 1.000000)",
        "차이를 계산하는 팩터는 같은 값끼리 빼서 항상 0 이라 분산이 0 이 되어 데이터베이스에 실리지 못했습니다")),

    list(type = "kv", emoji = "📊", heading = "팩터별 실측 판정",
      kv = list(
        "C10 SUE 지속성" = "C01_SUE와 완전 동일 · 표본 8개월 전건 최대오차 0.000e+00 · 순위상관 +1.000000",
        "C13 개정 폭 3개월" = "C04_ESBR와 완전 동일 · 최대오차 0.000e+00 · 순위상관 +1.000000",
        "C15 예측오차 추세" = "미산출 · 값이 정확히 0인 비율 1.000000 · 표준편차 0.000e+00",
        "C18 실적발표 3일 초과수익" = "증분 t값 -2.551 이나 자격 불인정 · 아래 참조")),

    list(type = "bullet", emoji = "⚠️", heading = "C18 은 t값을 넘고도 왜 자격이 없나",
      items = c(
        "부호가 반대입니다. 사전에 양(+)으로 등록했는데 실측은 음(-)이라 가설 자체가 반증됐습니다",
        "이름과 실체가 다릅니다. 발표일을 잡는 코드가 한 달에 서로 다른 날짜를 5~6개만 만들어냅니다 (같은 달 종목 287~382개 대상)",
        "즉 종목별 발표일이 아니라 전 종목 공통 월말 창이고 실체는 월말 6일간 시장 대비 등락이었습니다 (순위상관 +0.674)",
        "결정적 확인: 그 6일 등락을 통제하자 t값이 2.551에서 1.486으로 무너졌습니다 (문턱 2.0 아래)",
        "사전에 단기반전과 구별되지 않으면 t값과 무관하게 자격 불인정으로 등록해 두었기에 그대로 적용했습니다")),

    list(type = "bullet", emoji = "🧪", heading = "고쳐서 다시 만들어 본 3종",
      items = c(
        "값이 바뀌는 시점만 남겨 분기 단위로 제대로 만든 판본 3종을 추가로 쟀습니다",
        "기존 팩터와 구별은 됐습니다 (순위상관 0.545~0.623, 재탕 기준 0.9 미만) 즉 진짜 다른 팩터입니다",
        "그러나 증분 기여는 전부 없었습니다 (t값 -0.456 / +0.737 / -0.909, 무작위 대조 p 0.375~0.665)",
        "단 검정력이 부족해 효과 없음으로 단정하지 않습니다. 이 표본에서 감지 가능한 최소 효과는 연 2.3~5.1%였습니다",
        "부수 소득: C13 스텝판은 단독으로는 신호가 있습니다 (정보계수 t값 +3.41). 순위 매기기가 아닌 종목 걸러내기 용도로 재검토합니다")),

    list(type = "bullet", emoji = "🎯", heading = "다음 단계",
      items = c(
        "C18을 제대로 만들기. 진짜 발표일인 전자공시 접수일로 바꾸면 처음으로 진짜 이벤트 팩터가 됩니다",
        "지금 결과는 잘못 만든 대용품에 대한 판정이지 아이디어 자체에 대한 판정이 아닙니다",
        "C13 스텝판의 단독 신호력을 종목 필터 용도로 순회합니다. 순위로는 죽었는데 필터로는 살아난 전례가 있습니다",
        "아직 안 재본 C계열 9종의 정체 검사. 이번에 세운 이름이 아니라 값으로 재라를 그대로 적용합니다",
        "인프라 이관 4건: 기록 정정 · 중복 배출 처분 · 발표일 대용품 재설계 · 배출 감시에 정체 검사 축 추가")),

    list(type = "kv", emoji = "🔒", heading = "검증과 범위",
      kv = list(
        "미래참조 검증" = "통과 · 원본 재계산값과 데이터베이스값의 월별 순위상관 최소 0.999986 · 11개월 전건 부호 일치",
        "표본 편중" = "C18 표본은 대형주 편중 · 수익 편의는 없음 (t값 0.22)",
        "전이 진단" = "시가총액 가중 t값 -1.040 · 동일가중 -2.335 · 부호 뒤집어도 자본 기준 2.95에 크게 미달",
        "주장 범위" = "재료 자격까지만 · 자본 배정 주장 없음",
        "데이터 버전" = "build_hash 20260809203741_8c9befe0 · 283개월 2003-01~2026-07")),

    list(type = "kv", emoji = "📁", heading = "산출물",
      kv = list(
        "판정 원본" = "stage_artifacts/WT_D20260809_005/alpha_validation.json",
        "패키지" = "qepm/mailbox/worktask/WT-D20260809_005/alpha_package.json",
        "적대검증" = "qepm/mailbox/worktask/WT-D20260809_005/challenge_note.md · 9건",
        "프론티어 큐" = "FQ-198 · 지시받은 FQ-174는 병렬 세션이 선점 중이라 규약대로 재배정"))
  ),
  charts = charts
)
cat(sprintf("[tg] 발송 결과 클래스: %s\n", paste(class(res), collapse="/")))
print(utils::head(res, 3))
