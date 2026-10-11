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
- 档案: 站点档案列表与详情
- 用户空间: 查看 up 主的资料与投稿
- 私信: 收件箱与会话详情, 支持发送与回复
- 视频播放: 多分P, 倍速, 全屏, 进度记忆
- 播放器手势: 横向拖动调进度, 左侧竖向拖动调音量, 长按 3 倍速
- 弹幕: 滚动 / 顶部 / 底部弹幕渲染, 样式可配置, 支持发送
- 评论: 评论列表, 楼中楼, 点赞, 发送评论
- 播放历史: 本地记录进度, 可续播
- 登录与注册: 站点账号登录, 内置注册页与修改密码, cookie 持久化
- 设置: 主题, 播放器, 弹幕参数

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

`.github/workflows/build.yml` 在推送与合并请求时执行静态检查, 单元测试与安卓构建.
手动触发工作流并填写 tag 时会构建全部 ABI 并发布 GitHub Release.

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
