# Nuxt 插件与中间件入门（面向小白）

## 一、前置概念
- 插件（plugins）
  - 在 Nuxt 应用创建时运行的一段初始化逻辑，用来“安装能力”：注入全局对象、注册路由守卫、挂载事件、配置第三方库等。
- 中间件（middleware）
  - 路由导航发生时执行的函数，用来“决定去哪里”：做权限校验、重定向、设置布局、预取数据等。
- 关系
  - 插件更偏“启动期/全局能力”；中间件更偏“每次路由进入时的业务决策”。

## 二、典型生命周期与执行时机

### 插件（大致顺序）
```text
app 启动 -> 依次执行 plugins/* -> 注册路由守卫/注入工具 -> 创建 router -> 首次导航
```
- 本项目示例：
  - `plugins/nprogress.client.ts`：注册 beforeEach/afterEach 全局进度条
  - `plugins/gtag.client.ts`：注册 afterEach 上报 page_view
  - `plugins/i18n.loader.ts` & `plugins/i18n.client.ts`：装配/加载语言包
  - `plugins/route-history.client.ts`：记录路由历史

### 中间件（每次导航）
```text
router.push() -> 匹配路由 -> 执行 Nuxt 路由中间件 -> 执行组件守卫 -> 提交导航
```
- 本项目示例：
  - `middleware/auth.global.ts`：需要登录的页面做重定向
  - `middleware/settings.ts`：访问 /settings 时重定向到具体子页
  - `middleware/soccer-data-base.ts`、`middleware/soccer-inner.ts`：根据路径设置布局或预取数据

## 三、类型与写法

### 1) 插件
```ts
// plugins/nprogress.client.ts
import NProgress from 'nprogress'
import 'nprogress/nprogress.css'

export default defineNuxtPlugin(() => {
  useRouter().beforeEach(() => NProgress.start())
  useRouter().afterEach(() => NProgress.done())
})
```
- .client 只在浏览器执行；.server 只在服务端；不带后缀则两端皆可（注意分支判断）。

### 2) 路由中间件
```ts
// middleware/auth.global.ts
export default defineNuxtRouteMiddleware((to) => {
  const localePath = useLocalePath()
  const { checkAuth } = useAuthCheck()
  if (to.meta.requiresAuth && !checkAuth()) {
    return navigateTo(localePath('/'))
  }
})
```
- 命名中间件：文件名就是中间件名，在页面 `definePageMeta({ middleware: 'auth' })` 使用。
- 全局中间件：以 `.global` 结尾，所有路由都会执行（如 `auth.global.ts`）。

## 四、ASCII 时序图（整体框架）
```text
启动阶段：
Node/Nitro -> NuxtApp -> 执行 plugins -> 注册守卫/注入 -> createRouter -> 首次导航

导航阶段（每次）：
router.push -> 匹配 -> Nuxt 中间件 -> 组件守卫 -> 懒加载组件/数据 -> 提交导航 -> afterEach
```

## 五、mm 流程图（复制到思维导图工具）
```mm
<map version="1.0">
  <node TEXT="Nuxt 插件 & 中间件">
    <node TEXT="插件">
      <node TEXT="初始化全局能力"/>
      <node TEXT="注册守卫/注入对象"/>
      <node TEXT="i18n/nprogress/gtag"/>
    </node>
    <node TEXT="中间件">
      <node TEXT="路由时机执行"/>
      <node TEXT="权限/重定向/布局/数据"/>
      <node TEXT="auth/settings/soccer"/>
    </node>
    <node TEXT="生命周期">
      <node TEXT="启动: 执行插件 -> 建 Router"/>
      <node TEXT="导航: 中间件 -> 守卫 -> 提交"/>
    </node>
    <node TEXT="最佳实践">
      <node TEXT="插件防重注册"/>
      <node TEXT="中间件轻量化、避免阻塞"/>
      <node TEXT="SSR 注意环境分支"/>
    </node>
  </node>
</map>
```

## 六、最佳实践
- 插件
  - 防重注册：开发态 HMR 可能重复执行，使用模块级标记避免重复挂钩。
  - 环境分支：埋点、DOM 操作使用 `process.client` 或 `.client` 文件后缀。
- 中间件
  - 轻量优先：做校验和跳转，不要在中间件里做重型数据请求（放到页面 useAsyncData）。
  - 明确作用域：只在需要的页面使用命名中间件，避免全局中间件过重。
  - 链式重定向最少化：减少多次 push 带来的耗时与复杂度。

## 七、结合你项目的提示
- 首屏“多次 push”多源于：i18n 前缀归一化 + `settings.ts` 的二次重定向。
- 若要优化：
  - 合并重定向逻辑（一次跳到目标）。
  - 插件里对路由钩子做“只注册一次”的保护。
  - 将中间件中的数据获取下沉至页面，利用 SSR/CSR 的 useAsyncData 缓存与并发策略。
