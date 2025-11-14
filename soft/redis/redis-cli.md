## Redis 常用命令速览（按对象分类）

### 基础信息
| 命令 | 作用 | 参数说明 / Demo |
| --- | --- | --- |
| `PING` | 测试连接是否可用 | `PING` → 返回 `PONG` |
| `AUTH <password>` | 客户端认证 | `AUTH mypass`；若启用 ACL，可用 `AUTH user pass` |
| `SETEX <key> <seconds> <value>` | 设置字符串并指定过期时间 | `SETEX session:1 300 token123` |
| `EXPIRE <key> <seconds>` | 设置键过期时间 | `EXPIRE cache:user 60`；查询剩余时间用 `TTL cache:user` |
| `DEL <key...>` | 删除键 | `DEL user:1 user:2` |
| `UNLINK <key...>` | 异步删除，降低阻塞 | `UNLINK big:list` |
| `TYPE <key>` | 查看键类型 | `TYPE user:profile` → 返回 `hash` |
| `MOVE <key> <db>` | 将键迁移到指定 DB | `MOVE temp 1` |
| `SCAN <cursor> [MATCH pattern] [COUNT n]` | 游标遍历键空间 | `SCAN 0 MATCH user:* COUNT 100` |
| `KEYS <pattern>` | 按模式列出键（慎用） | `KEYS session:*`；大规模场景改用 `SCAN` |

### 字符串 String
| 命令 | 作用 | 参数说明 / Demo |
| --- | --- | --- |
| `SET <key> <value> [NX|XX] [EX|PX ttl]` | 写入字符串，支持条件与过期 | `SET lock:order 1 NX EX 10` 用作分布式锁 |
| `GET <key>` | 读取字符串 | `GET user:1:name` |
| `MSET <key value...>` | 批量写入 | `MSET user:1:name Bob user:1:age 18` |
| `MGET <key...>` | 批量读取 | `MGET user:1:name user:1:age` |
| `GETSET <key> <value>` | 设置新值并返回旧值 | `GETSET counter 0` |
| `INCR <key>` / `DECR <key>` | 将值加 1 / 减 1 | `INCR visit:2025-11-07` |
| `INCRBYFLOAT <key> <increment>` | 浮点自增 | `INCRBYFLOAT price 0.5` |
| `APPEND <key> <suffix>` | 追加内容 | `APPEND log "line"` |
| `STRLEN <key>` | 获取字符串长度 | `STRLEN user:bio` |
| `GETRANGE <key> <start> <end>` | 截取子串 | `GETRANGE token 0 7` |
| `SETNX <key> <value>` | 仅在键不存在时写入 | `SETNX initFlag 1` |
| `BITOP <op> <dest> <key...>` | 位运算 | `BITOP OR online:all online:pc online:mobile` |
| `BITCOUNT <key> [start end]` | 统计位图中 1 的数量 | `BITCOUNT online:2025-11-07` |
| `GETBIT <key> <offset>` | 读取指定 bit | `GETBIT online:2025-11-07 123` |

### 哈希 Hash
| 命令 | 作用 | 参数说明 / Demo |
| --- | --- | --- |
| `HSET <key> <field> <value>` | 设置字段值 | `HSET user:1 name Bob` |
| `HGET <key> <field>` | 读取字段值 | `HGET user:1 name` |
| `HGETALL <key>` | 取出整条哈希 | `HGETALL user:1` |
| `HMSET <key> <field value...>` | 批量写字段 | `HMSET user:1 age 18 city "BJ"` |
| `HMGET <key> <field...>` | 批量读字段 | `HMGET user:1 age city` |
| `HDEL <key> <field...>` | 删除字段 | `HDEL user:1 city` |
| `HEXISTS <key> <field>` | 判断字段存在 | `HEXISTS user:1 email` |
| `HINCRBY <key> <field> <increment>` | 整数加减 | `HINCRBY user:1 score 5` |
| `HINCRBYFLOAT <key> <field> <increment>` | 浮点加减 | `HINCRBYFLOAT user:1 balance -12.5` |
| `HKEYS <key>` / `HVALS <key>` | 列出所有字段 / 值 | `HKEYS user:1` |
| `HSCAN <key> <cursor> [MATCH pattern] [COUNT n]` | 游标遍历哈希 | `HSCAN user:1 0 MATCH addr:* COUNT 50` |

### 列表 List
| 命令 | 作用 | 参数说明 / Demo |
| --- | --- | --- |
| `LPUSH <key> <value...>` | 从左侧插入 | `LPUSH queue job3 job2` |
| `RPUSH <key> <value...>` | 从右侧插入 | `RPUSH queue job1` |
| `LPOP <key>` / `RPOP <key>` | 从左 / 右弹出 | `LPOP queue` |
| `BLPOP <key...> <timeout>` | 阻塞弹出左端 | `BLPOP queue 5`（超时 5 秒） |
| `BRPOP <key...> <timeout>` | 阻塞弹出右端 | `BRPOP queue 0`（0 表示永久阻塞） |
| `LRANGE <key> <start> <stop>` | 获取区间元素 | `LRANGE queue 0 9` |
| `LLEN <key>` | 列表长度 | `LLEN queue` |
| `LINSERT <key> BEFORE|AFTER <pivot> <value>` | 在 pivot 附近插入 | `LINSERT queue BEFORE job1 job0` |
| `LREM <key> <count> <value>` | 删除匹配元素 | `LREM queue 0 job1`（0 表示删全部） |
| `LTRIM <key> <start> <stop>` | 裁剪列表 | `LTRIM queue 0 99` 保留前 100 个 |

### 集合 Set
| 命令 | 作用 | 参数说明 / Demo |
| --- | --- | --- |
| `SADD <key> <member...>` | 添加成员 | `SADD tags user1 user2` |
| `SREM <key> <member...>` | 移除成员 | `SREM tags user2` |
| `SMEMBERS <key>` | 查看所有成员 | `SMEMBERS tags` |
| `SISMEMBER <key> <member>` | 判断成员存在 | `SISMEMBER tags user1` |
| `SCARD <key>` | 成员数量 | `SCARD tags` |
| `SPOP <key> [count]` | 随机弹出 | `SPOP tags 2` |
| `SRANDMEMBER <key> [count]` | 随机获取（不删除） | `SRANDMEMBER tags 3` |
| `SDIFF <key...>` | 差集 | `SDIFF set:a set:b` |
| `SINTER <key...>` | 交集 | `SINTER set:a set:b` |
| `SUNION <key...>` | 并集 | `SUNION set:a set:b` |
| `SDIFFSTORE` / `SINTERSTORE` / `SUNIONSTORE` | 运算结果写入目标集合 | `SINTERSTORE set:c set:a set:b` |
| `SSCAN <key> <cursor> [MATCH pattern] [COUNT n]` | 游标遍历集合 | `SSCAN tags 0 MATCH user:* COUNT 100` |

### 有序集合 Sorted Set
| 命令 | 作用 | 参数说明 / Demo |
| --- | --- | --- |
| `ZADD <key> [NX|XX] [GT|LT] <score> <member> ...` | 添加或更新成员分数 | `ZADD rank 100 user1 80 user2` |
| `ZMPOP <numkeys> <key...> MIN|MAX [COUNT count]` | 按最小/大分数弹出 | `ZMPOP 1 rank MIN COUNT 2` |
| `ZRANGE <key> <start> <stop> [WITHSCORES]` | 按索引区间获取 | `ZRANGE rank 0 9 WITHSCORES` |
| `ZREVRANGE <key> <start> <stop>` | 逆序获取 | `ZREVRANGE rank 0 9` |
| `ZRANGEBYSCORE <key> <min> <max> [WITHSCORES] [LIMIT offset count]` | 按分数区间取成员 | `ZRANGEBYSCORE rank 50 100 WITHSCORES LIMIT 0 5` |
| `ZREVRANGEBYSCORE <key> <max> <min>` | 逆序按分数区间 | `ZREVRANGEBYSCORE rank 100 80` |
| `ZCARD <key>` | 成员数量 | `ZCARD rank` |
| `ZCOUNT <key> <min> <max>` | 区间数量 | `ZCOUNT rank 80 100` |
| `ZINCRBY <key> <increment> <member>` | 调整成员分数 | `ZINCRBY rank 5 user1` |
| `ZRANK <key> <member>` / `ZREVRANK` | 查询排名 | `ZRANK rank user1` |
| `ZREM <key> <member...>` | 删除成员 | `ZREM rank user3` |
| `ZREMRANGEBYRANK <key> <start> <stop>` | 按排名删 | `ZREMRANGEBYRANK rank 0 9` |
| `ZREMRANGEBYSCORE <key> <min> <max>` | 按分数删 | `ZREMRANGEBYSCORE rank 0 50` |
| `ZINTER <numkeys> <key...> [WEIGHTS w...] [AGGREGATE SUM|MIN|MAX]` | 有序集合交集 | `ZINTER 2 rank:day rank:week WEIGHTS 1 0.5` |
| `ZUNION <numkeys> <key...>` | 有序集合并集 | `ZUNION 2 rank:day rank:week` |

### HyperLogLog
| 命令 | 作用 | 参数说明 / Demo |
| --- | --- | --- |
| `PFADD <key> <element...>` | 添加元素 | `PFADD pv:2025-11-07 user1 user2` |
| `PFCOUNT <key...>` | 估算基数 | `PFCOUNT pv:2025-11-07`；可对多个键估算并集 |
| `PFMERGE <dest> <source...>` | 合并 HyperLogLog | `PFMERGE pv:week pv:mon pv:tue` |

### 位图 Bitmap
| 命令 | 作用 | 参数说明 / Demo |
| --- | --- | --- |
| `SETBIT <key> <offset> <value>` | 设置指定 bit | `SETBIT online:2025-11-07 123 1` |
| `GETBIT <key> <offset>` | 获取指定 bit | `GETBIT online:2025-11-07 123` |
| `BITCOUNT <key> [start end]` | 统计位图中 1 的数量 | `BITCOUNT online:2025-11-07` |
| `BITPOS <key> <bit> [start end]` | 查找首个设定位 | `BITPOS online:2025-11-07 1` |
| `BITFIELD <key> [GET|SET|INCRBY type offset value]...` | 批量位操作 | `BITFIELD flags GET u8 0 SET u8 0 7` |
| `BITOP <op> <dest> <key...>` | 多位图按位运算 | `BITOP AND online:both online:pc online:mobile` |

### 布隆过滤器（RedisBloom 模块）
| 命令 | 作用 | 参数说明 / Demo |
| --- | --- | --- |
| `BF.RESERVE <key> <error-rate> <capacity>` | 初始化过滤器 | `BF.RESERVE bf:user 0.01 100000` |
| `BF.ADD <key> <item>` | 插入元素 | `BF.ADD bf:user user1` |
| `BF.MADD <key> <item...>` | 批量插入 | `BF.MADD bf:user user2 user3` |
| `BF.EXISTS <key> <item>` | 判断是否可能存在 | `BF.EXISTS bf:user user1` |
| `BF.MEXISTS <key> <item...>` | 批量判断 | `BF.MEXISTS bf:user user1 user9` |

### 地理空间 Geo
| 命令 | 作用 | 参数说明 / Demo |
| --- | --- | --- |
| `GEOADD <key> <lon> <lat> <member> ...` | 添加地理位置 | `GEOADD shop 116.397 39.908 beijing` |
| `GEOPOS <key> <member...>` | 获取坐标 | `GEOPOS shop beijing` |
| `GEODIST <key> <member1> <member2> [unit]` | 计算距离 | `GEODIST shop beijing shanghai km` |
| `GEOSEARCH <key> FROMMEMBER <member> BYRADIUS <radius> <unit>` | 半径搜索（推荐） | `GEOSEARCH shop FROMMEMBER beijing BYRADIUS 100 km` |
| `GEOHASH <key> <member...>` | 返回 geohash | `GEOHASH shop beijing` |
| `GEOSEARCHSTORE <dest> <key> ...` | 搜索结果保存 | `GEOSEARCHSTORE shop:near shop FROMMEMBER beijing BYRADIUS 5 km` |

### 流 Stream
| 命令 | 作用 | 参数说明 / Demo |
| --- | --- | --- |
| `XADD <key> <id> <field value...>` | 添加消息 | `XADD stream * user 1 action login` |
| `XREAD [COUNT n] [BLOCK ms] STREAMS <key...> <id...>` | 按顺序读取 | `XREAD COUNT 10 STREAMS stream 0-0` |
| `XGROUP CREATE <key> <group> <id> [MKSTREAM]` | 创建消费组 | `XGROUP CREATE stream group1 0 MKSTREAM` |
| `XREADGROUP GROUP <group> <consumer> ...` | 消费组读取 | `XREADGROUP GROUP group1 c1 COUNT 5 STREAMS stream >` |
| `XACK <key> <group> <id...>` | 确认消息 | `XACK stream group1 169934123-0` |
| `XDEL <key> <id...>` | 删除消息 | `XDEL stream 169934123-0` |
| `XPENDING <key> <group> [start end count [consumer]]` | 查看待处理消息 | `XPENDING stream group1 - + 10` |
| `XTRIM <key> MAXLEN|MINID ...` | 截断流数据 | `XTRIM stream MAXLEN 1000` |

### 发布订阅 Pub/Sub
| 命令 | 作用 | 参数说明 / Demo |
| --- | --- | --- |
| `PUBLISH <channel> <message>` | 发布消息 | `PUBLISH news "hello"` |
| `SUBSCRIBE <channel...>` | 订阅频道 | `SUBSCRIBE news` |
| `PSUBSCRIBE <pattern...>` | 模式订阅 | `PSUBSCRIBE news:*` |
| `UNSUBSCRIBE [channel...]` | 取消频道订阅 | `UNSUBSCRIBE news` |
| `PUNSUBSCRIBE [pattern...]` | 取消模式订阅 | `PUNSUBSCRIBE news:*` |

### 事务与脚本
| 命令 | 作用 | 参数说明 / Demo |
| --- | --- | --- |
| `MULTI` | 开启事务（入队命令） | `MULTI` → 后续命令排队 |
| `EXEC` / `DISCARD` | 提交 / 放弃事务 | `EXEC` 执行，`DISCARD` 放弃 |
| `WATCH <key...>` | 监视键，配合事务实现乐观锁 | `WATCH stock:1` |
| `EVAL <script> <numkeys> <key...> <arg...>` | 执行 Lua | `EVAL "return redis.call('GET', KEYS[1])" 1 user:1:name` |
| `EVALSHA <sha1> ...` | 通过脚本哈希执行 | 先 `SCRIPT LOAD` 后 `EVALSHA` |
| `SCRIPT LOAD <script>` | 将 Lua 脚本加载到缓存 | `SCRIPT LOAD "redis.call('PING')"` |
| `SCRIPT EXISTS <sha1...>` | 检查脚本是否存在 | `SCRIPT EXISTS 3a5c...` |
| `SCRIPT FLUSH` | 清空脚本缓存 | `SCRIPT FLUSH` |

### 持久化与复制
| 命令 | 作用 | 参数说明 / Demo |
| --- | --- | --- |
| `SAVE` | 阻塞生成 RDB | `SAVE`（阻塞主线程） |
| `BGSAVE` | 后台生成 RDB | `BGSAVE` |
| `BGREWRITEAOF` | 重写 AOF 文件 | `BGREWRITEAOF` |
| `LASTSAVE` | 查看最后一次成功保存时间 | `LASTSAVE` |
| `INFO replication` | 查看复制与同步状态 | `INFO replication` |
| `SLAVEOF <host> <port>` | 旧版从节点配置主节点 | `SLAVEOF 10.0.0.1 6379` |
| `REPLICAOF <host> <port>` | 从 Redis 5 开始替代 `SLAVEOF` | `REPLICAOF 10.0.0.1 6379` |
| `PSYNC <replid> <offset>` | 部分复制（内部命令） | 一般由主从自动协商，不手动调用 |

### 服务器管理
| 命令 | 作用 | 参数说明 / Demo |
| --- | --- | --- |
| `INFO [section]` | 查看服务器状态 | `INFO memory` / `INFO` |
| `CONFIG GET <pattern>` | 查询配置 | `CONFIG GET maxmemory` |
| `CONFIG SET <parameter> <value>` | 修改配置 | `CONFIG SET requirepass mypass` |
| `CLIENT LIST` | 列出客户端 | `CLIENT LIST` |
| `CLIENT KILL <filter>` | 杀掉连接 | `CLIENT KILL TYPE pubsub` |
| `MONITOR` | 实时监控命令执行 | `MONITOR`（慎用） |
| `SLOWLOG GET [n]` | 查看慢查询 | `SLOWLOG GET 10` |
| `FLUSHDB` / `FLUSHALL` | 清空当前库 / 所有库 | `FLUSHDB ASYNC` |
| `SHUTDOWN [SAVE|NOSAVE]` | 关闭服务器 | `SHUTDOWN NOSAVE` |

### 集群 Cluster
| 命令 | 作用 | 参数说明 / Demo |
| --- | --- | --- |
| `CLUSTER INFO` | 查看集群整体信息 | `CLUSTER INFO` |
| `CLUSTER NODES` | 查看节点拓扑 | `CLUSTER NODES` |
| `CLUSTER MEET <ip> <port>` | 让节点加入集群 | `CLUSTER MEET 10.0.0.2 6379` |
| `CLUSTER ADDSLOTS <slot...>` | 为节点分配槽位 | `CLUSTER ADDSLOTS 0 1 2 3` |
| `CLUSTER DELSLOTS <slot...>` | 回收槽位 | `CLUSTER DELSLOTS 0 1` |
| `CLUSTER FAILOVER [FORCE|TAKEOVER]` | 触发主从切换 | `CLUSTER FAILOVER` |
| `CLUSTER KEYSLOT <key>` | 计算键所属槽 | `CLUSTER KEYSLOT user:1` → 返回槽号 |

### 推荐实践
- 生产环境中键管理建议使用 `SCAN` 系列避免阻塞
- 使用阻塞式命令时需控制超时时间，避免连接被占满
- 结合 `EXPIRE` / `SETEX` 控制数据生命周期，避免内存膨胀
- 分布式锁、限流等场景要注意原子性（`SET NX PX`、Lua 脚本等方案）

