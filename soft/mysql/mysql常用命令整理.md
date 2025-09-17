# MySQL 常用命令整理

## 📊 数据库空间使用分析

### 1. 按数据库统计空间占用
```sql
-- 查看各数据库占用空间（GB）
SELECT 
    table_schema AS '数据库',
    ROUND(SUM(data_length + index_length) / 1024 / 1024 / 1024, 2) AS '占用GB'
FROM information_schema.tables
GROUP BY table_schema
ORDER BY 占用GB DESC;

-- 查看数据库占用空间汇总（包含总计）
SELECT 
    COALESCE(table_schema, '总计') AS '数据库',
    ROUND(SUM(data_length + index_length) / 1024 / 1024 / 1024, 2) AS '占用GB'
FROM information_schema.tables
GROUP BY table_schema WITH ROLLUP
ORDER BY 
    CASE WHEN table_schema IS NULL THEN 1 ELSE 0 END,
    占用GB DESC;
```

### 2. 按表统计空间占用
```sql
-- 查看占用空间最大的20个表
SELECT 
    table_schema AS '数据库',
    table_name AS '表名',
    ROUND(((data_length + index_length) / 1024 / 1024), 2) AS '大小MB',
    table_rows AS '行数',
    ROUND(data_length / 1024 / 1024, 2) AS '数据大小MB',
    ROUND(index_length / 1024 / 1024, 2) AS '索引大小MB'
FROM information_schema.tables 
WHERE table_schema NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys')
ORDER BY (data_length + index_length) DESC
LIMIT 20;
```

## 🔧 系统配置检查

### 1. 内存配置参数
```sql
-- 查看关键内存配置
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';      -- 缓冲池大小
SHOW VARIABLES LIKE 'innodb_log_buffer_size';       -- 日志缓冲区大小
SHOW VARIABLES LIKE 'key_buffer_size';              -- MyISAM键缓冲区
SHOW VARIABLES LIKE 'query_cache_size';             -- 查询缓存大小
SHOW VARIABLES LIKE 'tmp_table_size';               -- 临时表大小
SHOW VARIABLES LIKE 'max_heap_table_size';          -- 内存表最大大小
SHOW VARIABLES LIKE 'sort_buffer_size';             -- 排序缓冲区
SHOW VARIABLES LIKE 'read_buffer_size';             -- 读缓冲区
SHOW VARIABLES LIKE 'read_rnd_buffer_size';         -- 随机读缓冲区
SHOW VARIABLES LIKE 'join_buffer_size';             -- 连接缓冲区
SHOW VARIABLES LIKE 'max_connections';              -- 最大连接数
SHOW VARIABLES LIKE 'thread_cache_size';            -- 线程缓存大小
```

### 2. 连接配置检查
```sql
-- 查看连接相关配置
SHOW VARIABLES LIKE '%connection%';
SHOW VARIABLES LIKE '%thread%';
SHOW VARIABLES LIKE '%timeout%';
```

## 📈 性能监控

### 1. 连接状态监控
```sql
-- 查看当前连接状态
SHOW STATUS LIKE 'Threads_connected';    -- 当前连接数
SHOW STATUS LIKE 'Threads_running';      -- 活跃连接数
SHOW STATUS LIKE 'Max_used_connections'; -- 历史最大连接数
SHOW STATUS LIKE 'Threads_created';      -- 已创建线程数
SHOW STATUS LIKE 'Threads_cached';       -- 缓存线程数
```

### 2. 缓冲池性能监控
```sql
-- 查看缓冲池使用情况
SHOW STATUS LIKE 'Innodb_buffer_pool_pages_data';     -- 数据页数
SHOW STATUS LIKE 'Innodb_buffer_pool_pages_total';    -- 总页数
SHOW STATUS LIKE 'Innodb_buffer_pool_pages_free';     -- 空闲页数
SHOW STATUS LIKE 'Innodb_buffer_pool_pages_dirty';    -- 脏页数
SHOW STATUS LIKE 'Innodb_buffer_pool_reads';          -- 磁盘读取次数
SHOW STATUS LIKE 'Innodb_buffer_pool_read_requests';  -- 读取请求次数
SHOW STATUS LIKE 'Innodb_page_size';                  -- 页大小
```

### 3. 查询性能监控
```sql
-- 查看临时表使用情况
SHOW STATUS LIKE 'Created_tmp_tables';      -- 临时表创建次数
SHOW STATUS LIKE 'Created_tmp_disk_tables'; -- 磁盘临时表创建次数
SHOW STATUS LIKE 'Created_tmp_files';       -- 临时文件创建次数

-- 查看慢查询统计
SHOW STATUS LIKE 'Slow_queries';            -- 慢查询次数
SHOW STATUS LIKE 'Questions';               -- 总查询次数
SHOW STATUS LIKE 'Queries';                 -- 总语句数
```

## 🔍 实时状态检查

### 1. 当前活动查询
```sql
-- 查看当前正在执行的查询
SHOW PROCESSLIST;

-- 查看详细的进程信息
SHOW FULL PROCESSLIST;
```

### 2. 锁等待情况
```sql
-- 查看InnoDB详细状态（包含锁信息）
SHOW ENGINE INNODB STATUS;
```

### 3. 线程池状态
```sql
-- 查看线程池相关状态
SHOW STATUS LIKE 'thread_pool%';
```

## 🚨 问题排查

### 1. 内存使用分析
```sql
-- 查看所有内存相关状态
SHOW STATUS LIKE '%buffer%';
SHOW STATUS LIKE '%cache%';
SHOW STATUS LIKE '%memory%';
SHOW STATUS LIKE '%pool%';
```

### 2. 磁盘I/O分析
```sql
-- 查看磁盘I/O相关状态
SHOW STATUS LIKE '%disk%';
SHOW STATUS LIKE '%file%';
SHOW STATUS LIKE '%log%';
```

### 3. 网络连接分析
```sql
-- 查看网络相关状态
SHOW STATUS LIKE '%connection%';
SHOW STATUS LIKE '%aborted%';
SHOW STATUS LIKE '%timeout%';
```

## 📋 快速健康检查

### 1. 一键健康检查
```sql
-- 查看所有关键状态
SHOW STATUS;

-- 查看所有配置
SHOW VARIABLES;

-- 查看InnoDB引擎状态
SHOW ENGINE INNODB STATUS;
```

### 2. 性能指标计算
```sql
-- 缓冲池使用率计算：
-- 使用率 = (Innodb_buffer_pool_pages_data * Innodb_page_size) / innodb_buffer_pool_size * 100%

-- 缓冲池命中率计算：
-- 命中率 = (1 - Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests) * 100%

-- 临时表磁盘使用率计算：
-- 磁盘使用率 = Created_tmp_disk_tables / Created_tmp_tables * 100%

-- 连接使用率计算：
-- 连接使用率 = Threads_connected / max_connections * 100%
```

## 🖥️ 系统级监控命令

```bash
# 查看MySQL进程内存使用
ps aux | grep mysql | grep -v grep

# 查看MySQL内存映射
pmap -x $(pgrep mysqld)

# 查看系统内存使用情况
free -h

# 查看MySQL内存使用详情
cat /proc/$(pgrep mysqld)/status | grep -E "(VmPeak|VmSize|VmRSS|VmHWM)"

# 使用top命令查看MySQL进程
top -p $(pgrep mysqld)

# 查看MySQL错误日志
tail -f /var/log/mysql/error.log

# 查看MySQL慢查询日志
tail -f /var/log/mysql/slow.log
```

## 📝 使用场景索引

- **🔍 空间不足排查**: 数据库空间使用分析
- **⚡ 性能优化**: 缓冲池性能监控 + 查询性能监控
- **🔧 配置调优**: 系统配置检查
- **🚨 问题排查**: 实时状态检查 + 问题排查
- **📊 日常监控**: 快速健康检查
- **🖥️ 系统监控**: 系统级监控命令

