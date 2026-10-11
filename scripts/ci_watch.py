#!/usr/bin/env python3
"""观察当前提交对应的 GitHub Actions 运行, 直到出终态.

认领方式是按本地短 hash 匹配, 而不是直接取最新一条, 避免并发触发时拿错运行.
等待期间每轮打印一次状态, 便于事后判断卡在哪一步; 失败的 job 只摘出关键错误行,
全量日志落在 .tmp/ci/ 下.
"""

import json
import os
import subprocess
import sys
import time

CI_LOG_DIR = os.path.join(".tmp", "ci")

# 认领运行与等待终态的次数上限, 每次间隔 15 秒.
CLAIM_ROUNDS = 20
WAIT_ROUNDS = 80
INTERVAL = 15

# 判定失败用的关键字, 尽量覆盖各工具链的输出习惯.
ERROR_PATTERN = r"Error:|error:|FAILURE|##\[error\]"


def repo_root():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run(argv):
    result = subprocess.run(argv, capture_output=True, text=True)
    if result.returncode != 0:
        return ""
    return result.stdout


def short_hash():
    return run(["git", "rev-parse", "HEAD"]).strip()[:7]


def repo_name():
    """从远端地址推出 owner/repo, 兼容 https 与 ssh 两种写法."""
    url = run(["git", "remote", "get-url", "origin"]).strip()
    if url.endswith(".git"):
        url = url[:-4]
    if ":" in url and not url.startswith("http"):
        url = url.split(":", 1)[1]
    parts = url.split("/")
    return "/".join(parts[-2:])


def claim_run(repo, sha):
    for _ in range(CLAIM_ROUNDS):
        raw = run(
            [
                "gh",
                "run",
                "list",
                "-R",
                repo,
                "--limit",
                "10",
                "--json",
                "databaseId,headSha",
            ]
        )
        if raw:
            for item in json.loads(raw):
                if item.get("headSha", "").startswith(sha):
                    return str(item["databaseId"])
        time.sleep(INTERVAL)
    return None


def wait_finished(repo, run_id):
    for i in range(1, WAIT_ROUNDS + 1):
        raw = run(
            [
                "gh",
                "run",
                "view",
                "-R",
                repo,
                run_id,
                "--json",
                "status,conclusion",
            ]
        )
        state = "-"
        if raw:
            data = json.loads(raw)
            state = "{}/{}".format(
                data.get("status", "-"), data.get("conclusion") or "-"
            )
        print("{} round={} {}".format(
            time.strftime("%H:%M:%S"), i, state
        ), flush=True)
        if state.startswith("completed/"):
            return state
        time.sleep(INTERVAL)
    return "timeout/-"


def report_jobs(repo, run_id):
    raw = run(
        ["gh", "run", "view", "-R", repo, run_id, "--json", "jobs"]
    )
    if not raw:
        return []
    failed = []
    print("=== jobs ===")
    for job in json.loads(raw).get("jobs", []):
        print("{} {}/{}".format(
            job.get("name"),
            job.get("status"),
            job.get("conclusion") or "-",
        ))
        if job.get("conclusion") == "failure":
            failed.append(str(job.get("databaseId")))
    return failed


def dump_failures(repo, failed):
    if not failed:
        return
    os.makedirs(CI_LOG_DIR, exist_ok=True)
    for job_id in failed:
        path = os.path.join(CI_LOG_DIR, "fail-{}.log".format(job_id))
        with open(path, "w", encoding="utf-8", errors="replace") as handle:
            handle.write(
                run(
                    [
                        "gh",
                        "api",
                        "/repos/{}/actions/jobs/{}/logs".format(repo, job_id),
                    ]
                )
            )
        print("=== failed job {} ===".format(job_id))
        errors = run(["grep", "-nE", ERROR_PATTERN, path]).strip()
        if errors:
            print("\n".join(errors.splitlines()[:30]))
        else:
            print("\n".join(open(path, encoding="utf-8", errors="replace")
                            .read().splitlines()[-20:]))


def main():
    os.chdir(repo_root())
    repo = repo_name()
    sha = short_hash()
    print("claiming run for {} in {}".format(sha, repo), flush=True)

    run_id = claim_run(repo, sha)
    if run_id is None:
        print("ERROR: 未认领到 {} 的运行".format(sha))
        return 1
    print("claimed run {}".format(run_id), flush=True)

    state = wait_finished(repo, run_id)
    failed = report_jobs(repo, run_id)
    dump_failures(repo, failed)

    if not state.startswith("completed/success"):
        print("CI 未通过: {}".format(state))
        return 1
    print("CI 通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
