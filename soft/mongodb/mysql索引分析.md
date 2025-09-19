好的，我来帮你详细拆解这个执行计划的各部分含义，让你完全理解 **每个字段和阶段的作用**。为了清晰，我会按照 **逻辑顺序**讲解。

---

## 1️⃣ 顶层结构

```json
{
  "stages": [...],
  "serverInfo": {...},
  "command": {...},
  "ok": 1.0,
  "operationTime": ...
}
```

* `stages` → 聚合管道的每个阶段执行计划和统计信息
* `serverInfo` → 服务器信息（Mongo 版本、主机、端口）
* `command` → 本次执行的命令，包括 `aggregate` 的 pipeline
* `ok` → 命令是否成功
* `operationTime` → 执行时间戳

---

## 2️⃣ `stages[0]` → `$cursor` 阶段

```json
{
  '$cursor': {
    'queryPlanner': {...},
    'executionStats': {...}
  }
}
```

* `$cursor` 阶段 → 聚合的起点，表示从集合扫描文档（可能走索引）
* `queryPlanner` → **查询规划信息**（Mongo 如何选择索引和扫描方式）
* `executionStats` → **实际执行统计**（扫描多少文档、耗时等）

---

## 3️⃣ `queryPlanner` 关键字段

```json
'winningPlan': {
  'stage': "FETCH",
  'filter': {...},
  'inputStage': {
    'stage': "IXSCAN",
    'keyPattern': {...},
    'indexName': "...",
    'indexBounds': {...}
  }
}
```

### 各部分含义：

* `winningPlan` → Mongo 选择的最终执行计划
* `stage: "FETCH"` → 从索引扫描到的文档再去**主集合中获取完整文档**，并应用 `filter`

  * 这里 `filter` 就是 `$match` 中索引未覆盖的条件
* `inputStage: IXSCAN` → **索引扫描阶段**

  * `keyPattern` → 索引字段顺序 `{ delFlag: 1, updateTime: -1 }`
  * `indexName` → 使用的索引名称
  * `indexBounds` → 索引扫描范围

    * `"delFlag": ["[\"0\",\"0\"]"]` → 索引在 `delFlag=0` 上扫描
    * `"updateTime": ["[MaxKey, MinKey]"]` → `updateTime` 没有限制（全扫描）

---

## 4️⃣ `executionStats` → 执行统计

```json
'totalKeysExamined': 187194,
'totalDocsExamined': 187194,
'nReturned': 0
```

* `totalKeysExamined` → 索引条目扫描数量
* `totalDocsExamined` → 实际读取的文档数（FETCH 阶段）
* `nReturned` → 返回给客户端的文档数

🔍 从数据看：

* 索引只用到了 `delFlag`，`issueTime` + `userType` 都在 FETCH 阶段过滤
* 所以扫描了 187k 条文档，但返回 0 条

---

## 5️⃣ `$group` 阶段

```json
{
  '$group': {
    '_id': {'$const': null},
    'count': {'$sum': {'$const': 1}}
  },
  'maxAccumulatorMemoryUsageBytes': 0,
  'totalOutputDataSizeBytes': 0,
  'usedDisk': false
}
```

* 聚合阶段，用于统计数量
* `_id: null` → 全部聚合为一条结果
* `count: { $sum: 1 }` → 累加每条文档
* `usedDisk: false` → 内存足够，没有使用磁盘临时存储

---

## 6️⃣ 优化建议

从计划里可以看出：

* **走了索引** → `IXSCAN`
* **索引覆盖不全** → `issueTime` + `userType` 在 FETCH 阶段过滤
* **扫描量大** → 187k 条文档

✅ 建议索引：

```js
db.articleComment.createIndex({ delFlag: 1, userType: 1, issueTime: 1 })
```

* 这样 `$match` 三个条件都走索引
* `FETCH` 阶段只过滤非常少的文档
* 执行效率大幅提升

---

如果你愿意，我可以画一张 **执行流程图**，直观显示 **IXSCAN → FETCH → \$group** 流程和每个字段的作用，这样更容易理解索引优化前后的区别。
