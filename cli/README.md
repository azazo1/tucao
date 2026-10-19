# tucao CLI

吐槽弹幕网 (`tucao.my`) 的命令行客户端, 用 Go 写成.
覆盖安卓端里可以数据化的功能: 分区浏览, 时间表, 榜单, 搜索, 番组索引, 档案,
用户空间, 私信, 评论, 弹幕, 离线下载, 账号与本地收藏.

## 功能

- 首页概览: 站点在线人数与在线播放器数, 首页广告位, 分区树与首页新番时间表
- 分区列表: 按最新 / 弹幕 / 播放排序, 分页浏览
- 榜单: 排行榜, 弹幕榜, 神评论, 无人区, 追番榜, 在线榜, 今天更新, 今天推荐
- 热搜榜与 u 榜, 榜单页面按今天 / 本周 / 本月 / 今年分组
- 搜索: 关键词, 分区过滤, 排序, 本地搜索历史
- 番组: 番组索引按季度 / 年代 / 题材 / 星期筛选, 本周新番按日期分组
- 档案: 档案列表与详情, 详情含正文段落与图片, 标签, 分类与发布时间, 以及评论区
- 用户空间: 用户资料与投稿列表
- 用户图片: 下载用户头像与横幅
- 私信: 收件箱, 会话内容, 发送与回复
- 视频详情: 分P与直链, 播放页完整简介, 番组信息, 播放 / 在线 / 评论 / 追番统计
- 弹幕: 拉取并导出 ass / xml / 纯文本, 支持发送
- 评论: 列表, 楼中楼, 发送与回复, 点赞
- 离线下载: 单文件分P下载, Range 断点续传
- 账号: 登录, 注册, 退出, 修改密码, 邮箱找回密码 (含图形验证码)
- 本地收藏与播放历史, 不与站点账号同步
- 配置管理: 站点域名, 输出格式, 下载参数, 弹幕排版, safety 开关

## 构建

```shell
# 构建当前平台的二进制到 cli/bin/tucao
just cli build
./cli/bin/tucao --version

# 直接运行, 不落盘
just cli run --json rank --type hot

# 运行测试与静态检查
just cli test
just cli lint
```

也可以直接用 Go:

```shell
cd cli
go run ./cmd/tucao home
```

`tucao --version` 显示的版本来自构建时注入的版本号: 正式发布用 tag (`v1.3.0`),
分支构建与 apk 用同一个构建版本 (`1.3.0-7e33cd3`). 本地直接构建时按版本 tag 推导,
没有版本 tag 时显示 `devel`.

## 配置

配置文件默认位于 `~/.config/tucao/config.toml`, 登录态位于
`~/.config/tucao/auth.json`, 收藏与历史位于 `~/.local/share/tucao/`.

```shell
tucao config init              # 写入默认配置
tucao config status            # 配置位置与每个字段的来源
tucao config get site.host     # 读单个字段
tucao config set site.host www.tucao.my
tucao config upgrade           # 把旧配置补齐到当前格式
```

可用的环境变量:

| 变量 | 作用 |
| --- | --- |
| `TUCAO_CONFIG_DIR` | 覆盖配置目录 |
| `TUCAO_DATA_DIR` | 覆盖本地数据目录 |
| `TUCAO_COOKIE` | 直接导入 cookie 头, 用于复用已有登录态 |
| `TUCAO_USERNAME` / `TUCAO_PASSWORD` | 登录时避免把用户名密码写进命令行 |
| `OUTPUT` | 覆盖输出格式, 取值同 `output.format` |

站点更换域名时改 `site.host` 即可, 不必等新版本.

## 登录

```shell
tucao me login                 # 交互输入用户名与密码
tucao me login -u 用户名 -p 密码
TUCAO_PASSWORD=密码 tucao me login -u 用户名
tucao me                        # 查看登录状态, 会向站点确认一次
tucao me --no-check             # 只看本地保存的内容
tucao me logout                 # 退出登录并清除本地 cookie
```

注册, 改密与找回密码:

```shell
tucao me register -u 用户名 --email 邮箱 --password 密码
tucao me password --old 旧密码 --new 新密码
tucao me forgot captcha -o /tmp/tucao-captcha.png    # 第一步: 存下验证码图片
tucao me forgot submit --email 邮箱 --code 1234      # 第二步: 用同一个会话提交
```

找回密码的两步必须紧挨着执行, 站点按 cookie 里的会话校验验证码, 中间不要清理配置目录.

## 输出

查询命令默认按当前环境选择格式: 交互终端输出对齐表格, 管道或脚本里输出 YAML.
`--json` 与 `--yaml` 可以显式指定, `--no-truncate` 关闭表格截断.

成功与失败都使用统一结构, 便于脚本解析:

```json
{ "ok": true, "schema_version": "1", "data": { } }
```

```json
{ "ok": false, "schema_version": "1", "error": { "code": "invalid_input", "message": "…" } }
```

退出码:

| 退出码 | 含义 |
| --- | --- |
| 0 | 成功 |
| 1 | 网络, 上游或磁盘等一般失败 |
| 2 | 命令行用法与参数错误 |
| 3 | 未登录 |
| 4 | 被 safety 开关或确认策略拒绝 |
| 5 | 目标不存在 |

## 浏览

```shell
tucao home                                  # 首页概览: 在线人数, 广告位, 分区树, 时间表
tucao channel                               # 分区树
tucao channel 新番                          # 单个分区
tucao week                                  # 新番时间表 (周日到周六, 剧场, 天朝)
tucao week --group 周一
tucao list --channel 24 --order mukio       # 分区列表, 排序支持 date / mukio / views
tucao rank --type hot --period week         # 排行榜, 本周维度
tucao rank --type online                    # 在线榜
tucao rank hot-search --limit 10            # 热搜榜
tucao rank user                             # u 榜
tucao search "学生会" --channel 11          # 搜索, 会写入本地搜索历史
tucao search "学生会" --no-history
tucao ad                                    # 首页广告位
```

## 番组与档案

```shell
tucao bgm --season 10月 --year 2026         # 番组索引
tucao bgm --weekday 星期一 --types 恋爱
tucao bgm week                              # 本周新番, 按日期分组
tucao article                               # 档案列表
tucao article --category 情报 --page 2
tucao article show 7301                     # 档案详情
tucao article comment 7301                  # 档案评论
```

## 视频, 弹幕与评论

```shell
tucao video 4107864                         # 详情 + 完整简介 + 番组信息 + 统计
tucao video 4107864 --no-stats
tucao video danmaku 4107864                 # 终端预览前 20 条
tucao video danmaku 4107864 --limit 0       # 不截断
tucao video danmaku 4107864 --format ass,xml,txt -o ./danmaku
tucao video danmaku 4107864 --from 1m --to 3m
tucao video danmaku send 4107864 "前方高能" --progress 1m20s --mode top --color '#FF0000'
tucao video comment 4107864                 # 评论列表
tucao video comment send 4107864 "好番"      # 发评论
tucao video comment send 4107864 "同意" --reply-id 316510 --reply-uid 453580
tucao video comment like 4107864 --id 316510
tucao video favorite 4107864                # 加入站点账号的收藏
```

导出文件名默认是 `<视频编号>-p<分P序号>.<扩展名>`, 例如 `4107864-p1.ass`,
`--basename` 可以改前缀. 导出文件始终包含拉到的全部弹幕, 不受 `--limit` 影响.

## 下载

```shell
tucao video download 4107864                # 单分P视频直接下到当前目录
tucao video download 4107864 -o ~/Downloads
tucao video download 4107864 --all-parts --threads 4
tucao video download 4107864 --with-danmaku # 顺带导出同名 ass
```

站点只提供单文件媒体, 不支持 HLS 分段缓存. 下载中断会留下 `.part` 文件,
再次执行同一命令会从断点续传; 目标文件已存在时需要用 `--overwrite` 覆盖.
下载的同时会从直链里取扩展名, 取不到时按 `.mp4` 保存.

用户空间里的头像与横幅同样能下载:

```shell
tucao image user 442223                     # 头像与横幅都下到当前目录
tucao image user u442223 --only avatar      # 只要头像, 也可以只取 banner
tucao image user 442223 -o ~/Pictures --basename tucao-442223
```

文件名默认是 `用户名-avatar.<扩展名>` 与 `用户名-banner.<扩展名>`,
断点续传与 `--overwrite` 的规则同上. 图片按内容认格式, 扩展名取识别出来的
真实格式, 因此地址是 `.jpg` 而内容是 PNG 的头像会存成 `.png`.

没有设置头像或横幅的账号, 站点给的是占位图与只有文件头的坏文件, 这类内容
不会落盘, 只在结果里作为警告列出; 两类都没取到有效图片时命令以失败结束.

## 私信

```shell
tucao msg                                   # 收件箱
tucao msg show 1001                         # 会话内容
tucao msg send --to 442223 --subject 你好 "内容"
tucao msg reply --id 1001 --to 442223 "回复内容"
```

## 本地收藏与历史

```shell
tucao fav                                   # 本地收藏
tucao fav add 4107864
tucao fav rm 4107864 --yes
tucao fav toggle 4107864

tucao history                               # 播放历史
tucao history add 4107864 --part 1 --progress 120 --duration 1440
tucao history rm 4107864 --yes
tucao history clear --yes

tucao history search                        # 搜索历史
tucao history search rm "学生会" --yes
tucao history search clear --yes
```

命令行工具没有播放器, 因此不会自动产生播放进度, `tucao history add` 供脚本写入;
安卓端的记录与这里的记录各自独立, 互不读取.

## safety 开关

`config.toml` 里的三个开关控制写操作:

| 开关 | 作用 |
| --- | --- |
| `safety.read_only` | 拒绝发弹幕, 发评论, 点赞, 站点收藏, 私信发送与回复, 注册, 改密与找回密码; 登录与登出不受影响 |
| `safety.non_destructive` | 拒绝删除与清空类操作, 例如删除本地收藏, 清空播放历史 |
| `safety.confirm_dangerous_actions` | 这些删除操作需要显式带 `--yes` |

```shell
tucao config set safety.read_only true      # 交给脚本跑只读任务时打开
```

## 与安卓端的差异

- 没有播放器, 投屏, 弹幕渲染与画中画, 播放历史需要手动写入.
- 弹幕导出为 ass / xml / 纯文本文件, 不在终端里渲染.
- 离线缓存是单次直连下载, 没有安卓端那样的任务清单与暂停队列.
- 本地数据与安卓端分别存放, 互不影响.

## 开发

```shell
just cli test          # go test ./...
just cli lint          # go vet ./...
just cli fmt           # gofmt
just cli run --help

# 交叉编译全部六个平台并校验产物
just cli dist-all
```

代码是纯 Go, 不依赖 cgo, 因此任一平台都能产出全部目标的二进制, 发布产物在
一个 linux runner 上就能做完. 交叉编译出来的产物跑不起来, 所以 `verify`
改用文件头与编译期注入的版本串核对: 归档里只有一个预期文件, ELF / Mach-O / PE
的架构与目标一致, 二进制里带着本次构建的版本号.

`go test` 必须在本机跑, 交叉编译不能替代, 因此 CI 里另有一组按系统 (Linux,
Windows, macOS) 各跑一遍的测试任务.

解析测试直接复用仓库根目录 `test/fixtures/` 里的真实页面样本,
因此 `go test` 需要在仓库内运行.
