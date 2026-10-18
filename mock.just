[private]
default:
    @just --list

# just mock tv / just mock tv --play
# 需要在能访问局域网的终端里运行, 沙箱内组播发不出去.
# 启动 mock 电视, 局域网内的客户端可以发现并投屏.
tv *args:
    uv run --no-project python scripts/mock_tv/main.py {{args}}

# just mock probe / just mock probe --url http://192.168.1.108:58920/guard/sample.mp4
# 带 guard 的地址会因缺少 Referer 被拒, 属于预期结果.
# 以客户端身份自检 mock 电视, 跑完整的发现与投屏流程.
probe *args:
    uv run --no-project python scripts/mock_tv/probe.py {{args}}
