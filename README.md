# mongo_sh_tools — MongoDB 交互管理工具

纯 Bash 实现的 MongoDB 交互式管理脚本，零依赖（仅需 `mongosh`），适用于无法安装图形化工具的 Linux 服务器环境。

## 目录结构

```
mongo_sh_tools/
  mongo_sh_tools  # 主脚本（唯一执行文件）
  export_*.json   # 导出的 JSON 文件（按需生成）
  export_*.csv    # 导出的 CSV 文件（按需生成）
  mongosh         # mongosh 二进制（需手动放置，见下方部署说明）

~/.mongo_sh_tools/
  config.json     # 连接配置（首次运行时自动引导生成）
  .mongo_history  # 查询历史记录（自动生成，无需手动管理）
```

## 部署

### 1. 准备 mongosh

在能联网的机器上下载 mongosh：

```bash
wget https://downloads.mongodb.com/compass/mongosh-2.3.8-linux-x64.tgz
tar xzf mongosh-2.3.8-linux-x64.tgz
```

将解压后的 `mongosh-2.3.8-linux-x64/bin/mongosh` 拷贝到脚本同目录下。

> 如果目标服务器 PATH 中已安装 mongosh，可跳过此步。脚本会优先使用同目录下的 mongosh，其次使用系统 PATH 中的。

### 2. 赋权并运行

```bash
cd mongo_sh_tools
chmod +x mongo_sh_tools mongosh
./mongo_sh_tools
```

### 3. 首次配置

首次运行时，如果 `~/.mongo_sh_tools/config.json` 不存在或内容无效，脚本会自动启动配置向导：

```
==============================
  首次使用 — 配置向导
==============================

未检测到有效配置，现在引导你完成 MongoDB 连接配置。

配置模式:
  [1] 单环境 — 只配置一个 MongoDB 连接
  [2] 多环境 — 配置多个环境(如 开发/测试/生产)
选择 [默认1]:
```

向导会依次询问：

| 参数 | 说明 | 默认值 |
|------|------|--------|
| 主机地址 | MongoDB 服务器 IP 或域名 | `127.0.0.1` |
| 端口 | MongoDB 端口（校验 1-65535） | `27017` |
| 数据库名 | 连接的默认数据库（**必填**） | — |
| 用户名 | 认证用户名（回车跳过=无认证） | — |
| 密码 | 认证密码（隐藏输入） | — |
| 认证数据库 | authSource | 与数据库名相同 |
| SSL | 是否启用 SSL | 否 |
| 默认查询条数 | 每次查询的默认 limit | `20` |

配置完成后自动写入 `~/.mongo_sh_tools/config.json` 并继续启动。

---

## 配置文件格式

### 单环境

```json
{
  "host": "10.110.0.106",
  "port": 27018,
  "database": "saas",
  "username": "developer",
  "password": "iamadeveloper",
  "authSource": "saas",
  "ssl": false,
  "defaultLimit": 20,
  "exportLimit": 10000
}
```

### 多环境

```json
{
  "defaultLimit": 20,
  "exportLimit": 10000,
  "environments": [
    {
      "name": "开发环境",
      "host": "10.110.0.106",
      "port": 27018,
      "database": "saas",
      "username": "developer",
      "password": "iamadeveloper",
      "authSource": "saas",
      "ssl": false
    },
    {
      "name": "测试环境",
      "host": "10.110.0.107",
      "port": 27018,
      "database": "saas_test",
      "username": "tester",
      "password": "testerpass",
      "authSource": "saas_test",
      "ssl": false
    }
  ]
}
```

### 配置项说明

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `host` | string | 是 | `127.0.0.1` | MongoDB 服务器地址 |
| `port` | number | 否 | `27017` | 端口号 (1-65535) |
| `database` | string | 是 | — | 默认数据库 |
| `username` | string | 否 | — | 认证用户名，省略则无认证连接 |
| `password` | string | 否 | — | 认证密码 |
| `authSource` | string | 否 | 同 database | 认证数据库 |
| `ssl` | boolean | 否 | `false` | 是否启用 SSL |
| `defaultLimit` | number | 否 | `20` | 查询默认条数 |
| `exportLimit` | number | 否 | `10000` | 导出默认条数上限，设为 `0` 不限制 |
| `environments` | array | 否 | — | 多环境配置数组，存在时忽略顶层连接字段 |

多环境模式下，启动时会列出所有环境供选择。两种格式向后兼容，无需迁移。

无认证连接时，省略 `username`、`password`、`authSource` 字段即可。

---

## 功能总览

启动后进入主菜单：

```
==============================
  MongoDB 交互管理工具
  当前: saas > device_logs
==============================

  [q] 查询        [d] 数据操作      [i] 索引管理
  [c] 集合管理    [s] 统计分析      [e] 环境切换
  [h] 查询历史    [x] 退出

  快捷: [1] 快速查询  [f] 查看字段
```

共 **7 大分类、22 项功能**。输入对应字母进入子菜单，子菜单内按编号操作，`b` 返回主菜单。

---

## 功能详解

### [q] 查询

| 编号 | 功能 | 说明 |
|------|------|------|
| 1 | 查询数据 | 设置条数 + 构建过滤条件 + `sort({_id:-1})` |
| 2 | 字段投影查询 | 查询前选择要显示的字段（多选），只返回选中字段 |
| 3 | 分页浏览 | 基于 `skip/limit` 分页，`n` 下一页、`p` 上一页、`g` 跳转、`q` 退出 |
| 4 | Explain 分析 | 执行 `.explain("executionStats")`，展示是否命中索引、扫描行数、执行时间等 |
| 5 | 自定义排序查询 | 选择排序字段和方向（ASC/DESC），替代默认的 `{_id:-1}` |

#### 过滤条件构建

所有涉及查询的功能（包括删除、更新、导出）都复用同一套过滤条件构建器：

- **按编号选择字段**：输入字段编号后，根据字段类型提供对应的过滤方式
  - string：精确匹配 / 正则模糊匹配
  - number：等于 / 大于 / 大于等于 / 小于 / 小于等于 / 范围
  - boolean：true / false
  - date：之后 / 之前 / 范围
  - objectId：精确匹配
- **手动表达式**：支持 `field=value`、`field>value`、`field<value`、`field>=value`、`field<=value`、`field~pattern`（正则）
- 可叠加多个条件，回车或输入 `done` 结束
- 所有用户输入均经过 JS 转义处理，防止注入

### [d] 数据操作

| 编号 | 功能 | 说明 |
|------|------|------|
| 1 | 删除文档 | 构建过滤 → 预览匹配数量 → 选择 deleteOne/deleteMany → **二次确认**后执行 |
| 2 | 更新文档 | 构建过滤 → 预览匹配数量 → 选择字段和新值 → updateOne/updateMany → **二次确认** |
| 3 | 导出数据 | 构建过滤 → 设置导出条数 → 选择 JSON/CSV 格式 → 流式写入文件 |
| 4 | 导入数据 | 选择 JSON Lines 文件 → 校验与预览前 3 条 → **确认**后按 500 条一批插入 |

- **删除/更新**：当未设置过滤条件（空 filter）且选择了 Many 操作时，会显示醒目警告
- **导出数据**：默认导出上限为 `10000` 条（可通过 `~/.mongo_sh_tools/config.json` 的 `exportLimit` 修改），导出时可临时输入其他值，输入 `0` 则不限制
- CSV 导出以集合字段名作为表头，逐行流式输出，字段中的逗号替换为分号、换行替换为空格
- 导入文件使用 JSON Lines 格式，即每行一条 JSON 文档；可直接导入脚本导出的 JSON 文件
- 导入会保留文件中的 `_id`。若目标集合已有相同 `_id`，该文档会导入失败，结果会汇总成功数与失败数
- 普通 JSON 无法保留 `ObjectId`、`Date` 等 BSON 类型；需要保留类型时，请提供 Extended JSON 格式的导入文件
- 导出和导入过程中会显示已处理数量、总数和完成百分比

### [i] 索引管理

| 编号 | 功能 | 说明 |
|------|------|------|
| 1 | 查看索引 | 列出所有索引的名称、字段、方向及属性（UNIQUE/SPARSE/TTL/PARTIAL） |
| 2 | 创建索引 | 从字段列表选择（支持复合索引），选择方向（ASC/DESC/TEXT/HASHED）和属性 |
| 3 | 删除索引 | 列出索引，按编号选择删除（`_id_` 系统索引禁止删除），**二次确认** |

### [c] 集合管理

| 编号 | 功能 | 说明 |
|------|------|------|
| 1 | 切换集合 | 列出当前数据库所有集合，选择后自动分析字段结构 |
| 2 | 查看字段 | 采样最近 10 条文档，分析并展示所有字段的名称、类型和建议过滤方式 |
| 3 | 重命名集合 | 输入新名称，检查是否冲突，**确认**后通过 `renameCollection` 执行 |
| 4 | 删除集合 | 显示文档数量作为预警，需**手动输入集合名称**确认（防误删） |
| 5 | 创建集合 | 输入名称，可选普通集合或 Capped（指定大小和文档上限），创建后自动切换 |

### [s] 统计分析

| 编号 | 功能 | 说明 |
|------|------|------|
| 1 | 集合统计 | 执行 `collStats()`，展示文档数、数据大小、存储大小、索引大小、平均文档大小、各索引详情 |
| 2 | 聚合统计 | 选择字段 → 选择操作（count/sum/avg/min/max）→ 可选 group by 字段 → 执行 aggregate pipeline |

### [e] 环境切换

| 编号 | 功能 | 说明 |
|------|------|------|
| 1 | 切换数据库 | 通过 `listDatabases` 列出所有数据库（含大小），选择后重新选集合。如无权限则手动输入 |
| 2 | 多环境配置选择 | 重新加载配置文件中的 `environments` 列表，选择并切换到目标环境 |

> 环境切换后会重新选择集合并分析字段。

### [h] 查询历史

- 自动保存最近 **20 条**查询记录到 `~/.mongo_sh_tools/.mongo_history`
- 每条记录包含：时间、集合名、过滤条件、查询条数
- 选择编号可重新执行该查询（如果集合不同会自动切换）

### 快捷键

在主菜单直接输入，无需进子菜单：

| 快捷键 | 功能 |
|--------|------|
| `1` | 快速查询数据（等同 `q` → `1`） |
| `f` | 快速查看字段结构（等同 `c` → `2`） |

---

## 使用示例

### 查询最近 10 条 status 为 "online" 的设备日志

```
请输入: 1
查询条数 [默认 20]: 10

添加过滤条件 — 输入字段编号选择，或手动输入(如 field=value)
  直接回车 = 跳过(无过滤)  |  done = 结束添加
------------------------------------------------------------
过滤(编号或表达式): 3          ← 选择第3个字段 status
  字段 [status] (string) 过滤方式:
    [1] 精确匹配    [2] 模糊匹配(正则)
  选择 [1/2]: 1
  输入值: online
  已添加: "status":"online"
过滤(编号或表达式):            ← 回车结束

执行: db.device_logs.find({"status":"online"}).sort({_id:-1}).limit(10)
------------------------------------------------------------
{ ... }
------------------------------------------------------------
匹配总数: 1234 | 本次显示: 10 条
```

### 导出数据为 CSV

```
请输入: d           ← 进入数据操作子菜单
选择: 3             ← 导出数据

添加过滤条件...
过滤(编号或表达式):  ← 回车，无过滤

匹配文档数: 58000
导出条数上限 [默认 10000，0=不限]:
  提示: 匹配 58000 条，将只导出前 10000 条 (可在 ~/.mongo_sh_tools/config.json 中修改 exportLimit)

导出格式:  [1] JSON  [2] CSV
选择 [默认1]: 2
  ✓ 正在导出 CSV...
已导出: /path/to/mongo_sh_tools/export_device_logs_20250211_143022.csv (10000 行)
```

> 导出条数上限默认 10000，可在 `~/.mongo_sh_tools/config.json` 中修改 `exportLimit`，或在导出时临时输入其他值（输入 `0` 不限制）。

### 导入 JSON Lines 数据

```
请输入: d
选择: 4

导入 JSON Lines 数据（每行一条 JSON 文档）
导入文件路径: /path/to/data.json

待导入文档数: 100
预览前 3 条:
{ ... }

⚠ 将向集合 [device_logs] 插入 100 条文档，此操作不可撤销。
确认导入? [y/N]: y
导入结果: {"total":100,"inserted":100,"failed":0,"errors":[]}
```

导入会先复制源文件到权限为 `600` 的临时快照，确认后始终从该快照读取。若同一集合已存在相同 `_id`，对应文档不会覆盖，而会被计入失败数。

### Explain 分析慢查询

```
请输入: q           ← 进入查询子菜单
选择: 4             ← Explain 分析

添加过滤条件...
过滤(编号或表达式): deviceId=ABC123
  已添加: deviceId=ABC123
过滤(编号或表达式):

执行 Explain 分析: db.device_logs.find({"deviceId":"ABC123"}).explain('executionStats')
------------------------------------------------------------
查询计划: COLLSCAN
执行时间: 342 ms
扫描文档数: 89000
扫描索引数: 0
返回文档数: 15
命中率: 0.0%

⚠ 警告: 全表扫描(COLLSCAN)，建议为查询字段创建索引
------------------------------------------------------------
```

发现 COLLSCAN 后，可立即进入 `i` → `2` 创建索引。

### 聚合统计

```
请输入: s           ← 进入统计分析
选择: 2             ← 聚合统计

选择聚合字段:
  [1] _id (objectId)
  [2] deviceId (string)
  [3] status (string)
  [4] temperature (number)
字段编号: 4

聚合操作:
  [1] count  [2] sum  [3] avg  [4] min  [5] max
选择: 3

是否按字段分组? (输入字段编号，回车跳过)
分组字段编号: 3     ← 按 status 分组

聚合: avg(temperature) group by "$status"
------------------------------------------------------------
online: 36.5
offline: 22.1
error: 78.9

共 3 条结果
------------------------------------------------------------
```

---

## 安全说明

- **JS 注入防护**：所有用户输入（过滤值、集合名、字段名等）在拼入 mongosh 执行前均经过转义处理（`"` `\` `'` `` ` `` 及换行符）
- **空 filter 警告**：执行 `deleteMany` 或 `updateMany` 时若未设置过滤条件，会显示醒目警告提示将影响全部文档
- **删除文档 / 删除集合** 等破坏性操作均需**二次确认**，删除集合还需手动输入集合名
- **临时文件保护**：脚本运行时的临时 JS 文件（`/tmp/mq_*.js`）权限设为 `600`，仅当前用户可读
- 密码在配置向导中使用**隐藏输入**（`read -s`），但会明文写入 `~/.mongo_sh_tools/config.json`
- 建议对配置文件设置合适的文件权限：
  ```bash
  chmod 600 ~/.mongo_sh_tools/config.json
  ```
- 脚本不会对外发起任何网络请求，所有操作仅通过 `mongosh` 与指定的 MongoDB 实例通信

---

## 系统要求

- **操作系统**：Linux（CentOS/Ubuntu/Debian 等）、macOS
- **Shell**：Bash 4.0+（需支持 `local -n` nameref，CentOS 7 自带 Bash 4.2）
- **mongosh**：2.x（放在脚本同目录或系统 PATH 中）
- **无其他依赖**：不需要 jq、python 或其他工具，JSON 解析由纯 Bash 实现

---

## 常见问题

### Q: 启动报错 "未找到 mongosh"

将 mongosh 二进制放到脚本同目录下并赋予执行权限：

```bash
chmod +x mongosh
```

### Q: 连接超时 / 无法获取集合列表

检查 `~/.mongo_sh_tools/config.json` 中的 host、port 是否正确，以及网络是否可达：

```bash
telnet 10.110.0.106 27018
```

连接失败后脚本不会退出，可通过 `[e] 环境切换` 重新选择环境或数据库。

### Q: 如何修改已有配置？

直接编辑 `~/.mongo_sh_tools/config.json`，下次启动时自动生效。也可以删除该文件后重新运行脚本触发配置向导。

### Q: 如何从单环境升级为多环境？

手动编辑 `~/.mongo_sh_tools/config.json`，将原有配置包裹进 `environments` 数组中（参考上方多环境格式），并为每个环境添加 `name` 字段。`defaultLimit` 和 `exportLimit` 放在顶层，所有环境共享。

### Q: 导出的文件在哪里？

导出文件生成在脚本同目录下，命名格式为 `export_<集合名>_<时间戳>.json` 或 `.csv`。

### Q: 如何修改导出条数限制？

在 `~/.mongo_sh_tools/config.json` 中添加或修改 `exportLimit` 字段：

```json
{
  "exportLimit": 50000
}
```

设为 `0` 表示不限制。也可以在每次导出时临时输入不同的值。

### Q: 旧版 .mongo_history 格式不兼容？

历史记录分隔符从 `|` 更新为 tab 字符。如果旧历史记录显示异常，删除历史文件即可，不影响任何功能：

```bash
rm ~/.mongo_sh_tools/.mongo_history
```
