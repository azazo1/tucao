# 吐槽弹幕网客户端

Flutter 重建的吐槽弹幕网 (`tucao.my`) 第三方安卓客户端.
界面参考官方老版客户端与 PiliPlus, 接口沿用官方最新安卓端 `tucao-v2.0.4` 使用的定义.

本项目仅供学习交流, 与站点官方无关.

## 功能

- 首页分区浏览: 新番 / 影剧 / 综合, 含子分区切换
- 首页时间表: 按周日到周六分组的新番时间表
- 分区列表: 支持按最新 / 弹幕 / 播放排序, 分页加载
- 排行榜: 全站与各分区, 今天 / 本周 / 本月 / 今年, 含神评论, 追番榜,
  无人区, 在线榜, 今天更新, 今天推荐与热搜榜
- u榜: 按用户维度排行, 点按进入用户空间
- 搜索: 关键词搜索, 分区过滤, 排序, 本地搜索历史
- 番组: 新番索引按季度 / 年代 / 题材筛选, 本周新番按日期分组
- 档案: 站点档案列表与详情, 详情含播放 / 在线 / 评论统计与评论区
- 用户空间: 查看 up 主的资料与投稿
- 私信: 收件箱与会话详情, 支持发送与回复
- 视频播放: 多分P, 倍速, 全屏, 画中画, 进度记忆, 复制分P链接与浏览器备用入口
- 播放统计: 播放页显示总播放量, 实时在线人数, 评论, 弹幕与追番数, 在线人数每 30 秒刷新
- 播放器手势: 横向拖动调进度, 移到顶部左右角可取消, 左侧竖向拖动调音量, 长按 3 倍速
- 跳过片头片尾: 播放器按钮按设置秒数前进, 秒数在设置页可调
- 画中画: 播放器按钮进入系统小窗, 回桌面或切到其他应用时也可自动进入,
  小窗只保留画面, 开关在设置页
- 弹幕: 滚动 / 顶部 / 底部渲染, 播放中调整字号, 字重, 透明度, 时长, 描边,
  行高, 显示区域与字幕避让, 支持发送
- 评论: 播放页与档案详情都支持评论, 含楼中楼, 点赞与发送
- 播放历史: 本地记录进度, 可续播
- 本地收藏: 视频页收藏与取消, 收藏列表管理, 不与站点账号同步
- 离线缓存: 直链单文件分P多选, 前台下载队列, 暂停与从头重试, 本地播放与删除
- 登录与注册: 站点账号登录, 内置注册页, 修改密码与邮箱找回密码, cookie 持久化
- 设置: 主题, 播放器, 弹幕参数

## 缓存说明

视频页菜单中的 "下载缓存" 支持选择可用直链分P, 在 "我的 - 离线缓存" 管理任务.
视频文件与任务清单放在 Android 提供的外部专属目录 `Android/data/com.azazo1.tucao/files/downloads/`,
不使用内部 `/data/data` 存放视频, 外部存储不可用时提示重试. 无需公共存储权限,
但 Android 11 及以上通常限制文件管理器访问该目录, 卸载应用会删除缓存.

当前仅支持单文件媒体, 不支持 HLS 分段缓存或后台下载. 暂停及失败后从头重试,
重启应用不会自动恢复流量. 下载响应若为网页, 错误文本或播放列表, 不会标为已缓存.
本地播放不请求站点详情或弹幕, 因此可以离线观看已完成的文件.

## 开发

项目使用 [just](https://github.com/casey/just) 编排常用命令.

```shell
# 查看全部可用命令
just

# 获取依赖
just check deps

# 静态检查
just check analyze

# 运行测试
just check test

# 本地构建
just build android

# 在设备上运行
just device run
```

## 构建

安卓构建依赖 JDK 17 与 Flutter stable.

```shell
just build android          # 构建 Release APK
just build android-split    # 按 ABI 拆分
just build android-debug    # 调试构建
```

发布构建的签名配置见 `android/key.properties.example`, 本地没有该文件时回落到调试签名.

## 持续集成

[CI 工作流](<.github/workflows/build.yml>) 在推送与合并请求时执行静态检查, 单元测试与安卓构建.
手动触发工作流并填写 tag 时会构建全部 ABI, 全部检查通过后发布 GitHub Release.

## 接口

站点接口沿用官方安卓端定义, 集中登记在 `lib/http/api_path.dart`:

| 用途 | 地址 |
| --- | --- |
| 分区列表 | `api_v2/list.php` |
| 视频详情 | `api_v2/view.php` |
| 搜索 | `api_v2/search.php` |
| 弹幕 | `index.php?m=mukio&c=index&a=init` |
| 评论 | `index.php?m=comment&c=index&a=ajax` |
| 登录状态 | `api.php?op=user` |
| 排行榜 | `html/hot.html` (页面解析) |
| 番组索引 | `bgm/` (页面解析) |
| 本周新番 | `html/week_bgm.html` (页面解析) |
| 用户空间 | `play/u{uid}/` (页面解析) |
| 注册 | `index.php?m=member&c=index&a=register` |
| 修改密码 | `index.php?m=member&c=index&a=account_manage_password` |
| 找回密码 | `index.php?m=member&c=index&a=public_forget_password` |
| 私信 | `index.php?m=message&c=index&a=inbox` (页面解析) |

站点的排行榜 json 接口 `rank.php` 与播放地址接口 `api/playurl` 都已废弃,
排行榜, 番组索引, 本周新番与用户空间没有可用的 json 接口, 这些页面通过
解析 html 获取数据, 与官方客户端早期版本的做法一致.

页面解析集中放在 `lib/http/` 下对应的 `*_http.dart`, 解析函数与请求分离,
便于用固定的页面样本做单元测试, 样本放在 `test/fixtures/`.

## 目录结构

```
lib/
  common/     常量, 主题, 公共组件, 分页基类
  http/       接口定义与请求实现
  models/     数据模型
  pages/      页面
  plugin/     播放器等独立插件
  router/     路由登记
  services/   账户, 历史, 主题等全局服务
  utils/      日志, 存储, 格式化等工具
```

## 许可

本项目基于 [MIT](LICENSE) 发布.
应用图标取自吐槽弹幕网官方客户端, 版权归原站点所有.
