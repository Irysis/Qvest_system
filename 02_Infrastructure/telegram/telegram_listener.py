#!/usr/bin/env python3
"""
Quant Module Moltbot — Telegram Remote Control Listener
========================================================
텔레그램으로 전략 실행 및 상태 조회 명령을 받아 처리합니다.

지원 명령어:
  /run STR_025           -- 해당 전략 백테스트 실행
  /status                -- 현재 실행 중인 전략 목록 + 완료 결과
  /stop_all              -- 실행 중인 모든 R 프로세스 종료
  /brief                 -- 현재까지 결과 브리핑 발송
  /queue STR_025,026     -- 여러 전략 순차 실행
  /list                  -- code_ready 전략 목록

실행 방법 (WSL):
  nohup python3 telegram_listener.py > /tmp/tg_listener.log 2>&1 &
  echo $! > /tmp/tg_listener.pid

중지:
  kill $(cat /tmp/tg_listener.pid)
"""

import os, json, subprocess, time, re, signal, sys
from datetime import datetime

# ── Credentials (.env 로드, hardcoded 금지 — 2026-04-17 rotation) ─────────────
BASE        = os.environ.get("QM_ROOT", "/mnt/g/Quant_Module_Moltbot")

def _load_env():
    env_path = f"{BASE}/.env"
    if os.path.exists(env_path):
        with open(env_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())

_load_env()
BOT_TOKEN   = os.environ.get("TG_BOT_TOKEN", "")
CHAT_ID     = os.environ.get("TG_PERSONAL_CHAT_ID", "1355291682")
CHANNEL_ID  = os.environ.get("TG_CHAT_ID", "")
if not BOT_TOKEN or not CHANNEL_ID:
    raise SystemExit("[telegram_listener] TG_BOT_TOKEN / TG_CHAT_ID 미설정. .env 확인.")
STRAT_DIR   = f"{BASE}/04_Research/strategies"
REGISTRY    = f"{BASE}/06_Registry/strategy_registry.json"
POLL_SECS   = 3
R_LIBS      = "~/R/libs"

# ── HTTP helpers ──────────────────────────────────────────────────────────────
def tg_api(method, **params):
    import urllib.request, urllib.parse
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/{method}"
    data = urllib.parse.urlencode(params).encode()
    try:
        with urllib.request.urlopen(url, data=data, timeout=10) as r:
            return json.loads(r.read())
    except Exception as e:
        print(f"[TG] API error: {e}", flush=True)
        return None

def send(text, channel=False):
    """Send HTML-formatted message. Default: personal DM only.
    channel=True for important results (Grade A, briefing) to broadcast."""
    tg_api("sendMessage", chat_id=CHAT_ID, text=text, parse_mode="HTML")
    if channel:
        tg_api("sendMessage", chat_id=CHANNEL_ID, text=text, parse_mode="HTML")
    dest = "User+Ch" if channel else "User"
    print(f"[TG → {dest}] {text[:100]}", flush=True)

# ── Command handlers ──────────────────────────────────────────────────────────
def handle_status():
    """Show running R processes and recent strategy results."""
    lines = []
    # Running processes
    try:
        out = subprocess.check_output(
            ["ps", "aux"], text=True, stderr=subprocess.DEVNULL
        )
        running = [l for l in out.splitlines() if "exec/R" in l or "Rscript" in l]
        if running:
            lines.append(f"<b>🔄 실행 중 ({len(running)})</b>")
            for l in running:
                # Extract strategy name from cmd
                m = re.search(r"STR_\d+_\w+", l)
                pid = l.split()[1]
                lines.append(f"  PID {pid}: {m.group() if m else '?'}")
        else:
            lines.append("✅ 실행 중인 R 프로세스 없음")
    except Exception as e:
        lines.append(f"[ps error: {e}]")

    # Recent results from disk (most recently modified hurdle_result.json)
    try:
        import glob
        hurdle_files = glob.glob(f"{STRAT_DIR}/*/output/hurdle_result.json")
        # Sort by modification time, newest first
        hurdle_files.sort(key=lambda f: os.path.getmtime(f), reverse=True)
        lines.append(f"\n<b>📊 테스트 완료 ({len(hurdle_files)}개)</b>")
        lines.append("<b>최근 5개:</b>")
        for hf in hurdle_files[:5]:
            try:
                with open(hf) as f:
                    hr = json.load(f)
                dir_nm = os.path.basename(os.path.dirname(os.path.dirname(hf)))
                m = re.match(r"(STR_\d+)", dir_nm)
                str_id = m.group(1) if m else "?"
                icon = "✅" if hr.get('pass') else "❌"
                sc = hr.get('total_score', 0) or 0
                cagr = hr.get('metrics', {}).get('CAGR', '?')
                lines.append(f"  {icon} {str_id} | {sc:.0f}/100 | CAGR {cagr}%")
            except:
                pass
    except Exception as e:
        lines.append(f"[disk scan error: {e}]")

    send("\n".join(lines))

def handle_run(args):
    """Run a single strategy by ID."""
    if not args:
        send("사용법: /run STR_025")
        return
    str_id = args.strip().upper()
    if not re.match(r"STR_\d+", str_id):
        send(f"잘못된 전략 ID: {str_id}")
        return

    # Find matching directory
    dirs = [d for d in os.listdir(STRAT_DIR) if d.upper().startswith(str_id)]
    if not dirs:
        send(f"❌ {str_id} 디렉토리를 찾을 수 없습니다")
        return
    strat_path = os.path.join(STRAT_DIR, dirs[0], "run_all.R")
    if not os.path.exists(strat_path):
        send(f"❌ run_all.R 없음: {dirs[0]}")
        return

    log_dir = os.path.join(STRAT_DIR, dirs[0], "output")
    os.makedirs(log_dir, exist_ok=True)
    log_path = os.path.join(log_dir, "run_remote.log")

    cmd = (
        f'nohup Rscript --no-save -e '
        f'".libPaths(c(\\\"~/R/libs\\\", .libPaths())); source(\\\"{strat_path}\\\")" '
        f'> "{log_path}" 2>&1 &'
    )
    subprocess.Popen(cmd, shell=True)
    send(f"🚀 <b>{str_id}</b> 백테스트 시작!\n로그: {log_path}")

def handle_queue(args):
    """Run multiple strategies sequentially."""
    if not args:
        send("사용법: /queue STR_025,STR_026")
        return
    ids = [x.strip().upper() for x in args.split(",")]
    send(f"📋 큐 시작: {', '.join(ids)}")
    # Build sequential shell commands
    cmds = []
    for str_id in ids:
        dirs = [d for d in os.listdir(STRAT_DIR) if d.upper().startswith(str_id)]
        if not dirs:
            send(f"⚠️ {str_id} 디렉토리 없음 — 건너뜁니다")
            continue
        strat_path = os.path.join(STRAT_DIR, dirs[0], "run_all.R")
        log_path = os.path.join(STRAT_DIR, dirs[0], "output", "run_remote.log")
        os.makedirs(os.path.dirname(log_path), exist_ok=True)
        run_cmd = (
            f'Rscript --no-save -e ".libPaths(c(\\\"~/R/libs\\\", .libPaths())); '
            f'source(\\\"{strat_path}\\\")" >> "{log_path}" 2>&1'
        )
        cmds.append(run_cmd)
    if cmds:
        full_cmd = " && ".join(cmds)
        subprocess.Popen(f"nohup bash -c '{full_cmd}' &", shell=True)

def handle_stop_all():
    """Kill all running R processes."""
    try:
        out = subprocess.check_output(
            ["ps", "aux"], text=True, stderr=subprocess.DEVNULL
        )
        killed = 0
        for line in out.splitlines():
            if "exec/R" in line or ("Rscript" in line and "grep" not in line):
                pid = int(line.split()[1])
                try:
                    os.kill(pid, signal.SIGTERM)
                    killed += 1
                except:
                    pass
        send(f"🛑 R 프로세스 {killed}개 종료 완료")
    except Exception as e:
        send(f"❌ stop_all 오류: {e}")

def handle_brief():
    """Send performance brief — disk-based scan for accuracy."""
    try:
        import glob
        hurdle_files = sorted(glob.glob(f"{STRAT_DIR}/*/output/hurdle_result.json"))
        passed = []; failed = []; grade_a = []

        for hf in hurdle_files:
            try:
                with open(hf) as f:
                    hr = json.load(f)
                # Extract strategy directory name from path (parent of parent)
                dir_name = os.path.basename(os.path.dirname(os.path.dirname(hf)))
                m = re.match(r"(STR_\d+)", dir_name)
                str_id = m.group(1) if m else dir_name
                metrics = hr.get('metrics', {})
                # Ensure fail_reasons is always a list of strings
                raw_reasons = hr.get('fail_reasons', [])
                if isinstance(raw_reasons, str):
                    raw_reasons = [raw_reasons] if raw_reasons else []
                elif isinstance(raw_reasons, list):
                    raw_reasons = [str(r) for r in raw_reasons]
                entry = {
                    'id': str_id,
                    'name': dir_name.replace(str_id + "_", "").replace("_", " "),
                    'pass': hr.get('pass', False),
                    'score': hr.get('total_score', 0) or 0,
                    'grade': hr.get('grade', ''),
                    'cagr': metrics.get('CAGR', '?'),
                    'sharpe': metrics.get('Sharpe', '?'),
                    'mdd': metrics.get('MDD', '?'),
                    'fail_reasons': raw_reasons
                }
                if entry['pass']:
                    passed.append(entry)
                    if entry['grade'] == 'A':
                        grade_a.append(entry)
                else:
                    failed.append(entry)
            except:
                pass

        passed.sort(key=lambda x: -x['score'])
        failed.sort(key=lambda x: -x['score'])

        msg = f"<b>📈 연구 현황 브리핑 — {datetime.now().strftime('%Y-%m-%d %H:%M')}</b>\n\n"
        msg += f"테스트: {len(hurdle_files)}개 | ✅ PASS: {len(passed)}개 | ❌ FAIL: {len(failed)}개\n"
        msg += f"⭐ Grade A: {len(grade_a)}개\n\n"

        if passed:
            msg += "<b>✅ 통과 전략:</b>\n"
            for s in passed:
                ga = " ⭐" if s['grade'] == 'A' else ""
                msg += (f"  {s['id']} {s['name']}{ga} | {s['score']:.0f}점\n"
                        f"    CAGR {s['cagr']}% | SR {s['sharpe']} | MDD {s['mdd']}%\n")

        if failed:
            msg += f"\n<b>🟡 근접 FAIL (상위 5):</b>\n"
            for s in failed[:5]:
                reason = ', '.join(s['fail_reasons'])[:45] if s['fail_reasons'] else ''
                msg += f"  {s['id']} | {s['score']:.0f}점 | {reason}\n"

        send(msg)
    except Exception as e:
        send(f"❌ 브리핑 오류: {e}")

def handle_refresh():
    """Run daily data refresh pipeline."""
    send("🔄 데이터 최신화 시작...")
    try:
        refresh_script = f"{BASE}/02_Infrastructure/daily_refresh.sh"
        log_path = f"/tmp/qm_refresh_{datetime.now().strftime('%Y%m%d_%H%M')}.log"
        subprocess.Popen(f'bash "{refresh_script}" > "{log_path}" 2>&1', shell=True)
        send(f"🔄 백그라운드 실행 중\n로그: {log_path}")
    except Exception as e:
        send(f"❌ 리프레시 오류: {e}")

def handle_grade_a():
    """Show all Grade A strategies with details."""
    try:
        import glob
        hurdle_files = glob.glob(f"{STRAT_DIR}/*/output/hurdle_result.json")
        grade_a = []
        for hf in hurdle_files:
            try:
                with open(hf) as f:
                    hr = json.load(f)
                if hr.get('grade') == 'A':
                    dir_nm = os.path.basename(os.path.dirname(os.path.dirname(hf)))
                    m = re.match(r"(STR_\d+)", dir_nm)
                    str_id = m.group(1) if m else "?"
                    metrics = hr.get('metrics', {})
                    grade_a.append({
                        'id': str_id,
                        'name': dir_nm.replace(str_id + "_", "").replace("_", " "),
                        'score': hr.get('total_score', 0) or 0,
                        'cagr': metrics.get('CAGR', '?'),
                        'sharpe': metrics.get('Sharpe', '?'),
                        'mdd': metrics.get('MDD', '?'),
                    })
            except:
                pass
        grade_a.sort(key=lambda x: -x['score'])
        if not grade_a:
            send("⭐ Grade A 전략 없음")
            return
        msg = f"<b>⭐ Grade A 전략 ({len(grade_a)}개)</b>\n\n"
        for i, s in enumerate(grade_a, 1):
            msg += (f"{i}. <b>{s['id']}</b> {s['name']}\n"
                    f"   Score {s['score']:.0f} | CAGR {s['cagr']}% | SR {s['sharpe']} | MDD {s['mdd']}%\n")
        send(msg)
    except Exception as e:
        send(f"❌ Grade A 조회 오류: {e}")

def handle_list():
    """List code_ready strategies."""
    try:
        with open(REGISTRY) as f:
            data = json.load(f)
        ready = [s for s in data if s.get('status') == 'code_ready']
        if not ready:
            send("📋 실행 대기 중인 전략 없음")
        else:
            lines = [f"<b>📋 실행 대기 전략 ({len(ready)}개)</b>"]
            for s in ready:
                lines.append(f"  {s['id']} | {s.get('name','')[:40]}")
            send("\n".join(lines))
    except Exception as e:
        send(f"❌ 목록 오류: {e}")

# ── QEPM Multi-Agent Commands ──────────────────────────────────────────────
DISPATCH_R = f"{BASE}/qepm/R/orchestration/skill_dispatch.R"
MAILBOX_R  = f"{BASE}/qepm/R/orchestration/agent_mailbox.R"

def _run_rscript(expr, timeout=120):
    """Run R expression and return stdout."""
    try:
        env = os.environ.copy()
        env["QEPM_PROJECT_ROOT"] = BASE
        result = subprocess.run(
            ["Rscript", "-e", expr],
            capture_output=True, text=True, timeout=timeout,
            cwd=BASE, env=env
        )
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return None
    except Exception as e:
        return f"R error: {e}"

def handle_regime():
    """국면 분석 — qepm-regime skill."""
    send("🌐 국면 분석 중...")
    out = _run_rscript(
        'source("02_Infrastructure/config.R"); '
        'source("02_Infrastructure/regime_signal.R"); '
        'dt <- build_regime_signal_table(); '
        'latest <- dt[nrow(dt),]; '
        'cat(sprintf("🌐 <b>현재 국면</b>\\n'
        'MRS Score: %s\\n'
        'Cross-Asset: TS=%s HY=%s VIX=%s (%d/3)\\n'
        '판정: %s\\n'
        '기준일: %s", '
        'round(latest$regime_score, 1), '
        'latest$TS_Signal, latest$HY_Signal, latest$VIX_Signal, '
        'sum(c(latest$TS_Signal, latest$HY_Signal, latest$VIX_Signal)==1, na.rm=TRUE), '
        'ifelse(latest$regime_score >= 30, "RISK_OFF", '
        'ifelse(latest$regime_score >= 15, "CAUTION", "RISK_ON")), '
        'latest$Date))'
    )
    if out:
        send(out)
    else:
        send("🌐 국면 조회 실패 (timeout)")

def handle_allocation():
    """현재 목표 배분."""
    send("⚖️ 배분 계산 중...")
    out = _run_rscript(
        'library(yaml); '
        'cfg <- read_yaml("config/dynamic_alloc_config.yaml"); '
        'w <- cfg$regime_weight_map$RISK_ON; '
        'lines <- sapply(names(w), function(s) sprintf("  %s: %.0f%%", s, w[[s]]*100)); '
        'cat(paste(c("⚖️ <b>현재 목표 배분 (RISK_ON)</b>", "", lines, "", '
        '"국면별 배분:", '
        'sprintf("  CAUTION: Defense %.0f%%", cfg$regime_weight_map$CAUTION$defense*100), '
        'sprintf("  RISK_OFF: Defense %.0f%%", cfg$regime_weight_map$RISK_OFF$defense*100)), '
        'collapse="\\n"))'
    )
    if out:
        send(out)
    else:
        send("⚖️ 배분 조회 실패")

def handle_memory():
    """메모리 파이프라인 현황."""
    out = _run_rscript(
        'memory_base <- file.path("'+ BASE +'", "memory"); '
        'layers <- c("raw_artifacts","episodes","families","evidence",'
        '"regime_payoff","portfolio_policy","post_trade"); '
        'counts <- sapply(layers, function(l) { '
        '  d <- file.path(memory_base, l); '
        '  if (dir.exists(d)) length(list.files(d)) else 0 }); '
        'cat(paste(c("💾 <b>메모리 파이프라인</b>", "", '
        'sprintf("R0 Raw: %d", counts[1]), '
        'sprintf("R1 Digest: %d", counts[2]), '
        'sprintf("R2 Family: %d", counts[3]), '
        'sprintf("R3 Evidence: %d", counts[4]), '
        'sprintf("R4 Regime Payoff: %d", counts[5]), '
        'sprintf("R5 Portfolio Policy: %d", counts[6]), '
        'sprintf("R6 Post-Trade: %d", counts[7])), '
        'collapse="\\n"))'
    )
    if out:
        send(out)
    else:
        send("💾 메모리 조회 실패")

def handle_backlog():
    """연구 백로그 현황."""
    backlog_file = f"{BASE}/qepm/registry/backlog.json"
    try:
        if not os.path.exists(backlog_file):
            send("📝 백로그: 비어있음")
            return
        with open(backlog_file) as f:
            bl = json.load(f)
        if not bl:
            send("📝 백로그: 비어있음")
            return
        bl.sort(key=lambda x: -(x.get('priority_score') or 0))
        lines = [f"📝 <b>연구 백로그 ({len(bl)}개)</b>", ""]
        for i, item in enumerate(bl[:10], 1):
            fam = item.get('task_family', '?')
            obj = (item.get('objective', '') or '')[:40]
            pri = item.get('priority_score', 0) or 0
            lines.append(f"{i}. [{fam}] {obj} (P:{pri:.2f})")
        send("\n".join(lines))
    except Exception as e:
        send(f"📝 백로그 오류: {e}")

def handle_research(args):
    """리서치 시작 — backlog에서 디스패치 or 새 과제 등록."""
    args = args.strip() if args else ""

    if not args or args.isdigit():
        # /research 또는 /research 3 → backlog에서 N개 디스패치
        n = int(args) if args.isdigit() else 1
        send(f"🔬 백로그에서 {n}개 디스패치 중...")
        out = _run_rscript(
            f'source("qepm/R/orchestration/skill_dispatch.R"); '
            f'results <- dispatch_batch({n}); '
            f'n_ok <- sum(sapply(results, function(r) isTRUE(r$success))); '
            f'n_fail <- length(results) - n_ok; '
            f'cat(sprintf("🔬 디스패치 완료: %d개 (성공 %d / 실패 %d)", '
            f'length(results), n_ok, n_fail))',
            timeout=300
        )
        if out:
            send(out)
        else:
            send("🔬 디스패치 timeout (300초)")
        return

    # /research add <family> <objective> → 백로그에 새 과제 추가
    if args.startswith("add "):
        parts = args[4:].strip().split(" ", 1)
        family = parts[0] if parts else "general"
        objective = parts[1] if len(parts) > 1 else "Research task"
        out = _run_rscript(
            f'source("02_Infrastructure/config.R"); '
            f'source("qepm/R/utils/common.R"); '
            f'source("qepm/R/orchestration/backlog.R"); '
            f'backlog_add(objective="{objective}", task_family="{family}"); '
            f'cat("📝 백로그에 추가 완료: [{family}] {objective}")'
        )
        send(out or "📝 백로그 추가 실패")
        return

    # /research run STR_XXX → 특정 전략 직접 실행
    if args.upper().startswith("RUN "):
        str_id = args[4:].strip()
        handle_run(str_id)
        return

    send("🔬 <b>연구 명령어</b>\n"
         "/research — 백로그 1개 디스패치\n"
         "/research 3 — 백로그 3개 디스패치\n"
         "/research add Defense \"IdioVol 변형 실험\" — 과제 등록\n"
         "/research run STR_710 — 특정 전략 실행")

def handle_dispatch_status():
    """에이전트 메일박스 현황."""
    out = _run_rscript(
        'source("qepm/R/orchestration/agent_mailbox.R"); '
        'st <- mailbox_status(); '
        'lines <- c("📬 <b>에이전트 메일박스</b>", ""); '
        'for (agent in names(st)) { '
        '  s <- st[[agent]]; '
        '  icon <- if (s$inbox_pending > 0) "🔴" else "🟢"; '
        '  lines <- c(lines, sprintf("%s %s: 대기 %d | 총 in:%d out:%d", '
        '    icon, agent, s$inbox_pending, s$inbox_total, s$outbox_total)) }; '
        'cat(paste(lines, collapse="\\n"))'
    )
    if out:
        send(out)
    else:
        send("📬 메일박스 조회 실패")

def handle_perpetual(args):
    """무한 자율 리서치 엔진 — 목표 달성까지 자동 실행."""
    args = args.strip() if args else ""
    max_cycles = int(args) if args.isdigit() else 20

    send(f"🔄 <b>Perpetual Engine 시작</b>\n"
         f"최대 {max_cycles} 사이클 | 목표: Sharpe 2.0+, MDD &lt;25%\n"
         f"진행 상황은 5사이클마다 보고합니다.")

    out = _run_rscript(
        'source("02_Infrastructure/config.R"); '
        'source("qepm/R/utils/common.R"); '
        'source("qepm/R/memory/r0_raw.R"); '
        'source("qepm/R/orchestration/state_machine.R"); '
        'tryCatch(source("qepm/scripts/hybrid_mode.R"), error=function(e) NULL); '
        f'result <- orch_perpetual_engine(max_cycles={max_cycles}, pause_between=3, notify_every=5); '
        'cat(sprintf("Perpetual 완료: %d cycles (%d OK, %d Grade A)", '
        'result$cycles_run, result$cycles_success, result$grade_a_found))',
        timeout=600
    )
    if out:
        send(f"🏁 {out}")
    else:
        send("🔄 Perpetual Engine timeout (10분). 백그라운드에서 계속 실행 중일 수 있습니다.")

def handle_targets():
    """현재 목표 대비 진행 상태."""
    out = _run_rscript(
        'source("02_Infrastructure/config.R"); '
        'source("qepm/R/utils/common.R"); '
        'source("qepm/R/orchestration/state_machine.R"); '
        't <- orch_check_targets(); '
        'cat(sprintf("🎯 <b>목표 달성 현황</b>\\n\\n'
        'Sharpe: %.3f / 2.000 (%s)\\n'
        'MDD: %.1f%% / 25.0%% (%s)\\n'
        'CAGR: %.1f%% / 16.0%% (%s)\\n\\n'
        '종합: %s", '
        't$best$sharpe, ifelse(t$gaps$sharpe<=0, "✅", sprintf("❌ +%.3f 필요", t$gaps$sharpe)), '
        'abs(t$best$mdd)*100, ifelse(t$gaps$mdd<=0, "✅", sprintf("❌ -%.1f%%p 필요", t$gaps$mdd*100)), '
        't$best$cagr*100, ifelse(t$gaps$cagr<=0, "✅", sprintf("❌ +%.1f%%p 필요", t$gaps$cagr*100)), '
        'ifelse(t$met, "🎉 전체 목표 달성!", "⏳ 아직 달성 안됨")))'
    )
    if out:
        send(out)
    else:
        send("🎯 목표 상태 조회 실패")

def handle_agents(args):
    """에이전트에게 직접 태스크 전송."""
    args = args.strip() if args else ""
    if not args:
        send("🤖 <b>에이전트 명령어</b>\n"
             "/agent forge backtest STR_654 — Forge에게 백테스트 지시\n"
             "/agent judge verify STR_654 — Judge에게 검증 지시\n"
             "/agent scout search momentum — Scout에게 문헌 조사 지시\n"
             "/agent watch regime — Watch에게 국면 확인 지시\n"
             "/agent status — 메일박스 현황")
        return

    if args == "status":
        handle_dispatch_status()
        return

    parts = args.split(" ", 2)
    if len(parts) < 2:
        send("사용법: /agent <agent> <task> [detail]")
        return

    agent = parts[0].lower()
    task = parts[1]
    detail = parts[2] if len(parts) > 2 else ""
    valid_agents = ["scout", "forge", "judge", "blender", "watch"]

    if agent not in valid_agents:
        send(f"❌ 알 수 없는 에이전트: {agent}\n가능: {', '.join(valid_agents)}")
        return

    # Map task to skill
    task_skill_map = {
        "backtest": ("qepm-backtest", "run"),
        "verify":   ("qepm-stat-defense", "run"),
        "hurdle":   ("qepm-hurdle", "run"),
        "regime":   ("qepm-regime", "classify"),
        "search":   ("qepm-lawbook", "search"),
        "optimize": ("qepm-optimize", "run"),
        "briefing": ("qepm-briefing", "full"),
        "memory":   ("qepm-memory", "status"),
        "diversity":("qepm-diversity", "check"),
    }

    if task not in task_skill_map:
        send(f"❌ 알 수 없는 태스크: {task}\n"
             f"가능: {', '.join(task_skill_map.keys())}")
        return

    skill, subcmd = task_skill_map[task]
    body_json = json.dumps({"skill": skill, "subcmd": subcmd,
                            "inputs": {"query": detail} if detail else {}})
    body_escaped = body_json.replace('"', '\\"')

    send(f"🤖 {agent}에게 {task} 지시 전송 중...")
    out = _run_rscript(
        f'source("qepm/R/orchestration/agent_mailbox.R"); '
        f'library(jsonlite); '
        f'body <- fromJSON(\'{body_json}\', simplifyVector=FALSE); '
        f'mid <- mailbox_send(to="{agent}", from="q_lead", type="task", '
        f'  subject="{task} {detail}", body=body, priority=0.9); '
        f'cat(sprintf("✅ {agent}에게 전송 완료 (ID: %s)", mid))'
    )
    send(out or f"❌ {agent} 전송 실패")

# ── Free-text auto-response ──────────────────────────────────────────────────
def handle_freetext(text):
    """한국어 자유 텍스트 질문에 자동 응답. 응답 가능하면 문자열, 아니면 None."""
    text_lower = text.lower()
    keywords = text_lower + " " + text  # 한글+영어 검색

    # ── 1. 실행 상태 질문 ──
    if any(k in keywords for k in ["실행", "돌아가", "코드", "진행", "running", "큐"]):
        return _auto_status()

    # ── 2. 전략 결과 / 성과 질문 ──
    if any(k in keywords for k in ["결과", "성과", "pass", "fail", "통과", "점수", "score"]):
        return _auto_results()

    # ── 3. 현재 몇개 / 진행률 ──
    if any(k in keywords for k in ["몇개", "몇 개", "진행률", "현황", "상황"]):
        return _auto_progress()

    # ── 4. 전략 방향 / 계획 ──
    if any(k in keywords for k in ["방향", "계획", "다음", "앞으로", "전략 구성"]):
        return _auto_direction()

    # ── 5. 특정 전략 질문 (STR_XXX) ──
    m = re.search(r"STR_(\d+)", text, re.IGNORECASE)
    if m:
        return _auto_strategy_detail(f"STR_{m.group(1)}")

    # ── 6. 데이터/리프레시 관련 ──
    if any(k in keywords for k in ["데이터", "최신", "업데이트", "리프레시", "refresh", "캐시"]):
        return _auto_data_status()

    # ── 7. 인사/안부 ──
    if any(k in keywords for k in ["안녕", "ㅎㅇ", "hi", "hello", "잘", "뭐해", "어때"]):
        return _auto_greeting()

    # ── 8. 마지막 fallback — 키워드 기반 광범위 응답 ──
    if any(k in keywords for k in ["왜", "어떻게", "뭐", "알려", "설명", "도움"]):
        return ("🤖 자동 응답 범위 밖의 질문이에요.\n"
                "Claude 세션에서 더 자세히 답변드릴게요!\n\n"
                "사용 가능 명령어:\n"
                "/status /brief /grade_a /refresh /help")

    return None  # 자동 응답 불가 → inbox 저장

def _auto_status():
    """현재 R 프로세스 상태."""
    try:
        out = subprocess.check_output(["ps", "aux"], text=True, stderr=subprocess.DEVNULL)
        r_procs = [l for l in out.splitlines() if "exec/R" in l or ("Rscript" in l and "grep" not in l)]
        if r_procs:
            strats = []
            for l in r_procs:
                m = re.search(r"STR_\d+_\w+", l)
                pid = l.split()[1]
                strats.append(f"  PID {pid}: {m.group() if m else '알 수 없음'}")
            return f"🔄 <b>실행 중 ({len(r_procs)}개)</b>\n" + "\n".join(strats)
        else:
            # 큐 프로세스 확인
            queue_procs = [l for l in out.splitlines() if "rerun_g" in l or "q4" in l or "q3" in l]
            if queue_procs:
                return f"🔄 큐 스크립트 {len(queue_procs)}개 실행 중 (R 대기/완료 상태)"
            return "✅ 현재 실행 중인 R 프로세스 없음"
    except:
        return "⚠️ 프로세스 상태 확인 실패"

def _auto_results():
    """PASS/FAIL 요약 — disk-based."""
    try:
        import glob
        hurdle_files = glob.glob(f"{STRAT_DIR}/*/output/hurdle_result.json")
        passed = []; all_tested = []
        for hf in hurdle_files:
            try:
                with open(hf) as f:
                    hr = json.load(f)
                dir_nm = os.path.basename(os.path.dirname(os.path.dirname(hf)))
                m = re.match(r"(STR_\d+)", dir_nm)
                str_id = m.group(1) if m else "?"
                score = hr.get('total_score', 0) or 0
                entry = {'id': str_id, 'pass': hr.get('pass', False), 'score': score,
                         'grade': hr.get('grade', ''), 'cagr': hr.get('metrics',{}).get('CAGR','?')}
                all_tested.append(entry)
                if entry['pass']:
                    passed.append(entry)
            except:
                pass

        passed.sort(key=lambda x: -x['score'])
        msg = f"<b>📊 전략 결과 요약</b>\n테스트: {len(all_tested)}개 | ✅ PASS: {len(passed)}개\n"
        if passed:
            msg += "\n<b>PASS 전략:</b>\n"
            for s in passed:
                ga = " ⭐" if s['grade'] == 'A' else ""
                msg += f"  ✅ {s['id']}{ga}: {s['score']:.0f}점 (CAGR {s['cagr']}%)\n"
        # 상위 FAIL 3
        failed = sorted([s for s in all_tested if not s['pass']], key=lambda x: -x['score'])[:3]
        if failed:
            msg += "\n<b>근접 FAIL (상위 3):</b>\n"
            for s in failed:
                msg += f"  🟡 {s['id']}: {s['score']:.0f}점\n"
        return msg
    except Exception as e:
        return f"⚠️ 결과 조회 오류: {e}"

def _auto_progress():
    """전체 진행률."""
    try:
        with open(REGISTRY) as f:
            data = json.load(f)
        n_total = len(data)
        tested = len([s for s in data if s.get('status', '').startswith('tested')])
        code_ready = len([s for s in data if s.get('status') == 'code_ready'])
        pending = len([s for s in data if s.get('status') == 'pending'])
        passed = len([s for s in data if s.get('hurdle_pass')])

        # 실제 hurdle_result.json 파일 수 세기
        import glob
        actual_tested = len(glob.glob(f"{STRAT_DIR}/*/output/hurdle_result.json"))

        msg = (f"<b>📈 진행 현황</b>\n"
               f"전체 전략: {n_total}개\n"
               f"백테스트 완료: {actual_tested}개 (레지스트리: {tested}개)\n"
               f"코드 준비: {code_ready}개\n"
               f"대기중: {pending}개\n"
               f"✅ 허들 통과: {passed}개\n"
               f"진행률: {actual_tested}/{n_total} ({actual_tested/n_total*100:.0f}%)")
        return msg
    except Exception as e:
        return f"⚠️ 진행률 조회 오류: {e}"

def _auto_direction():
    """현재 연구 방향 — 디스크 기반 동적 생성."""
    try:
        import glob
        hurdle_files = glob.glob(f"{STRAT_DIR}/*/output/hurdle_result.json")
        n_tested = len(hurdle_files)
        n_pass = 0; grade_a = 0; best_score = 0
        for hf in hurdle_files:
            try:
                with open(hf) as f:
                    hr = json.load(f)
                if hr.get('pass'):
                    n_pass += 1
                    if hr.get('grade') == 'A':
                        grade_a += 1
                    sc = hr.get('total_score', 0) or 0
                    if sc > best_score:
                        best_score = sc
            except:
                pass
        return (
            f"<b>🧭 현재 연구 방향</b>\n"
            f"📊 테스트 완료: {n_tested}개 | ✅ PASS: {n_pass}개 | ⭐ Grade A: {grade_a}개\n\n"
            f"<b>현재 단계:</b>\n"
            f"1️⃣ 237개 논문 기반 단일 팩터 전략 + 앙상블 전략 완료\n"
            f"2️⃣ 가격 팩터 변형 탐색 완료 (IdioVol 유일한 방어 팩터 확인)\n"
            f"3️⃣ 파라미터 변형 실험 완료 (쿨다운/집중도/BZ 최적화)\n\n"
            f"<b>다음 방향:</b>\n"
            f"🔬 펀더멘털 팩터(DART) 결합 탐색\n"
            f"🔬 앙상블 재설계 (PASS 전략 기반)\n"
            f"🎯 목표: Grade A 5개 달성 (현재 {grade_a}개)"
        )
    except Exception as e:
        return f"⚠️ 방향 조회 오류: {e}"

def _auto_data_status():
    """데이터 최신 상태."""
    try:
        cache_dir = f"{BASE}/.cache"
        files = {
            'RAWDATA': 'RAWDATA.parquet',
            'DART': 'fundamental_dart.parquet',
            'FRED': 'macro_regime.parquet',
            'Benchmark': 'benchmark.parquet',
        }
        msg = "<b>📦 데이터 캐시 현황</b>\n"
        for name, fname in files.items():
            fp = os.path.join(cache_dir, fname)
            if os.path.exists(fp):
                mtime = datetime.fromtimestamp(os.path.getmtime(fp))
                size_mb = os.path.getsize(fp) / (1024*1024)
                msg += f"  {name}: {mtime.strftime('%m/%d %H:%M')} ({size_mb:.0f}MB)\n"
            else:
                msg += f"  {name}: ❌ 없음\n"
        msg += f"\n💡 /refresh 로 최신화 가능"
        return msg
    except Exception as e:
        return f"⚠️ 데이터 상태 조회 오류: {e}"

def _auto_greeting():
    """인사 자동응답."""
    try:
        import glob
        hurdle_files = glob.glob(f"{STRAT_DIR}/*/output/hurdle_result.json")
        n_a = sum(1 for hf in hurdle_files if json.load(open(hf)).get('grade') == 'A')
        # Running processes
        out = subprocess.check_output(["ps", "aux"], text=True, stderr=subprocess.DEVNULL)
        r_procs = len([l for l in out.splitlines() if "exec/R" in l or ("Rscript" in l and "grep" not in l)])

        msg = f"🤖 Q 보고드립니다!\n\n"
        msg += f"⭐ Grade A: {n_a}개 | 테스트 완료: {len(hurdle_files)}개\n"
        if r_procs > 0:
            msg += f"🔄 현재 R 프로세스 {r_procs}개 실행 중\n"
        else:
            msg += f"✅ 현재 대기 상태\n"
        msg += f"\n명령어: /status /brief /grade_a /refresh"
        return msg
    except:
        return "🤖 Q 보고드립니다! /help 명령어를 참고해주세요."

def _auto_strategy_detail(str_id):
    """특정 전략 상세."""
    try:
        # 레지스트리에서 찾기
        with open(REGISTRY) as f:
            data = json.load(f)
        match = [s for s in data if s.get('id') == str_id]
        if not match:
            return f"❓ {str_id} 레지스트리에 없음"
        s = match[0]
        msg = f"<b>📋 {str_id}</b> {s.get('name','')}\n"
        msg += f"상태: {s.get('status','?')}\n"
        if s.get('hurdle_score') is not None:
            icon = "✅" if s.get('hurdle_pass') else "❌"
            msg += f"{icon} 점수: {s.get('hurdle_score',0):.1f}/100\n"
            if s.get('cagr'): msg += f"CAGR: {s['cagr']}%\n"
            if s.get('sharpe'): msg += f"Sharpe: {s['sharpe']}\n"
            if s.get('mdd'): msg += f"MDD: {s['mdd']}%\n"
        else:
            msg += "아직 테스트되지 않음\n"

        # hurdle_result.json 확인
        import glob
        hrs = glob.glob(f"{STRAT_DIR}/{str_id}*/output/hurdle_result.json")
        if hrs:
            with open(hrs[0]) as f:
                hr = json.load(f)
            m = hr.get('metrics', {})
            msg += f"\n<b>상세 지표:</b>\n"
            for k in ['CAGR', 'Sharpe', 'MDD', 'IR', 'Calmar']:
                if k in m:
                    msg += f"  {k}: {m[k]}\n"
        return msg
    except Exception as e:
        return f"⚠️ {str_id} 조회 오류: {e}"

# ── Main polling loop ─────────────────────────────────────────────────────────
def main():
    print(f"[Listener] 시작됨 @ {datetime.now()}", flush=True)
    send(f"🤖 <b>QEPM Listener v2 시작</b>\n"
         f"/help 로 전체 명령어 확인\n"
         f"핵심: /brief /research /regime /agent")

    last_update_id = 0
    # Get current offset
    res = tg_api("getUpdates", offset=-1, limit=1, timeout=1)
    if res and res.get("result"):
        last_update_id = res["result"][-1]["update_id"] + 1

    while True:
        try:
            res = tg_api("getUpdates", offset=last_update_id, limit=10, timeout=POLL_SECS)
            if not res or not res.get("ok"):
                time.sleep(POLL_SECS)
                continue

            for upd in res.get("result", []):
                last_update_id = upd["update_id"] + 1
                msg = upd.get("message", {})
                text = msg.get("text", "").strip()
                chat = msg.get("chat", {}).get("id")

                if str(chat) != CHAT_ID:
                    continue

                print(f"[Cmd] {text}", flush=True)

                if text.startswith("/status"):
                    handle_status()
                elif text.startswith("/run "):
                    handle_run(text[5:])
                elif text.startswith("/queue "):
                    handle_queue(text[7:])
                elif text.startswith("/stop_all"):
                    handle_stop_all()
                elif text.startswith("/brief"):
                    handle_brief()
                elif text.startswith("/list"):
                    handle_list()
                elif text.startswith("/refresh"):
                    handle_refresh()
                elif text.startswith("/grade_a"):
                    handle_grade_a()
                # ── QEPM Multi-Agent Commands ──
                elif text.startswith("/regime"):
                    handle_regime()
                elif text.startswith("/allocation"):
                    handle_allocation()
                elif text.startswith("/memory"):
                    handle_memory()
                elif text.startswith("/backlog"):
                    handle_backlog()
                elif text.startswith("/perpetual"):
                    handle_perpetual(text[10:].strip())
                elif text.startswith("/targets"):
                    handle_targets()
                elif text.startswith("/research"):
                    handle_research(text[9:].strip())
                elif text.startswith("/agent"):
                    handle_agents(text[6:].strip())
                elif text.startswith("/mailbox"):
                    handle_dispatch_status()
                elif text.startswith("/help"):
                    send("📖 <b>QEPM 명령어</b>\n"
                         "\n<b>📊 조회</b>\n"
                         "/status — 시스템 상태\n"
                         "/regime — 국면 분석\n"
                         "/allocation — 목표 배분\n"
                         "/memory — 메모리 파이프라인\n"
                         "/grade_a — Grade A 전략\n"
                         "/brief — 전체 브리핑\n"
                         "\n<b>🔬 연구</b>\n"
                         "/research — 백로그 1개 실행\n"
                         "/research 3 — 백로그 3개 실행\n"
                         "/research add Family 목표 — 과제 등록\n"
                         "/backlog — 연구 백로그 현황\n"
                         "/perpetual — 목표 달성까지 무한 자율 리서치\n"
                         "/perpetual 50 — 최대 50사이클 무한 리서치\n"
                         "/targets — 현재 목표 달성 현황\n"
                         "\n<b>🤖 에이전트</b>\n"
                         "/agent forge backtest STR_654\n"
                         "/agent judge verify STR_654\n"
                         "/agent status — 메일박스 현황\n"
                         "\n<b>⚙️ 실행</b>\n"
                         "/run STR_025 — 전략 실행\n"
                         "/queue STR_025,026 — 순차 실행\n"
                         "/refresh — 데이터 최신화\n"
                         "/stop_all — 모든 R 중단")
                else:
                    # Unknown command or free text
                    if text.startswith("/"):
                        send(f"❓ 알 수 없는 명령어. /help 참고")
                    elif text:
                        # Free-text → 자동 응답 시도, 실패시 inbox 저장
                        auto_reply = handle_freetext(text)
                        if auto_reply:
                            send(auto_reply, channel=False)
                        else:
                            inbox_path = "/tmp/tg_inbox.txt"
                            ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                            with open(inbox_path, "a", encoding="utf-8") as f:
                                f.write(f"[{ts}] {text}\n")
                            send(f"📬 Claude에게 전달 완료! 2분 내 답변드릴게요.\n"
                                 f"<i>'{text[:60]}'</i>", channel=False)

        except KeyboardInterrupt:
            print("[Listener] 종료", flush=True)
            send("🔴 Quant Listener 종료됨")
            break
        except Exception as e:
            print(f"[Listener] 오류: {e}", flush=True)
            time.sleep(5)


if __name__ == "__main__":
    main()
