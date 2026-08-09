## p4 — ★정정 전파: 오늘 4단 전파된 오독을 원장·지도·아티팩트에서 바로잡는다
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/ladder_sweep")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p4] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/frontier_queue_io.R")

MAG <- 1.371; SE_R <- 0.729; MEAN_T <- -0.132
CORE <- paste0(
  "EW-유니버스 basis 는 '벤치 핸디캡 제거' 가 아니다. 두 채널의 합성이며 실측 분해는: ",
  "①mean 채널 = 재료 무관 **상수**(8/8 음수 · sd 0.000019 · 연 -0.48%) 이고 방향은 **불리**(t 기여 -0.132) ",
  "— EW 유니버스 벤치 수익이 cap-w 벤치보다 **높아** mean 기준 더 **어려운** 벤치다. ",
  "②se 채널 = se_EW/se_capw **0.729** → t 를 **부호 무관 x1.371 배율**. ",
  "EW 벤치가 포트(EW top-N)와 구성이 닮아 active 변동이 27% 작아지기 때문이다. ",
  "★증거: 음수 알파 5재료가 EW 에서 **더 음수**가 된다(배율기는 부호를 안 가림). ",
  "★따라서 EW t 는 자본 자격에 대한 정보를 담지 않는다 — v8.3 dual-basis 의무의 용도는 '기각 전 재분류 확인' 이지 문턱 근사가 아니다.")

## ── 1. FQ191/validation.json 정정 ────────────────────────────────────────────
p <- "stage_artifacts/FQ191/validation.json"
V <- fromJSON(p, simplifyVector = FALSE)
V$port_t_ladder_20260809$SUPERSEDED <- paste0(
  "★2026-08-09 후속 측정으로 **이 블록의 해석이 뒤집혔다**. 아래 correction_ladder_20260809 참조. ",
  "수치(2.204/2.379/2.966)는 재현되나 '비-신호 채널이 갭의 102%를 설명' 이라는 판독이 틀렸다.")
V$correction_ladder_20260809 <- list(
  what_i_wrote = "갭 0.746 중 0.762 를 비용+벤치 두 비-신호 채널이 설명(102%) — 제거하면 2.966 > 2.95 로 이 아크 첫 문턱 통과",
  why_it_was_wrong = CORE,
  identity_check = paste0(
    "★계약 신호에 직접 분해: gross cap-w t 2.363 · se 0.00350 → EW t 2.946 · se 0.00249. ",
    "배율만으로 예측 2.363 x 1.406 - 0.268 = **2.946**, 실측 **2.946** — 소수점 3자리 항등. ",
    "즉 2.966(≈2.946, 창 처리 차) 은 신호가 드러난 값이 아니라 **자를 바꾼 값**이다."),
  corrected_accounting = paste0(
    "진짜 채널은 **비용뿐**이다: net 2.189 → gross 2.363(Δ +0.174, 연 +0.76%). ",
    "갭 0.761 중 비용이 설명하는 몫 = **23%**. 나머지 **77% 는 신호 부족**이다. ",
    "비용도 고정 축(15bps)이라 반사실일 뿐 자본 주장 불가 — 이 부분은 원래 맞게 썼다."),
  verdict_impact = "H3(자본 자격 없음 · 오버레이 라우팅) **불변** — 애초에 cap-w 로 내렸다. 바뀌는 것은 '왜 미달인가' 의 설명이다: 신호가 벤치에 가려진 게 아니라 미달이 맞다.",
  repeat_offense = paste0(
    "★★이건 **08-08 에 이미 잡힌 함정**이다. `stage_artifacts/fq141_precheck_20260808/precheck_findings.md` 가 ",
    "'EW basis 로는 2.86' 을 성취로 승격하는 서술을 명시 금지했고 메모리 카드까지 있다. 지식으로 막히지 않았다. ",
    "다만 08-08 의 기전 서술('더 쉬운 벤치로 채점')도 **방향이 반대**였음이 이번 실측으로 드러났다(EW 는 mean 기준 더 어렵다). ",
    "금지 규범은 옳았고 근거만 틀렸던 셈."),
  mechanical_fix = paste0(
    "계약에 못박음 — `canonical_screen_bt()` 의 diag_ew_universe 에 **basis_channels** 필드 추가(2026-08-09): ",
    "se_ratio_ew_over_capw · t_magnification · mean_shift_t_contrib · se_shrink_t_contrib · dominant_channel · interpretation_note. ",
    "검사 `08_Tests/contract_regression/test_basis_channels.R` **22/22** (위반 주입: 벤치 괴리 17.9배 주입 → 배율 1.009→6.516 검출, ",
    "음수 알파 주입 시 EW 에서 더 음수 확인)."))
writeLines(toJSON(V, auto_unbox = TRUE, pretty = 2, digits = NA), p)
say("1. FQ191/validation.json 정정 기입")

## ── 2. 원장 정정 (FQ-191 + M26 라운드) ───────────────────────────────────────
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
n_before <- length(Q$entries)

i <- which(ids == "FQ-191")
if (length(i) == 1L) {
  Q$entries[[i]]$next_action <- paste0(Q$entries[[i]]$next_action,
    " ★★★재정정(2026-08-09 ladder_sweep): 위 '갭의 102%를 비-신호 채널이 설명 · 제거 시 2.966>2.95 첫 통과' 판독은 **틀렸다**. ",
    CORE,
    " 항등 확인: gross 2.363 x 배율 1.406 - 0.268 = **2.946** = 실측. ",
    "정정 회계 = 진짜 채널은 비용뿐이고 갭 0.761 중 **23%**, 나머지 **77% 는 신호 부족**. ",
    "H3 판정 불변(cap-w 로 내렸음). ★계약 수리 완료 = diag_ew_universe$basis_channels(검사 22/22).")
  say("2a. FQ-191 원장 정정")
}

j <- which(vapply(Q$entries, function(e) {
  b <- tolower(paste(unlist(e), collapse = " ")); grepl("wt.?d20260809_001|m26_revenue", b) }, TRUE))
for (k in j) {
  Q$entries[[k]]$next_action <- paste0(as.character(Q$entries[[k]]$next_action)[1],
    " ★정정(2026-08-09 ladder_sweep): 이 라운드의 **결론은 불변**(두 채널 제거해도 2.818 < 2.95 = 미달)이나 ",
    "'벤치 핸디캡' 이라는 **기전 서술이 틀렸다**. ", CORE,
    " M26 의 EW 4.084(8재료 재측정) 역시 배율 산물이다. 자본 귀속에는 cap-w 만 쓴다.")
  say("2b. M26 라운드 원장 정정 (%s)", ids[k])
}

## ── 3. 신규 FQ 등재: 일반화 규칙 + 소비면 ────────────────────────────────────
nums <- suppressWarnings(as.integer(sub("^FQ-", "", ids[grepl("^FQ-\\d+$", ids)])))
nid <- sprintf("FQ-%03d", max(nums, na.rm = TRUE) + 1L)
Q$entries[[length(Q$entries) + 1L]] <- list(
  id = nid,
  title = "★basis 전환 진단의 채널 분리 — se 배율을 신호로 읽는 오독의 기계적 차단 + 소비면 순회",
  status = "frontier_open",
  owner = "Q-Lead session 832fa2fc",
  claim = list(state = "complete", session = "832fa2fc", note = "계약 수리·검사·정정 전파 완료. 소비면 잔여는 next_probe."),
  ev_rationale = paste0(
    "동일 오독이 **이틀 연속·독립 세션에서 재발**하고 두 번 다 4단 전파됐다(08-08 challenge_note→지도→FQ / ",
    "08-09 validation→원장→지도 v55). 규범·메모리 카드로는 안 막혔다 — 산출물이 t 를 맨몸으로 내놓는 한 누구든 같은 오독을 한다."),
  wall_check = paste0("실측 분해(8재료 + 계약신호): ", CORE),
  next_action = paste0(
    "완료분 = ①`canonical_screen_bt()` diag_ew_universe$**basis_channels** 발행(mean/se 채널·배율·지배채널·해석경고) ",
    "②검사 `08_Tests/contract_regression/test_basis_channels.R` 22/22(위반 주입 포함) ③FQ-191·M26 원장·지도 정정. ",
    "★next_probe(2) = ①**소비자 배선 실측** — dual-basis 를 인용하는 지점(08-08 감사가 목록화)이 basis_channels 를 실제로 읽는지 ",
    "확인하고 미배선이면 인용부에 배율 병기 의무화(★'표준은 있는데 소비자 0' 계통 재발 방지). ",
    "②**cap-tier diag 도 같은 병 아닌가** — diag_cap_tier(MEGA/MID 분해)도 basis 를 바꾸므로 동일 배율 오독이 가능하다. ",
    "동일 분해를 붙일지 실측으로 판단."),
  consumer_surfaces = c("canonical_screen_bt diag", "alpha screening 기각 전 재분류", "병목지도 갭 귀속",
                        "FQ wall_check 인용", "challenge_note 적대검증"),
  revival_condition = "판정 basis 를 EW 로 옮기자는 제안이 다시 나오면 이 카드의 배율 실측(0.729/x1.371)과 음수-재료 지문을 먼저 제시",
  created = "2026-08-09")
Q$updated <- "2026-08-09"
write_frontier_queue(Q)
Q2 <- read_frontier_queue()
say("3. 신규 등재 %s · 항목 %d → %d (순수 추가 %s)", nid, n_before, length(Q2$entries),
    length(Q2$entries) == n_before + 1L)

## ── 4. 병목 지도 v56 ─────────────────────────────────────────────────────────
mp <- "06_Registry/layer_bottleneck_map.md"
raw <- readBin(mp, "raw", file.size(mp)); txt <- rawToChar(raw); Encoding(txt) <- "UTF-8"
anchor <- "**\uac31\uc2e0**: 2026-08-09 v55 ("
if (length(gregexpr(anchor, txt, fixed = TRUE)[[1]]) == 1L) {
  ins <- paste0(
    "**갱신**: 2026-08-09 v56 (★★**v55 ③항 정정 — 갭 귀속이 바뀐다**[ladder_sweep]. ",
    "v53~v55 가 PORT_t 사다리 3단(EW-유니버스 basis)을 '벤치 핸디캡 제거' 로 읽었으나 실측 분해가 이를 뒤집었다. ",
    "①mean 채널 = 재료 무관 상수(8/8 음수·sd 0.000019·연 -0.48%)이고 방향은 **불리**(t 기여 -0.132) — ",
    "EW 유니버스 벤치 수익이 cap-w 보다 **높아 mean 기준 더 어려운 벤치**다. ",
    "②se 채널 = se비율 **0.729** → **부호 무관 x1.371 배율**(EW 벤치가 포트와 구성이 닮아 active 변동 27%↓). ",
    "★증거 = 음수 알파 5재료가 EW 에서 **더 음수**. ★항등 = gross 2.363 x1.406 -0.268 = **2.946** = 실측(3자리 일치). ",
    "⇒ **'두 채널 제거 시 2.966>2.95 첫 통과' 는 성립하지 않는다** — 자를 바꾼 것이다. ",
    "정정 회계: 진짜 채널은 비용뿐이고 갭 0.761 중 **23%**, 나머지 **77% = 신호 부족**. ",
    "⑨자본 행 귀속 = '벤치가 가림' → **'신호 미달이 맞음'**. FQ-191 H3 판정 자체는 불변(cap-w 로 내렸음). ",
    "③★★**이틀 연속 재발** — 08-08 이 같은 오독을 잡고 금지 규범·메모리 카드를 남겼는데 08-09 에 독립 세션이 또 밟고 또 4단 전파. ",
    "다만 08-08 의 기전('더 쉬운 벤치')도 방향이 반대였다(규범은 옳고 근거가 틀림). ",
    "⇒ 대응을 규범이 아니라 **계약**으로: `canonical_screen_bt()` diag_ew_universe$**basis_channels** 발행 + ",
    "검사 `test_basis_channels.R` **22/22**(벤치 괴리 17.9배 주입 → 배율 1.009→6.516 검출). ",
    "상세 = `stage_artifacts/ladder_sweep/`) | ")
  txt2 <- sub(anchor, paste0(ins, anchor), txt, fixed = TRUE)
  outb <- charToRaw(enc2utf8(txt2)); writeBin(outb, mp)
  raw2 <- readBin(mp, "raw", file.size(mp))
  say("4. 지도 v56: %d → %d바이트 · CR %d(원 %d) · v56 존재 %s · v55 보존 %s",
      length(raw), length(outb), sum(raw2 == as.raw(13)), sum(raw == as.raw(13)),
      grepl("v56", rawToChar(raw2), fixed = TRUE), grepl("v55 (", rawToChar(raw2), fixed = TRUE))
} else say("4. ★지도 앵커 불일치 — 건너뜀")
say("=== p4 완료 ===")
