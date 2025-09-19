# MongoDB 流量应对与扩容策略

## 1. 流量监控与预警机制

### 1.1 关键监控指标

#### 性能指标
```javascript
// 实时监控脚本
function monitorMongoDB() {
  const stats = db.serverStatus();
  
  // 连接数监控
  const connections = stats.connections;
  console.log(`当前连接数: ${connections.current}/${connections.available}`);
  
  // 操作统计
  const opcounters = stats.opcounters;
  console.log(`查询/秒: ${opcounters.query}`);
  console.log(`插入/秒: ${opcounters.insert}`);
  console.log(`更新/秒: ${opcounters.update}`);
  console.log(`删除/秒: ${opcounters.delete}`);
  
  // 内存使用
  const mem = stats.mem;
  console.log(`内存使用: ${mem.resident}MB`);
  
  // 网络I/O
  const network = stats.network;
  console.log(`网络入: ${network.bytesIn} bytes`);
  console.log(`网络出: ${network.bytesOut} bytes`);
}

// 设置监控阈值
const thresholds = {
  connections: 0.8,    // 连接数超过80%告警
  memory: 0.85,        // 内存使用超过85%告警
  cpu: 0.8,           // CPU使用超过80%告警
  responseTime: 100    // 响应时间超过100ms告警
};
```

#### 业务指标
```javascript
// 业务监控指标
const businessMetrics = {
  // QPS监控
  qps: {
    read: 0,
    write: 0,
    threshold: 10000  // QPS阈值
  },
  
  // 响应时间监控
  responseTime: {
    p50: 0,    // 50分位数
    p95: 0,    // 95分位数
    p99: 0,    // 99分位数
    threshold: 100
  },
  
  // 错误率监控
  errorRate: {
    current: 0,
    threshold: 0.01  // 1%错误率阈值
  }
};
```

### 1.2 预警系统

#### 自动预警脚本
```bash
#!/bin/bash
# MongoDB监控脚本

MONGO_HOST="localhost:27017"
ALERT_EMAIL="admin@company.com"

# 检查连接数
CONNECTIONS=$(mongo $MONGO_HOST --eval "db.serverStatus().connections.current" --quiet)
MAX_CONNECTIONS=$(mongo $MONGO_HOST --eval "db.serverStatus().connections.available" --quiet)
CONNECTION_RATIO=$(echo "scale=2; $CONNECTIONS / $MAX_CONNECTIONS" | bc)

if (( $(echo "$CONNECTION_RATIO > 0.8" | bc -l) )); then
    echo "警告: 连接数使用率过高 ($CONNECTION_RATIO)" | mail -s "MongoDB连接数告警" $ALERT_EMAIL
fi

# 检查内存使用
MEMORY_USAGE=$(mongo $MONGO_HOST --eval "db.serverStatus().mem.resident" --quiet)
if [ $MEMORY_USAGE -gt 8000 ]; then
    echo "警告: 内存使用过高 (${MEMORY_USAGE}MB)" | mail -s "MongoDB内存告警" $ALERT_EMAIL
fi

# 检查慢查询
SLOW_QUERIES=$(mongo $MONGO_HOST --eval "db.currentOp({'secs_running': {'$gt': 5}}).length()" --quiet)
if [ $SLOW_QUERIES -gt 10 ]; then
    echo "警告: 慢查询数量过多 ($SLOW_QUERIES)" | mail -s "MongoDB慢查询告警" $ALERT_EMAIL
fi
```

## 2. 快速应对策略

### 2.1 立即响应措施

#### 连接池优化
```javascript
// 应用层连接池配置
const mongoose = require('mongoose');

// 紧急情况下的连接池配置
const emergencyConfig = {
  maxPoolSize: 50,        // 最大连接数
  minPoolSize: 10,        // 最小连接数
  maxIdleTimeMS: 30000,   // 最大空闲时间
  serverSelectionTimeoutMS: 5000,  // 服务器选择超时
  socketTimeoutMS: 45000,  // Socket超时
  bufferMaxEntries: 0,     // 禁用缓冲
  bufferCommands: false    // 禁用命令缓冲
};

mongoose.connect(uri, emergencyConfig);
```

#### 查询优化
```javascript
// 紧急查询优化
function optimizeQueries() {
  // 1. 禁用复杂聚合查询
  db.setProfilingLevel(0);  // 关闭性能分析
  
  // 2. 优化慢查询
  db.currentOp().inprog.forEach(function(op) {
    if (op.secs_running > 5) {
      db.killOp(op.opid);  // 杀死长时间运行的查询
    }
  });
  
  // 3. 临时禁用非必要索引
  // db.collection.dropIndex("non_critical_index");
  
  // 4. 调整查询超时
  db.adminCommand({setParameter: 1, maxTimeMS: 5000});
}
```

#### 缓存策略
```javascript
// Redis缓存策略
const redis = require('redis');
const client = redis.createClient();

// 热点数据缓存
async function cacheHotData() {
  const hotQueries = [
    'user:active:list',
    'product:featured:list',
    'order:recent:stats'
  ];
  
  for (const query of hotQueries) {
    const data = await getFromMongoDB(query);
    await client.setex(query, 300, JSON.stringify(data)); // 5分钟缓存
  }
}

// 查询时优先使用缓存
async function getData(query) {
  // 先查缓存
  const cached = await client.get(query);
  if (cached) {
    return JSON.parse(cached);
  }
  
  // 缓存未命中，查数据库
  const data = await getFromMongoDB(query);
  await client.setex(query, 300, JSON.stringify(data));
  return data;
}
```

### 2.2 读写分离

#### 副本集读写分离
```javascript
// 应用层读写分离配置
const readPreference = {
  // 读操作配置
  read: {
    readPreference: 'secondaryPreferred',  // 优先从节点
    maxStalenessSeconds: 30,               // 最大延迟30秒
    tagSets: [{region: 'asia'}]            // 指定区域标签
  },
  
  // 写操作配置
  write: {
    writeConcern: {w: 1, j: false},        // 只要求主节点确认
    readPreference: 'primary'               // 写操作必须走主节点
  }
};

// 查询时使用从节点
db.collection.find(query).readPref('secondaryPreferred');

// 写入时使用主节点
db.collection.insertOne(doc, {writeConcern: {w: 1}});
```

#### 应用层路由
```javascript
// 智能路由策略
class MongoDBRouter {
  constructor() {
    this.primary = 'mongodb://primary:27017';
    this.secondaries = [
      'mongodb://secondary1:27017',
      'mongodb://secondary2:27017'
    ];
    this.currentSecondary = 0;
  }
  
  // 读操作路由
  async read(operation) {
    try {
      // 尝试从节点
      const secondary = this.secondaries[this.currentSecondary];
      return await this.executeOnNode(secondary, operation);
    } catch (error) {
      // 从节点失败，使用主节点
      return await this.executeOnNode(this.primary, operation);
    }
  }
  
  // 写操作路由
  async write(operation) {
    return await this.executeOnNode(this.primary, operation);
  }
  
  // 负载均衡
  getNextSecondary() {
    this.currentSecondary = (this.currentSecondary + 1) % this.secondaries.length;
    return this.secondaries[this.currentSecondary];
  }
}
```

## 3. 扩容策略详解

### 3.1 垂直扩容 (Scale Up)

#### 硬件升级
```yaml
# 推荐配置升级路径
upgrade_paths:
  # 当前配置
  current:
    cpu: "4 cores"
    memory: "16GB"
    storage: "500GB SSD"
    
  # 升级配置1
  upgrade_1:
    cpu: "8 cores"
    memory: "32GB"
    storage: "1TB SSD"
    
  # 升级配置2
  upgrade_2:
    cpu: "16 cores"
    memory: "64GB"
    storage: "2TB NVMe SSD"
```

#### 配置优化
```javascript
// 内存配置优化
storage:
  wiredTiger:
    engineConfig:
      cacheSizeGB: 32  # 设置为可用内存的50-60%
      journalCompressor: snappy
      directoryForIndexes: true
    collectionConfig:
      blockCompressor: snappy
    indexConfig:
      prefixCompression: true

// 网络配置优化
net:
  maxIncomingConnections: 1000
  compression:
    compressors: snappy,zstd

// 操作配置优化
operationProfiling:
  slowOpThresholdMs: 100
  mode: slowOp
```

### 3.2 水平扩容 (Scale Out)

#### 分片集群扩容

**1. 添加新分片**
```javascript
// 添加新分片到集群
sh.addShard("shard3/shard3-rs1:27017,shard3-rs2:27017,shard3-rs3:27017")

// 验证分片状态
sh.status()

// 检查数据分布
sh.getBalancerState()
```

**2. 数据重新平衡**
```javascript
// 启用平衡器
sh.startBalancer()

// 检查平衡状态
sh.isBalancerRunning()

// 手动触发平衡
sh.startBalancer("shard1", "shard2")
```

**3. 分片键优化**
```javascript
// 分析当前分片键效果
db.collection.getShardDistribution()

// 重新选择分片键（需要重新分片）
sh.shardCollection("mydb.collection", {new_shard_key: 1})

// 分片键选择原则：
// 1. 高基数（唯一值多）
// 2. 均匀分布
// 3. 查询模式匹配
// 4. 避免热点
```

#### 副本集扩容

**1. 添加新节点**
```javascript
// 添加新节点到副本集
rs.add({
  _id: 3,
  host: "mongodb3:27017",
  priority: 1,
  votes: 1
})

// 验证副本集状态
rs.status()

// 检查复制延迟
rs.printSlaveReplicationInfo()
```

**2. 节点角色配置**
```javascript
// 配置隐藏节点（用于备份）
rs.reconfig({
  _id: 3,
  host: "mongodb3:27017",
  priority: 0,
  hidden: true,
  votes: 0
})

// 配置延迟节点（用于恢复）
rs.reconfig({
  _id: 4,
  host: "mongodb4:27017",
  priority: 0,
  hidden: true,
  slaveDelay: 3600,  // 延迟1小时
  votes: 0
})
```

### 3.3 应用层扩容

#### 连接池扩容
```javascript
// 动态调整连接池
class ConnectionPoolManager {
  constructor() {
    this.basePoolSize = 10;
    this.maxPoolSize = 100;
    this.currentPoolSize = this.basePoolSize;
  }
  
  // 根据负载调整连接池大小
  adjustPoolSize(load) {
    if (load > 0.8) {
      this.currentPoolSize = Math.min(
        this.currentPoolSize * 1.5,
        this.maxPoolSize
      );
    } else if (load < 0.3) {
      this.currentPoolSize = Math.max(
        this.currentPoolSize * 0.8,
        this.basePoolSize
      );
    }
    
    this.updateConnectionPool();
  }
  
  updateConnectionPool() {
    // 更新MongoDB连接配置
    mongoose.connection.close();
    mongoose.connect(uri, {
      maxPoolSize: this.currentPoolSize
    });
  }
}
```

#### 缓存层扩容
```javascript
// Redis集群扩容
const redis = require('redis');
const cluster = redis.createCluster({
  nodes: [
    {host: 'redis1', port: 7000},
    {host: 'redis2', port: 7000},
    {host: 'redis3', port: 7000},
    {host: 'redis4', port: 7000},  // 新增节点
    {host: 'redis5', port: 7000},  // 新增节点
    {host: 'redis6', port: 7000}   // 新增节点
  ]
});

// 缓存预热
async function warmupCache() {
  const hotKeys = await getHotKeysFromMongoDB();
  
  for (const key of hotKeys) {
    const data = await getFromMongoDB(key);
    await cluster.setex(key, 3600, JSON.stringify(data));
  }
}
```

## 4. 应急处理流程

### 4.1 流量激增应急流程

#### 立即响应 (0-5分钟)
```bash
#!/bin/bash
# 应急响应脚本

echo "=== MongoDB 应急响应开始 ==="

# 1. 检查系统状态
echo "1. 检查系统状态..."
mongo --eval "db.serverStatus().connections"
mongo --eval "db.serverStatus().mem"
mongo --eval "db.currentOp().inprog.length"

# 2. 杀死慢查询
echo "2. 处理慢查询..."
mongo --eval "
db.currentOp().inprog.forEach(function(op) {
  if (op.secs_running > 10) {
    db.killOp(op.opid);
    print('Killed slow operation: ' + op.opid);
  }
});
"

# 3. 调整连接限制
echo "3. 调整连接限制..."
mongo --eval "db.adminCommand({setParameter: 1, maxIncomingConnections: 2000})"

# 4. 启用读写分离
echo "4. 启用读写分离..."
# 应用层配置调整

echo "=== 应急响应完成 ==="
```

#### 短期应对 (5-30分钟)
```javascript
// 短期应对措施
function shortTermResponse() {
  // 1. 启用查询缓存
  enableQueryCache();
  
  // 2. 调整索引策略
  optimizeIndexes();
  
  // 3. 启用数据压缩
  enableCompression();
  
  // 4. 调整写入关注级别
  adjustWriteConcern();
}

function enableQueryCache() {
  // 启用查询结果缓存
  db.adminCommand({setParameter: 1, queryCacheSize: 1000000});
}

function optimizeIndexes() {
  // 临时禁用非关键索引
  const nonCriticalIndexes = [
    "text_index",
    "geospatial_index"
  ];
  
  nonCriticalIndexes.forEach(index => {
    try {
      db.collection.dropIndex(index);
      print(`Dropped non-critical index: ${index}`);
    } catch (e) {
      print(`Failed to drop index ${index}: ${e.message}`);
    }
  });
}

function adjustWriteConcern() {
  // 降低写入关注级别
  db.adminCommand({
    setDefaultRWConcern: {
      defaultWriteConcern: {w: 1, j: false}
    }
  });
}
```

#### 中期扩容 (30分钟-2小时)
```javascript
// 中期扩容措施
function mediumTermScaling() {
  // 1. 添加副本集节点
  addReplicaSetNodes();
  
  // 2. 启用分片
  enableSharding();
  
  // 3. 调整应用层配置
  adjustApplicationConfig();
  
  // 4. 启用CDN和缓存
  enableCDNAndCache();
}

function addReplicaSetNodes() {
  // 添加新的副本集节点
  rs.add({
    _id: 3,
    host: "mongodb3:27017",
    priority: 1,
    votes: 1
  });
  
  // 等待节点同步
  rs.status();
}

function enableSharding() {
  // 启用分片
  sh.enableSharding("mydb");
  
  // 选择分片键
  sh.shardCollection("mydb.collection", {shard_key: 1});
  
  // 添加分片
  sh.addShard("shard2/shard2-rs1:27017,shard2-rs2:27017");
}
```

### 4.2 故障恢复流程

#### 主节点故障
```javascript
// 主节点故障处理
function handlePrimaryFailure() {
  // 1. 检查副本集状态
  const status = rs.status();
  
  // 2. 手动选举新主节点
  if (status.members.some(m => m.state === 1)) {
    // 有主节点，无需处理
    return;
  }
  
  // 3. 强制选举
  rs.stepDown(60);  // 60秒后重新选举
  
  // 4. 检查新主节点
  setTimeout(() => {
    const newStatus = rs.status();
    const newPrimary = newStatus.members.find(m => m.state === 1);
    if (newPrimary) {
      print(`New primary elected: ${newPrimary.name}`);
    }
  }, 10000);
}
```

#### 数据恢复
```javascript
// 数据恢复流程
function dataRecovery() {
  // 1. 停止应用写入
  stopApplicationWrites();
  
  // 2. 从备份恢复
  restoreFromBackup();
  
  // 3. 验证数据完整性
  validateDataIntegrity();
  
  // 4. 重新启动应用
  restartApplication();
}

function restoreFromBackup() {
  // 从最新备份恢复
  const backupPath = "/backup/mongodb/latest";
  
  // 停止MongoDB服务
  system("sudo systemctl stop mongod");
  
  // 清空数据目录
  system("rm -rf /var/lib/mongodb/*");
  
  // 恢复数据
  system(`mongorestore --dbpath /var/lib/mongodb ${backupPath}`);
  
  // 启动MongoDB服务
  system("sudo systemctl start mongod");
}
```

## 5. 预防措施

### 5.1 容量规划

#### 容量计算公式
```javascript
// 容量规划计算
function calculateCapacity() {
  const metrics = {
    // 当前指标
    current: {
      qps: 1000,
      dataSize: 100,  // GB
      connections: 100,
      memory: 16      // GB
    },
    
    // 增长预测
    growth: {
      qpsGrowth: 0.2,      // 20%月增长
      dataGrowth: 0.15,    // 15%月增长
      connectionGrowth: 0.1 // 10%月增长
    },
    
    // 安全系数
    safety: {
      qps: 2.0,        // 2倍安全系数
      memory: 1.5,     // 1.5倍安全系数
      connection: 1.8  // 1.8倍安全系数
    }
  };
  
  // 计算6个月后的需求
  const months = 6;
  const future = {
    qps: metrics.current.qps * Math.pow(1 + metrics.growth.qpsGrowth, months) * metrics.safety.qps,
    dataSize: metrics.current.dataSize * Math.pow(1 + metrics.growth.dataGrowth, months),
    connections: metrics.current.connections * Math.pow(1 + metrics.growth.connectionGrowth, months) * metrics.safety.connection,
    memory: metrics.current.memory * Math.pow(1 + metrics.growth.dataGrowth, months) * metrics.safety.memory
  };
  
  return future;
}
```

### 5.2 自动化扩容

#### 自动扩容脚本
```javascript
// 自动扩容监控
class AutoScaler {
  constructor() {
    this.thresholds = {
      cpu: 0.8,
      memory: 0.85,
      connections: 0.8,
      qps: 0.9
    };
    
    this.scalingActions = {
      vertical: ['increaseMemory', 'increaseCPU'],
      horizontal: ['addReplica', 'addShard']
    };
  }
  
  async monitor() {
    const metrics = await this.getMetrics();
    
    if (this.shouldScale(metrics)) {
      await this.executeScaling(metrics);
    }
  }
  
  async getMetrics() {
    const stats = db.serverStatus();
    return {
      cpu: this.getCPUUsage(),
      memory: stats.mem.resident / (1024 * 1024), // MB
      connections: stats.connections.current / stats.connections.available,
      qps: stats.opcounters.query
    };
  }
  
  shouldScale(metrics) {
    return Object.keys(metrics).some(key => 
      metrics[key] > this.thresholds[key]
    );
  }
  
  async executeScaling(metrics) {
    if (metrics.memory > this.thresholds.memory) {
      await this.addReplica();
    }
    
    if (metrics.connections > this.thresholds.connections) {
      await this.addShard();
    }
  }
  
  async addReplica() {
    // 添加副本集节点
    const newId = rs.status().members.length;
    rs.add({
      _id: newId,
      host: `mongodb${newId}:27017`,
      priority: 1,
      votes: 1
    });
  }
  
  async addShard() {
    // 添加分片
    const shardId = `shard${Date.now()}`;
    sh.addShard(`${shardId}/${shardId}-rs1:27017,${shardId}-rs2:27017`);
  }
}

// 启动自动扩容
const autoScaler = new AutoScaler();
setInterval(() => autoScaler.monitor(), 60000); // 每分钟检查一次
```

## 6. 最佳实践总结

### 6.1 流量应对最佳实践

1. **监控先行**: 建立完善的监控体系，提前预警
2. **分层应对**: 从应用层到数据库层，逐层优化
3. **缓存策略**: 合理使用缓存，减少数据库压力
4. **读写分离**: 充分利用副本集，分散读压力
5. **查询优化**: 优化慢查询，提高响应速度

### 6.2 扩容最佳实践

1. **容量规划**: 提前规划容量，避免临时扩容
2. **自动化扩容**: 使用自动化工具，快速响应
3. **分片策略**: 合理设计分片键，确保数据均匀分布
4. **备份恢复**: 建立完善的备份恢复机制
5. **测试验证**: 定期进行压力测试，验证扩容效果

### 6.3 应急处理最佳实践

1. **预案准备**: 制定详细的应急处理预案
2. **快速响应**: 建立快速响应机制，及时处理问题
3. **团队协作**: 建立跨团队协作机制，快速解决问题
4. **经验总结**: 及时总结应急处理经验，持续改进
5. **预防为主**: 以预防为主，减少应急情况发生

---

*本策略基于MongoDB 4.4+版本，实际实施时请根据具体环境和需求进行调整。*
