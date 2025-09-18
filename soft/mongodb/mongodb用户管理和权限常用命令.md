# MongoDB 用户权限管理命令

## 1. 修改用户角色权限

### 1.1 添加新角色给用户
```javascript
// 给用户添加新角色
db.updateUser("reddit_user", {
  roles: [
    { role: "reddit_collections_access", db: "community" },
    { role: "read", db: "analytics" }  // 添加新角色
  ]
})
```

### 1.2 替换用户的所有角色
```javascript
// 完全替换用户角色
db.updateUser("reddit_user", {
  roles: [
    { role: "readWrite", db: "community" }
  ]
})
```

### 1.3 使用grantRolesToUser添加角色
```javascript
// 给用户授予新角色（保留现有角色）
db.grantRolesToUser("reddit_user", [
  { role: "read", db: "analytics" }
])
```

### 1.4 使用revokeRolesFromUser移除角色
```javascript
// 从用户移除特定角色
db.revokeRolesFromUser("reddit_user", [
  { role: "read", db: "analytics" }
])
```

## 2. 修改用户密码

### 2.1 修改密码
```javascript
// 修改用户密码
db.changeUserPassword("reddit_user", "new_secure_password")
```

### 2.2 使用updateUser修改密码
```javascript
// 使用updateUser修改密码
db.updateUser("reddit_user", {
  pwd: "new_secure_password"
})
```

## 3. 修改用户其他属性

### 3.1 修改用户自定义数据
```javascript
// 添加或修改用户自定义数据
db.updateUser("reddit_user", {
  customData: {
    department: "engineering",
    level: "senior"
  }
})
```

### 3.2 修改用户认证机制
```javascript
// 修改用户认证机制
db.updateUser("reddit_user", {
  mechanisms: ["SCRAM-SHA-1", "SCRAM-SHA-256"]
})
```

## 4. 查看用户权限

### 4.1 查看用户信息
```javascript
// 查看用户基本信息
db.getUser("reddit_user")

// 查看用户详细信息（包括权限）
db.getUser("reddit_user", {showPrivileges: true})
```

### 4.2 查看用户角色
```javascript
// 查看用户角色
db.runCommand({usersInfo: "reddit_user"})

// 查看用户权限详情
db.runCommand({usersInfo: "reddit_user", showPrivileges: true})
```

## 5. 角色管理

### 5.1 创建自定义角色
```javascript
// 创建自定义角色
db.createRole({
  role: "reddit_collections_access",
  privileges: [
    {
      resource: { db: "community", collection: "reddit_post" },
      actions: ["find", "insert", "update", "remove"]
    },
    {
      resource: { db: "community", collection: "redditLog" },
      actions: ["find", "insert", "update", "remove"]
    }
  ],
  roles: []
})
```

### 5.2 修改角色权限
```javascript
// 修改角色权限
db.updateRole("reddit_collections_access", {
  privileges: [
    {
      resource: { db: "community", collection: "reddit_post" },
      actions: ["find", "insert", "update", "remove"]
    },
    {
      resource: { db: "community", collection: "redditLog" },
      actions: ["find", "insert", "update", "remove"]
    }
  ],
  roles: []
})
```

### 5.3 查看角色权限
```javascript
// 查看角色权限
db.getRole("reddit_collections_access", {showPrivileges: true})

// 查看所有角色
db.getRoles({showPrivileges: true})
```

## 6. 用户管理

### 6.1 删除用户
```javascript
// 删除用户
db.dropUser("reddit_user")
```

### 6.2 删除角色
```javascript
// 删除角色
db.dropRole("reddit_collections_access")
```

### 6.3 查看所有用户
```javascript
// 查看所有用户
db.getUsers()

// 查看所有用户详细信息
db.runCommand({usersInfo: 1, showPrivileges: true})
```

## 7. 常用权限操作示例

### 7.1 给用户添加只读权限
```javascript
// 给用户添加只读权限
db.grantRolesToUser("reddit_user", [
  { role: "read", db: "community" }
])
```

### 7.2 给用户添加读写权限
```javascript
// 给用户添加读写权限
db.grantRolesToUser("reddit_user", [
  { role: "readWrite", db: "community" }
])
```

### 7.3 给用户添加数据库管理权限
```javascript
// 给用户添加数据库管理权限
db.grantRolesToUser("reddit_user", [
  { role: "dbAdmin", db: "community" }
])
```

## 8. 批量操作

### 8.1 批量创建用户
```javascript
// 批量创建用户
var users = [
  { user: "user1", pwd: "pwd1", roles: [{ role: "read", db: "community" }] },
  { user: "user2", pwd: "pwd2", roles: [{ role: "readWrite", db: "community" }] }
];

users.forEach(function(userData) {
  db.createUser(userData);
});
```

### 8.2 批量修改用户权限
```javascript
// 批量给用户添加角色
var users = ["user1", "user2", "user3"];
var role = { role: "read", db: "analytics" };

users.forEach(function(username) {
  db.grantRolesToUser(username, [role]);
});
```

## 9. 权限验证

### 9.1 测试用户权限
```javascript
// 切换到目标数据库
use community

// 测试查询权限
db.reddit_post.find().limit(1)

// 测试插入权限
db.reddit_post.insertOne({test: "data"})

// 测试更新权限
db.reddit_post.updateOne({test: "data"}, {$set: {updated: true}})

// 测试删除权限
db.reddit_post.deleteOne({test: "data"})
```

### 9.2 检查权限是否生效
```javascript
// 检查当前用户权限
db.runCommand({connectionStatus: 1})

// 检查特定操作权限
db.runCommand({usersInfo: 1, showPrivileges: true})
```

## 10. 注意事项

1. **权限生效**：修改用户权限后立即生效，无需重启服务
2. **角色继承**：用户权限是所有角色权限的并集
3. **权限检查**：MongoDB在每次操作时都会检查权限
4. **备份重要**：修改权限前建议备份用户配置
5. **测试验证**：修改权限后务必测试验证功能是否正常

## 11. 错误处理

### 11.1 常见错误及解决方案
```javascript
// 错误：用户不存在
// 解决：先创建用户
db.createUser({
  user: "reddit_user",
  pwd: "password",
  roles: [{ role: "read", db: "community" }]
})

// 错误：角色不存在
// 解决：先创建角色
db.createRole({
  role: "custom_role",
  privileges: [...],
  roles: []
})

// 错误：权限不足
// 解决：使用具有userAdmin角色的账号操作
```
