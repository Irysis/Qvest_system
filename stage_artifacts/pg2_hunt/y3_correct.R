## y3 — FQ-206 순환 서술 정정 + 아크 실제 판정 확정
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[y3] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/frontier_queue_io.R")

CORE <- paste0(
  "★★정정(2026-08-09 y1/y2 실측): 위 서술의 **'순환 의심'은 철회**한다. ",
  "`FQ138/p1_measure.R:53` 이 정의를 명시한다 — `mega_spread = mean(ret_1m[top10]) - median(ret_1m)` ",
  "= **상위10 시총 평균수익 − 전체 중앙값**, 순수 시장 수익률이지 계약 데이터가 아니다. ",
  "**정의를 확인하기 전에 의심을 원장에 기록한 것이 성급했다**(같은 날 08-08 카드를 '기전이 반대'로 ",
  "정정했다가 철회한 것과 같은 계통 — 정정문을 쓰는 순간이 새 오독 지점). ",
  "★대안 설명 2개도 함께 기각됐다: ",
  "①**표본 불안정 아님** — ON월 rho +0.186 블록부트 CI **[-0.024, +0.210]** 이 무작위 중앙 0.399 를 ",
  "포함하지 않고 leave-one-out 최대 이동 0.119. x2(0.369) vs x9(0.564) 불일치의 원인은 표본이 아니라 ",
  "**2026-03~06 오염 4개월**이었다(2026-06 슬리브 active −0.437 = 오늘 검거한 벤치 결함 구간, 칩 task_5452df6a). ",
  "②**교락 아님** — rho 분해에서 ON vs 전체 cov 비율 **0.387** < 분모 비율 0.767 ⇒ 분자가 더 줄었다 ",
  "= 실제로 덜 함께 움직인다. 그리고 PG2 순풍(ON active 0.0130 vs OFF 0.0278)을 ON 더미 회귀로 제거해도 ",
  "잔차 rho **+0.186** 로 **소수 3자리 불변**. ",
  "⇒ 계약 슬리브의 ON월 직교성은 **순환도 교락도 표본 잡음도 아닌 실측된 성질**이다. ",
  "★x9 의 독립 라벨 미재현(unified 0.338 · jump 0.657, 백분위 70%/72%)은 '계약 결과가 가짜' 가 아니라 ",
  "**'다른 라벨이 이 일을 못 한다'** 는 뜻이다 — mega_spread 는 메가캡-소형 상대성과 축이고 ",
  "PG2·계약 둘 다 소형편향이므로 그 축에서 구조가 갈리는 것이 기전적으로 자연스럽다.")

Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
hit <- 0L
for (k in seq_along(Q$entries)) {
  b <- paste(unlist(Q$entries[[k]]), collapse = "")
  if (grepl("\uc21c\ud658", b) && grepl("mega_spread", b)) {     # "순환" ∧ mega_spread
    Q$entries[[k]]$next_action <- paste0(as.character(Q$entries[[k]]$next_action)[1], " ", CORE)
    hit <- hit + 1L; say("정정 기입 %s", ids[k])
  }
}
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
say("원장 %d개 항목 정정 · 총 %d", hit, length(read_frontier_queue()$entries))

## 병목 지도 v58
mp <- "06_Registry/layer_bottleneck_map.md"
raw <- readBin(mp, "raw", file.size(mp)); txt <- rawToChar(raw); Encoding(txt) <- "UTF-8"
anchor <- "**\uac31\uc2e0**: 2026-08-09 v57 ("
if (length(gregexpr(anchor, txt, fixed=TRUE)[[1]]) == 1L) {
  ins <- paste0(
    "**갱신**: 2026-08-09 v58 (★**PG2 사냥 아크 종결 판정 — 재료 행 확정**[pg2_hunt x1~y2]. ",
    "①**331 전수 + 합성 8셀 + insider 12셀 + 유니버스필터 12셀 + 이식 24셀 + 반전 8셀 = 자본 문턱 통과 0**. ",
    "가중 무제약 천장으로도 331/331 미달(최대 +0.0199 = 문턱의 39.8%). ",
    "②사망 기전 = **상관 과다 단독 0건**, 전부 IR 이 먼저 무너진다(IR≥0.5 가 331 중 **1건**). ",
    "③**국면 라벨의 정체 재규정**: '언제 살까' 아니라 **'언제 신호가 북과 직교한가'** 선택기. ",
    "계약 전체 rho +0.369(무작위 0.378, 백분위 38% = 구분 안 됨) ∧ **ON월 rho +0.186(백분위 0%)** · 파킹 IR +0.758(**100%**). ",
    "④★**이식 실패 0/24** ⇒ 계약+mega_spread 는 특이 쌍. 부수로 라벨 방향성 2건 관측(unified 인하 8/8 · jump 상승 8/8, 각 p 0.0039)했으나 ",
    "jump 반전 규칙은 직접 측정에서 **기각**(무작위 대비 0/8 · IR 대가 −0.230). ",
    "⑤★★**계약 직교성의 3중 반증 시도가 모두 실패 = 성질 확정**: 순환 아님(mega_spread 는 시장 수익률 정의) · ",
    "표본 불안정 아님(ON rho CI [−0.024, +0.210], 무작위 중앙 0.399 미포함) · 교락 아님(순풍 제거 후 rho 소수3자리 불변). ",
    "★x2/x9 불일치(0.369 vs 0.564)는 표본이 아니라 **2026 오염 4개월**. ",
    "⑥유니버스 행 신규: '계약 공시를 낸 회사' 선별에 **IR +0.349**(12/12 · paired t 8.867 · p<1e-4, 동일크기 무작위 대조 −0.363 대비) — ",
    "**북 종목 필터**로 소비 가능하나 rho 는 안 내려 단독 통과 불가. ",
    "⑦측정 행: 문턱 0.05 가 269개월에서도 **1.09se** ⇒ 탈락은 유효·통과는 무효. `verdict_ci` 신설로 CI 병기. ",
    "⑧★Q-Lead 오류 = **정의 확인 전 순환 의심을 원장에 기록**(철회). 상세 = `stage_artifacts/pg2_hunt/`) | ")
  txt2 <- sub(anchor, paste0(ins, anchor), txt, fixed = TRUE)
  ob <- charToRaw(enc2utf8(txt2)); writeBin(ob, mp)
  r2 <- readBin(mp, "raw", file.size(mp))
  say("지도 v58: %d → %d바이트 · CR %d(원 %d) · v58 %s · v57 보존 %s",
      length(raw), length(ob), sum(r2==as.raw(13)), sum(raw==as.raw(13)),
      grepl("v58", rawToChar(r2), fixed=TRUE), grepl("v57 (", rawToChar(r2), fixed=TRUE))
} else say("★지도 앵커 불일치")
say("=== y3 완료 ===")
