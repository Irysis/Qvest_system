"""mem_gate.py — 메모리 정책 식 관문(단일 출처 · 2026-11-15)

도훈 결정
  MEMORY-USE-90PCT-20261115      식: 가용 메모리(Available) − 그 작업의 예상 정점 ≥ reserve_gb(물리의 10%)
  MEMORY-PEAK-BACKCALC-20261115  예상 정점 = 실제로 성공한 출발에서 거꾸로 센 값(성공 출발 역산) · 기록 없는 작업 = 순간 정점(첫 성공 뒤 역산값으로 낮춘다)
  MEMORY-GATE-LANE-TICKS-20261115 관문 위치 = 충실구현 레인 검증기 출발 · :37 상설 판 측정 · :37 강화 사슬 측정 — 먼저 뜬 작업이 돌고 나머지는 다음 틱에 뜬다

정본 = 06_Registry/memory_policy.json — reserve_gb · peaks.<작업 키>.gb · conflicts.<작업 키>(명령줄 정규식 목록)
  conflicts = '먼저 뜬 무거운 작업' 표지. 출발 직후라 아직 정점에 닿지 않은 작업(예: 감사 단계의 레인 검증기)이 살아 있으면 가용이 넉넉해 보여도 기다린다.

사용: python -X utf8 02_Infrastructure/ops/mem_gate.py <작업 키>
  rc 0 = 통과 · 1 = 대기(가용 부족 또는 먼저 뜬 무거운 작업) · 2 = 판독 불가(정책 · 가용 · 프로세스 목록) — 부르는 쪽은 0 이 아니면 출발하지 않는다(fail-closed)
  출력 = 판정과 근거 한 줄.
시험 주입: MG_POLICY(정책 파일) · MG_AVAIL_MB(가용 MiB 고정) · MG_PROCS_FILE(프로세스 목록 대신 쓰는 파일 — 한 줄 = 'pid<TAB>명령줄')
"""
import ctypes
import json
import os
import re
import subprocess
import sys

SELF_RX = re.compile(r"mem_gate\.py|Get-CimInstance")


def avail_mib():
    v = os.environ.get("MG_AVAIL_MB")
    if v is not None:
        return int(float(v))

    class MS(ctypes.Structure):
        _fields_ = [("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong),
                    ("ullTotalPhys", ctypes.c_ulonglong), ("ullAvailPhys", ctypes.c_ulonglong),
                    ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong),
                    ("ullTotalVirtual", ctypes.c_ulonglong), ("ullAvailVirtual", ctypes.c_ulonglong),
                    ("ullAvailExtendedVirtual", ctypes.c_ulonglong)]
    m = MS()
    m.dwLength = ctypes.sizeof(MS)
    if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m)):
        raise OSError("GlobalMemoryStatusEx 실패")
    return int(m.ullAvailPhys // (1024 * 1024))


def proc_rows():
    f = os.environ.get("MG_PROCS_FILE")
    if f:
        lines = open(f, encoding="utf-8").read().splitlines()
    else:
        # 탭은 [char]9 로 만든다 — 작은따옴표 문자열 안의 `t 는 이스케이프가 아니라 글자 그대로라(11-15 af597c328 판) 탭 구분 행이 0 이 되어
        # 겹침 표지가 한 번도 발화하지 않았다(1계층 세션 11-15 16:2x 재현: 522줄 중 탭 0 · 글자 `t 468).
        ps = "Get-CimInstance Win32_Process | ForEach-Object { '{0}{1}{2}' -f $_.ProcessId, [char]9, $_.CommandLine }"
        r = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", ps], capture_output=True, timeout=90)
        if r.returncode != 0 or not r.stdout:
            raise OSError("프로세스 목록 조회 실패(rc %s)" % r.returncode)
        lines = r.stdout.decode("utf-8", "replace").splitlines()   # 표지 정규식은 ASCII — 한글 경로가 깨져도 판정에는 무관
    rows = []
    for ln in lines:
        if "\t" not in ln:
            continue
        pid, cl = ln.split("\t", 1)
        if cl.strip() and not SELF_RX.search(cl):
            rows.append((pid.strip(), cl))
    if not f and not rows:   # 실제 목록이 탭 구분 0행 = 판독 실패(프로세스가 하나도 없을 수는 없다) — 조용히 '겹침 없음'으로 통과시키지 않는다
        raise OSError("탭 구분 행 0(원본 %d줄) — 조회 형식 결함" % len(lines))
    return rows


def main(argv):
    if not argv:
        print("판독 불가 — 작업 키 없음(사용: mem_gate.py <작업 키>)")
        return 2
    key = argv[0]
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    pol_path = os.environ.get("MG_POLICY") or os.path.join(root, "06_Registry", "memory_policy.json")
    try:
        with open(pol_path, encoding="utf-8") as fh:
            pol = json.load(fh)
        resv = float(pol["reserve_gb"])
        pk = pol["peaks"][key]
        peak = float(pk["gb"])
        conf = [re.compile(p) for p in (pol.get("conflicts") or {}).get(key, [])]
        if not (resv > 0 and peak > 0):
            raise ValueError("reserve_gb · gb 는 양수여야 한다")
    except Exception as e:  # noqa: BLE001 — 무엇이든 판독 불가 = 출발 안 함
        print("판독 불가 — 정책 %s · 키 %s: %s" % (pol_path, key, e))
        return 2
    try:
        am = avail_mib()
    except Exception as e:  # noqa: BLE001
        print("판독 불가 — 가용 메모리: %s" % e)
        return 2
    need = int(round((peak + resv) * 1024))
    hits = []
    if conf:
        try:
            rows = proc_rows()
        except Exception as e:  # noqa: BLE001
            print("판독 불가 — 프로세스 목록: %s" % e)
            return 2
        for pid, cl in rows:
            for c in conf:
                if c.search(cl):
                    hits.append("%s(pid %s)" % (c.pattern.replace("\\", ""), pid))
                    break
    cmp_ = ">=" if am >= need else "<"
    basis = pk.get("basis", "?")
    msg = "가용 %.1f GB − 정점 %g GB(%s · %s) %s 여유 %g GB" % (am / 1024, peak, key, basis, cmp_, resv)
    if hits:
        print("대기 — 먼저 뜬 무거운 작업 %s · %s" % (", ".join(hits[:3]), msg))
        return 1
    if am < need:
        print("대기 — " + msg)
        return 1
    print("통과 — " + msg)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
