#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generate High-Quality Architecture Diagrams for Codyssey B4-1
Outputs:
1. docs/images/architecture_system_overview.png
2. docs/images/architecture_security_acl.png
3. docs/images/architecture_monitor_flow.png
"""

import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as patches

# 폰트 설정 (Windows 한글 폰트 적용)
plt.rcParams['font.family'] = 'Malgun Gothic'
plt.rcParams['axes.unicode_minus'] = False

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "docs", "images")
os.makedirs(OUTPUT_DIR, exist_ok=True)

# ------------------------------------------------------------------------------
# 1. 전체 시스템 및 네트워크 보안 인프라 아키텍처 다이어그램
# ------------------------------------------------------------------------------
def draw_system_overview():
    fig, ax = plt.subplots(figsize=(16, 10), dpi=300)
    fig.patch.set_facecolor('#0f172a') # Dark modern slate background
    ax.set_facecolor('#0f172a')

    # 메인 타이틀
    ax.text(0.5, 0.95, "[Codyssey B4-1] 전체 시스템 및 네트워크 보안 인프라 아키텍처", 
            fontsize=20, weight='bold', color='#f8fafc', ha='center', va='top')
    ax.text(0.5, 0.915, "네트워크 방화벽 격리 | 다중 사용자 권한 체계 | 5단계 부팅 시퀀스 | 순수 Bash 무중단 관제", 
            fontsize=12, color='#94a3b8', ha='center', va='top')

    # 구역 1: 외부 인터넷 영역 (왼쪽)
    box_ext = patches.FancyBboxPatch((0.03, 0.12), 0.20, 0.74, boxstyle="round,pad=0.02,rounding_size=0.03",
                                    facecolor='#1e293b', edgecolor='#334155', linewidth=2)
    ax.add_patch(box_ext)
    ax.text(0.13, 0.83, "[ZONE 1] 외부 인터넷 영역", fontsize=13, weight='bold', color='#38bdf8', ha='center')

    # 외부 액터들
    actors = [
        ("자동화 봇넷 / 해커\n(22번 포트 무작위 공격)", "#f43f5e", 0.68),
        ("시스템 관리자\n(agent-admin / agent-dev)", "#10b981", 0.47),
        ("일반 서비스 사용자\n(Web / App Client)", "#a855f7", 0.26)
    ]
    for text, color, y in actors:
        actor_box = patches.FancyBboxPatch((0.05, y - 0.06), 0.16, 0.12, boxstyle="round,pad=0.015,rounding_size=0.02",
                                          facecolor='#0f172a', edgecolor=color, linewidth=1.8)
        ax.add_patch(actor_box)
        ax.text(0.13, y, text, fontsize=10.5, color='#f1f5f9', ha='center', va='center', weight='bold')

    # 구역 2: UFW 방화벽 레이어 (중앙 왼쪽)
    box_fw = patches.FancyBboxPatch((0.27, 0.12), 0.18, 0.74, boxstyle="round,pad=0.02,rounding_size=0.03",
                                   facecolor='#1e1b4b', edgecolor='#6366f1', linewidth=2.5, linestyle='--')
    ax.add_patch(box_fw)
    ax.text(0.36, 0.83, "[ZONE 2] UFW 방화벽\n(Default Deny)", fontsize=13, weight='bold', color='#818cf8', ha='center')

    fw_rules = [
        ("[DROP] Port 22\n(기본 SSH 전면 차단)", "#ef4444", 0.68),
        ("[ALLOW] Port 20022/tcp\n(관리자 SSH 허용)", "#22c55e", 0.47),
        ("[ALLOW] Port 15034/tcp\n(앱 서비스 허용)", "#22c55e", 0.26)
    ]
    for text, color, y in fw_rules:
        rbox = patches.FancyBboxPatch((0.285, y - 0.055), 0.15, 0.11, boxstyle="round,pad=0.01,rounding_size=0.015",
                                      facecolor='#0f172a', edgecolor=color, linewidth=1.5)
        ax.add_patch(rbox)
        ax.text(0.36, y, text, fontsize=10, color='#f8fafc', ha='center', va='center', weight='bold')

    # 구역 3: Ubuntu 22.04 LTS 호스트 내부 (중앙 오른쪽 & 오른쪽)
    box_host = patches.FancyBboxPatch((0.48, 0.08), 0.49, 0.78, boxstyle="round,pad=0.02,rounding_size=0.03",
                                     facecolor='#1e293b', edgecolor='#475569', linewidth=2)
    ax.add_patch(box_host)
    ax.text(0.725, 0.83, "[ZONE 3] Ubuntu 22.04 LTS 서버 내부 (Linux Host)", fontsize=13.5, weight='bold', color='#facc15', ha='center')

    # 3-1: OpenSSH 서비스
    ssh_box = patches.FancyBboxPatch((0.51, 0.58), 0.43, 0.18, boxstyle="round,pad=0.015,rounding_size=0.02",
                                    facecolor='#0f172a', edgecolor='#38bdf8', linewidth=1.8)
    ax.add_patch(ssh_box)
    ax.text(0.53, 0.72, "[Service 1] OpenSSH Daemon (sshd)", fontsize=12, weight='bold', color='#38bdf8', va='top')
    ax.text(0.53, 0.64, "• 커스텀 리슨 포트: TCP 20022\n• 루트 원격 로그인 차단: PermitRootLogin no\n• 접속 권한: 일반 계정(agent-admin/dev)만 인증 허용",
            fontsize=9.5, color='#cbd5e1', va='center')

    # 3-2: Agent Application 서비스
    app_box = patches.FancyBboxPatch((0.51, 0.35), 0.43, 0.20, boxstyle="round,pad=0.015,rounding_size=0.02",
                                    facecolor='#0f172a', edgecolor='#10b981', linewidth=1.8)
    ax.add_patch(app_box)
    ax.text(0.53, 0.51, "[Service 2] Python App (agent_app.py)", fontsize=12, weight='bold', color='#34d399', va='top')
    ax.text(0.53, 0.42, "• 리슨 바인딩: 0.0.0.0:15034 (LISTEN)\n• 실행 정책: 일반 계정 전용 (루트 실행 시 즉시 중단)\n• 5단계 Boot Sequence: 환경변수 -> 비밀키 -> 업로드 -> 로그 -> 포트 [OK]\n• 정상 기동 완료 신호: 'Agent READY' 출력",
            fontsize=9.5, color='#cbd5e1', va='center')

    # 3-3: crontab & monitor.sh 관제 레이어
    mon_box = patches.FancyBboxPatch((0.51, 0.11), 0.43, 0.21, boxstyle="round,pad=0.015,rounding_size=0.02",
                                    facecolor='#0f172a', edgecolor='#f59e0b', linewidth=1.8)
    ax.add_patch(mon_box)
    ax.text(0.53, 0.28, "[Automation] crontab + monitor.sh (Pure Bash)", fontsize=12, weight='bold', color='#fbbf24', va='top')
    ax.text(0.53, 0.19, "• cron 주기: agent-admin 계정으로 매분(* * * * *) 자동 실행\n• Health Check: 프로세스 및 포트(15034) 검사 (실패 시 exit 1)\n• 상태 및 자원 수집: 방화벽 상태, CPU(>20%), MEM(>10%), DISK(>80%) 경고\n• 로그 및 로테이션: /var/log/agent-app/monitor.log (최대 10MB x 10개 파일)",
            fontsize=9.5, color='#cbd5e1', va='center')

    # 연결 화살표 (트래픽 흐름)
    arrow_style = dict(arrowstyle="->", lw=2, mutation_scale=15)
    # 봇넷 -> 포트 22 차단
    ax.annotate("", xy=(0.285, 0.68), xytext=(0.21, 0.68), arrowprops=dict(**arrow_style, color="#ef4444", ls=":"))
    # 관리자 -> 20022 -> SSHD
    ax.annotate("", xy=(0.285, 0.47), xytext=(0.21, 0.47), arrowprops=dict(**arrow_style, color="#22c55e"))
    ax.annotate("", xy=(0.51, 0.64), xytext=(0.435, 0.47), arrowprops=dict(**arrow_style, color="#22c55e"))
    # 사용자 -> 15034 -> App
    ax.annotate("", xy=(0.285, 0.26), xytext=(0.21, 0.26), arrowprops=dict(**arrow_style, color="#a855f7"))
    ax.annotate("", xy=(0.51, 0.42), xytext=(0.435, 0.26), arrowprops=dict(**arrow_style, color="#a855f7"))
    # monitor.sh -> App 상태 감시
    ax.annotate("", xy=(0.725, 0.35), xytext=(0.725, 0.32), arrowprops=dict(**arrow_style, color="#f59e0b", ls="--"))
    ax.text(0.74, 0.335, "상태 점검 (PID & Port)", fontsize=9, color='#fbbf24', weight='bold')

    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis('off')
    
    out_path = os.path.join(OUTPUT_DIR, "architecture_system_overview.png")
    plt.tight_layout()
    plt.savefig(out_path, facecolor=fig.get_facecolor(), edgecolor='none')
    plt.close()
    print(f"Generated: {out_path}")

# ------------------------------------------------------------------------------
# 2. 역할 기반 계정 & 디렉토리 권한/ACL 아키텍처 다이어그램
# ------------------------------------------------------------------------------
def draw_security_acl():
    fig, ax = plt.subplots(figsize=(15, 9), dpi=300)
    fig.patch.set_facecolor('#0f172a')
    ax.set_facecolor('#0f172a')

    # 타이틀
    ax.text(0.5, 0.95, "역할 기반 접근 제어(RBAC) 및 디렉토리 권한/ACL 아키텍처", 
            fontsize=20, weight='bold', color='#f8fafc', ha='center', va='top')
    ax.text(0.5, 0.915, "최소 권한의 원칙(Least Privilege)에 입각한 사용자 • 그룹 • 디렉토리 격리 구조", 
            fontsize=12, color='#94a3b8', ha='center', va='top')

    # 좌측: 사용자 계정 (Users)
    u_title = patches.FancyBboxPatch((0.05, 0.78), 0.26, 0.08, boxstyle="round,pad=0.01,rounding_size=0.02",
                                     facecolor='#1e293b', edgecolor='#38bdf8', linewidth=2)
    ax.add_patch(u_title)
    ax.text(0.18, 0.82, "[계정] 사용자 계정 (Users)", fontsize=13, weight='bold', color='#38bdf8', ha='center', va='center')

    users = [
        ("agent-admin\n(운영 및 관리, cron 실행자, sudo 권한)", 0.64, '#38bdf8'),
        ("agent-dev\n(개발 및 운영, monitor.sh 작성자)", 0.44, '#38bdf8'),
        ("agent-test\n(QA 및 테스터, 일반 권한자)", 0.24, '#94a3b8')
    ]
    for text, y, col in users:
        ubox = patches.FancyBboxPatch((0.05, y - 0.06), 0.26, 0.12, boxstyle="round,pad=0.01,rounding_size=0.02",
                                     facecolor='#0f172a', edgecolor=col, linewidth=1.5)
        ax.add_patch(ubox)
        ax.text(0.18, y, text, fontsize=10.5, color='#f1f5f9', ha='center', va='center', weight='bold')

    # 중앙: 그룹 계층 (Groups)
    g_title = patches.FancyBboxPatch((0.37, 0.78), 0.26, 0.08, boxstyle="round,pad=0.01,rounding_size=0.02",
                                     facecolor='#1e293b', edgecolor='#a855f7', linewidth=2)
    ax.add_patch(g_title)
    ax.text(0.50, 0.82, "[그룹] 소속 그룹 (Groups)", fontsize=13, weight='bold', color='#c084fc', ha='center', va='center')

    groups = [
        ("agent-core (핵심 보안 그룹)\n구성원: agent-admin, agent-dev\n권한: 비밀키 및 로그 전용 접근", 0.55, '#c084fc'),
        ("agent-common (공통 작업 그룹)\n구성원: admin, dev, test 전원\n권한: 파일 업로드 공유 접근", 0.31, '#a855f7')
    ]
    for text, y, col in groups:
        gbox = patches.FancyBboxPatch((0.37, y - 0.07), 0.26, 0.14, boxstyle="round,pad=0.01,rounding_size=0.02",
                                     facecolor='#0f172a', edgecolor=col, linewidth=1.5)
        ax.add_patch(gbox)
        ax.text(0.50, y, text, fontsize=10.5, color='#f1f5f9', ha='center', va='center', weight='bold')

    # 우측: 디렉토리 및 파일 권한 (Resources)
    r_title = patches.FancyBboxPatch((0.69, 0.78), 0.26, 0.08, boxstyle="round,pad=0.01,rounding_size=0.02",
                                     facecolor='#1e293b', edgecolor='#10b981', linewidth=2)
    ax.add_patch(r_title)
    ax.text(0.82, 0.82, "[보안] 리소스 및 권한 (ACL)", fontsize=13, weight='bold', color='#34d399', ha='center', va='center')

    resources = [
        ("$AGENT_HOME/api_keys\n소유: agent-admin:agent-core\n권한: 0750 (rwxr-x---)\n* t_secret.key (0640) 보관 / test 차단", 0.66, '#ef4444'),
        ("/var/log/agent-app\n소유: agent-admin:agent-core\n권한: 0775 (rwxrwxr-x) + POSIX ACL\n* core 그룹만 R/W 작성 가능", 0.46, '#f59e0b'),
        ("$AGENT_HOME/upload_files\n소유: agent-admin:agent-common\n권한: 2770 (rwxrws---) + setgid\n* 전원(admin, dev, test) 자유 R/W", 0.26, '#10b981')
    ]
    for text, y, col in resources:
        rbox = patches.FancyBboxPatch((0.69, y - 0.07), 0.26, 0.14, boxstyle="round,pad=0.01,rounding_size=0.02",
                                     facecolor='#0f172a', edgecolor=col, linewidth=1.5)
        ax.add_patch(rbox)
        ax.text(0.82, y, text, fontsize=10, color='#f1f5f9', ha='center', va='center', weight='bold')

    # 매핑 화살표
    arrow_style = dict(arrowstyle="->", lw=1.8, mutation_scale=12)
    # Users -> Groups
    ax.annotate("", xy=(0.37, 0.58), xytext=(0.31, 0.64), arrowprops=dict(**arrow_style, color="#38bdf8"))
    ax.annotate("", xy=(0.37, 0.55), xytext=(0.31, 0.44), arrowprops=dict(**arrow_style, color="#38bdf8"))
    ax.annotate("", xy=(0.37, 0.33), xytext=(0.31, 0.64), arrowprops=dict(**arrow_style, color="#38bdf8", ls=":"))
    ax.annotate("", xy=(0.37, 0.31), xytext=(0.31, 0.44), arrowprops=dict(**arrow_style, color="#38bdf8", ls=":"))
    ax.annotate("", xy=(0.37, 0.29), xytext=(0.31, 0.24), arrowprops=dict(**arrow_style, color="#94a3b8"))

    # Groups -> Resources
    ax.annotate("", xy=(0.69, 0.66), xytext=(0.63, 0.58), arrowprops=dict(**arrow_style, color="#c084fc"))
    ax.annotate("", xy=(0.69, 0.48), xytext=(0.63, 0.54), arrowprops=dict(**arrow_style, color="#c084fc"))
    ax.annotate("", xy=(0.69, 0.26), xytext=(0.63, 0.31), arrowprops=dict(**arrow_style, color="#a855f7"))

    # test 사용자가 api_keys 접근 시도 시 차단 마크
    ax.annotate("[차단] test 계정 접근 불가", xy=(0.69, 0.62), xytext=(0.48, 0.16),
                arrowprops=dict(arrowstyle="->", color="#ef4444", lw=2, ls="--"),
                fontsize=11, color="#ef4444", weight='bold')

    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis('off')

    out_path = os.path.join(OUTPUT_DIR, "architecture_security_acl.png")
    plt.tight_layout()
    plt.savefig(out_path, facecolor=fig.get_facecolor(), edgecolor='none')
    plt.close()
    print(f"Generated: {out_path}")

# ------------------------------------------------------------------------------
# 3. monitor.sh 관제 파이프라인 및 로그 로테이션 아키텍처 다이어그램
# ------------------------------------------------------------------------------
def draw_monitor_flow():
    fig, ax = plt.subplots(figsize=(15, 9), dpi=300)
    fig.patch.set_facecolor('#0f172a')
    ax.set_facecolor('#0f172a')

    # 타이틀
    ax.text(0.5, 0.95, "monitor.sh 관제 라이프사이클 및 로그 로테이션 큐 메커니즘", 
            fontsize=20, weight='bold', color='#f8fafc', ha='center', va='top')
    ax.text(0.5, 0.915, "Health Check(Exit 1) vs Warning 이원화 대응 | 10MB x 10개 파일 순환 보존 큐", 
            fontsize=12, color='#94a3b8', ha='center', va='top')

    # 단계 1: 트리거
    s1 = patches.FancyBboxPatch((0.04, 0.72), 0.26, 0.14, boxstyle="round,pad=0.015,rounding_size=0.02",
                                facecolor='#1e293b', edgecolor='#38bdf8', linewidth=2)
    ax.add_patch(s1)
    ax.text(0.17, 0.81, "1. 스케줄러 트리거", fontsize=13, weight='bold', color='#38bdf8', ha='center')
    ax.text(0.17, 0.75, "agent-admin crontab\n(* * * * * 매분 실행)", fontsize=10.5, color='#e2e8f0', ha='center')

    # 단계 2: Health Check (프로세스 & 포트)
    s2 = patches.FancyBboxPatch((0.37, 0.72), 0.26, 0.14, boxstyle="round,pad=0.015,rounding_size=0.02",
                                facecolor='#1e293b', edgecolor='#ef4444', linewidth=2)
    ax.add_patch(s2)
    ax.text(0.50, 0.81, "2. 필수 Health Check", fontsize=13, weight='bold', color='#f87171', ha='center')
    ax.text(0.50, 0.75, "• agent_app.py 생존 (PID)\n• TCP 15034 LISTEN 상태", fontsize=10.5, color='#e2e8f0', ha='center')

    # 2-FAIL: 비정상 종료
    f_box = patches.FancyBboxPatch((0.70, 0.72), 0.25, 0.14, boxstyle="round,pad=0.015,rounding_size=0.02",
                                   facecolor='#450a0a', edgecolor='#ef4444', linewidth=2)
    ax.add_patch(f_box)
    ax.text(0.825, 0.81, "[ERROR] 즉시 비정상 종료", fontsize=13, weight='bold', color='#fca5a5', ha='center')
    ax.text(0.825, 0.75, "exit code 1 반환\n표준 에러(stderr) 장애 출력", fontsize=10.5, color='#fee2e2', ha='center')

    # 단계 3: 상태 점검 & 리소스 수집
    s3 = patches.FancyBboxPatch((0.04, 0.40), 0.42, 0.24, boxstyle="round,pad=0.015,rounding_size=0.02",
                                facecolor='#1e293b', edgecolor='#f59e0b', linewidth=2)
    ax.add_patch(s3)
    ax.text(0.25, 0.59, "3. 상태 점검 & 자원 수집 (경고만 출력, 계속 진행)", fontsize=12.5, weight='bold', color='#fbbf24', ha='center')
    ax.text(0.25, 0.48, "• 방화벽(UFW) 점검: 비활성 시 [WARNING]\n• CPU 점검: > 20% 초과 시 [WARNING]\n• 메모리 점검: > 10% 초과 시 [WARNING]\n• 디스크 점검: 루트 파티션 > 80% 초과 시 [WARNING]",
            fontsize=10.5, color='#fde68a', ha='center', va='center')

    # 단계 4: 로그 로테이션 (10MB 큐)
    s4 = patches.FancyBboxPatch((0.53, 0.40), 0.42, 0.24, boxstyle="round,pad=0.015,rounding_size=0.02",
                                facecolor='#1e293b', edgecolor='#a855f7', linewidth=2)
    ax.add_patch(s4)
    ax.text(0.74, 0.59, "4. 로그 용량 관리 (10MB x 10개 순환 큐)", fontsize=12.5, weight='bold', color='#c084fc', ha='center')
    ax.text(0.74, 0.48, "• 파일 크기 검사: monitor.log >= 10MB ?\n• 백업 순환: .10 삭제 -> .9~.1 인덱스 쉬프트\n• 신규 전환: 현재 monitor.log -> monitor.log.1 이동\n• 디스크 보호: 로그 전체 총량 <= 100MB 엄격 보장",
            fontsize=10.5, color='#e9d5ff', ha='center', va='center')

    # 단계 5: 규격 로그 저장 및 정상 종료
    s5 = patches.FancyBboxPatch((0.15, 0.10), 0.70, 0.22, boxstyle="round,pad=0.015,rounding_size=0.02",
                                facecolor='#064e3b', edgecolor='#10b981', linewidth=2.5)
    ax.add_patch(s5)
    ax.text(0.50, 0.27, "5. /var/log/agent-app/monitor.log 규격 라인 누적 기록 및 성공 완료", 
            fontsize=13, weight='bold', color='#34d399', ha='center')
    ax.text(0.50, 0.19, "[2026-10-01 14:00:00] PID:1440 CPU:12% MEM:8% DISK_USED:42%", 
            fontsize=12, family='monospace', weight='bold', color='#ffffff', ha='center',
            bbox=dict(boxstyle="round,pad=0.5", facecolor="#022c22", edgecolor="#10b981"))
    ax.text(0.50, 0.13, "[SUCCESS] exit code 0 반환 (성공)", fontsize=11, color='#6ee7b7', weight='bold', ha='center')

    # 화살표 연결
    arrow_style = dict(arrowstyle="->", lw=2, mutation_scale=15)
    # 1 -> 2
    ax.annotate("", xy=(0.37, 0.79), xytext=(0.30, 0.79), arrowprops=dict(**arrow_style, color="#38bdf8"))
    # 2 -> Fail (실패 시)
    ax.annotate("실패 (앱/포트 다운)", xy=(0.70, 0.79), xytext=(0.63, 0.79),
                arrowprops=dict(**arrow_style, color="#ef4444"), fontsize=9.5, color="#f87171", weight='bold', va='bottom')
    # 2 -> 3 (정상 통과 시)
    ax.annotate("정상 통과", xy=(0.25, 0.64), xytext=(0.50, 0.72),
                arrowprops=dict(**arrow_style, color="#22c55e"), fontsize=10, color="#22c55e", weight='bold')
    # 3 -> 4
    ax.annotate("", xy=(0.53, 0.52), xytext=(0.46, 0.52), arrowprops=dict(**arrow_style, color="#f59e0b"))
    # 4 -> 5
    ax.annotate("", xy=(0.50, 0.32), xytext=(0.74, 0.40), arrowprops=dict(**arrow_style, color="#10b981"))

    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis('off')

    out_path = os.path.join(OUTPUT_DIR, "architecture_monitor_flow.png")
    plt.tight_layout()
    plt.savefig(out_path, facecolor=fig.get_facecolor(), edgecolor='none')
    plt.close()
    print(f"Generated: {out_path}")

if __name__ == "__main__":
    draw_system_overview()
    draw_security_acl()
    draw_monitor_flow()
    print("All architecture diagrams created successfully.")
