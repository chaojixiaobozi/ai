# Redis 高级数据结构与应用场景

本文档详细介绍 Redis 的高级数据结构：HyperLogLog、Bitmap、RedisBloom、GEO、Stream、Pub/Sub 的结构、应用场景和实际案例。

---

## 1. HyperLogLog

### 结构说明

HyperLogLog 是一种概率性数据结构，用于估算集合的基数（不重复元素的数量）。它使用固定大小的内存（约 12KB），可以估算数十亿级别的基数，误差率约为 0.81%。

**内部结构**：
- 使用 16384 个寄存器（6位寄存器）
- 每个寄存器存储最大前导零的数量
- 通过调和平均数估算基数
- 内存占用固定，与元素数量无关

**数据结构特点**：
```
HyperLogLog Key
├── 16384 个寄存器（每个 6 位）
├── 存储最大前导零数量
└── 通过统计方法估算基数
```

### 应用场景

1. **网站 UV 统计**：统计独立访客数量
2. **用户行为分析**：统计独立用户数、独立 IP 数
3. **大数据去重**：在内存受限情况下估算去重后的数量
4. **实时监控**：统计独立事件数量
5. **A/B 测试**：统计不同版本的独立用户数

### 实际案例：电商网站日活用户统计

**场景**：某电商平台需要统计每日独立访客数（UV），每天可能有数千万次访问，但独立用户可能只有几百万。

**实现步骤**：

```redis
# 1. 添加用户访问记录（自动去重）
PFADD uv:2025-01-15 user:12345 user:67890 user:12345 user:11111

# 2. 查询当日独立访客数
PFCOUNT uv:2025-01-15
# 返回：3（user:12345 被去重）

# 3. 合并多天的数据，统计一周的独立访客数
PFADD uv:2025-01-15 user:12345 user:67890
PFADD uv:2025-01-16 user:12345 user:99999
PFADD uv:2025-01-17 user:67890 user:88888

PFMERGE uv:week:2025-01-15 uv:2025-01-15 uv:2025-01-16 uv:2025-01-17
PFCOUNT uv:week:2025-01-15
# 返回：4（一周内的独立访客数）
```

**优势**：
- 内存占用极小：12KB 可统计数十亿级别的基数
- 性能优异：O(1) 时间复杂度
- 适合高并发场景：支持海量数据统计

---

## 2. Bitmap（位图）

### 结构说明

Bitmap 是 Redis 的字符串类型的一种特殊用法，将字符串的每个位（bit）当作标志位使用。每个位可以表示 0 或 1，非常适合表示布尔值集合。

**内部结构**：
- 底层使用字符串存储
- 每个字节 8 位
- 支持按位操作（AND、OR、XOR、NOT）
- 可以按字节范围操作

**数据结构特点**：
```
Bitmap Key (字符串)
├── 字节 0: [bit0 bit1 bit2 bit3 bit4 bit5 bit6 bit7]
├── 字节 1: [bit8 bit9 bit10 bit11 bit12 bit13 bit14 bit15]
└── ...
```

### 应用场景

1. **用户签到系统**：记录用户每日签到状态
2. **在线状态统计**：记录用户在线/离线状态
3. **用户标签系统**：标记用户属性
4. **布隆过滤器**：实现简单的布隆过滤器
5. **活跃度统计**：统计用户活跃天数
6. **权限管理**：用位表示权限开关

### 实际案例：用户签到系统

**场景**：某社交应用需要记录用户每日签到状态，并统计连续签到天数、月度签到天数等。

**实现步骤**：

```redis
# 1. 用户 user:1001 在 2025 年 1 月 15 日签到（第 15 天）
SETBIT sign:2025-01:user:1001 14 1

# 2. 用户 user:1001 在 2025 年 1 月 20 日签到（第 20 天）
SETBIT sign:2025-01:user:1001 19 1

# 3. 查询用户 1 月 15 日是否签到
GETBIT sign:2025-01:user:1001 14
# 返回：1（已签到）

# 4. 统计用户 1 月份签到总天数
BITCOUNT sign:2025-01:user:1001
# 返回：2

# 5. 统计用户 1 月前 15 天的签到天数
BITCOUNT sign:2025-01:user:1001 0 1
# 返回：1（前 16 位中只有 1 位为 1）

# 6. 查找用户第一次签到的日期
BITPOS sign:2025-01:user:1001 1
# 返回：14（第 15 天）

# 7. 批量操作：设置多个位（使用 BITFIELD）
BITFIELD sign:2025-01:user:1001 SET u1 14 1 SET u1 19 1 SET u1 25 1

# 8. 统计多个用户的签到情况（位运算）
# 假设有两个用户，统计同时签到的日期
SETBIT sign:2025-01:user:1001 14 1
SETBIT sign:2025-01:user:1002 14 1
BITOP AND sign:2025-01:both sign:2025-01:user:1001 sign:2025-01:user:1002
BITCOUNT sign:2025-01:both
# 返回：1（两个用户在同一天都签到了）
```

**优势**：
- 内存效率极高：1 个用户 1 个月只需 4 字节（31 天）
- 支持位运算：可以快速进行集合运算
- 操作简单：适合高频读写场景

---

## 3. RedisBloom（布隆过滤器）

### 结构说明

RedisBloom 是 Redis 的一个扩展模块，实现了布隆过滤器（Bloom Filter）。布隆过滤器是一种概率性数据结构，用于判断元素是否**可能存在**于集合中。

**内部结构**：
- 使用多个哈希函数
- 维护一个位数组
- 元素通过多个哈希函数映射到位数组的多个位置
- 查询时检查所有位置是否都为 1

**数据结构特点**：
```
Bloom Filter
├── 位数组（Bit Array）
├── k 个哈希函数（Hash Functions）
├── 错误率（Error Rate）
└── 容量（Capacity）
```

**工作原理**：
1. **添加元素**：通过 k 个哈希函数计算 k 个位置，将这些位置置为 1
2. **查询元素**：通过 k 个哈希函数计算 k 个位置，如果所有位置都为 1，则可能存在；如果有任一位置为 0，则一定不存在

### 应用场景

1. **缓存穿透防护**：在查询数据库前先判断数据是否存在
2. **去重系统**：判断内容是否已处理过
3. **爬虫去重**：判断 URL 是否已爬取
4. **推荐系统**：快速过滤已推荐内容
5. **垃圾邮件过滤**：判断邮件是否可能是垃圾邮件

### 实际案例：防止缓存穿透

**场景**：电商系统查询商品信息，如果商品不存在，大量请求会穿透缓存直接查询数据库，造成数据库压力。使用布隆过滤器可以快速判断商品 ID 是否可能存在。

**实现步骤**：

```redis
# 1. 初始化布隆过滤器（错误率 0.01，容量 100 万）
BF.RESERVE bf:products 0.01 1000000

# 2. 商品上架时，添加到布隆过滤器
BF.ADD bf:products product:12345
BF.ADD bf:products product:67890
BF.MADD bf:products product:11111 product:22222 product:33333

# 3. 查询商品前，先检查布隆过滤器
BF.EXISTS bf:products product:12345
# 返回：1（可能存在，继续查询缓存/数据库）

BF.EXISTS bf:products product:99999
# 返回：0（一定不存在，直接返回，不查询数据库）

# 4. 批量检查
BF.MEXISTS bf:products product:12345 product:99999 product:11111
# 返回：1) (integer) 1
#      2) (integer) 0
#      3) (integer) 1
```

**业务流程**：
```
用户请求商品信息
    ↓
检查布隆过滤器
    ↓
    ├─ 返回 0 → 商品不存在，直接返回（不查数据库）
    └─ 返回 1 → 继续查询缓存
                    ↓
               缓存命中？
                    ↓
            ├─ 是 → 返回缓存数据
            └─ 否 → 查询数据库
                        ↓
                   数据库有数据？
                        ↓
                ├─ 是 → 写入缓存，返回数据
                └─ 否 → 返回空（商品不存在）
```

**优势**：
- 内存占用小：100 万元素仅需约 1.2MB（错误率 0.01）
- 查询速度快：O(k) 时间复杂度，k 为哈希函数数量
- 防止缓存穿透：有效减少无效数据库查询

---

## 4. GEO（地理空间）

### 结构说明

GEO 是 Redis 3.2+ 引入的地理空间数据结构，基于有序集合（Sorted Set）实现，使用 GeoHash 算法将二维坐标编码为一维字符串。

**内部结构**：
- 底层使用 Sorted Set（ZSET）
- 成员（member）存储位置名称
- 分数（score）存储 GeoHash 编码后的值
- 支持半径查询、距离计算

**数据结构特点**：
```
GEO Key (底层为 Sorted Set)
├── Member: 位置名称（如 "beijing"）
├── Score: GeoHash 编码值
└── 支持地理坐标（经度、纬度）
```

**GeoHash 原理**：
- 将地球划分为网格
- 使用二进制编码表示网格位置
- 编码长度决定精度（52 位精度约 0.6 米）

### 应用场景

1. **附近的人/商家**：查找附近的用户、餐厅、商店
2. **配送系统**：查找附近的配送员、仓库
3. **位置服务**：记录用户位置、车辆位置
4. **地理围栏**：判断用户是否在指定区域内
5. **地图应用**：POI（兴趣点）搜索

### 实际案例：附近餐厅搜索

**场景**：某外卖平台需要根据用户位置，查找附近 3 公里内的餐厅，并按距离排序。

**实现步骤**：

```redis
# 1. 添加餐厅位置（经度、纬度、餐厅名称）
GEOADD restaurants 116.397128 39.916527 "restaurant:001"
GEOADD restaurants 116.407526 39.918123 "restaurant:002"
GEOADD restaurants 116.390456 39.910234 "restaurant:003"
GEOADD restaurants 116.415678 39.925678 "restaurant:004"

# 2. 查询餐厅坐标
GEOPOS restaurants restaurant:001
# 返回：1) 1) "116.39712804555892944"
#         2) "39.91652672558038889"

# 3. 计算两个餐厅之间的距离
GEODIST restaurants restaurant:001 restaurant:002 km
# 返回："1.2345"（公里）

# 4. 以某个餐厅为中心，查找 3 公里内的餐厅
GEOSEARCH restaurants FROMMEMBER restaurant:001 BYRADIUS 3 km WITHDIST
# 返回：
# 1) 1) "restaurant:001"
#    2) "0.0000"
# 2) 1) "restaurant:002"
#    2) "1.2345"
# 3) 1) "restaurant:003"
#    2) "0.8765"

# 5. 以坐标为中心，查找附近的餐厅
GEOSEARCH restaurants FROMLONLAT 116.397128 39.916527 BYRADIUS 3 km WITHDIST ASC COUNT 10

# 6. 获取餐厅的 GeoHash 值（可用于其他系统）
GEOHASH restaurants restaurant:001
# 返回：1) "wx4g0b7xrt0"

# 7. 将搜索结果保存到新的键中
GEOSEARCHSTORE nearby:restaurants restaurants FROMMEMBER restaurant:001 BYRADIUS 3 km
```

**业务流程**：
```
用户打开外卖 App
    ↓
获取用户当前位置（GPS）
    ↓
调用 GEOSEARCH 查询附近餐厅
    ↓
返回餐厅列表（按距离排序）
    ↓
展示在地图上
```

**优势**：
- 查询效率高：O(N+log(M))，N 为结果数量，M 为集合大小
- 支持复杂查询：半径查询、矩形查询
- 距离计算准确：基于 Haversine 公式

---

## 5. Stream（流）

### 结构说明

Stream 是 Redis 5.0+ 引入的日志型数据结构，类似于 Kafka 的消息队列，支持消息持久化、消费组、消息确认等特性。

**内部结构**：
- 使用 Radix Tree（基数树）存储消息
- 每条消息有唯一 ID（时间戳-序号）
- 支持多个消费组（Consumer Group）
- 每个消费组可以有多个消费者（Consumer）

**数据结构特点**：
```
Stream Key
├── 消息列表（按 ID 排序）
│   ├── 消息 ID: 1699341234-0
│   │   ├── field1: value1
│   │   └── field2: value2
│   └── 消息 ID: 1699341235-0
│       └── ...
├── 消费组列表
│   ├── Group1
│   │   ├── Consumer1 (待处理消息列表)
│   │   └── Consumer2 (待处理消息列表)
│   └── Group2
└── Pending 列表（已读取但未确认的消息）
```

### 应用场景

1. **消息队列**：异步任务处理、事件驱动架构
2. **日志收集**：应用日志、审计日志
3. **事件溯源**：记录系统状态变化历史
4. **数据同步**：主从数据同步、多数据中心同步
5. **实时数据流**：传感器数据、用户行为数据

### 实际案例：订单处理系统

**场景**：电商系统需要处理订单，包括创建订单、支付、发货、确认收货等步骤。使用 Stream 实现异步订单处理流程。

**实现步骤**：

```redis
# 1. 创建订单，发送到订单流
XADD orders * order_id "ORD001" user_id "1001" amount "299.00" status "created"
# 返回：1699341234-0（消息 ID）

# 2. 创建消费组（处理订单）
XGROUP CREATE orders order-processors 0 MKSTREAM

# 3. 消费者 1 读取订单（处理支付）
XREADGROUP GROUP order-processors consumer1 COUNT 1 STREAMS orders >
# 返回：
# 1) 1) "orders"
#    2) 1) 1) "1699341234-0"
#          2) 1) "order_id"
#             2) "ORD001"
#             3) "user_id"
#             4) "1001"
#             5) "amount"
#             6) "299.00"
#             7) "status"
#             8) "created"

# 4. 支付完成后，更新订单状态
XADD orders * order_id "ORD001" status "paid"

# 5. 确认消息已处理
XACK orders order-processors 1699341234-0

# 6. 消费者 2 读取订单（处理发货）
XREADGROUP GROUP order-processors consumer2 COUNT 1 STREAMS orders >
# 读取到支付完成的消息

# 7. 查看待处理消息（Pending List）
XPENDING orders order-processors - + 10
# 返回：已读取但未确认的消息列表

# 8. 查看特定消费者的待处理消息
XPENDING orders order-processors - + 10 consumer1

# 9. 读取历史消息（从指定 ID 开始）
XREAD COUNT 10 STREAMS orders 0-0

# 10. 限制流长度（只保留最近 1000 条消息）
XTRIM orders MAXLEN 1000

# 11. 删除消息
XDEL orders 1699341234-0
```

**业务流程**：
```
用户下单
    ↓
XADD 写入订单流
    ↓
消费组 order-processors
    ├─ Consumer1（支付服务）读取订单
    │   ↓
    │   处理支付
    │   ↓
    │   XACK 确认
    │   ↓
    │   XADD 写入支付完成消息
    │
    └─ Consumer2（发货服务）读取支付完成消息
        ↓
        处理发货
        ↓
        XACK 确认
        ↓
        XADD 写入发货完成消息
```

**优势**：
- 消息持久化：数据不会丢失
- 消费组模式：支持多个消费者并行处理
- 消息确认机制：保证消息不丢失
- 支持阻塞读取：实时处理新消息

---

## 6. Pub/Sub（发布订阅）

### 结构说明

Pub/Sub 是 Redis 的发布订阅模式，实现消息的发布和订阅。发布者（Publisher）发送消息到频道（Channel），订阅者（Subscriber）订阅频道接收消息。

**内部结构**：
- 使用字典存储频道和订阅者列表
- 支持精确匹配和模式匹配
- 消息不持久化（实时传输）
- 订阅者断开连接后消息丢失

**数据结构特点**：
```
Pub/Sub 系统
├── 频道字典（Channel Dictionary）
│   ├── channel1 → [subscriber1, subscriber2, ...]
│   └── channel2 → [subscriber3, ...]
├── 模式字典（Pattern Dictionary）
│   └── news:* → [subscriber4, ...]
└── 订阅者列表（Subscriber List）
```

### 应用场景

1. **实时通知**：系统通知、消息推送
2. **事件广播**：系统事件、状态变更通知
3. **聊天系统**：群聊、频道聊天
4. **配置更新**：配置变更通知所有服务
5. **缓存失效**：分布式缓存失效通知

### 实际案例：系统配置热更新

**场景**：微服务架构中，多个服务需要共享配置。当配置更新时，需要通知所有相关服务重新加载配置。

**实现步骤**：

```redis
# ===== 发布者（配置管理服务）=====

# 1. 发布配置更新消息
PUBLISH config:update "database:host=192.168.1.100"
PUBLISH config:update "cache:ttl=3600"

# 2. 发布到模式频道
PUBLISH config:database:update "host=192.168.1.100"
PUBLISH config:cache:update "ttl=3600"

# ===== 订阅者（应用服务）=====

# 3. 订阅精确频道
SUBSCRIBE config:update
# 客户端进入订阅模式，等待消息
# 收到消息：
# 1) "message"
# 2) "config:update"
# 3) "database:host=192.168.1.100"

# 4. 订阅多个频道
SUBSCRIBE config:update config:database:update

# 5. 模式订阅（订阅所有 config:* 开头的频道）
PSUBSCRIBE config:*
# 收到消息：
# 1) "pmessage"
# 2) "config:*"
# 3) "config:database:update"
# 4) "host=192.168.1.100"

# 6. 取消订阅
UNSUBSCRIBE config:update
PUNSUBSCRIBE config:*

# ===== 实际应用示例 =====

# 发布者代码（Python 伪代码）
import redis
r = redis.Redis()

# 配置更新后，发布消息
def update_config(key, value):
    # 更新配置存储（如数据库）
    save_config(key, value)
    # 发布更新消息
    r.publish('config:update', f"{key}={value}")

# 订阅者代码（Python 伪代码）
def config_listener():
    pubsub = r.pubsub()
    pubsub.subscribe('config:update')
    
    for message in pubsub.listen():
        if message['type'] == 'message':
            config_data = message['data'].decode()
            # 解析配置并重新加载
            reload_config(config_data)
```

**业务流程**：
```
配置管理服务更新配置
    ↓
PUBLISH 发布配置更新消息
    ↓
Redis 广播消息到所有订阅者
    ↓
应用服务 1 接收消息 → 重新加载配置
应用服务 2 接收消息 → 重新加载配置
应用服务 3 接收消息 → 重新加载配置
```

**优势**：
- 解耦：发布者和订阅者不需要知道对方的存在
- 实时性：消息实时推送
- 灵活性：支持精确匹配和模式匹配

**注意事项**：
- 消息不持久化：订阅者离线期间的消息会丢失
- 不适合可靠消息传递：如需可靠性，使用 Stream
- 性能：大量订阅者时，Redis 需要向所有订阅者发送消息

---

## 总结对比

| 数据结构 | 主要用途 | 内存效率 | 持久化 | 适用场景 |
|---------|---------|---------|--------|---------|
| **HyperLogLog** | 基数估算 | 极高（固定 12KB） | 支持 | 大数据去重统计 |
| **Bitmap** | 位标志 | 极高（1 位/元素） | 支持 | 签到、在线状态 |
| **RedisBloom** | 存在性判断 | 高（约 1.2MB/100万） | 支持 | 缓存穿透防护 |
| **GEO** | 地理位置 | 中等 | 支持 | 附近搜索、LBS |
| **Stream** | 消息队列 | 中等 | 支持 | 异步处理、日志 |
| **Pub/Sub** | 消息广播 | 低（不存储） | 不支持 | 实时通知、事件 |

---

## 选择建议

- **需要统计不重复数量** → HyperLogLog
- **需要记录布尔状态** → Bitmap
- **需要判断元素是否存在** → RedisBloom
- **需要地理位置查询** → GEO
- **需要可靠的消息队列** → Stream
- **需要实时消息广播** → Pub/Sub
