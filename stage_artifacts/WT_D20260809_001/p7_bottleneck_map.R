## WT-D20260809_001 P7 — 병목 지도 갱신 (연속성 5호 의무)
## ★파일이 CRLF 이므로 readLines/writeLines 정규화(유령 diff) 회피 — 바이트 수준 삽입만.
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[p7] ", fmt, "\n"), ...)); flush.console() }

p <- "06_Registry/layer_bottleneck_map.md"
raw <- readBin(p, "raw", file.size(p))
txt <- rawToChar(raw); Encoding(txt) <- "UTF-8"
say("원본 %d바이트 · CR %d개 · LF %d개", length(raw), sum(raw == as.raw(13)), sum(raw == as.raw(10)))

anchor <- "**\uac31\uc2e0**: 2026-08-09 v52 ("
n_hit <- length(gregexpr(anchor, txt, fixed = TRUE)[[1]])
if (n_hit != 1L || gregexpr(anchor, txt, fixed = TRUE)[[1]][1] < 0) {
  say("\u2605\uc575\ucee4 %d\uac74 \u2014 \uc911\ub2e8", n_hit); quit(status = 1)
}
say("\uc575\ucee4 1\uac74 \ud655\uc778")

ins <- paste0(
  "**갱신**: 2026-08-09 v53 (★★★**전이 벽은 단일 현상이 아니다 — M26 에서 갭이 가법 분해됐다**[WT-D20260809_001, FQ-161 후속]. ",
  "④construction 행 갱신. 사다리(cap-w · top-25 EW · 15bps · 유동성 2e8 · 283개월 2003-01~2026-07): ",
  "**net 1.5441 → 비용 제거(반사실 0bps) 2.0407(+0.497) → EW-유니버스 basis 2.8180(+0.777)** [참조 rank-IC t_NW3 2.9714 · FMB NW3 t 2.5553]. ",
  "즉 갭의 대부분이 **거래비용 + 벤치-측 핸디캡** 두 **비-신호** 채널로 회계된다. 비용 채널은 회계 항등으로 검증됨(turnover 11.7422/yr × 15bps = 연 1.7613%p vs 실측 차이 1.76%p). ",
  "★**'재료가 전이에서 죽는다'는 프레이밍이 M26 에는 맞지 않다** — 신호는 전이된다: decile 단조성 spearman **+0.879**(유동성필터) / **+0.964**(무필터), ",
  "D10 연초과 **+6.550%(t_NW3 +2.822)**, D1 −5.298%(t −2.502), long_side_share **0.553**(long 측이 short 측보다 약간 **강함**). ",
  "⇒ 인계 큐가 '검증 전'이라 못박은 기전 후보('rank-IC 가 고변동 꼬리 왜도를 못 봄')는 **본 실측으로 지지되지 않는다**. ",
  "★단 비-신호 채널을 **둘 다 제거해도 2.818 < HARD 2.95** — '비용·벤치만 없으면 졸업'도 아니다. M26 standalone 자본 자격 불변(미달). ",
  "★breadth 도 아님: PORT_t(50) − PORT_t(25) = **+0.147**(N∈{15,25,50,75} 곡선 폭 0.52, N=75 에서 하락). ★N>25 는 진단 전용 — 어떤 N 도 자본 주장 불가(INV-7). ",
  "★★**제약 조건 안 유일 레버(보유기간)는 1:1 교환**: 점수 staleness K∈{1,2,3,6} 로 회전율 11.74→3.73/yr(**−68%**) 이동 시 ",
  "비용 절감 1.20%p 와 gross 알파 손실 1.17%p(7.62%→6.45%)가 상쇄 — **paired NW3 11셀 전부 비유의**(최대 |t| 0.858, 필요 효과 연 3.01~5.55% vs 관측 −2.70~+2.00%) = INCONCLUSIVE_UNDERPOWERED. ",
  "이로써 **FQ-090**('회전율이 신호력과 독립적으로 PORT_t 를 움직이는가')에 M26 위에서 직접 응답 — 격리 측정 최초. ",
  "★★★**부수 확립 = 리밸 위상 추첨**: K=6 위상 6개 PORT_t 스프레드 **1.291**(0.841~2.133, 2/6 만 기준선 상회) · K=2 스프레드 0.816 · K=3 스프레드 0.141. ",
  "1차 측정(offset=0 만)의 '+0.467 개선'은 **추첨이었다** — 자가 적대검증이 적발해 결론을 뒤집음. ",
  "⚠**범위 제한(과잉 일반화 금지)**: 이 폭은 staleness 연산자(K≥2) 위에서만 실측됐고 **K=1(현행 월간 리밸)은 위상 자유도가 원리적으로 없다** — ",
  "'현행 book 측정도 추첨 성분을 포함한다'로 확장하면 08-08 capw−EW 오독과 같은 **범주 오류**다. book 급 일반화는 미측정(NP). ",
  "[[project-threshold-single-draw-fragility-20260802]] 의 **시간축 판본**. ",
  "후속 등재 = **FQ-164**(부분-리밸 연산자 — 점수 fresh 유지·교체 상한만, staleness 와 직교) · **FQ-165**(소비면 ⑥ composite/선별라벨 — D10 gross 를 production PG2 base 위 book-marginal ΔIR 로) · ",
  "**FQ-166**(사다리 일반화 — D03_EWMA PORT_t −1.73 · Q01_EB −0.21 에 동일 분해 적용해 **벽이 단일 현상인지 판별**). ",
  "★갭 귀속 긴장 해소 방향: 08-08 인계는 '3재료가 전부 ④에서 죽었다'였는데, M26 은 ④에서 죽은 게 아니라 **비용·벤치에서 감가**됐다. ",
  "음수 PORT_t 인 D03/Q01 은 같은 구조일 수 없으므로 FQ-166 이 판별 관문. 그 전까지 **기존 귀속 유지**. ",
  "상세 = `stage_artifacts/WT_D20260809_001/{alpha_validation.json,challenge_note.md,p1_arms.csv,p4_k_curve_phase_averaged.csv,p5_paired.csv}`) | ")

txt2 <- sub(anchor, paste0(ins, anchor), txt, fixed = TRUE)
if (nchar(txt2) <= nchar(txt)) { say("\u2605\uc0bd\uc785 \uc2e4\ud328 \u2014 \uc911\ub2e8"); quit(status = 1) }

out <- charToRaw(enc2utf8(txt2))
writeBin(out, p)
say("\uae30\ub85d \uc644\ub8cc: %d \u2192 %d\ubc14\uc774\ud2b8 (+%d)", length(raw), length(out), length(out) - length(raw))

## 재읽기 검증 + CRLF 보존 확인
raw2 <- readBin(p, "raw", file.size(p))
say("\uc7ac\uc77d\uae30: CR %d\uac1c(\uc6d0\ubcf8 %d) \u00b7 LF %d\uac1c(\uc6d0\ubcf8 %d)",
    sum(raw2 == as.raw(13)), sum(raw == as.raw(13)),
    sum(raw2 == as.raw(10)), sum(raw == as.raw(10)))
if (sum(raw2 == as.raw(13)) != sum(raw == as.raw(13)) ||
    sum(raw2 == as.raw(10)) != sum(raw == as.raw(10))) {
  say("\u2605\u2605\uc904\ub05d \ubcc0\uacbd \uac10\uc9c0 \u2014 \uc720\ub839 diff \uc704\ud5d8")
} else say("  \uc904\ub05d \ubcf4\uc874 \ud655\uc778")
t2 <- rawToChar(raw2); Encoding(t2) <- "UTF-8"
say("v53 \ubb38\uc790\uc5f4 \uc874\uc7ac: %s", grepl("2026-08-09 v53", t2, fixed = TRUE))
