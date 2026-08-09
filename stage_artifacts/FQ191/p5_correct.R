## FQ-191 P5 — ★판정문·원장 정정 (내 oos 진단 오류 + 사다리 결과 반영)
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ191")
say  <- function(fmt, ...) { cat(sprintf(paste0("[cx] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/frontier_queue_io.R")

V <- fromJSON(file.path(OUT, "validation.json"), simplifyVector = FALSE)
V$correction_20260809 <- list(
  what_i_wrote = "close_round 및 validation.json 의 oos 진단: '원인은 신호 열화가 아니라 표본 구조다 — 국면 ON 이 27개월뿐이라 OOS 분할이 표본을 무너뜨린다'",
  why_it_was_wrong = paste0(
    "★실측 반증: anchored 분할의 IS/OOS 국면 ON 비율이 **거의 같다**(55%: 35.0/36.4 · 65%: 36.2/34.6 · 75%: 37.0/31.6). ",
    "사건 희소성 차이가 없으므로 '표본 구조' 설명은 성립하지 않는다."),
  what_i_almost_wrote_instead = "'신호 감쇠 확정' — 전반 연 +40.53% vs 후반 +12.78% 를 보고 정정하려 했다",
  why_that_was_also_wrong = paste0(
    "★차이 연 +27.74% 의 Welch **t +1.355 · p 0.1921** 로 유의하지 않다. ",
    "게다가 검정력: ON 26개월 split 설계는 연 **36.79%** 가 있어야 검출하는데 관측은 그 아래다. ",
    "연도별로도 −0.89%(2023) ~ +39.98%(2022) 로 흩어지고 추세 spearman −0.543(n=6)."),
  correct_label = "★★**검정력 부족** — 감쇠인지 잡음인지 이 표본으로는 가릴 수 없다. 원 진단도 정정안도 둘 다 과장이었다.",
  consequence_for_revival = paste0(
    "부활 조건이 바뀐다. 원래 '국면 ON 월이 쌓이면 oos 회복' 이라 썼는데 그 근거(표본 구조 설명)가 사라졌다. ",
    "정확히는 **표본이 쌓여야 감쇠 여부 자체를 알 수 있다** — 회복을 예상하는 게 아니라 판별이 가능해진다."),
  process_note = "★정정문을 쓰기 전에 한 번 더 걸렀다. 틀린 진단을 다른 틀린 진단으로 바꿀 뻔했다.")

V$port_t_ladder_20260809 <- list(
  method = "FQ-178 사다리(net → gross → EW-유니버스 basis)를 국면-조건부 규칙에 적용",
  net_capw = 2.204, gross_capw = 2.379, gross_ew = 2.966,
  delta_cost = 0.175, delta_bench = 0.587,
  gap_to_hard = 0.746, explained_by_nonsignal = 0.762, explained_pct = 102,
  reading = paste0("★갭 0.746 중 0.762 를 **비용+벤치 두 비-신호 채널**이 설명한다(102%). ",
    "두 채널을 제거하면 **2.966 > 2.95** 로 문턱을 넘는다 — 이 아크에서 처음이다. ",
    "M26 과 같은 구조이나 M26 은 제거해도 2.818 로 미달이었다(계약은 간발로 넘음)."),
  why_this_is_not_a_capital_claim = paste0(
    "두 채널 모두 **고정 축**이다 — 15bps 는 Production Constraints 이고 cap-w 벤치는 판정 권위다. ",
    "'제거하면 넘는다' 는 **왜 미달인지의 설명**이지 자격 주장이 아니다. H3 판정 불변."))
writeLines(toJSON(V, auto_unbox = TRUE, pretty = 2, digits = NA), file.path(OUT, "validation.json"))
say("validation.json 정정 기입")

Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
i <- which(ids == "FQ-191")
Q$entries[[i]]$next_action <- paste0(Q$entries[[i]]$next_action,
  " ★★정정(2026-08-09 P3~P5): ①**내 oos 진단이 틀렸다** — '표본 구조' 설명은 실측 반증(IS/OOS 국면 ON 비율 35.0/36.4·36.2/34.6·37.0/31.6 로 거의 동일). ",
  "②그렇다고 '신호 감쇠 확정' 도 아니다 — 전반 연 +40.53% vs 후반 +12.78% 차이가 Welch **t +1.355 p 0.1921** 로 비유의이고, ",
  "검정력상 이 표본은 연 36.79% 가 있어야 검출한다(관측 27.74%). **정확한 라벨 = 검정력 부족**. ",
  "③부활 조건 수정: '표본 쌓이면 회복' 이 아니라 '표본이 쌓여야 **감쇠 여부를 판별**할 수 있다'. ",
  "★★PORT_t 사다리 신규: net **2.204** → 비용제거 2.379(+0.175) → EW-basis **2.966**(+0.587). ",
  "갭 0.746 중 **0.762 를 비-신호 채널이 설명(102%)** 하고 두 채널 제거 시 **2.966 > 2.95** — 이 아크 첫 문턱 통과 수치. ",
  "⚠단 15bps 와 cap-w 벤치는 **고정 축**이므로 자본 주장 불가. H3 판정 불변.")
Q$updated <- "2026-08-09"
write_frontier_queue(Q)
say("원장 정정 기입 완료")

## 병목 지도에도 반영 (연속성 5호)
p <- "06_Registry/layer_bottleneck_map.md"
raw <- readBin(p, "raw", file.size(p)); txt <- rawToChar(raw); Encoding(txt) <- "UTF-8"
anchor <- "**\uac31\uc2e0**: 2026-08-09 v54 ("
if (length(gregexpr(anchor, txt, fixed=TRUE)[[1]]) == 1L) {
  ins <- paste0(
    "**갱신**: 2026-08-09 v55 (★**비-return 재료가 자본 관문에 처음 도달**[FQ-138→FQ-191, 계약수주]. ",
    "①재료 행: 사전등록 재판정 4축 통과 — 국면-조건부 DiD 연 **+26.09%**(NW3 t **+3.705**), ",
    "순풍 대조 **NEU_ON −1.05%** 로 교락 기각(cor(mega_spread, 벤치핸디캡 d)=+0.896 이었음). ",
    "②⑨자본 행: HARD 3종(2026 제외 n=73) **PORT_t +2.204 FAIL · oos_retention +0.414 FAIL(<0.5 무조건 band) · calmar +1.213 PASS** ⇒ ",
    "사전등록 H3 대로 **오버레이/선별 라벨 확정 라우팅**. 무조건부 +0.581 → 조건부 +2.204(**3.8배**)로 재료를 살려냈으나 문턱 미달. ",
    "③★★PORT_t 사다리: net 2.204 → 비용제거 2.379 → EW-basis **2.966** ⇒ 갭 0.746 중 **0.762 를 비용+벤치가 설명(102%)**. ",
    "M26(제거 후 2.818 미달)과 달리 **두 채널 제거 시 문턱을 넘는 첫 사례**. ⚠두 채널 다 고정 축이므로 자본 주장 아님. ",
    "④전환비용은 병목 아님(연 4.6회·연 0.68%p). calmar 통과는 OFF 월 벤치 보유 덕이며 신호 방어력 아님. ",
    "⑤★Q-Lead 자기정정 2단: oos 미달을 '표본 구조' 로 진단했다가 실측 반증(IS/OOS ON 비율 거의 동일), ",
    "'신호 감쇠 확정' 으로 정정하려다 그것도 **비유의**(Welch t +1.355 p 0.192, 필요 연 36.79% > 관측 27.74%) — ",
    "**정확한 라벨 = 검정력 부족**. 정정문 쓰기 전에 한 번 더 걸러 틀린 진단을 다른 틀린 진단으로 바꾸는 것을 막았다. ",
    "상세 = `stage_artifacts/FQ191/validation.json` · `stage_artifacts/FQ138/validation.json`) | ")
  txt2 <- sub(anchor, paste0(ins, anchor), txt, fixed = TRUE)
  out <- charToRaw(enc2utf8(txt2)); writeBin(out, p)
  raw2 <- readBin(p, "raw", file.size(p))
  say("병목 지도 v55: %d → %d바이트 · CR %d(원 %d) · v55 존재 %s",
      length(raw), length(out), sum(raw2==as.raw(13)), sum(raw==as.raw(13)),
      grepl("2026-08-09 v55", rawToChar(raw2), fixed=TRUE))
} else say("★지도 앵커 불일치 — 건너뜀")
say("=== P5 완료 ===")
