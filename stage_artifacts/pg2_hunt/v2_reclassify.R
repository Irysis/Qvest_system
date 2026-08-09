## v2 — ★아크 재분류: 'ON월 직교' 현상을 표본 산물로 확정 + 원장/지도/메모리 정합
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[v2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/ops/frontier_queue_io.R")
source("02_Infrastructure/contracts/close_round.R")

RECL <- paste0(
  "★★★재분류(2026-08-09 v1 결정적 검정): 이 항목이 근거로 삼은 **'ON월 직교' 현상은 존재하지 않는다**. ",
  "무작위 26개월 부분집합 **1000회** 귀무분포에서 관측 Δrho 의 백분위 = 계약 **14.8%** · V18_AM 16.5% · ",
  "R17/V19 14.7% · L11 25.1% — **5재료 전건 분포 안**(귀무 [−0.296, +0.215]). ",
  "73개월에서 아무 26개월이나 뽑아도 rho 가 ±0.2~0.3 흔들리며, 관측 −0.183 은 그 통상 변동이다. ",
  "★근본 원인 = **두 대조가 갈렸을 때 낮은 쪽을 기전으로 채택**했다 — 무작위 **신호** 대비 0% vs ",
  "무작위 **타이밍** 대비 15%. 갈림 자체가 '창이 아니라 신호가 특별하다' 는 답이었는데 창 쪽으로 읽었다. ",
  "그 위에서 설명 후보 7종을 기각하며 미해명 등재까지 했다 — **설명할 현상이 없었다**. ",
  "규약 적립: [[feedback-two-controls-disagree-that-is-the-signal]] — 대조가 갈리면 **더 보수적인 쪽으로 판정**하고, ",
  "창을 자르는 모든 주장은 **부분표본 귀무분포**를 선행할 것(1000회에 수 초). ",
  "★유효 잔존: 계약 파킹 IR 0.758·ΔIR +0.074(CI 1/5) 성과 측정 · 유니버스 효과 IR **+0.349**(12/12, p<1e-4) · ",
  "요구조건 지도 · 331 전수 통과 0 · 측정 해상도(문턱 1.09se) — 전부 이 재분류와 무관하다.")

Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
n0 <- length(Q$entries); hit <- 0L
TARGET <- c("FQ-204","FQ-206","FQ-207","FQ-208","FQ-211")
for (k in seq_along(Q$entries)) {
  if (ids[k] %in% TARGET) {
    Q$entries[[k]]$next_action <- paste0(as.character(Q$entries[[k]]$next_action)[1], " ", RECL)
    if (ids[k] == "FQ-211") Q$entries[[k]]$status <- "resolved_sample_artifact"
    hit <- hit + 1L; say("재분류 기입 %s%s", ids[k], if (ids[k]=="FQ-211") " (status → resolved)" else "")
  }
}
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
say("원장 %d항목 · 재분류 %d건", length(read_frontier_queue()$entries), hit)

## 병목 지도 v59
mp <- "06_Registry/layer_bottleneck_map.md"
raw <- readBin(mp, "raw", file.size(mp)); txt <- rawToChar(raw); Encoding(txt) <- "UTF-8"
anchor <- "**\uac31\uc2e0**: 2026-08-09 v58 ("
if (length(gregexpr(anchor, txt, fixed=TRUE)[[1]]) == 1L) {
  ins <- paste0(
    "**갱신**: 2026-08-09 v59 (★★★**v57/v58 ③항 재분류 — 'ON월 직교' 현상은 표본 산물**[pg2_hunt v1]. ",
    "무작위 26개월 부분집합 **1000회** 귀무분포: 관측 Δrho 백분위 계약 **14.8%** · V18_AM 16.5% · ",
    "R17/V19 14.7% · L11 25.1% ⇒ **5재료 전건 분포 안**(귀무 [−0.296, +0.215]). ",
    "73개월에서 임의 26개월을 뽑으면 rho 가 ±0.2~0.3 흔들리고 관측 −0.183 은 통상 변동이다. ",
    "⇒ **국면 라벨이 직교 구간을 고른다는 기전은 존재하지 않는다.** ",
    "★근본 원인 = **두 대조가 갈렸을 때 낮은 쪽 채택**(무작위 신호 0% vs 무작위 타이밍 15%). ",
    "갈림 자체가 '창이 아니라 신호가 특별' 이라는 답이었는데 창으로 읽었고, 그 위에서 설명 7종을 기각했다. ",
    "규약 = 대조 갈리면 **보수적인 쪽으로 판정** + 창 자르는 주장은 **부분표본 귀무분포 선행**. ",
    "★★유효 잔존(재분류 무관): 요구조건 지도(rho 0.4에서 필요 IR 0.925) · 331 전수 통과 0 · ",
    "합성 항등(k≤12 완전직교여도 불가) · 측정 해상도(문턱 0.05 = 1.09se, 탈락만 유효) · ",
    "유니버스 효과 IR **+0.349**(12/12 · t 8.867 · p<1e-4) · 계약 4종(book_marginal·verdict_ci·governor 경고·proxy_axis) · 검사 76/76. ",
    "★자본 행 최종: **통과 0건**, 계약 후보는 성과 측정만 유효(IR 0.758·ΔIR +0.074·CI 1/5)이고 ",
    "직교성 근거는 철회. 상세 = `stage_artifacts/pg2_hunt/v1_null_subset.csv`) | ")
  txt2 <- sub(anchor, paste0(ins, anchor), txt, fixed = TRUE)
  ob <- charToRaw(enc2utf8(txt2)); writeBin(ob, mp)
  r2 <- readBin(mp, "raw", file.size(mp))
  say("지도 v59: %d → %d바이트 · CR %d(원 %d) · v59 %s · v58 보존 %s",
      length(raw), length(ob), sum(r2==as.raw(13)), sum(raw==as.raw(13)),
      grepl("v59", rawToChar(r2), fixed=TRUE), grepl("v58 (", rawToChar(r2), fixed=TRUE))
} else say("★지도 앵커 불일치")

r <- close_round(
  round_id = "PG2_RECLASSIFY_20260809",
  verdict_type = "config_scoped_negative",
  layer = "measurement",
  mechanism_diagnosis = paste0(
    "아크의 핵심 관측을 **자기 부정**으로 닫았다. 'ON월 직교' 현상을 무작위 26개월 부분집합 1000회로 ",
    "검정하니 5재료 전건이 귀무분포 안이었다(계약 백분위 14.8%). 73개월에서 26개월을 뽑는 것만으로 ",
    "rho 가 ±0.2~0.3 흔들리므로 관측 −0.183 은 통상 변동이다. ",
    "★근본 원인은 데이터가 아니라 **판독**이다 — 두 대조(무작위 신호 0% vs 무작위 타이밍 15%)가 ",
    "갈렸을 때 낮은 쪽을 기전으로 채택했고, 갈림 자체가 답('창이 아니라 신호')이었다. ",
    "그 위에서 설명 후보 7종을 기각하며 6라운드를 돌았다. ",
    "★이 오류가 되돌려진 이유 = 각 라운드가 **정직하게 음성을 보고**했고 마지막에 가장 싼 결정적 검정을 ",
    "돌렸기 때문이다(1000회에 수 초). 규약으로 적립: 창을 자르는 모든 주장은 부분표본 귀무분포가 선행."),
  next_probes = c(
    "★대조군 갈림 게이트 — `proxy_axis.R` 이 대리 축 판본을 막듯, **대조군 판본**도 계약으로 막는다. assert_controls_agree(control_a, control_b) 로 두 대조 백분위가 크게 갈리면 경고 발행",
    "창-자르기 주장의 선행 게이트 — 국면·부분표본 상관 주장 시 같은 개수 무작위 부분집합 귀무분포를 강제 산출(assert_subsample_null). 1000회에 수 초라 비용 없음",
    "x9 비대칭의 올바른 소비 — '그 창에서 이 신호가 특별' 이라는 읽기는 아직 살아 있다. 무작위 신호 대비 0% 를 창과 분리해 재검정(창을 무작위로 바꿔도 신호 우위가 유지되는가)",
    "계약 후보의 유효 잔존분 재정리 — 성과(IR 0.758·ΔIR +0.074)와 유니버스 효과(+0.349)는 유효하다. 직교성 근거를 뺀 상태에서 오버레이 후보 자격을 재판정"),
  consumer_surfaces = c("국면·부분표본 상관 주장 전반", "대조군 설계", "book-marginal 후보 평가",
    "병목지도 자본 행", "계약 검사 배터리"),
  frontier_update = "FQ-204/206/207/208/211 재분류 · FQ-211 status → resolved_sample_artifact · 병목지도 v59",
  live_trigger = "창을 자르는 새 주장이 나오면 부분표본 귀무분포를 선행 요구 · x9 비대칭 재검정에서 신호 우위가 창과 분리되면 재개",
  evidence_refs = c("stage_artifacts/pg2_hunt/v1_null_subset.csv",
    "stage_artifacts/pg2_hunt/w4_comovement.csv", "stage_artifacts/pg2_hunt/x9_circularity.csv"))
say("close_round: %s", if (is.list(r)) "OK" else as.character(r))
