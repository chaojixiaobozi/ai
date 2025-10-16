# CPU 问题定位补充上下文

## 1. Node / Nuxt 3 / Vue 是如何融合的（以一次请求为例）

- 核心角色
  - Node：运行时进程，承载 Nitro（Nuxt 的服务端引擎），负责接收 HTTP 请求、执行服务器端渲染（SSR）与 API/中间层逻辑。
  - Nuxt 3：框架层，基于 Nitro（服务端）+ Vite（构建/开发）+ Vue 3（视图）。Nuxt 负责路由、文件约定、插件/中间件、数据获取、SSR/CSR 切换、产物组织。
  - Vue 3：视图库，负责组件渲染与响应式。SSR 时用于把组件树渲染为 HTML 字符串，CSR 时接管浏览器端交互与水合。

- 关键产物
  - 构建后，Nuxt 产出 `.output/server/index.mjs`（Nitro 入口）与 `.output/public`（静态资源）。
  - Node 执行 Nitro 入口，注册路由（页面/服务端 API），对外提供 HTTP 服务。

- 一次 SSR 请求的典型链路

```text
Client --> Node(Nitro) --> Nuxt SSR --> Vue 渲染 --> HTML 返回
          ^               ^            ^
          |               |            |
        中间件          路由匹配     组件树渲染
```

- 更详细的时序（ASCII 时序图）

```text
Client            Node(Nitro)            Nuxt(App)                 Vue 3
  |  HTTP GET /page   |                      |                        |
  |------------------>|  1. 接收请求         |                        |
  |                   |--2. 运行 Nitro 中间件/route rules------------>|
  |                   |                      |                        |
  |                   |--3. 解析 Nuxt 应用实例(若未就绪/或每请求隔离)-->|
  |                   |                      |--3.1 创建应用与插件---->|
  |                   |                      |--3.2 创建/配置路由------>|
  |                   |                      |--3.3 加载页面与布局---->|
  |                   |                      |--3.4 运行页面中间件---->|
  |                   |                      |--3.5 运行 data fetching |
  |                   |                      |                        |
  |                   |----------------------|----4. SSR 渲染调用----->|--4.1 组件树渲染为 HTML
  |                   |                      |                        |
  |<------------------| 5. 返回 HTML(含状态) |                        |
  |  载入 HTML/JS     |                      |                        |
  |------浏览器端------|                      |                        |
  |  6. 下载客户端 JS  |                      |                        |
  |  7. Vue 水合/挂载  |----------------------客户端运行-----------------|
```

说明：
- 步骤 3.2 中会涉及 `vue-router` 的创建与路由记录注册（下文详述 `createRouter`）。
- 生产环境通常采用「长驻应用实例 + 每请求上下文」模型；某些组合或特定模块可能在 HMR/冷启动/异常恢复时重新创建应用与路由。

---

## 2. createRouter 的来源、作用与调用时机（概要）

- `createRouter` 来源：来自 `vue-router@4`，是创建路由实例（包含 matcher、导航守卫容器、历史实现等）的工厂函数。
- 作用：
  - 根据路由记录（由 Nuxt 依据 `pages/` 目录与 i18n 策略扩展生成）构建 matcher；
  - 绑定历史实现（SSR 使用 `createMemoryHistory`，客户端使用 `createWebHistory` 等）；
  - 提供 `push/replace/beforeEach/afterEach` 等导航 API；
  - 在 SSR/CSR 中协助完成初始匹配与后续导航。
- 调用时机：
  - 服务器端：Nuxt 创建应用实例（`createNuxtApp`）过程中，组装路由并调用 `createRouter`；每次冷启动必调，某些情况下（隔离上下文策略、错误恢复）会重复创建。
  - 客户端：应用首屏水合前创建客户端路由实例；HMR 或热替换某些核心模块时可能触发重建。

后续将在本文件继续补充：`createRouter` 的详细调用链、为何会成为 CPU 热点及优化要点。

### 2.1 createRouter 详细调用链（结合 Nuxt 3）

```text
Nitro(req) -> createNuxtApp() -> install plugins & modules -> resolve routes
  -> vue-router.createRouter({ history, routes })
      -> createRouterMatcher(routes)
         -> 规范化每条路由记录（含 i18n 扩张、动态参数、嵌套路由）
         -> 建立 path/record/children 的匹配结构（trie/列表）
      -> 初始化导航守卫容器（beforeEach/afterEach 等）
      -> 返回 router 实例
  -> SSR: router.push(initialURL) & isReady()
  -> 渲染组件树
```

与 Nuxt 的耦合点：
- routes 来源：Nuxt 根据 `pages/` 目录生成基础路由，再叠加模块（如 i18n 的多语前缀策略）进行扩张；你项目中 `locales` 很多，会指数级放大路由记录数。
- history：SSR 用 `createMemoryHistory`，客户端用 `createWebHistory`，这在 SSR->CSR 切换时会再创建一次客户端 router。
- 守卫与插件：`plugins/*.ts` 中注册的 `beforeEach/afterEach` 会在 router 创建后挂载；HMR/错误恢复不当时可能重复注册。

### 2.2 为什么 createRouter 会成为 CPU 热点
- 路由规模大：`页面数 × 语种数（i18n 策略）` 导致 `createRouterMatcher` 要遍历、规范化并索引大量记录。
- 复杂嵌套路由/动态段：正则与参数解析、路径规范化成本增大。
- 初始化即触发导航：SSR 会在创建后立即 `push(initialURL)`，触发匹配与守卫执行。
- 插件钩子多：多个 `beforeEach/afterEach`、埋点、进度条等在初始化导航就会运行。
- GC 压力：创建/规范化路由记录、正则、闭包与临时对象多，V8 GC 在该阶段明显活跃（你火焰图中蓝色 “garbage collector” 就是这一迹象）。

### 2.3 生产环境中常见触发路径
- 冷启动或实例重建：容器滚动发布/Pod 重建/无内存复用下，应用首次请求前必经 `createRouter`。
- 错误恢复：某些异常导致应用实例被丢弃并重建，会再次调用 `createRouter`。
- 多租户/隔离：若以“每请求隔离应用实例”的模式（非常规），也会频繁创建路由（不建议）。

### 2.4 观察与优化方向（生产态）
- 观测
  - 在创建 router 前后埋点：记录路由记录数量、创建耗时（`performance.now()`）、首次导航耗时。
  - 打印最终路由条数（可在 `hooks.pages:extend` 或运行时 `router.getRoutes().length`）。
  - 统计守卫数量与执行耗时，避免过重逻辑放在 `beforeEach`。
- 优化
  - 缩减 i18n 路由扩张：在生产仅保留必要前缀策略/语种；或使用 `strategy: 'no_prefix'` + 运行时切换（视业务而定）。
  - 合理分层路由：减少深嵌套与宽扁平的极端情况；对很少访问的区域进行懒注册（模块化路由）。
  - 守卫与插件瘦身：
    - 防止 HMR/重建时重复注册；
    - 将重逻辑下沉至页面/组件生命周期或服务端中间层，守卫只保留快速校验与重定向。
  - 预热：节点启动后执行一次预热路由访问，填充缓存，摊薄首个真实请求的延迟。
  - 版本/实现：升级 `vue-router` 至最新小版本，利用可能的性能改进；检查第三方插件是否对路由做了大量动态变更。
