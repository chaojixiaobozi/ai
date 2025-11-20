# Redis 事务与脚本、持久化与复制

本文档详细介绍 Redis 的事务与脚本机制、持久化与复制机制的结构、处理流程和实际案例。

---

## 第一部分：事务与脚本

## 1. 事务（Transaction）

### 结构说明

Redis 事务通过 `MULTI`、`EXEC`、`DISCARD`、`WATCH` 命令实现。事务将多个命令打包，按顺序执行，保证原子性（要么全部执行，要么全部不执行）。

**事务结构**：
```
事务流程
├── MULTI（开启事务）
│   └── 命令入队（Command Queue）
│       ├── 命令1
│       ├── 命令2
│       └── 命令3
├── EXEC（执行事务）
│   └── 按顺序执行所有命令
│       └── 返回所有命令的执行结果
└── DISCARD（取消事务）
    └── 清空命令队列，不执行
```

**WATCH 机制**：
```
WATCH 键
    ↓
监控键的变化
    ↓
MULTI ... EXEC
    ↓
检查键是否被修改
    ├─ 未修改 → 执行事务
    └─ 已修改 → 事务失败（返回 nil）
```

### 处理流程

#### 标准事务流程

```
1. 客户端发送 MULTI
   ↓
2. Redis 返回 OK，进入事务模式
   ↓
3. 客户端发送多个命令
   ↓
4. Redis 将命令入队，返回 QUEUED
   ↓
5. 客户端发送 EXEC
   ↓
6. Redis 按顺序执行所有命令
   ↓
7. 返回所有命令的执行结果数组
```

#### WATCH 乐观锁流程

```
1. 客户端发送 WATCH key
   ↓
2. Redis 记录被监控的键
   ↓
3. 客户端发送 MULTI
   ↓
4. 客户端发送命令（如 INCR key）
   ↓
5. 客户端发送 EXEC
   ↓
6. Redis 检查 key 是否被修改
   ├─ 未修改 → 执行事务，返回结果
   └─ 已修改 → 事务失败，返回 nil
```

### 实际案例：库存扣减

**场景**：电商系统中，多个用户同时购买同一商品，需要保证库存扣减的原子性，避免超卖。

**实现步骤**：

```redis
# ===== 方案 1：使用事务保证原子性 =====

# 1. 设置商品库存
SET stock:product:1001 100

# 2. 用户购买商品（扣减库存）
MULTI
GET stock:product:1001
DECR stock:product:1001
EXEC
# 返回：
# 1) "100"
# 2) (integer) 99

# ===== 方案 2：使用 WATCH + 事务实现乐观锁 =====

# 客户端 1
WATCH stock:product:1001
MULTI
GET stock:product:1001
DECR stock:product:1001
EXEC
# 如果 stock:product:1001 在执行期间未被修改，返回结果
# 如果被修改，返回 (nil)

# 客户端 2（同时执行）
WATCH stock:product:1001
MULTI
GET stock:product:1001
DECR stock:product:1001
EXEC
# 如果客户端 1 已经修改了库存，此事务会失败

# ===== 方案 3：使用 Lua 脚本（推荐，见下文）=====
```

**业务流程**：
```
用户下单
    ↓
WATCH 监控库存键
    ↓
MULTI 开启事务
    ↓
检查库存是否充足
    ↓
扣减库存
    ↓
EXEC 执行事务
    ↓
    ├─ 成功 → 库存已扣减，继续订单流程
    └─ 失败（返回 nil）→ 库存已被其他请求修改，重试或返回失败
```

**注意事项**：
- Redis 事务不支持回滚：即使某个命令失败，其他命令仍会执行
- 事务中的命令不会立即执行：只有在 EXEC 时才执行
- WATCH 只在 EXEC 时检查：如果在 MULTI 和 EXEC 之间键被修改，事务会失败

---

## 2. Lua 脚本

### 结构说明

Redis 支持执行 Lua 脚本，脚本在服务器端原子性执行，可以执行多个 Redis 命令，保证原子性。

**脚本结构**：
```
Lua 脚本
├── 脚本内容（Lua 代码）
├── KEYS 数组（键名参数）
├── ARGV 数组（其他参数）
└── 返回值（Lua 值转换为 Redis 协议）
```

**执行方式**：
1. **EVAL**：直接执行脚本
2. **EVALSHA**：通过脚本 SHA1 哈希执行（需先 SCRIPT LOAD）
3. **SCRIPT LOAD**：加载脚本到服务器缓存
4. **SCRIPT EXISTS**：检查脚本是否存在
5. **SCRIPT FLUSH**：清空脚本缓存

### 处理流程

#### EVAL 执行流程

```
1. 客户端发送 EVAL script numkeys key1 key2 ... arg1 arg2 ...
   ↓
2. Redis 解析脚本和参数
   ↓
3. 在 Lua 环境中执行脚本
   ↓
4. 脚本中可以调用 redis.call() 或 redis.pcall()
   ↓
5. 返回脚本执行结果
```

#### EVALSHA 执行流程

```
1. 客户端发送 SCRIPT LOAD script
   ↓
2. Redis 加载脚本，返回 SHA1 哈希
   ↓
3. 客户端发送 EVALSHA sha1 numkeys key1 key2 ... arg1 arg2 ...
   ↓
4. Redis 通过 SHA1 查找脚本
   ↓
5. 执行脚本，返回结果
```

### 实际案例：分布式锁

**场景**：实现分布式锁，支持锁的获取、释放和自动过期。使用 Lua 脚本保证操作的原子性。

**实现步骤**：

```redis
# ===== 方案 1：使用 EVAL 执行脚本 =====

# 1. 获取锁（如果不存在则设置，并设置过期时间）
EVAL "
if redis.call('GET', KEYS[1]) == false then
    redis.call('SET', KEYS[1], ARGV[1])
    redis.call('EXPIRE', KEYS[1], ARGV[2])
    return 1
else
    return 0
end
" 1 lock:order:1001 "client:001" 10
# 返回：1（获取成功）或 0（获取失败）

# 2. 释放锁（只有锁的持有者才能释放）
EVAL "
if redis.call('GET', KEYS[1]) == ARGV[1] then
    return redis.call('DEL', KEYS[1])
else
    return 0
end
" 1 lock:order:1001 "client:001"
# 返回：1（释放成功）或 0（释放失败，不是锁的持有者）

# ===== 方案 2：使用 EVALSHA（推荐，性能更好）=====

# 1. 加载获取锁的脚本
SCRIPT LOAD "
if redis.call('GET', KEYS[1]) == false then
    redis.call('SET', KEYS[1], ARGV[1])
    redis.call('EXPIRE', KEYS[1], ARGV[2])
    return 1
else
    return 0
end
"
# 返回：a1b2c3d4e5f6...（SHA1 哈希）

# 2. 使用 SHA1 执行脚本
EVALSHA a1b2c3d4e5f6... 1 lock:order:1001 "client:001" 10

# 3. 检查脚本是否存在
SCRIPT EXISTS a1b2c3d4e5f6...
# 返回：1) (integer) 1

# ===== 方案 3：完整的分布式锁实现 =====

# 获取锁脚本（支持 SET NX EX 的原子操作）
# 注意：Redis 2.6.12+ 支持 SET NX EX，可以简化脚本
EVAL "
local result = redis.call('SET', KEYS[1], ARGV[1], 'NX', 'EX', ARGV[2])
if result then
    return 1
else
    return 0
end
" 1 lock:resource:001 "client:uuid:12345" 30

# 释放锁脚本（检查锁的持有者）
EVAL "
if redis.call('GET', KEYS[1]) == ARGV[1] then
    return redis.call('DEL', KEYS[1])
else
    return 0
end
" 1 lock:resource:001 "client:uuid:12345"

# 续期脚本（延长锁的过期时间）
EVAL "
if redis.call('GET', KEYS[1]) == ARGV[1] then
    return redis.call('EXPIRE', KEYS[1], ARGV[2])
else
    return 0
end
" 1 lock:resource:001 "client:uuid:12345" 30
```

**业务流程**：
```
客户端 1 尝试获取锁
    ↓
执行获取锁脚本（原子操作）
    ├─ 锁不存在 → 设置锁，返回成功
    └─ 锁已存在 → 返回失败
    ↓
执行业务逻辑
    ↓
执行释放锁脚本（原子操作）
    ├─ 是锁的持有者 → 删除锁，返回成功
    └─ 不是持有者 → 返回失败
```

**优势**：
- 原子性：脚本中的所有操作原子执行
- 性能：减少网络往返次数
- 灵活性：可以执行复杂的业务逻辑

---

## 第二部分：持久化与复制

## 3. 持久化（Persistence）

### 结构说明

Redis 提供两种持久化方式：RDB（Redis Database）和 AOF（Append Only File）。

#### RDB 持久化

**结构**：
```
RDB 文件
├── 文件头（REDIS 版本、数据库信息）
├── 数据库数据
│   ├── 键值对（压缩存储）
│   └── 过期时间（如果有）
└── 文件尾（校验和）
```

**触发方式**：
1. **手动触发**：`SAVE`（阻塞）、`BGSAVE`（后台）
2. **自动触发**：根据配置的保存条件（save 规则）

#### AOF 持久化

**结构**：
```
AOF 文件
├── 命令 1（Redis 协议格式）
├── 命令 2
├── 命令 3
└── ...
```

**写入方式**：
1. **always**：每个命令都同步写入磁盘
2. **everysec**：每秒同步一次（默认）
3. **no**：由操作系统决定何时同步

### 处理流程

#### RDB 持久化流程

```
1. 触发 RDB 保存（手动或自动）
   ↓
2. 如果是 BGSAVE，fork 子进程
   ↓
3. 子进程遍历数据库，生成 RDB 文件
   ↓
4. 父进程继续处理请求
   ↓
5. 子进程完成，替换旧 RDB 文件
   ↓
6. 通知父进程保存完成
```

#### AOF 持久化流程

```
1. 客户端执行命令
   ↓
2. 命令写入 AOF 缓冲区
   ↓
3. 根据配置的同步策略
   ├─ always → 立即同步到磁盘
   ├─ everysec → 每秒同步一次
   └─ no → 由操作系统决定
   ↓
4. 定期 AOF 重写（BGREWRITEAOF）
   ↓
5. 压缩 AOF 文件，生成新的 AOF 文件
```

#### AOF 重写流程

```
1. 触发 AOF 重写（手动或自动）
   ↓
2. fork 子进程
   ↓
3. 子进程读取当前数据库快照
   ↓
4. 将数据库状态转换为 Redis 命令
   ↓
5. 写入新的 AOF 文件
   ↓
6. 父进程继续处理请求，同时写入 AOF 缓冲区
   ↓
7. 子进程完成，通知父进程
   ↓
8. 父进程将 AOF 缓冲区内容追加到新 AOF 文件
   ↓
9. 原子替换旧 AOF 文件
```

### 实际案例：数据备份与恢复

**场景**：生产环境需要定期备份 Redis 数据，并在数据丢失时能够快速恢复。

**实现步骤**：

```redis
# ===== RDB 持久化配置与操作 =====

# 1. 查看当前 RDB 配置
CONFIG GET save
# 返回：
# 1) "save"
# 2) "900 1 300 10 60 10000"
# 含义：900 秒内至少 1 个键变化，或 300 秒内至少 10 个键变化，或 60 秒内至少 10000 个键变化

# 2. 手动触发 RDB 保存（阻塞，不推荐生产环境）
SAVE

# 3. 后台触发 RDB 保存（推荐）
BGSAVE
# 返回：Background saving started by pid 12345

# 4. 查看最后一次保存时间
LASTSAVE
# 返回：(integer) 1699341234

# 5. 配置自动保存规则
CONFIG SET save "3600 1 1800 10 300 100"
# 含义：1 小时内至少 1 个键变化，或 30 分钟内至少 10 个键变化，或 5 分钟内至少 100 个键变化

# ===== AOF 持久化配置与操作 =====

# 1. 启用 AOF
CONFIG SET appendonly yes

# 2. 查看 AOF 配置
CONFIG GET appendonly
CONFIG GET appendfsync
# 返回：
# 1) "appendonly"
# 2) "yes"
# 1) "appendfsync"
# 2) "everysec"

# 3. 设置 AOF 同步策略
CONFIG SET appendfsync everysec
# 可选值：always（每个命令同步）、everysec（每秒同步）、no（操作系统决定）

# 4. 手动触发 AOF 重写
BGREWRITEAOF
# 返回：Background append only file rewriting started by pid 12346

# ===== 数据恢复流程 =====

# 1. 停止 Redis 服务
SHUTDOWN

# 2. 恢复 RDB 文件
# 将备份的 RDB 文件复制到 Redis 数据目录（dbfilename 配置的路径）
# 默认文件名：dump.rdb

# 3. 恢复 AOF 文件
# 将备份的 AOF 文件复制到 Redis 数据目录（appendfilename 配置的路径）
# 默认文件名：appendonly.aof

# 4. 启动 Redis 服务
# Redis 会自动加载 RDB 或 AOF 文件

# ===== 混合持久化（Redis 4.0+）=====

# 1. 启用混合持久化
CONFIG SET aof-use-rdb-preamble yes

# 混合持久化：AOF 文件前半部分是 RDB 格式，后半部分是 AOF 格式
# 优点：结合 RDB 快速加载和 AOF 数据完整性
```

**备份策略**：
```
日常备份
    ↓
RDB：每小时自动保存（BGSAVE）
    ↓
AOF：每秒同步（appendfsync everysec）
    ↓
定期备份
    ├─ RDB 文件 → 复制到备份服务器
    └─ AOF 文件 → 复制到备份服务器
    ↓
恢复时
    ├─ 优先使用 AOF（数据更完整）
    └─ 如果没有 AOF，使用 RDB
```

**配置建议**：
- **RDB**：适合数据备份、灾难恢复，恢复速度快
- **AOF**：适合数据完整性要求高的场景，但文件较大
- **混合持久化**：推荐使用，兼顾性能和完整性

---

## 4. 复制（Replication）

### 结构说明

Redis 复制支持主从模式（Master-Slave），主节点（Master）将数据同步到从节点（Replica/Slave）。

**复制结构**：
```
主从复制架构
├── Master（主节点）
│   ├── 处理写请求
│   ├── 处理读请求
│   └── 将写操作同步到 Replica
└── Replica（从节点，Redis 5.0+ 使用 REPLICAOF）
    ├── 只处理读请求（默认）
    ├── 接收 Master 的同步数据
    └── 可以配置为级联复制（Replica 也可以有 Replica）
```

**复制方式**：
1. **全量复制**：首次连接或复制积压缓冲区不足时
2. **部分复制**：基于复制积压缓冲区（Replication Backlog）的增量复制

### 处理流程

#### 全量复制流程

```
1. Replica 发送 REPLICAOF master_ip master_port
   ↓
2. Replica 与 Master 建立连接
   ↓
3. Replica 发送 PING，Master 返回 PONG
   ↓
4. Replica 发送 REPLCONF listening-port
   ↓
5. Replica 发送 PSYNC ? -1（请求全量复制）
   ↓
6. Master 执行 BGSAVE，生成 RDB 文件
   ↓
7. Master 将 RDB 文件发送给 Replica
   ↓
8. Replica 接收 RDB 文件，清空旧数据，加载 RDB
   ↓
9. Master 将复制积压缓冲区中的命令发送给 Replica
   ↓
10. Replica 执行这些命令，完成同步
    ↓
11. 之后 Master 的每个写命令都会同步到 Replica
```

#### 部分复制流程（断线重连）

```
1. Replica 与 Master 断开连接
   ↓
2. Replica 重新连接 Master
   ↓
3. Replica 发送 PSYNC replid offset（replid 和偏移量）
   ↓
4. Master 检查复制积压缓冲区
   ├─ 如果 offset 在缓冲区范围内 → 执行部分复制
   │   ↓
   │   Master 发送 +CONTINUE replid
   │   ↓
   │   Master 发送缓冲区中 offset 之后的所有命令
   │   ↓
   │   Replica 执行这些命令，完成同步
   │
   └─ 如果 offset 不在缓冲区范围内 → 执行全量复制
       ↓
       回到全量复制流程
```

#### 命令传播流程

```
1. 客户端向 Master 发送写命令
   ↓
2. Master 执行命令
   ↓
3. Master 将命令写入复制积压缓冲区
   ↓
4. Master 将命令发送给所有 Replica
   ↓
5. Replica 执行命令，保持数据一致
```

### 实际案例：读写分离架构

**场景**：高并发系统需要将读请求分散到多个 Redis 节点，提高系统吞吐量。使用主从复制实现读写分离。

**实现步骤**：

```redis
# ===== Master 节点配置 =====

# 1. 查看复制信息
INFO replication
# 返回：
# role:master
# connected_slaves:2
# slave0:ip=192.168.1.101,port=6379,state=online,offset=12345,lag=0
# slave1:ip=192.168.1.102,port=6379,state=online,offset=12345,lag=0

# 2. 配置复制积压缓冲区大小（用于部分复制）
CONFIG SET repl-backlog-size 100mb

# 3. 配置复制积压缓冲区保存时间
CONFIG SET repl-backlog-ttl 3600

# ===== Replica 节点配置 =====

# 1. 设置为主节点的从节点（Redis 5.0+）
REPLICAOF 192.168.1.100 6379
# 旧版本使用：SLAVEOF 192.168.1.100 6379

# 2. 取消复制（提升为独立节点）
REPLICAOF NO ONE

# 3. 查看复制信息
INFO replication
# 返回：
# role:slave
# master_host:192.168.1.100
# master_port:6379
# master_link_status:up
# master_last_io_seconds_ago:1
# master_sync_in_progress:0
# slave_repl_offset:12345
# slave_priority:100

# 4. 配置只读模式（默认从节点只读）
CONFIG SET replica-read-only yes

# ===== 应用层读写分离 =====

# 写请求 → 发送到 Master（192.168.1.100:6379）
SET user:1001:name "Alice"

# 读请求 → 可以发送到任意 Replica（负载均衡）
# Replica 1: 192.168.1.101:6379
GET user:1001:name

# Replica 2: 192.168.1.102:6379
GET user:1001:name

# ===== 故障转移（手动）=====

# 1. 如果 Master 宕机，选择一个 Replica 提升为 Master
# 在 Replica 上执行：
REPLICAOF NO ONE

# 2. 其他 Replica 重新指向新的 Master
REPLICAOF 192.168.1.101 6379

# ===== 级联复制 =====

# Replica 1 也可以有自己的 Replica
# 在 Replica 2 上执行：
REPLICAOF 192.168.1.101 6379
# 这样 Replica 2 从 Replica 1 复制数据，减轻 Master 的压力
```

**架构图**：
```
                    Master (192.168.1.100:6379)
                    / 写请求（写操作）
                   /  同步数据
                  /
        Replica 1 (192.168.1.101:6379)  ← 读请求
                  \
                   \  同步数据
                    \
        Replica 2 (192.168.1.102:6379)  ← 读请求
```

**业务流程**：
```
客户端写请求
    ↓
发送到 Master
    ↓
Master 执行写操作
    ↓
Master 同步数据到所有 Replica
    ↓
Replica 执行相同的写操作
    ↓
数据保持一致

客户端读请求
    ↓
负载均衡分发到 Replica
    ↓
Replica 返回数据
```

**优势**：
- **读写分离**：提高读性能，分散读压力
- **数据备份**：Replica 可以作为 Master 的备份
- **高可用**：Master 故障时可以快速切换到 Replica

**注意事项**：
- **数据延迟**：Replica 的数据可能有延迟（异步复制）
- **一致性**：最终一致性，不是强一致性
- **故障转移**：需要配合 Sentinel 或 Cluster 实现自动故障转移

---

## 总结对比

### 事务 vs Lua 脚本

| 特性 | 事务 | Lua 脚本 |
|-----|------|---------|
| **原子性** | 支持 | 支持 |
| **回滚** | 不支持 | 不支持 |
| **错误处理** | 命令失败仍继续执行 | 可以处理错误 |
| **性能** | 中等 | 高（减少网络往返）|
| **灵活性** | 低 | 高（可执行复杂逻辑）|
| **适用场景** | 简单命令组合 | 复杂业务逻辑 |

### RDB vs AOF

| 特性 | RDB | AOF |
|-----|-----|-----|
| **文件大小** | 小（压缩） | 大（命令日志） |
| **恢复速度** | 快 | 慢 |
| **数据完整性** | 可能丢失最后一次保存后的数据 | 完整性高 |
| **性能影响** | BGSAVE 时 fork 子进程 | 写入时有一定开销 |
| **适用场景** | 数据备份、灾难恢复 | 数据完整性要求高 |

### 主从复制要点

| 特性 | 说明 |
|-----|------|
| **复制方式** | 全量复制 + 部分复制 |
| **数据一致性** | 最终一致性（异步复制） |
| **读写分离** | Replica 默认只读 |
| **故障转移** | 需要 Sentinel 或 Cluster 支持 |
| **级联复制** | 支持，减轻 Master 压力 |

---

## 最佳实践

1. **事务使用**：
   - 简单命令组合使用事务
   - 复杂逻辑使用 Lua 脚本
   - 需要乐观锁时使用 WATCH

2. **持久化配置**：
   - 生产环境推荐混合持久化
   - RDB 用于定期备份
   - AOF 用于数据完整性

3. **复制配置**：
   - 至少配置 1 个 Replica 作为备份
   - 合理设置复制积压缓冲区大小
   - 使用 Sentinel 或 Cluster 实现高可用

