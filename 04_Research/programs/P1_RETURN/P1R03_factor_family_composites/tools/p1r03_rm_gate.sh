#!/usr/bin/env bash
# p1r03_rm_gate.sh — P1R03 재측정 셸(p1r03_remeasure_*) 공통 출발 관문 · source 해서 쓴다(2026-11-15)
#   통과 = 리프레시 배리어 free ∧ 가용 메모리 − 셀 워커 예상 정점 ≥ 여유
#   여유 = 06_Registry/memory_policy.json::reserve_gb(도훈 결정 MEMORY-USE-90PCT-20261115 · 물리의 10% · 판독 불가 = 출발 안 함)
#   예상 정점 = 셀 워커 1개 7.45 GB(11-03 메인 PC 실측) — P1R03_RM_PEAK_GB 로 바꿀 수 있다
#   가용 = Win32_OperatingSystem.FreePhysicalMemory(= Available MBytes · 11-15 실측 8,601 vs 8,617 MiB) · 단위 GiB
#   ★관문은 칸마다 출발 직전에만 본다 — 셸 둘을 나란히 띄우면 정점에 못 간 워커가 가용에 덜 잡혀 둘 다 통과할 수 있다. 나란히 띄울 땐 시차를 둔다.
RM_POLICY="${P1R03_RM_POLICY:-06_Registry/memory_policy.json}"
RM_PEAK_GB="${P1R03_RM_PEAK_GB:-7.45}"
RM_MAXWAIT="${P1R03_RM_MAXWAIT:-1800}"; RM_STEP="${P1R03_RM_STEP:-60}"

p1r03_rm_reserve_gb() { python -c "import json,sys;v=float(json.load(open(sys.argv[1],encoding='utf-8'))['reserve_gb']);sys.exit(1) if not v > 0 else print(v)" "$RM_POLICY" 2>/dev/null; }
p1r03_rm_avail_mib() { powershell.exe -NoProfile -NonInteractive -Command "[math]::Floor((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1KB)" 2>/dev/null | tr -d '\r\n '; }

# p1r03_rm_gate_wait — 0 = 통과(mg = 가용 GB 를 남긴다) · 6 = 대기 상한 · 7 = 메모리 정책 판독 불가 · 설정 값(정점 · 대기 상한 · 간격) 이상
p1r03_rm_gate_wait() {
  local rs need w=0 rb am
  if ! { [[ "$RM_PEAK_GB" =~ ^[0-9]+([.][0-9]+)?$ ]] && awk -v p="$RM_PEAK_GB" 'BEGIN{exit !(p > 0)}' &&
         [[ "$RM_MAXWAIT" =~ ^[0-9]+$ ]] && [[ "$RM_STEP" =~ ^[1-9][0-9]*$ ]]; }; then
    echo "[rm] 관문 설정 값 이상(정점 '$RM_PEAK_GB' GB · 대기 상한 '$RM_MAXWAIT' 초 · 간격 '$RM_STEP' 초) — 출발 안 함"; return 7
  fi
  rs=$(p1r03_rm_reserve_gb)
  [ -n "$rs" ] || { echo "[rm] 메모리 정책 판독 불가($RM_POLICY::reserve_gb) — 출발 안 함"; return 7; }
  need=$(awk -v p="$RM_PEAK_GB" -v r="$rs" 'BEGIN{printf "%d", (p + r) * 1024 + 0.5}')   # MiB
  while :; do
    bash 02_Infrastructure/ops/refresh_barrier.sh status >/dev/null 2>&1; rb=$?
    am=$(p1r03_rm_avail_mib)
    mg=$(awk -v m="$am" 'BEGIN{ if (m ~ /^[0-9]+$/) printf "%.1f", m / 1024; else print "?" }')
    if [ "$rb" = "0" ] && [[ "$am" =~ ^[0-9]+$ ]] && [ "$am" -ge "$need" ]; then return 0; fi
    if [ "$w" -ge "$RM_MAXWAIT" ]; then echo "[rm] 대기 상한(배리어 rc=$rb · 가용 ${mg}GB · 출발 = 정점 ${RM_PEAK_GB} + 여유 ${rs}GB) — 중단"; return 6; fi
    echo "[rm] 대기(배리어 rc=$rb · 가용 ${mg}GB · 출발 = 정점 ${RM_PEAK_GB} + 여유 ${rs}GB) $(date '+%F %T')"; sleep "$RM_STEP"; w=$((w + RM_STEP))
  done
}
