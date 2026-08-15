## WT-D20260813_005 후속 · D6 — validation 에 기전 시간구조 진단(D5) 편입
##
## ★판정(primary NOT_SUPPORTED, t +1.5706)은 건드리지 않는다. D5 는 진단이며,
##   추가되는 것은 "왜 sp3 에서 이득이 사라졌나" 의 실측 답이다(next_probe P1 의 1차 증거).
##   패치 사실을 patch_log 에 남긴다 (No Silent Override).
##
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260813_005/depth_aligned/d6_patch_validation.R")'

suppressPackageStartupMessages({library(data.table); library(jsonlite)})
source("02_Infrastructure/config.R")
DOUT <- "stage_artifacts/WT-D20260813_005/depth_aligned"
V  <- fromJSON(file.path(DOUT, "alpha_validation_depth.json"), simplifyVector = FALSE)
D5 <- readRDS(file.path(DOUT, "d5_mechanism_timeline.rds"))
lv <- as.data.table(D5$level_by_block)
g <- function(a, b) lv[arm == a & blk == b, mean_active]
gt <- function(a, b) lv[arm == a & blk == b, nw3_t]

V$mechanism_timeline <- list(
  purpose = "CF3(이득의 sp1 집중·sp3 소멸)의 기전을 가른다 — (a)연료 감쇠 vs (b)프레임 공통 감쇠. 진단 전용, 판정 축 아님.",
  fuel_trend = list(
    skewtop_per_yr = D5$fuel_trend$skewtop_per_yr,
    gap_depth_per_yr = D5$fuel_trend$gap_depth_per_yr,
    split_share_per_yr = D5$fuel_trend$split_share_per_yr,
    by_block = D5$fuel_by_block,
    reading = "연료는 마르지 않았다 — 상위25 왜도(skewtop) sp1 0.595 → sp3 0.797 로 **증가**(추세 +0.0156/yr), 평균−중앙값 갈림(gap_depth)은 −0.00048 → −0.00300 으로 **확대**, rank 와의 부호 갈림 비중 0.285 → 0.291 유지. 기전이 먹는 구조는 최근이 오히려 두껍다."),
  level_decomposition = list(
    mean_active_by_block = list(
      sp1 = list(OBJ_RANK = g("OBJ_RANK","sp1"), OBJ_MEAN_Q5 = g("OBJ_MEAN_Q5","sp1"),
                 OBJ_MEAN_DEPTH = g("OBJ_MEAN_DEPTH","sp1"), OBJ_MED_DEPTH = g("OBJ_MED_DEPTH","sp1")),
      sp2 = list(OBJ_RANK = g("OBJ_RANK","sp2"), OBJ_MEAN_Q5 = g("OBJ_MEAN_Q5","sp2"),
                 OBJ_MEAN_DEPTH = g("OBJ_MEAN_DEPTH","sp2"), OBJ_MED_DEPTH = g("OBJ_MED_DEPTH","sp2")),
      sp3 = list(OBJ_RANK = g("OBJ_RANK","sp3"), OBJ_MEAN_Q5 = g("OBJ_MEAN_Q5","sp3"),
                 OBJ_MEAN_DEPTH = g("OBJ_MEAN_DEPTH","sp3"), OBJ_MED_DEPTH = g("OBJ_MED_DEPTH","sp3"))),
    nw3_t_by_block = list(
      sp1 = list(OBJ_RANK = gt("OBJ_RANK","sp1"), OBJ_MEAN_DEPTH = gt("OBJ_MEAN_DEPTH","sp1")),
      sp3 = list(OBJ_RANK = gt("OBJ_RANK","sp3"), OBJ_MEAN_DEPTH = gt("OBJ_MEAN_DEPTH","sp3"))),
    both_arms_declined = D5$both_arms_declined,
    reading = "★ sp3 에서 **4개 arm 전부** 활성이 음수다 (월 −0.006 ~ −0.013, NW3 t −0.9 ~ −1.5). sp1 에서는 4개 전부 양수(t 1.8 ~ 3.5). 즉 2020년 이후 이 재료(월간·return-파생 320종)에서는 **어떤 선별 규칙도 활성을 못 낸다** — 선별 축의 이득이 사라진 게 아니라 **선별할 알파가 사라졌다**."),
  verdict = "(b) 프레임 공통 감쇠. 기전의 연료(왜도·갈림)는 증가했는데 재료 전체의 활성이 죽었다 ⇒ 선별층 질문은 sp3 구간에서 원리적으로 답할 수 없다(선택 대상이 비어 있다).",
  consequence = "본 라운드의 pooled t +1.5706 은 '활성이 존재하던 구간(sp1)의 신호'와 '활성이 없는 구간(sp3)의 잡음'을 한 통계량에 섞은 값이다. 이는 문턱 사후 조정 사유가 아니라(판정 불변), 다음 라운드를 **선별 축이 아니라 재료 축**으로 보내는 근거다.",
  label = "diagnostic — 판정 축 아님. 성과 선택·사후 문턱 조정에 사용 금지.")

V$routing$next_probe[[1]] <- paste0(
  "P1 (완료 — 본 라운드에서 실측): 이득의 sp1 집중·sp3 소멸은 **연료 감쇠가 아니라 프레임 공통 감쇠**다. ",
  "연료(상위25 왜도 0.595→0.797, 평균−중앙값 갈림 −0.00048→−0.00300)는 오히려 두꺼워졌는데, ",
  "sp3(2020-01~)에서 4개 arm 전부 활성 음수(월 −0.006~−0.013, t −0.9~−1.5)다. ",
  "⇒ 선별할 알파 자체가 재료에서 사라졌다. 후속 축은 선별층이 아니라 재료층(P3). 상세 = mechanism_timeline 블록.")
V$routing$next_probe[[5]] <- paste0(
  "P5 (신규, 재료 사망 자체의 검정): '월간 return-파생 320종의 활성이 2020 이후 구조적으로 소멸' 은 본 라운드가 부수로 얻은 ",
  "가장 큰 관측이며 선별 축과 독립이다. 이 명제를 **자체 사전등록 라운드**로 검정하고(base = 동일 프레임 rank 선별, ",
  "primary = sp3 구간 active NW3 t 의 사전등록 방향 검정, 통제 = EW-유니버스 벤치·cap-tier 분해), ",
  "참이면 factor DB 월간 축 소비 전반(FR/RAMP 포함)에 대한 경보다. 본 라운드 데이터로 판정 금지(사후선택).")
V$routing$destination <- paste0(
  "재료 축(FQ-234 일별 · 비-return 원천) — 강화된 근거: 선별 규칙 4종 전부가 sp3 에서 음수 활성. ",
  "선별 축은 '기각'이 아니라 '재료가 살아 있는 구간에서만 물을 수 있는 질문'으로 조건부 보류.")

V$patch_log <- list(list(at = format(Sys.time()), by = "d6_patch_validation.R",
  what = "mechanism_timeline 블록 추가 + routing.next_probe P1 실측 답으로 교체 + P5 신규 + destination 근거 강화",
  unchanged = "primary_endpoint / verdict / 문턱 / falsification / detection_power / three_way_comparison 전부 불변"))

write_json(V, file.path(DOUT, "alpha_validation_depth.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat(sprintf("패치 완료: %s/alpha_validation_depth.json (primary 불변: t %+.4f / %s)\n", DOUT,
            V$primary_endpoint$nw3_t, V$primary_endpoint$verdict))
