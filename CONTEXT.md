# MongoDB 交互管理

该上下文描述在终端中选择 MongoDB 环境、数据库和集合，并对集合执行查询与管理操作的语言。

## Language

**Collection workspace**:
当前选定的 MongoDB 环境、数据库、集合及其字段发现结果。
_Avoid_: field cache, current collection state

**Transfer job**:
一次经用户确认后执行的集合数据导入或导出。
_Avoid_: file operation, import/export task
