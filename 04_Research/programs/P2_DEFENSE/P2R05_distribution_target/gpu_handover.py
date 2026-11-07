# -*- coding: utf-8 -*-
# ★폐기(쓰지 말 것 · 2026-11-06 표기) — 10-18 '전 종목 THGNN 을 T 일치로 체크포인트 재개' 전제로 썼다. 10-20 THGNN 이 새 축(K200∪KQ150 · 2000~) ·
#   처음부터 학습으로 바뀌어 전제가 무효다(인계 카드 L1_HANDOVER_20261020 §4). P2R05 GPU 창은 gpu_chain.sh(THGNN 측정 끝 대기 → 같은 배치 워밍 → 측정)가 맡는다.
"""GPU 인계 — 충실구현 레인 THGNN(2601.04602) 측정을 체크포인트 지점에서 멈추고 P2R05 워밍에 GPU 를 넘긴 뒤, 레인 재개 때 THGNN 이
같은 엔진 · 같은 감사로 체크포인트에서 이어지게 준비한다(도훈 10-18 19:3x 선택 '일시정지 + THGNN 메모리 수리 후 재개' · 판단 원장 J-20261018-008).

순서(handover):
  0. 사전 확인 — P2R05 사전등록 정본 존재 · 레인 스위치 꺼짐(lane_hold) · THGNN 체크포인트 판독(에폭 · 스텝 기록 · CPU 사본)
  1. THGNN 체인의 맨 위 레인 프로세스(rf_replication_auto.sh = claim 소유자)를 트리째 끝낸다(taskkill /T /F) — 동적 탐색(하드코딩 pid 없음)
  2. GPU 메모리가 풀렸는지 확인(nvidia-smi memory.used < 2,000 MiB · 최대 3분)
  3. 세션 판정 기록 — replication_request.json::audit_ruling = {action = 이 엔진 · 이 감사 파일의 실제 처분(rf_audit_disposition · 재감사 회차 그대로),
     engine_md5 = 지금 engine.R} → 레인 재개 때 rf_replication_auto.sh 의 HAS_RULING 분기 = 에이전트 재구현 없이 검증기만 · rf_audit_gate 가 감사를
     다시 사지 않고 남은 감사 파일로 처분 → 엔진 불변 → thgnn.py SRC_KEY 불변 → 체크포인트 재개(같은 궤적 · 손실 ≤ 50스텝)
  4. 메모리 수리 — rf_replication_auto.sh 머리에 PYTORCH_CUDA_ALLOC_CONF 기본값 1줄(결과 무관 할당기 설정 · P2R03 measure_now_vram.sh 와 같은 처치 ·
     이미 있으면 그대로) · 체인을 끝낸 뒤에만 고친다(실행 중 bash 스크립트는 지연 판독 — 제자리 수정 금지) · bash -n 문법 검사
  ★재개는 이 스크립트가 하지 않는다 — lane_hold_wait.sh(P2R05 워밍 센티널 또는 10-19 20:00)가 스위치를 켜면 다음 레인 틱이 고아 claim 을 회수하고 재개한다.
  ★데이터 경계: thgnn.py 체크포인트는 T(날짜 수)가 같아야 재개된다 — 화 10-20 00:03 갱신(월 10-19 거래일 추가) 전에 레인이 재개돼야 한다.
사용: python gpu_handover.py handover [--dry]   (로그 = 같은 폴더 gpu_handover.log)"""
import datetime as dt, hashlib, io, json, os, re, shutil, subprocess, sys, tempfile, time

ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
sys.path.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "02_Infrastructure", "ops"))
from qv_bash import qv_bash  # bare "bash" 금지(금칙 ⑦ · 11-07) — WSL 있는 PC 에선 System32 bash 가 PATH 보다 먼저 잡힌다
RD = os.path.join(ROOT, "04_Research/programs/P2_DEFENSE/P2R05_distribution_target")
LOG = os.path.join(RD, "gpu_handover.log")
WDIR = os.path.join(ROOT, "04_Research/strategies/RP_AUTO_CLEAN_2601_04602")
REQ = os.path.join(ROOT, "06_Registry/replication_request.json")
CFG = os.path.join(ROOT, "06_Registry/reinforce_auto_config.json")
LANE_SH = os.path.join(ROOT, "02_Infrastructure/ops/rf_replication_auto.sh")
PREREG = os.path.join(ROOT, "stage_artifacts/programs/P2_DEFENSE/P2R05_distribution_target/prereg.json")
VENV_PY = os.path.join(ROOT, ".venv_qvest_ml/Scripts/python.exe")
ALLOC = "roundup_power2_divisions:2"
EXPORT_LINE = ('export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-%s}"   '
               '# ★GPU 메모리 넘침 방지(2026-10-18 도훈 \'일시정지 + THGNN 메모리 수리 후 재개\' · P2R03 measure_now_vram.sh 와 같은 처치 — '
               'Windows WDDM 시스템 메모리 폴백은 CUDA OOM 을 내지 않아 캐싱 할당기가 커지는 할당을 새 세그먼트로 계속 쥔다 · THGNN 10-18 공유 9.7GB · '
               '결과 무관 할당기 설정 · 이미 정해져 있으면 덮지 않는다)' % ALLOC)
ANCHOR = 'PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"'


def log(msg):
    line = "%s %s" % (dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"), msg)
    print(line, flush=True)
    with io.open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def md5(p):
    with open(p, "rb") as f:
        return hashlib.md5(f.read()).hexdigest()


def ps(cmd):
    r = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", cmd], capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.returncode, r.stdout


def procs():
    rc, out = ps("Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,CommandLine | ConvertTo-Json -Compress")
    if rc != 0 or not out.strip():
        raise SystemExit("[handover] 프로세스 목록 실패")
    js = json.loads(out)
    return {int(p["ProcessId"]): (int(p["ParentProcessId"] or 0), p.get("CommandLine") or "") for p in js}


def lane_top(P):
    """thgnn.py(2601.04602) 파이썬에서 부모를 거슬러 올라가 맨 위 rf_replication_auto.sh 프로세스를 찾는다."""
    leaves = [pid for pid, (_, cl) in P.items() if "RP_AUTO_CLEAN_2601_04602" in cl and "thgnn.py" in cl and "python" in cl.lower()
              and "gpu_handover" not in cl and "snapshot-bash" not in cl]   # 세션 셸의 검색 명령줄 제외
    if not leaves:
        return None, []
    chain, cur, top = [(pid, P[pid][1][:140]) for pid in leaves[1:]], leaves[0], None
    seen = set()
    while cur in P and cur not in seen:
        seen.add(cur)
        ppid, cl = P[cur]
        chain.append((cur, cl[:140]))
        if "rf_replication_auto.sh" in cl:
            top = cur
        cur = ppid
    return top, chain


def gpu_used():
    r = subprocess.run(["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"], capture_output=True, text=True)
    try:
        return int(r.stdout.strip().splitlines()[0])
    except Exception:
        return -1


def ckpt_state():
    src = os.path.join(WDIR, "_work", "thgnn_ckpt.pt")
    if not os.path.exists(src):
        return None
    tmp = os.path.join(tempfile.gettempdir(), "thgnn_ckpt_handover_peek.pt")
    shutil.copy2(src, tmp)
    code = ("import torch,json,os;st=torch.load(r'%s',map_location='cpu',weights_only=False);sc=st['sched'];"
            "print(json.dumps({'epoch':int(st['epoch']),'bi':int(st.get('bi',0)),'steps':int(sc['last_epoch']),'T_max':int(sc['T_max']),"
            "'T':int(st['T']),'src':str(st.get('src'))[:16]}));os.remove(r'%s')") % (tmp, tmp)
    env = dict(os.environ, CUDA_VISIBLE_DEVICES="")
    r = subprocess.run([VENV_PY, "-X", "utf8", "-c", code], capture_output=True, text=True, env=env)
    try:
        d = json.loads(r.stdout.strip().splitlines()[-1])
    except Exception:
        d = {"error": (r.stderr or "")[-300:]}
    d["mtime"] = dt.datetime.fromtimestamp(os.path.getmtime(src)).strftime("%Y-%m-%dT%H:%M:%S")
    return d


def audit_action():
    """이 엔진 · 이 감사 파일 · 요청의 재감사 회차로 감사 관문이 낸 처분을 그대로 재도출(rf_audit_disposition)."""
    with io.open(REQ, "r", encoding="utf-8") as f:
        rq = json.load(f)
    tries = int(rq.get("audit_retries") or 0)
    rs = ('suppressMessages(source("%s/02_Infrastructure/ops/rf_fidelity_audit_lib.R"));'
          'a<-rf_audit_read("%s/fidelity_audit.json");if(!is.null(a$reason))stop(a$reason);'
          'cat(rf_audit_disposition(a,retries_done=%d)$action)') % (ROOT, WDIR.replace("\\", "/"), tries)   # R 문자열 안 역슬래시 = 이스케이프(\0 파싱 실패 · 10-18 건식 실측)
    r = subprocess.run(["Rscript", "-e", rs], capture_output=True, text=True, encoding="utf-8", errors="replace")
    act = (r.stdout or "").strip().splitlines()[-1] if (r.stdout or "").strip() else ""
    if not act:
        log("감사 처분 재도출 실패(rc %d): %s" % (r.returncode, (r.stderr or "")[-300:]))
    return act, tries, rq


def write_ruling(dry):
    act, tries, rq = audit_action()
    if act not in ("proceed", "proceed_suspect"):
        raise SystemExit("[handover] 감사 처분이 진행형이 아니다(%r) — 세션 판정을 쓰지 않는다(엔진이 재구현 경로로 갈 수 있음 · 세션 확인)" % act)
    eng = os.path.join(WDIR, "engine.R")
    ruling = {"action": act, "engine_md5": md5(eng), "by": "session", "at": dt.datetime.now().strftime("%Y-%m-%dT%H:%M:%S%z") or dt.datetime.now().isoformat(),
              "audit_file_md5": md5(os.path.join(WDIR, "fidelity_audit.json")), "audit_retries": tries,
              "decision": ("GPU 배분 일시정지 재개(도훈 10-18 '일시정지 + THGNN 메모리 수리 후 재개' · 판단 원장 J-20261018-008) — 감사 상충 아님 · "
                           "같은 엔진 · 같은 감사 파일의 기존 처분(재감사 %d회 뒤 %s)을 그대로 쓴다 · 감사 재구매 없음 · 엔진 보존 → THGNN 체크포인트 재개") % (tries, act)}
    log("세션 판정 = %s" % json.dumps(ruling, ensure_ascii=False))
    if dry:
        return ruling
    rq["audit_ruling"] = ruling
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(REQ), suffix=".tmp")
    with io.open(fd, "w", encoding="utf-8", newline="\n") as f:
        json.dump(rq, f, ensure_ascii=False, indent=1)
    os.replace(tmp, REQ)
    log("replication_request.json::audit_ruling 기록 완료(원자적 교체)")
    return ruling


def patch_lane(dry):
    with io.open(LANE_SH, "r", encoding="utf-8", newline="") as f:
        s = f.read()
    if "PYTORCH_CUDA_ALLOC_CONF" in s:
        log("레인 스크립트에 이미 PYTORCH_CUDA_ALLOC_CONF 가 있다 — 그대로 둔다")
        return False
    nl = "\r\n" if "\r\n" in s else "\n"
    if s.count(ANCHOR) != 1:
        raise SystemExit("[handover] 레인 스크립트 앵커(PY= 줄)가 정확히 1곳이 아니다 — 수정하지 않는다")
    new = s.replace(ANCHOR, ANCHOR + nl + EXPORT_LINE, 1)
    if dry:
        log("(건식) 레인 스크립트에 넣을 줄: %s" % EXPORT_LINE[:120])
        return True
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(LANE_SH), suffix=".tmp")
    with io.open(fd, "w", encoding="utf-8", newline="") as f:
        f.write(new)
    r = subprocess.run([qv_bash(), "-n", tmp.replace("\\", "/")], capture_output=True, text=True)
    if r.returncode != 0:
        os.remove(tmp)
        raise SystemExit("[handover] 수정본 bash -n 실패 — 원본 유지: %s" % r.stderr[-300:])
    os.replace(tmp, LANE_SH)
    log("레인 스크립트 수정 완료(PY= 줄 다음 1줄 · bash -n 통과) — 새 md5 %s" % md5(LANE_SH))
    return True


def handover(dry):
    log("== GPU 인계 시작%s ==" % (" (건식)" if dry else ""))
    if not os.path.exists(PREREG) and not dry:
        raise SystemExit("[handover] P2R05 사전등록 정본이 아직 없다 — 등록 · 커밋 뒤 인계")
    with io.open(CFG, "r", encoding="utf-8") as f:
        en = (json.load(f).get("replication_lane") or {}).get("enabled")
    if en is not False:
        raise SystemExit("[handover] 레인 스위치가 켜져 있다(%r) — 보류 상태에서만 인계(체인을 끝내면 다음 틱이 곧바로 재구현할 수 있음)" % en)
    st = ckpt_state()
    log("THGNN 체크포인트(인계 직전) = %s" % json.dumps(st, ensure_ascii=False))
    P = procs()
    top, chain = lane_top(P)
    log("THGNN 체인(아래→위): %s" % " ← ".join("%d" % c[0] for c in chain))
    if top is None:
        log("THGNN 체인 없음 — 이미 끝났거나 멈춤(끝낼 프로세스 없음)")
    elif dry:
        log("(건식) 끝낼 맨 위 레인 프로세스 = %d" % top)
    else:
        ck = os.path.join(WDIR, "_work", "thgnn_ckpt.pt")   # 체크포인트 저장 직후에 끝낸다(손실 최소 — 50스텝마다 · 에폭 끝 저장)
        if os.path.exists(ck):
            m0 = os.path.getmtime(ck); t0 = time.time()
            log("다음 체크포인트 저장 대기(최대 30분 · 지금 %s)" % dt.datetime.fromtimestamp(m0).strftime("%H:%M:%S"))
            while time.time() - t0 < 1800 and os.path.getmtime(ck) <= m0:
                time.sleep(5)
            time.sleep(5)   # os.replace 완료 여유
            log("체크포인트 저장 확인 %s → 끝낸다 · %s" % (dt.datetime.fromtimestamp(os.path.getmtime(ck)).strftime("%H:%M:%S"), json.dumps(ckpt_state(), ensure_ascii=False)))
        r = subprocess.run(["taskkill", "/T", "/F", "/PID", str(top)], capture_output=True, text=True, encoding="cp949", errors="replace")
        log("taskkill /T /F /PID %d → rc %d · %s" % (top, r.returncode, (r.stdout or r.stderr).strip().replace("\n", " | ")[:300]))
        t0 = time.time()
        while time.time() - t0 < 180:
            u = gpu_used()
            if 0 <= u < 2000:
                break
            time.sleep(5)
        log("GPU memory.used = %d MiB(%.0f초 뒤)" % (gpu_used(), time.time() - t0))
        left = [pid for pid in procs() if pid in dict(chain)]
        if left:
            raise SystemExit("[handover] 체인 프로세스가 남았다: %s" % left)
    write_ruling(dry)
    patch_lane(dry)
    log("== GPU 인계 끝 — 다음: P2R05 warm_cache.sh(GPU 게이트) · 레인 재개 = lane_hold_wait.sh 가 워밍 센티널 뒤 · THGNN 재개 확인(체크포인트 스텝 증가 · 공유 GPU 메모리) ==")


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a or a[0] != "handover":
        sys.exit("usage: gpu_handover.py handover [--dry]")
    handover("--dry" in a)
