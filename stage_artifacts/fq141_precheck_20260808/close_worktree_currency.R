# close_worktree_currency.R — worktree 헌법 최신성 사각 라운드 마감
# ★Rscript -e 에 한글을 넣으면 Windows 인코딩으로 침묵 실패(헌법 R Execution Pattern). 파일로 source().
source("02_Infrastructure/contracts/close_round.R")

r <- close_round(
  round_id = "BOOTCURRENCY_WORKTREE_STALENESS_20260808",
  verdict_type = "capability_established",
  layer = "하네스/부팅검사",
  mechanism_diagnosis = paste(
    "boot_currency_check.sh 는 트리-로컬 자기-정합 검사다 — 배너/qvest.md 를 '그 트리의 CLAUDE.md' 와만 대조하고,",
    "main 정본 대비 최신성 축이 없다. 따라서 구판 헌법을 든 worktree 는 내부적으로 일관하므로 PASS 를 낸다.",
    "실측: worktree 31개 중 현행(claude-opus-5) 0개 · 구판 claude-fable-5 26개 · Active Version 미파싱 5개 (main = claude-opus-5).",
    "★미파싱 5개는 그 트리에서 부팅 시 C0 FAIL 이 나고, 오늘 main 에서 수리한 'C0 실패가 C1/C1b/C1c/C2/C3 를 통째로 스킵' 상태가 그대로 재현된다.",
    "즉 오늘의 수리는 main 한정이고 노출 표면은 31개 트리다.",
    "계통 = 이 저장소가 반복 검거해온 '존재 검사로 정체성 검사 대체' 의 변종 — 여기서는 '자기-정합 검사로 최신성 검사 대체'."),
  next_probes = c(
    "C8 축 신설 — 트리-로컬 CLAUDE.md Active Version 이 main(또는 merge-base) 정본과 일치하는지 부팅에서 표시. 위반 주입 테스트 동반(구판 헌법 픽스처 주입 시 발화 확인). 이게 없으면 구판 헌법 세션이 자기가 낡은 줄 모르고 돈다",
    "노출 실측 — 31개 트리 중 실제로 부팅이 돌아간 트리가 몇 개인지 events.jsonl/부팅 로그로 확인. 0 이면 C8 우선순위 하락, >0 이면 그 세션들이 어떤 구판 규범으로 판단했는지 소급 확인 대상",
    "파급 전수 — 다른 부팅 검사(hook-integrity·PG2 coherence·measurement coherence·cache_core sync)도 트리-로컬 값끼리만 비교하는 자기-정합 형태인지 확인. 같은 사각이면 같은 방식으로 새는 축이 더 있다"),
  consumer_surfaces = c("monitoring", "부팅검사", "타모드이식"),
  frontier_update = "칩 분리(worktree 헌법 최신성 축) · main 트리 Fable 5-Native 잔존 0 확인(역사기록 fable5_harness_audit_20260724.md 만 보존)",
  live_trigger = "worktree 에서 부팅한 세션이 관측되면 즉시 C8 착수 / 병합으로 31개가 현행화되면 노출 자연 해소되나 축 자체는 남음",
  evidence_refs = c("02_Infrastructure/ops/boot_currency_check.sh",
                    "08_Tests/hooks/test_boot_currency.sh")
)
cat("[close_worktree_currency] RC_OK\n")
