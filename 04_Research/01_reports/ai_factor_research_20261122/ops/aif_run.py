"""aif_run.py — AI 팩터 연구 실행 감시 셸(승인 계획 '자원 배분과 안정성' · '진행 알림'). 표준 라이브러리만 쓴다.

하는 일
  1. 출발 조건을 기다린다 — 새벽 시간대(설정 no_start_hours) · 다른 무거운 작업 · 가용 메모리 식(인프라 mem_gate.py 를 연구 전용 정책으로 부른다)
  2. 작업을 '보통 이하' 우선순위로 띄우고, 스레드 수 환경변수를 작업 상한으로 묶는다
  3. 도는 동안 30초마다 본다 — 가용 메모리가 모자라면 작업 프로세스 나무를 멈췄다가 회복되면 잇는다 · 작업 메모리가 상한을 넘으면 끝낸다 ·
     GPU 작업이면 온도가 높을 때 멈췄다가 식으면 잇는다
  4. 약 10분마다 진행 알림 스크립트를 부른다(보낼 때인지는 그 스크립트가 정한다) · 실패로 끝나면 상태를 오류로 적고 오류 통을 보낸다

사용: python -X utf8 ops/aif_run.py --job perf --stage perf_base [--no-notify] -- <명령 ...>
종료 코드: 작업의 종료 코드 · 86 = 메모리 상한 초과로 끝냄
"""
import argparse
import ctypes
import ctypes.wintypes as wt
import datetime as dt
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
RDIR = os.path.dirname(HERE)
ROOT = os.environ.get("AIF_ROOT") or os.environ.get("QM_ROOT") or os.path.abspath(os.path.join(RDIR, "..", "..", ".."))
CFG = json.load(open(os.path.join(RDIR, "aif_config.json"), encoding="utf-8"))
OUT = os.path.join(ROOT, CFG["paths"]["out_cache"])
STATUS = os.path.join(OUT, "status.json")
RSCRIPT = CFG.get("tools", {}).get("rscript", "Rscript")
PYEXE = os.environ.get("QVEST_PY") or sys.executable
k32 = ctypes.WinDLL("kernel32", use_last_error=True)
ntdll = ctypes.WinDLL("ntdll")
BELOW_NORMAL = 0x00004000


def now():
    return dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def log(fh, msg):
    line = "[aif-run %s] %s" % (now(), msg)
    print(line, flush=True)
    if fh:
        fh.write(line + "\n")
        fh.flush()


def status_update(**kw):
    os.makedirs(os.path.dirname(STATUS), exist_ok=True)
    st = {}
    if os.path.exists(STATUS):
        try:
            with open(STATUS, encoding="utf-8") as fh:      # 읽자마자 닫는다 — 열어 둔 사이에 작업 쪽의 덮어쓰기가 '액세스 거부'로 실패하지 않게
                st = json.load(fh)
        except Exception:  # noqa: BLE001 — 읽다 깨진 상태 파일은 새로 쓴다
            st = {}
    for k, v in kw.items():
        if v is None:
            st.pop(k, None)
        else:
            st[k] = v
    st["updated_at"] = now()
    tmp = "%s.%d.tmp" % (STATUS, os.getpid())                # 작업 쪽 임시 파일과 겹치지 않게 프로세스 번호를 넣는다
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(st, fh, ensure_ascii=False, indent=2)
        for i in range(40):                                  # 윈도: 대상을 다른 프로그램이 잠깐 잡고 있으면 '액세스 거부' — 짧게 기다렸다 다시 한다(합쳐 약 9초)
            try:
                os.replace(tmp, STATUS)
                break
            except PermissionError:
                if i == 39:
                    raise
                time.sleep(0.05 * (1 + i // 5))
    except OSError:                                          # 상태 파일은 진행 표시일 뿐이다 — 못 써도 감시를 멈추지 않는다
        try:
            os.remove(tmp)
        except OSError:
            pass


class MEMSTAT(ctypes.Structure):
    _fields_ = [("dwLength", wt.DWORD), ("dwMemoryLoad", wt.DWORD), ("ullTotalPhys", ctypes.c_ulonglong), ("ullAvailPhys", ctypes.c_ulonglong),
                ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong), ("ullTotalVirtual", ctypes.c_ulonglong),
                ("ullAvailVirtual", ctypes.c_ulonglong), ("ullAvailExtendedVirtual", ctypes.c_ulonglong)]


def avail_gb():
    m = MEMSTAT()
    m.dwLength = ctypes.sizeof(MEMSTAT)
    if not k32.GlobalMemoryStatusEx(ctypes.byref(m)):
        return float("nan")
    return m.ullAvailPhys / 1024 ** 3


class PE32(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD), ("th32ProcessID", wt.DWORD), ("th32DefaultHeapID", ctypes.c_size_t),
                ("th32ModuleID", wt.DWORD), ("cntThreads", wt.DWORD), ("th32ParentProcessID", wt.DWORD), ("pcPriClassBase", ctypes.c_long),
                ("dwFlags", wt.DWORD), ("szExeFile", ctypes.c_char * 260)]


class PMC(ctypes.Structure):
    _fields_ = [("cb", wt.DWORD), ("PageFaultCount", wt.DWORD), ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                ("QuotaPeakPagedPoolUsage", ctypes.c_size_t), ("QuotaPagedPoolUsage", ctypes.c_size_t), ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                ("QuotaNonPagedPoolUsage", ctypes.c_size_t), ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t)]


k32.CreateToolhelp32Snapshot.restype = wt.HANDLE
k32.OpenProcess.restype = wt.HANDLE
k32.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
k32.CloseHandle.argtypes = [wt.HANDLE]
k32.Process32First.argtypes = [wt.HANDLE, ctypes.POINTER(PE32)]
k32.Process32Next.argtypes = [wt.HANDLE, ctypes.POINTER(PE32)]
k32.K32GetProcessMemoryInfo.argtypes = [wt.HANDLE, ctypes.POINTER(PMC), wt.DWORD]
ntdll.NtSuspendProcess.argtypes = [wt.HANDLE]
ntdll.NtResumeProcess.argtypes = [wt.HANDLE]


def tree(pid):
    """pid 와 그 자손 프로세스의 pid 목록"""
    snap = k32.CreateToolhelp32Snapshot(0x2, 0)
    par = {}
    e = PE32()
    e.dwSize = ctypes.sizeof(PE32)
    ok = k32.Process32First(snap, ctypes.byref(e))
    while ok:
        par[e.th32ProcessID] = e.th32ParentProcessID
        ok = k32.Process32Next(snap, ctypes.byref(e))
    k32.CloseHandle(snap)
    out, front = [pid], [pid]
    while front:
        nxt = [p for p, q in par.items() if q in front and p not in out]
        out += nxt
        front = nxt
    return out


def private_gb(pids):
    tot = 0
    for p in pids:
        h = k32.OpenProcess(0x1000, False, p)      # PROCESS_QUERY_LIMITED_INFORMATION
        if not h:
            continue
        c = PMC()
        c.cb = ctypes.sizeof(PMC)
        if k32.K32GetProcessMemoryInfo(h, ctypes.byref(c), c.cb):
            tot += c.PagefileUsage
        k32.CloseHandle(h)
    return tot / 1024 ** 3


def set_suspended(pids, suspend):
    for p in pids:
        h = k32.OpenProcess(0x0800, False, p)      # PROCESS_SUSPEND_RESUME
        if not h:
            continue
        (ntdll.NtSuspendProcess if suspend else ntdll.NtResumeProcess)(h)
        k32.CloseHandle(h)


def gpu_temp():
    try:
        r = subprocess.run(["nvidia-smi", "--query-gpu=temperature.gpu", "--format=csv,noheader"], capture_output=True, timeout=20)
        return float(r.stdout.decode().strip().splitlines()[0])
    except Exception:  # noqa: BLE001
        return float("nan")


def gate(job):
    """(통과 여부, 사유 한 줄)"""
    hrs = CFG["resources"].get("no_start_hours", [])
    if dt.datetime.now().hour in hrs:
        return False, "새벽 %d~%d시에는 새 단위를 시작하지 않습니다" % (min(hrs), max(hrs) + 1)
    env = dict(os.environ, MG_POLICY=os.path.join(HERE, "aif_mem_policy.json"))
    try:
        r = subprocess.run([PYEXE, "-X", "utf8", os.path.join(ROOT, "02_Infrastructure", "ops", "mem_gate.py"), "aif_" + job],
                           capture_output=True, timeout=180, env=env)
        line = (r.stdout.decode("utf-8", "replace").strip().splitlines() or ["출력 없음"])[-1]
        return r.returncode == 0, line
    except Exception as e:  # noqa: BLE001 — 판독 불가 = 출발 안 함
        return False, "관문 판독 불가: %s" % e


def friendly(reason):
    if "daily_refresh" in reason or "qm_refresh" in reason:
        return "밤 갱신에 양보 중"
    if "먼저 뜬 무거운 작업" in reason:
        return "다른 무거운 작업에 양보 중"
    if reason.startswith("대기 — 가용"):
        return "가용 메모리 대기"
    return reason[:80]


def notify(fh, send, *extra):
    if not send:
        return
    try:
        r = subprocess.run([RSCRIPT, "--vanilla", os.path.join(RDIR, "notify", "aif_progress_notify.R"), "--send", *extra],
                           capture_output=True, timeout=600, cwd=ROOT)
        tail = (r.stdout.decode("utf-8", "replace").strip().splitlines() or [""])[-1]
        log(fh, "알림 — %s" % tail)
    except Exception as e:  # noqa: BLE001 — 알림 실패는 작업을 막지 않는다
        log(fh, "알림 실패(작업은 계속): %s" % e)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--job", required=True)
    ap.add_argument("--stage", required=True)
    ap.add_argument("--no-notify", action="store_true")
    ap.add_argument("--track", default="", help="실행 줄 — 빈 값 = 1단계(지금까지와 같다) · followup = 2단계(상태 파일 · 로그 · 작업 상한을 그 줄 것으로 쓴다)")
    ap.add_argument("--summary", default=None, help="작업이 성공으로 끝난 뒤 결과 통에 실을 요약 파일(json)")
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    cmd = a.cmd[1:] if a.cmd and a.cmd[0] == "--" else a.cmd
    if not cmd:
        ap.error("명령이 없다")
    global STATUS
    base = OUT
    if a.track:                                   # 2단계 줄 — 상태 파일 · 로그를 따로 두고, 자식 작업과 알림 스크립트에 같은 줄을 알린다(AIF_TRACK)
        base = os.path.join(OUT, a.track)
        STATUS = os.path.join(base, "status.json")
        os.environ["AIF_TRACK"] = a.track
    jc = (CFG[a.track] if a.track else CFG)["resources"]["jobs"][a.job]
    send = not a.no_notify
    os.makedirs(os.path.join(base, "logs"), exist_ok=True)
    stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    wlog = open(os.path.join(base, "logs", "%s_%s.wrapper.log" % (a.job, stamp)), "w", encoding="utf-8")
    jlog = open(os.path.join(base, "logs", "%s_%s.log" % (a.job, stamp)), "w", encoding="utf-8")
    log(wlog, "작업 %s · 단계 %s · 상한 스레드 %s · RAM %sGB%s" % (a.job, a.stage, jc["threads"], jc["ram_gb"], " · GPU %sGB" % jc["vram_gb"] if "vram_gb" in jc else ""))
    try:        # 단계가 바뀌면 단계 시작 시각을 새로 적는다 — 생성기의 stage_begin 은 '같은 단계면 유지' 라, 여기서 갈지 않으면 첫 단계의 시각이 끝까지 남아 알림의 '경과' 가 틀린다
        with open(STATUS, encoding="utf-8") as fh:
            prev_stage = json.load(fh).get("stage_key")
        if prev_stage != a.stage:
            status_update(stage_started_at=now())
    except Exception:  # noqa: BLE001 — 상태 파일이 없거나 깨졌으면 생성기가 새로 적는다
        pass

    # 1. 출발 조건
    waited = 0
    while True:
        ok, why = gate(a.job)
        if ok:
            log(wlog, "출발 — %s" % why)
            break
        if waited == 0 or waited % 6 == 0:
            log(wlog, "대기 — %s" % why)
        status_update(stage_key=a.stage, stage_state="waiting", wait_reason=friendly(why), job=a.job)
        notify(wlog, send)
        waited += 1
        time.sleep(300)

    # 2. 띄우기
    env = dict(os.environ)
    for v in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "NUMEXPR_NUM_THREADS", "VECLIB_MAXIMUM_THREADS", "LOKY_MAX_CPU_COUNT", "PYTHON_CPU_COUNT"):
        env[v] = str(jc["threads"])
    env.update(AIF_THREADS=str(jc["threads"]), AIF_RAM_GB=str(jc["ram_gb"]), AIF_ROOT=ROOT, PYTHONUTF8="1")
    status_update(stage_key=a.stage, stage_state="running", wait_reason=None, error=None, job=a.job, threads=jc["threads"])
    p = subprocess.Popen(cmd, stdout=jlog, stderr=subprocess.STDOUT, env=env, cwd=RDIR, creationflags=BELOW_NORMAL)
    log(wlog, "띄움 — pid %d · %s" % (p.pid, " ".join(cmd)))

    # 3. 감시
    res = CFG["resources"]
    paused, last_notify, peak, rc_override = False, time.time(), 0.0, None
    while p.poll() is None:
        time.sleep(30)
        pids = tree(p.pid)
        mine, free = private_gb(pids), avail_gb()
        peak = max(peak, mine)
        hot = gpu_temp() if "vram_gb" in jc else float("nan")
        need_pause = (free == free and free < res["pause_avail_gb"]) or (hot == hot and hot > res["gpu_temp_max_c"])
        if mine > jc["ram_gb"]:
            log(wlog, "★작업 메모리 %.1fGB > 상한 %sGB — 끝냅니다" % (mine, jc["ram_gb"]))
            subprocess.run(["taskkill", "/PID", str(p.pid), "/T", "/F"], capture_output=True)
            rc_override = 86
            break
        if need_pause and not paused:
            set_suspended(pids, True)
            paused = True
            why = "가용 메모리 %.1fGB" % free if free < res["pause_avail_gb"] else "GPU 온도 %.0f도" % hot
            log(wlog, "일시 중지 — %s" % why)
            status_update(stage_state="paused", wait_reason=why)
        elif paused and not need_pause and (free != free or free > res["pause_avail_gb"] + 1.0):
            set_suspended(pids, False)
            paused = False
            log(wlog, "재개 — 가용 메모리 %.1fGB" % free)
            status_update(stage_state="running", wait_reason=None)
        status_update(peak_tree_gb=round(peak, 2), tree_gb=round(mine, 2), avail_gb=round(free, 1))
        if time.time() - last_notify >= 600:
            notify(wlog, send)
            last_notify = time.time()

    rc = rc_override if rc_override is not None else p.returncode
    jlog.close()
    log(wlog, "끝 — 종료 코드 %s · 작업 메모리 정점 %.1fGB" % (rc, peak))
    if rc != 0:
        tail = ""
        try:
            tail = open(jlog.name, encoding="utf-8", errors="replace").read()[-400:].strip().replace("\n", " / ")
        except Exception:  # noqa: BLE001
            pass
        status_update(stage_state="error", error=("메모리 상한 초과로 끝냄" if rc == 86 else "종료 코드 %s · %s" % (rc, tail))[:300])
        notify(wlog, send, "--event=error")
    elif a.summary:
        notify(wlog, send, "--event=result", "--summary=" + a.summary)
    else:
        notify(wlog, send)
    wlog.close()
    return rc


if __name__ == "__main__":
    sys.exit(main())
