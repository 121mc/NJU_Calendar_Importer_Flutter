# 调休服务

Python 3.12 标准库 + SQLite + Caddy HTTPS，不依赖第三方 Python 包。


## API

- `GET /api/semesters`：已保存的学期编号。
- `GET /api/holidays?semester=2026-2027-1`：`{"semester":"2026-2027-1","rules":[],"revision":0}`。未配置学期返回空规则。
- `PUT /api/holidays`：管理员 Basic Auth，`Content-Type: application/json`、`X-Calendar-Admin: 1`，提交同格式对象。revision 乐观锁防止覆盖其他管理员刚保存的数据；冲突返回409。
- 规则：`{"label":"国庆节","holiday":"2026-10-01","makeup":"2026-10-10"}`；makeup可为null。label 仅用于后台识别模块，客户端按日期应用规则。此日期仅为格式示例，并非学校放假通知。
- 一学期内放假日、补课日不可重复或相互重叠，避免递归移动。日期按中国本地日历解释。考试不受影响。

管理页固定预留模块：第一学期为中秋节、国庆节、元旦、运动会、其他；第二学期为清明节、劳动节、端午节、其他；第三学期为其他 1、其他 2。每个模块可添加多组放假日和补课日；补课日留空表示仅放假。未填写放假日的行不会写入 API。

## 部署与运维

代码：`/opt/nju-calendar/app.py`、`admin.html`；数据：`/var/lib/nju-calendar/calendar.db`；服务：`nju-calendar.service`；反向代理配置：`/etc/caddy/Caddyfile`。使用独立低权限用户运行，监听127.0.0.1:8765，Caddy负责证书申请和续签。

修改源码后复制到 `/opt/nju-calendar/` 并 `sudo systemctl restart nju-calendar`。部署时不要覆盖数据或密码文件。使用 SQLite backup API 备份数据库；恢复前停止服务。轮换密码需更新密码文件并保留root:nju-calendar和640权限，新请求立即生效。

```sh
systemctl status nju-calendar caddy
python3 -m unittest discover -s server -v
```

## 调课解析范围

已采集格式见 `docs/后续调课信息.md`。支持明确的“第N周 周X A-B节”定位、停课、加课、教室/教师为(…)及包含完整原/目标时间的调课。未知格式中止拉取并保留原文报错，不猜测目标时间。当前尚无官方接口实际返回的加课、时间调课样本，因此这两类通过合成样本测试，取得真实样本后应补充验证。变更按完整课程时段匹配，不支持部分节次变更；此类重叠会报错，避免静默忽略。
