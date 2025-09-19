# MongoDB 完整教程

## 1. MongoDB 主要架构

### 1.1 整体架构概述

MongoDB 采用分布式架构，支持水平扩展，主要包含以下层次：

```
┌─────────────────────────────────────────────────────────────┐
│                    应用层 (Application Layer)                │
├─────────────────────────────────────────────────────────────┤
│                    驱动层 (Driver Layer)                     │
├─────────────────────────────────────────────────────────────┤
│                   路由层 (Mongos)                           │
├─────────────────────────────────────────────────────────────┤
│                   配置服务器 (Config Servers)                │
├─────────────────────────────────────────────────────────────┤
│                   分片集群 (Sharded Cluster)                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   Shard 1   │  │   Shard 2   │  │   Shard N   │         │
│  │             │  │             │  │             │         │
│  │ Replica Set │  │ Replica Set │  │ Replica Set │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 架构类型

#### 单机部署
- **适用场景**: 开发测试环境
- **特点**: 简单部署，无高可用性

#### 副本集 (Replica Set)
- **适用场景**: 生产环境，需要高可用性
- **特点**: 数据冗余，自动故障转移

#### 分片集群 (Sharded Cluster)
- **适用场景**: 大数据量，需要水平扩展
- **特点**: 数据分片，支持无限扩展

## 2. MongoDB 核心组件

### 2.1 存储引擎

#### WiredTiger (默认)
```
┌─────────────────────────────────────────┐
│              WiredTiger                 │
├─────────────────────────────────────────┤
│  • 文档级并发控制                        │
│  • 压缩存储 (Snappy/Zlib)               │
│  • 检查点机制                           │
│  • 缓存管理 (LRU)                      │
│  • 事务支持 (4.0+)                     │
└─────────────────────────────────────────┘
```

#### In-Memory
- **特点**: 纯内存存储，重启数据丢失
- **适用**: 缓存场景

### 2.2 核心进程

#### mongod (数据节点)
- **功能**: 数据存储和查询处理
- **端口**: 27017 (默认)

#### mongos (路由节点)
- **功能**: 查询路由和负载均衡
- **端口**: 27017 (默认)

#### mongocfg (配置节点)
- **功能**: 存储分片元数据
- **端口**: 27019 (默认)

### 2.3 数据模型

#### 文档结构
```json
{
  "_id": ObjectId("507f1f77bcf86cd799439011"),
  "name": "张三",
  "age": 30,
  "address": {
    "city": "北京",
    "district": "朝阳区"
  },
  "hobbies": ["读书", "游泳", "编程"],
  "created_at": ISODate("2024-01-01T00:00:00Z")
}
```

#### 集合 (Collection)
- 类似关系数据库的表
- 动态模式，无需预定义结构

#### 数据库 (Database)
- 包含多个集合
- 命名空间隔离

## 3. 写入流程详解

### 3.1 单机写入流程

```
应用请求 → 驱动 → mongod → WiredTiger → 磁盘
    ↓
1. 解析请求
2. 验证文档结构
3. 生成_id (如未提供)
4. 写入内存缓存
5. 记录操作日志 (Oplog)
6. 异步写入磁盘
7. 返回确认
```

### 3.2 副本集写入流程

```
┌─────────┐    写入请求    ┌─────────────┐
│  应用   │ ────────────→ │  Primary    │
└─────────┘               │  (主节点)    │
                          └─────────────┘
                                │
                                │ 1. 写入数据
                                │ 2. 记录Oplog
                                ▼
                          ┌─────────────┐
                          │ Secondary 1 │
                          │ (从节点)     │
                          └─────────────┘
                                │
                                │ 异步复制
                                ▼
                          ┌─────────────┐
                          │ Secondary 2 │
                          │ (从节点)     │
                          └─────────────┘
```

### 3.3 分片集群写入流程

```
应用请求 → mongos → 计算分片键 → 路由到目标分片 → 写入副本集
    ↓
1. mongos接收请求
2. 根据分片键计算目标分片
3. 路由请求到对应分片的主节点
4. 分片执行写入操作
5. 返回结果给应用
```

### 3.4 写入优化策略

#### 批量写入
```javascript
// 批量插入优化
db.collection.insertMany([
  {name: "用户1", age: 25},
  {name: "用户2", age: 30},
  {name: "用户3", age: 35}
], {ordered: false}) // 无序插入，性能更好
```

#### 写入关注级别
```javascript
// 不同级别的写入确认
db.collection.insertOne(doc, {writeConcern: {w: 1}})     // 主节点确认
db.collection.insertOne(doc, {writeConcern: {w: "majority"}}) // 多数节点确认
db.collection.insertOne(doc, {writeConcern: {w: 0}})     // 不等待确认
```

## 4. 读取流程详解

### 4.1 单机读取流程

```
应用请求 → 驱动 → mongod → 查询优化器 → 执行计划 → 返回结果
    ↓
1. 解析查询语句
2. 查询优化器分析
3. 选择最优执行计划
4. 从缓存或磁盘读取数据
5. 应用过滤条件
6. 返回匹配文档
```

### 4.2 副本集读取流程

```
┌─────────┐    读取请求    ┌─────────────┐
│  应用   │ ────────────→ │  Primary    │
└─────────┘               │  (主节点)    │
                          └─────────────┘
                                │
                                │ 或
                                ▼
                          ┌─────────────┐
                          │ Secondary   │
                          │ (从节点)     │
                          └─────────────┘
```

### 4.3 分片集群读取流程

```
应用请求 → mongos → 查询分析 → 并行查询各分片 → 结果合并 → 返回
    ↓
1. mongos接收查询请求
2. 分析查询条件
3. 确定需要查询的分片
4. 并行向各分片发送查询
5. 合并各分片结果
6. 排序和分页处理
7. 返回最终结果
```

### 4.4 查询优化

#### 索引策略
```javascript
// 创建复合索引
db.users.createIndex({name: 1, age: -1})

// 创建文本索引
db.articles.createIndex({title: "text", content: "text"})

// 创建地理空间索引
db.locations.createIndex({location: "2dsphere"})
```

#### 查询优化技巧
```javascript
// 使用投影减少网络传输
db.users.find({age: {$gt: 18}}, {name: 1, email: 1})

// 使用limit限制结果集
db.users.find({status: "active"}).limit(100)

// 使用hint强制使用特定索引
db.users.find({name: "张三"}).hint({name: 1})
```

## 5. 常见业务使用场景与性能优化

### 5.1 常见业务场景

#### 内容管理系统
```javascript
// 文章存储结构
{
  _id: ObjectId(),
  title: "MongoDB教程",
  content: "详细内容...",
  author: "张三",
  tags: ["数据库", "NoSQL"],
  publish_date: ISODate(),
  view_count: 1000,
  comments: [
    {
      user: "李四",
      content: "很好的教程",
      created_at: ISODate()
    }
  ]
}

// 创建索引
db.articles.createIndex({title: "text", content: "text"})
db.articles.createIndex({publish_date: -1})
db.articles.createIndex({tags: 1})
```

#### 用户行为分析
```javascript
// 用户行为记录
{
  _id: ObjectId(),
  user_id: "user123",
  action: "page_view",
  page: "/products/laptop",
  timestamp: ISODate(),
  session_id: "session456",
  device: "mobile",
  location: {
    country: "中国",
    city: "北京"
  }
}

// 聚合分析查询
db.user_actions.aggregate([
  {$match: {action: "purchase"}},
  {$group: {_id: "$page", count: {$sum: 1}}},
  {$sort: {count: -1}},
  {$limit: 10}
])
```

#### 实时推荐系统
```javascript
// 用户偏好存储
{
  _id: ObjectId(),
  user_id: "user123",
  preferences: {
    categories: ["电子产品", "图书"],
    price_range: [100, 1000],
    brands: ["苹果", "华为"]
  },
  behavior_score: 0.85,
  last_updated: ISODate()
}

// 推荐查询
db.user_preferences.find({
  "preferences.categories": {$in: ["电子产品"]},
  behavior_score: {$gt: 0.7}
})
```

### 5.2 性能优化案例

#### 案例1: 大表查询优化

**问题**: 用户表有1000万条记录，按年龄查询很慢

**优化方案**:
```javascript
// 1. 创建索引
db.users.createIndex({age: 1})

// 2. 使用复合索引
db.users.createIndex({age: 1, status: 1})

// 3. 查询优化
// 优化前
db.users.find({age: {$gte: 18, $lte: 65}})

// 优化后
db.users.find({age: {$gte: 18, $lte: 65}, status: "active"})
```

#### 案例2: 聚合查询优化

**问题**: 订单统计查询耗时过长

**优化方案**:
```javascript
// 1. 创建索引
db.orders.createIndex({order_date: -1, status: 1})
db.orders.createIndex({customer_id: 1, order_date: -1})

// 2. 使用聚合管道优化
db.orders.aggregate([
  {$match: {
    order_date: {$gte: ISODate("2024-01-01")},
    status: "completed"
  }},
  {$group: {
    _id: {$dateToString: {format: "%Y-%m", date: "$order_date"}},
    total_amount: {$sum: "$amount"},
    order_count: {$sum: 1}
  }},
  {$sort: {_id: 1}}
])
```

#### 案例3: 分片键选择优化

**问题**: 数据分布不均匀，查询性能差

**优化方案**:
```javascript
// 1. 选择合适的分片键
// 优化前: 使用_id作为分片键
sh.shardCollection("mydb.users", {_id: 1})

// 优化后: 使用复合分片键
sh.shardCollection("mydb.users", {user_id: 1, created_at: 1})

// 2. 确保分片键具有高基数
db.users.aggregate([
  {$group: {_id: "$user_id", count: {$sum: 1}}},
  {$group: {_id: null, unique_users: {$sum: 1}}}
])
```

### 5.3 监控与调优

#### 性能监控指标
```javascript
// 查看慢查询
db.setProfilingLevel(2, {slowms: 100})
db.system.profile.find().sort({ts: -1}).limit(5)

// 查看索引使用情况
db.users.aggregate([{$indexStats: {}}])

// 查看集合统计信息
db.users.stats()

// 查看当前操作
db.currentOp()
```

#### 内存优化
```javascript
// 配置缓存大小
storage:
  wiredTiger:
    engineConfig:
      cacheSizeGB: 8  # 设置为可用内存的50-60%

// 监控内存使用
db.serverStatus().wiredTiger.cache
```

## 6. 最佳实践总结

### 6.1 设计原则
1. **文档设计**: 合理嵌套，避免过度嵌套
2. **索引策略**: 为常用查询创建合适索引
3. **分片键选择**: 确保数据分布均匀
4. **写入优化**: 使用批量操作，合理设置写入关注级别

### 6.2 运维建议
1. **监控**: 定期监控性能指标
2. **备份**: 建立完善的备份策略
3. **升级**: 及时升级到稳定版本
4. **安全**: 启用认证和授权

### 6.3 常见陷阱
1. **过度索引**: 索引过多影响写入性能
2. **大文档**: 单个文档过大影响性能
3. **无分片键查询**: 导致全分片扫描
4. **忽略连接池**: 连接数配置不当

---

*本教程涵盖了MongoDB的核心概念、架构设计、操作流程和优化实践，帮助您快速掌握MongoDB的使用和优化技巧。*
