# SSR 水合（Hydration）入门指南

## 1. 前置知识
- SSR（Server-Side Rendering）：服务器端把 Vue 组件渲染成 HTML 发给浏览器。
- CSR（Client-Side Rendering）：浏览器下载 JS 后再由 Vue 渲染页面。
- 水合（Hydration）：浏览器用客户端 Vue 实例“接管”服务端返回的静态 HTML，绑定事件与状态，使页面“活起来”。
- 同构/通用：同一套组件既能在服务端渲染，也能在客户端运行。

## 2. 为什么需要水合
- SSR 提供“可见 HTML”，用户更快看到页面；
- 但 SSR 返回的是“静态 HTML”，没有点击/交互；
- 水合让客户端与这份 HTML 对齐（匹配 DOM 节点与组件树），之后事件/状态更新在客户端进行。

## 3. 从请求到水合：ASCII 时序
```text
Client -> Server(Nitro) -> Nuxt(App) -> Vue SSR
 1) Client: 请求 /page
 2) Server: 运行中间件/匹配路由/数据获取
 3) Vue SSR: 将组件树渲染为 HTML 字符串
 4) Server: 返回 HTML + 内联初始状态
 5) Client: 下载客户端 JS 包
 6) Hydration: 客户端 Vue 将组件树与现有 HTML 逐节点匹配并绑定事件
 7) 接管完成：页面可交互，后续导航/更新走 CSR
```

## 4. mm 流程图（复制到思维导图工具）
```mm
<map version="1.0">
  <node TEXT="SSR 水合">
    <node TEXT="服务端">
      <node TEXT="路由匹配/数据获取"/>
      <node TEXT="SSR 渲染为 HTML"/>
    </node>
    <node TEXT="客户端">
      <node TEXT="下载 JS"/>
      <node TEXT="Hydration 与 DOM 匹配"/>
      <node TEXT="绑定事件/恢复状态"/>
      <node TEXT="进入 CSR"/>
    </node>
  </node>
</map>
```

## 5. 最小示例（概念演示）
- 服务器返回：
```html
<div id="app">
  <h1>hello</h1>
  <button>count: 0</button>
</div>
<script>window.__NUXT__ = { state: { count: 0 } }</script>
```
- 客户端运行：
```ts
// 客户端 bundle 内部
createApp(App).mount('#app') // 实际为 hydrate，复用既有 DOM，绑定点击事件
```
- 用户点击按钮后，数字在客户端更新。

## 6. 水合做了哪些校验
- 组件树与 DOM 节点逐一匹配：标签、顺序、关键属性；
- 初始状态对齐：使用服务端内联的初始数据恢复 store/组件状态；
- 只补事件与少量差异，不会二次重绘整个页面（正确时）。

## 7. 常见问题与排错
- 服务端与客户端内容不一致（hydration mismatch）：
  - 典型原因：在 render 期间读到了 `Date.now()/Math.random()/window` 等导致两端结果不同；
  - 解决：把仅客户端可得的数据放到 `onMounted` 后取，或使用 `client-only` 包裹。
- 事件未绑定：
  - 可能是挂载点不一致、DOM 被外部脚本改写；
  - 检查控制台警告，确保 `mount` 到与 SSR 同一根元素。
- 白屏/闪烁：
  - 客户端包加载慢或错误；使用分块、预加载、错误边界；
  - 首屏异步数据应在 SSR 阶段完成，降低客户端等待。

## 8. 与 Nuxt 3 的关系（要点）
- Nuxt 3 在服务端完成 SSR（Nitro）并内联状态；
- 客户端入口加载后自动进行水合；
- 路由层面：SSR 用内存 history，客户端切换到 Web History；
- 数据层面：useAsyncData 首屏 SSR 获取的数据在客户端复用，不会重复请求（除非你手动刷新）。

## 9. 实践建议
- 保持 SSR 与 CSR 输出一致：避免时间、随机数、非确定性数据直接渲染；
- 用 `process.client` 分支处理只在浏览器存在的 API；
- 对大组件/非首屏内容使用懒加载与占位骨架；
- 结合 ISR/CDN，让更多请求直接用缓存跳过 SSR；
- 监控：记录 TTFB、JS 下载/执行、Hydration 完成时间。

## 10. 一个完整的小例子（从 SSR 到水合）

下面是用“最接近真实”的方式，演示从服务端渲染到客户端水合的全流程。示例采用 Vue 3 SSR 风格（Nuxt 3 内部也是基于同样原理）。

### 1) 组件（两端通用）
```ts
// App.vue（伪代码，等价 SFC）
export default {
  name: 'App',
  data: () => ({ count: 0 }),
  template: `
    <div>
      <h1>Counter</h1>
      <button @click="count++">count: {{ count }}</button>
    </div>
  `
}
```

### 2) 服务端入口（SSR 渲染）
```ts
// server.ts（极简示意）
import { createSSRApp } from 'vue'
import { renderToString } from 'vue/server-renderer'
import App from './App'

export async function handleRequest(req, res) {
  const app = createSSRApp(App)

  // 1) 用组件树渲染出 HTML 字符串
  const appHtml = await renderToString(app)

  // 2) 返回 HTML，并内联初始状态（这里是 count:0）
  const html = `<!doctype html>
<html>
  <head><meta charset="utf-8"><title>SSR hydration demo</title></head>
  <body>
    <div id="app">${appHtml}</div>
    <script>window.__INITIAL_STATE__ = { count: 0 }</script>
    <script type="module" src="/client-entry.js"></script>
  </body>
</html>`
  res.end(html)
}
```

- 关键点：`#app` 内已经有服务器渲染好的 HTML，用户立即可见。

### 3) 返回给浏览器的首包 HTML（查看“页面源代码”能看到）
```html
<div id="app">
  <div>
    <h1>Counter</h1>
    <button>count: 0</button>
  </div>
</div>
<script>window.__INITIAL_STATE__ = { count: 0 }</script>
<script type="module" src="/client-entry.js"></script>
```

### 4) 客户端入口（水合挂载）
```ts
// client-entry.ts（极简示意）
import { createApp, h } from 'vue'
import App from './App'

// 复用 SSR 内联的初始状态
const state = (window as any).__INITIAL_STATE__ || { count: 0 }

// 用已有 DOM 进行水合（Vue 内部会自动走 hydrate 流程）
const app = createApp({
  data: () => ({ count: state.count }),
  render: () => h(App)
})

// 重要：mount 到与 SSR 相同的容器 #app
app.mount('#app')
```

- 水合发生了什么：
  - Vue 将 `App` 生成的虚拟节点树与 `#app` 里现有的 SSR DOM 一一匹配；
  - 为 `<button>` 补上 @click 的事件监听器；
  - 使用 `__INITIAL_STATE__` 恢复初始数据（count:0）；
  - DOM 基本不重建，页面立即可交互。

### 5) 交互验证
- 页面初始可见“count: 0”；
- 点击按钮，数字变为 1、2、3……（这一步已经完全在客户端）。

### 6) 常见坑对应到这个例子
- 若在模板里直接渲染 `Date.now()`，SSR 与 CSR 值不同，会报 hydration mismatch；
- 若客户端 `mount('#app')` 容器不对，或 SSR HTML 被外部脚本改写，也会失败；
- 若你把 @click 的逻辑写在只在服务端执行的分支，客户端将不会绑定事件。

## 11. 客户端如何获得组件代码并在水合时补事件（详细时序）

结论：服务端与客户端并不是“共读同一份源码文件”，而是“由同一份源码各自编译出的两份产物”。
- 服务端使用 SSR Bundle（Node 可执行，供 Nitro 渲染 HTML）。
- 客户端使用 Client Bundle（浏览器下载的 JS 模块，内含编译后的 App.vue 渲染函数与事件信息）。

### 从源码到水合的完整时序
```text
开发/构建阶段（一次性）
App.vue ──编译→ [SSR Bundle]（Node可执行）
        └─编译→ [Client Bundle]（浏览器可执行）

请求阶段（每次）
Client ─HTTP GET /page────────────────────────────> Server(Nitro)
Server: 载入 [SSR Bundle] 执行 → 匹配路由/取数 → SSR 渲染出 HTML
Server: 返回 HTML + <script type="module" src="/_nuxt/entry.js"> + 内联初始状态
Client: 先显示 HTML（可见但尚不可交互）
Client: 下载 [Client Bundle]（entry.js 及其依赖，含 App.vue 编译后的渲染函数/事件）
Client: 运行客户端入口 → 生成同构 VNode（含 onClick/onInput 等）→ Hydration
Client: Hydration 将 VNode 与现有 DOM 对齐，并通过 addEventListener 补上事件监听
Client: 页面进入可交互状态，后续更新/导航走 CSR
```

### 为什么源代码里看不到 onclick
- SSR 只输出“静态 HTML”，不会写内联 onclick。
- 事件信息保存在客户端 Bundle 的渲染函数里。水合时 Vue 根据这些信息对 DOM 绑定监听器，所以“看源码”看不到 onclick，但按钮仍能响应点击。

### 客户端 Bundle 的来源
- 生产：`<script type="module" src="/_nuxt/xxx.js">` 加载 `.output/public/_nuxt/*.js`。
- 开发：由 Vite Dev Server 动态按模块 URL 提供 ESM（例如 `/@fs/.../App.vue?vue&type=script`）。
