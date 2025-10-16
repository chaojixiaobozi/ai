# 路由（Router）分析入门

本文面向完全小白，带你从 0 理解 Nuxt 3 / Vue Router 的核心概念与运行流程。

## 一、前置知识（必须先知道的概念）
- URL 与路径
  - URL 里域名后面的部分就是“路径”，如 `https://example.com/posts/123` 中的 `/posts/123`。
- 路由（route）
  - 把“路径”映射到“页面组件”的规则。比如 `/about` -> About 页面。
- 路由表（routes）
  - 一组路由规则的集合，供路由器（router）查表匹配。
- 匹配（matching）
  - 当访问某个路径时，路由器在路由表中找到“最合适”的那条记录（支持动态段、嵌套）。
- 历史模式（history）
  - 浏览器端的路径管理方式：`createWebHistory`（常用）、`createWebHashHistory`（带 `#`）、SSR 用 `createMemoryHistory`（内存）。
- 守卫（navigation guards）
  - 在“进入路由前/后”执行的钩子函数：`beforeEach/afterEach` 等，可做登录校验、埋点等。
- SSR 与 CSR
  - SSR（服务端渲染）：在服务器把组件渲染为 HTML 返回给浏览器。
  - CSR（客户端渲染）：浏览器下载 JS 后再由 Vue 接管页面与路由（也称“水合”）。

## 二、核心对象与职责
- createRouter（来自 vue-router@4）
  - 作用：创建“路由器”实例，内含：路由匹配器、历史实现、导航守卫容器与导航 API（`push/replace`）。
- 路由记录（RouteRecord）
  - 形如 `{ path: '/posts/:id', component: Post }`；支持嵌套 `children`、重定向、别名等。
- 匹配器（Matcher）
  - 根据 `routes` 建立索引结构（可理解为“高效查表”），请求来时用它快速找到对应组件树。

## 三、最小例子（逐步升级）

### 1) 一个最简单的单路由
```ts
// 逻辑等价示意（Nuxt 会自动根据 pages 目录生成 routes）
import { createRouter, createWebHistory } from 'vue-router'
import Home from '@/pages/index.vue'

const routes = [ { path: '/', component: Home } ]
const router = createRouter({ history: createWebHistory(), routes })
```
- 当访问 `/` 时，匹配到 `Home` 组件。

### 2) 动态参数
```ts
const routes = [
  { path: '/posts/:id', component: () => import('@/pages/posts/[id].vue') }
]
```
- 访问 `/posts/123`，`route.params.id === '123'`。

### 3) 嵌套路由（父子关系）
```ts
const routes = [
  {
    path: '/settings', component: () => import('@/pages/settings.vue'),
    children: [
      { path: 'account', component: () => import('@/pages/settings/account/index.vue') },
      { path: 'security', component: () => import('@/pages/settings/security.vue') }
    ]
  }
]
```
- 匹配 `/settings/account` 时，会同时渲染父组件中的 `<router-view>` 与子组件。

### 4) i18n 前缀（多语言）
- 当启用“前缀策略”（如 `/en/...`、`/zh/...`）时，每条基础路由会被“克隆”成多份：
```text
原始：/about
扩张：/en/about, /zh/about, /de/about, ...
```
- 这会让“路由记录数量 = 基础页面数 × 语言数”。记录越多，创建路由与匹配器初始成本越高。

## 四、Nuxt 3 与路由的关系（自动化）
- 约定式路由
  - 你在 `pages/` 里新增一个文件/目录，Nuxt 就会自动生成对应路由记录；
  - 如 `pages/posts/[id].vue` -> `/posts/:id`。
- 插件与中间件
  - 你可以在 `plugins/*.ts` 里通过 `useRouter()` 注册守卫、埋点；在 `middleware/*.ts` 里做基于路由的拦截。
- i18n 集成
  - 若使用 `@nuxtjs/i18n` 并启用“前缀策略”，Nuxt 会在生成路由时为每个语种扩张一份路由集合。

## 五、从“创建”到“导航”的流程（简化版）

### Mermaid 时序图
- ASCII 版（通用显示）：
```text
Client --> Nitro(Node/Nitro) --> Nuxt(App) --> vue-router
    1) Client: HTTP GET /page
    2) Nitro: 创建/复用应用实例
    3) Nuxt: createRouter({ history, routes })
    4) vue-router: 返回 router
    5) Nuxt: router.push(initialURL); await router.isReady()
    6) Nuxt -> Nitro: SSR 渲染完成(HTML)
    7) Nitro -> Client: 返回 HTML

客户端阶段：下载 JS -> 创建客户端 router -> 水合
```

### 流程图（创建与匹配）
- ASCII 版（通用显示）：
```text
[生成 routes(含 i18n 扩张)]
          |
          v
    [createRouter]
          |
          v
 [createRouterMatcher]
          |
          v
[规范化/索引所有记录]
          |
          v
 [router.push/resolve]
          |
          v
   +-------------------+
   | 匹配成功？        |
   +-------------------+
        |        \
       是         否
        |          \
        v           v
[渲染对应组件树]   [404/重定向]
```

## 六、常见问题与直觉理解
- 为什么 `createRouter` 会“重”？
  - 因为它要把所有路由记录（含 i18n 扩张、嵌套、动态参数）规范化并建立索引；记录越多、结构越复杂，初始化越重。
- 为什么“刚启动/首个请求”会慢？
  - 需要首次创建应用与路由，并进行一次初始导航匹配；之后命中缓存或复用实例会快很多。
- SSR 与客户端路由有什么不同？
  - SSR 使用内存历史并只做一次匹配；客户端用浏览器历史，负责后续交互时的导航与组件切换。

## 七、动手感受（练习建议）
1. 在 `pages/` 里新增/删除简单页面，观察路由是否自动生效。
2. 写一个动态路由页面，打印 `useRoute().params` 理解参数来源。
3. 增加一个 `beforeEach` 守卫，打印每次导航的 `to.path`，体会守卫的执行时机。
4. 启用 i18n 的前缀策略，并减少/增多语言，观察“路由总数”与“启动耗时”的变化。

## 八、思维导图（mm 结构，复制到思维导图工具即可）
```mm
<map version="1.0">
  <node TEXT="Router 入门">
    <node TEXT="前置概念">
      <node TEXT="URL/路径"/>
      <node TEXT="路由/路由表"/>
      <node TEXT="匹配/历史模式"/>
      <node TEXT="守卫"/>
      <node TEXT="SSR 与 CSR"/>
    </node>
    <node TEXT="核心对象">
      <node TEXT="createRouter"/>
      <node TEXT="RouteRecord"/>
      <node TEXT="Matcher"/>
    </node>
    <node TEXT="示例">
      <node TEXT="单路由"/>
      <node TEXT="动态参数"/>
      <node TEXT="嵌套"/>
      <node TEXT="i18n 前缀扩张"/>
    </node>
    <node TEXT="Nuxt 集成">
      <node TEXT="约定式路由(pages)"/>
      <node TEXT="plugins/middleware"/>
      <node TEXT="i18n 扩张"/>
    </node>
    <node TEXT="问题与优化">
      <node TEXT="为何 createRouter 变重"/>
      <node TEXT="减少路由数量/守卫负担"/>
      <node TEXT="SSR 预热/实例复用"/>
    </node>
  </node>
</map>
```

—— 到这里，你已经具备读懂“创建路由 -> 匹配 -> 渲染”这条链路的基础。若你愿意，我可以再结合你项目实际，输出“统计当前路由数量与创建耗时”的小工具，帮助你把抽象概念和真实数据对应起来。

## 九、FAQ：关于 SSR 的 router 复用与配置位置

### 1) SSR 下会不会复用同一个 router？
- 结论：不会。Nuxt 3 在服务器端渲染时，会为“每个请求”创建全新的应用实例与 router 实例，用于隔离跨请求状态，防止用户数据串扰。
- 可以复用的：已编译的服务器 bundle、静态路由定义数据（如由 `pages/` 生成的配置）。
- 降开销正确姿势：使用结果缓存而非复用 router 对象。
  - Nitro 响应缓存/ISR/CDN/反向代理缓存：命中时直接返回已渲染的 HTML，整条 SSR 链（包括 createRouter）都会被跳过。

### 2) 这些行为在哪里配置？
- 是否启用 SSR：`nuxt.config.ts` 中 `ssr: true|false`（默认 true）。
- 路由记录来源：`pages/` 目录（约定式路由）。
- 路由扩展/修改：`nuxt.config.ts` -> `hooks.pages:extend`（本项目已用），或模块（如 `@nuxtjs/i18n`）影响前缀/克隆策略。
- 路由器选项（如 `scrollBehavior`）：新建 `app/router.options.ts` 并导出 `defineNuxtRouterOptions(() => ({ ... }))`。
- 路由守卫/导航钩子：
  - `middleware/*.ts` 使用 `defineNuxtRouteMiddleware`（可 SSR/CSR）。
  - `plugins/*.ts` 内通过 `useRouter()` 注册 `beforeEach/afterEach` 等（主要客户端）。
- i18n 对路由规模的影响：`nuxt.config.ts` 的 `i18n` 配置（`strategy`、`locales` 等）会成倍扩张路由数量，放大 `createRouter` 的成本。
- 历史实现选择：Nuxt 自动选择（SSR 用 `createMemoryHistory`，客户端用 `createWebHistory`），通常无需手配。

### 实用建议（生产环境）
- 首选启用 Nitro 的响应缓存/ISR/CDN，命中时绕过 SSR 渲染与 createRouter。
- 控制路由记录规模：收敛 i18n 语种/前缀策略、精简 `pages/`，减少嵌套与动态段的复杂度。
- 守卫瘦身：避免在全局 `beforeEach` 做重逻辑；重活放到页面加载或服务端中间层。

## 十、为什么不能复用 router 实例？（深入理解）

### 1) 数据串扰的具体例子

假设我们复用同一个 router 实例：

```ts
// 用户 A 访问 /posts/123
router.push('/posts/123')
// router.currentRoute.value.params.id = '123'

// 同时，用户 B 访问 /posts/456  
router.push('/posts/456')
// router.currentRoute.value.params.id = '456'

// 用户 A 的页面渲染时，可能拿到的是用户 B 的参数！
```

### 2) 更复杂的串扰场景

```ts
// 用户 A（已登录）
const userStore = useUserStore()
userStore.user = { id: 1, name: 'Alice' }

// 用户 B（未登录）同时访问
const userStore = useUserStore() // 同一个实例！
userStore.user = null

// 用户 A 的页面可能显示"未登录"状态
```

### 3) 路由状态包含的内容

router 实例内部包含：
- `currentRoute`：当前路由信息（路径、参数、查询等）
- `beforeEach/afterEach` 守卫中的闭包变量
- 路由元信息（meta）
- 历史记录
- 各种内部状态

### 4) 这是哪个框架的机制？

- **Vue 3**：只是一个视图库，不涉及 SSR
- **Vue Router 4**：支持 SSR，但需要开发者自己管理实例隔离
- **Nuxt 3**：基于 Vue Router 4，但自动处理了 SSR 的实例隔离

### 5) Nuxt 3 的隔离机制

```ts
// Nuxt 3 内部大致逻辑
export async function renderToString(url: string) {
  // 每个请求都创建新的应用实例
  const app = createApp(App)
  const router = createRouter({
    history: createMemoryHistory(),
    routes: allRoutes
  })
  
  // 设置当前请求的路由
  router.push(url)
  await router.isReady()
  
  // 渲染
  const html = await renderToString(app)
  return html
}
```

### 6) 为什么感觉"都一样"？

- **表面看起来相同**：路由配置相同（都是基于 `pages/` 目录）、组件相同、逻辑相同
- **但运行时状态不同**：
  - 用户 A：访问 `/posts/123`，`route.params.id = '123'`
  - 用户 B：访问 `/posts/456`，`route.params.id = '456'`
  - 用户 C：访问 `/settings`，`route.params.id = undefined`
- **请求上下文不同**：不同的 cookies、headers、用户认证状态、语言偏好

### 7) 实际验证方法

```ts
// 在任意页面组件中
export default defineComponent({
  setup() {
    const route = useRoute()
    const router = useRouter()
    
    console.log('当前路由:', route.path)
    console.log('路由参数:', route.params)
    console.log('路由实例ID:', router.uid) // 每次请求都不同
  }
})
```

### 8) 总结
- **不能复用的原因**：每个请求的运行时状态不同（路由、用户数据、上下文）
- **这是 Nuxt 3 的机制**：自动处理 SSR 实例隔离
- **感觉"都一样"**：因为配置相同，但运行时状态不同
- **解决方案**：通过缓存渲染结果（ISR/CDN）来避免重复创建实例
