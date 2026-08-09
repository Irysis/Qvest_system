## 배분 축 일간 프레임 — 착수 전 폐기 판정 기록 + 원장 + close_round + 텔레그램
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/alloc_daily")
say  <- function(fmt, ...) { cat(sprintf(paste0("[cl] ", fmt, "\n"), ...)); flush.console() }
R <- fread(file.path(OUT, "p0_mde.csv"))

V <- list(
  round_id = "ALLOC_DAILY_20260809", parent = "FQ-180 next_probe ② (배분 축 복귀)",
  origin = "도훈 원 가설 — 위기신호 발현 시 총노출 확대. 월간 프레임 판정 불가 후 관측단위를 내려 검정력 확보 시도.",
  as_of = "2026-08-09", metric_type = "canonical_screen_diag", capital_claim = FALSE,
  verdict = "ABORTED_BEFORE_MEASUREMENT — 착수 전 폐기",

  headline = list(
    title = "★관측단위를 내려도 정보가 늘지 않는다 — 정보량은 **독립 위기 에피소드 수**에 묶여 있다",
    evidence = list(
      naive_MDE_annual = list(daily = "18.3~30.9%", monthly = "약 31.6%",
        reading = "★거의 동일하다. 일간 9,003 관측 vs 월간 282 관측인데 연환산 MDE 가 같다 — 표본 빈도가 아니라 **총 기간**이 정보를 정한다."),
      cluster_MDE_annual = list(daily = "223.8~299.4%", monthly = "24.6~87.7%",
        reading = "★일간이 **오히려 10배 나쁘다**. 에피소드당 관측이 많을수록 클러스터 팽창 sqrt(n_on/n_epi) 이 커지기 때문."),
      ratio_cluster = list(daily_max = 0.066, monthly = 0.59,
        reading = "★착수 자격 규칙(월간 0.59 상회) 대비 **9배 미달**")),
    mechanism = paste0(
      "연환산은 효과와 잡음을 같은 배율로 키운다. 지속적 조건부 평균을 추정할 때 표본을 잘게 썰어도 ",
      "**같은 사건을 더 여러 번 보는 것**이지 새 사건을 보는 게 아니다. ",
      "36년간 독립 위기 에피소드는 관측단위와 무관하게 ~4~9개이며, 그것이 정보의 상한이다.")),

  episode_structure = list(
    note = "★rle 에피소드는 문턱 재교차 잡음으로 부풀려진다 — 병합 정의를 함께 셌다(과대 독립성 방지)",
    dd252_10 = list(n_on_days = 4138, rle = 125, merged_20d = 37, merged_60d = 23, merged_120d = 15, merged_250d = 6),
    dd252_20 = list(n_on_days = 2050, rle = 91, merged_20d = 23, merged_60d = 19, merged_120d = 14, merged_250d = 8),
    dd252_30 = list(n_on_days = 846, rle = 48, merged_20d = 13, merged_60d = 9, merged_120d = 8, merged_250d = 8),
    monthly_reference = "dd12 <= -20%: ON 46개월 / 에피소드 4개",
    reading = "★rle 만 보면 '48~125 에피소드' 로 월간 4개 대비 크게 늘어 보이나, 60일 병합 시 **9~23개**로 줄고 250일 병합 시 **6~8개**로 수렴한다. 관측단위를 바꿔도 실질 사건 수는 한 자릿수~십몇 개다."),

  self_check_that_caught_it = paste0(
    "★1차 출력에서 rle 에피소드 125/91/48 을 보고 '일간이 에피소드 구속을 푼다' 로 읽을 뻔했다. ",
    "문턱을 들락날락하는 재교차가 같은 위기를 여러 에피소드로 쪼갠다는 것을 알아채고 병합 정의를 추가하자 ",
    "9~23 개로 줄었다. **에피소드 세는 방법이 판정을 만들 뻔했다.**"),

  input_reality = list(
    bench_daily = "RAWDATA BM_Ret — 9,003 고유일자 · 1990-01-05 ~ 2026-08-07 · 중복일자 0",
    daily_mean = 0.00038, daily_sd = 0.01696, annualized_sd_pct = 26.92,
    autocorr = list(lag1 = 0.012, lag5 = -0.043),
    dd252_coverage = 8752),

  what_is_NOT_concluded = c(
    "★도훈 원 가설이 기각된 것이 아니다 — 측정 자체를 하지 않았다(착수 전 폐기)",
    "관측 효과의 부호는 대체로 양(+)이었다(dd<=-20% 연 +8.5% · dd<=-30% 연 +19.6%) — 방향은 여전히 살아 있다",
    "주간·분기 등 다른 단위나 다른 판정량(변동성·MDD 기준)은 미검"),

  revival_conditions_INV7 = c(
    "★표본 확장이 유일한 정공법 — 독립 에피소드 수를 늘려야 한다. 타 시장(미국·일본 등 장기 시계열) 또는 KR 1990 이전 데이터",
    "판정량 교체 — 평균 수익이 아니라 **분산·MDD 기준**이면 에피소드 내 관측이 실제로 정보를 준다(변동성은 일간에서 잘 추정된다)",
    "국면 정의 교체 — 낙폭이 아닌 축(유동성·수급)은 사건이 더 자주·짧게 발생해 실질 에피소드 수가 클 수 있다",
    "가설 재서술 — '위기 뒤 평균이 높은가' 대신 '위기 뒤 분포 형태가 바뀌는가'(꼬리·왜도)로 바꾸면 일간 표본이 살아난다"),

  cumulative_arc = paste0(
    "도훈 발안에 대한 누적 상태(5라운드): ①배분축 월간 = 판정 불가 ②선별축 이분 = 판정 불가(에피소드 4) ",
    "③선별축 연속 = 판정 불가(효과 크기) ④선별축 42구성 지도 = LANE_CONFIG_CLOSED ⑤배분축 일간 = 착수 전 폐기(에피소드 구속 불변). ",
    "★다섯 번 모두 '효과 없음' 이 아니라 '검출 불가' 이며, **방향은 다섯 번 다 살아 있었다**. ",
    "확립된 것은 가설의 진위가 아니라 **이 데이터로는 이 질문에 답할 수 없다는 사실**이다."),

  artifacts = c("p0_precheck.R", "p0_mde.csv", "p0.rds"))
writeLines(toJSON(V, auto_unbox = TRUE, pretty = 2, digits = NA), file.path(OUT, "validation.json"))
say("validation.json 기록 — %s", V$verdict)

## ── 원장 등재 (ID 계산 + 재읽기 확인) ──────────────────────────────────────
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
nums <- suppressWarnings(as.integer(sub("^FQ-0*([0-9]+).*$", "\\1", ids))); nums <- nums[is.finite(nums)]
k <- max(nums); newid <- NULL
repeat { k <- k + 1L; c0 <- sprintf("FQ-%03d", k); if (!(c0 %in% ids)) { newid <- c0; break } }
Q$entries[[length(Q$entries)+1L]] <- list(
  id = newid, lane = "regime_allocation",
  title = "★분포 형태 축으로 가설 재서술 — '위기 뒤 평균이 높은가' 대신 '꼬리·왜도가 바뀌는가' (도훈 발안 승계)",
  hypothesis = paste0(
    "배분축 일간 프레임이 착수 전 폐기됐다(클러스터 ratio 0.066). 기전: 연환산은 효과와 잡음을 같은 배율로 키우므로 ",
    "**지속적 조건부 평균** 추정에서는 표본을 잘게 썰어도 같은 사건을 더 볼 뿐이다 — 정보 상한은 독립 에피소드 수(36년간 6~23개). ",
    "★그러나 **분산·꼬리·왜도는 일간 표본에서 실제로 잘 추정된다**. ",
    "가설을 '위기 뒤 평균 수익이 높은가'(에피소드 묶임) 에서 '위기 뒤 수익 **분포 형태**가 바뀌는가'(일간 표본 유효) 로 재서술하면 ",
    "도훈 원 취지(위기 뒤 기회)를 검정 가능한 형태로 옮길 수 있다."),
  ev_rationale = "5라운드 아크에서 유일하게 남은 **표본이 실제로 늘어나는** 축. 데이터 기지불(RAWDATA 9,003일).",
  wall_check = "진단 축 — 자본 주장 없음. 분포 형태가 바뀌어도 그것이 곧 '비중 확대' 를 지지하지는 않는다(별도 논증 필요). Production Constraints 불변.",
  data_gate = "없음",
  owner = "UNCLAIMED — ALLOC_DAILY_20260809 이 발행. 착수 세션은 'CLAIMED <session> <ts>' 로 갱신 후 시작.",
  status = "frontier_open",
  next_action = "①위기 ON/OFF 별 일간 수익 분포 적률(sd·왜도·첨도) 대조 ②꼬리 확률(하루 −3% 이하 빈도) ③분포 차이가 있어도 배분 함의는 별도 논증임을 명시",
  source_refs = list("stage_artifacts/alloc_daily/validation.json", "stage_artifacts/FQ180/validation.json"))
Q$updated <- "2026-08-09"
write_frontier_queue(Q)
say("%s 등재 · 재읽기 %s", newid,
    newid %in% vapply(read_frontier_queue()$entries, function(e) as.character(e$id)[1], character(1)))

source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "ALLOC_DAILY_20260809", verdict_type = "config_scoped_negative",
  mechanism_diagnosis = paste0(
    "관측단위를 월간에서 일간으로 내려도 정보가 늘지 않는다. 연환산은 효과와 잡음을 같은 배율로 키우므로 ",
    "지속적 조건부 평균 추정에서 표본을 잘게 써는 것은 같은 사건을 더 여러 번 보는 것이지 새 사건을 보는 게 아니다 ",
    "— 실측: 순진 MDE 가 일간 18.3~30.9%/yr 로 월간 31.6%/yr 와 사실상 동일하고, 에피소드-클러스터 보정 후에는 ",
    "일간이 223.8~299.4%/yr 로 **오히려 10배 나쁘다**(에피소드당 관측이 많아 클러스터 팽창이 커진다). ",
    "정보 상한은 36년간 독립 위기 에피소드 수이며 관측단위와 무관하게 6~23개다."),
  next_probes = c(
    paste0(newid, " 분포 형태 축으로 가설 재서술 — 평균은 에피소드에 묶이지만 분산·꼬리·왜도는 일간 표본에서 실제로 추정된다. 도훈 원 취지를 검정 가능한 형태로 옮기는 유일한 남은 경로."),
    "표본 확장 — 독립 에피소드를 늘리는 정공법. 타 시장 장기 시계열 또는 KR 1990 이전.",
    "판정량 교체 — 평균 수익이 아니라 MDD·변동성 기준이면 에피소드 내 관측이 정보를 준다.",
    "국면 정의 교체 — 낙폭 아닌 축(유동성 고갈·수급 급변)은 사건이 더 자주·짧게 나 실질 에피소드 수가 클 수 있다.",
    "★에피소드 계수 규약 제도화 — rle 는 문턱 재교차로 부풀려진다(125 vs 병합60 23). 국면 라운드의 유효표본 보고에 **병합 정의 병기**를 의무화."),
  consumer_surfaces = c(
    "①팩터 랭킹 — 해당 없음(배분 축 라운드)",
    "②유니버스 필터 — 해당 없음",
    "③오버레이/국면 — 원 가설이 겨눈 면. 평균 축은 이 데이터로 판정 불가 확정, **분포 축이 남는다**",
    "④위험모델 — ★가장 유망한 이식처: 일간 표본이 유효한 것은 분산·꼬리이며 그것이 위험모델의 재료다",
    "⑤monitoring — dd252 일간 계열은 PIT 자명, 국면 서술자로 즉시 사용 가능",
    "⑥선별 라벨 — negative 라벨: '관측단위 하향은 지속적 조건부 평균 문제에 정보를 추가하지 않는다'",
    "⑦타 모드 — 에피소드 계수 규약(rle vs 병합)을 FR·RAMP 국면 라운드에 이식"),
  frontier_update = paste0(newid, " 신규 등재 (기록 후 재읽기 확인)"),
  live_trigger = paste0("재개 조건: ①독립 에피소드를 늘리는 표본 확장 ②판정량을 분산·MDD·꼬리로 교체 ",
    "③국면 정의를 사건 빈도가 높은 축으로 교체. ★폐기는 **이 판정량(평균 수익)·이 표본** 한정이며 ",
    "도훈 가설의 진위 판정이 아니다 — 관측 효과 부호는 대체로 양(+)이었다(dd<=-30% 연 +19.6%)."),
  layer = "③오버레이/국면 + 측정무결성",
  evidence_refs = c("stage_artifacts/alloc_daily/validation.json", "stage_artifacts/alloc_daily/p0_mde.csv",
                    "stage_artifacts/FQ180/validation.json"))
say("=== 종결 ===")
