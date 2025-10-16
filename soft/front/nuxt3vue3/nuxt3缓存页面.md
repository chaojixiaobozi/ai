# Nuxt 3 页面缓存入门（面向小白）

## 一、前置知识
- 缓存是什么：把“已经算好的结果”存起来，命中时直接返回，避免重复计算（SSR 渲染、数据库查询等）。
- 缓存层级：
  - 浏览器缓存（HTTP 缓存控制）；
  - 中间层缓存（CDN、反向代理如 Nginx/Cloudflare）；
  - 应用层缓存（Nuxt/Nitro 的响应缓存、ISR）；
  - 数据层缓存（接口、数据库）。
- 关键概念：
  - 缓存键（Cache Key）：决定“同一份缓存”的唯一性；设计不当会串内容。
  - 过期/失效（TTL / Revalidate）：缓存多久、何时刷新。
  - Vary：告诉缓存层“需要根据哪些请求头/参数区分缓存”。

## 二、缓存的常见种类（Nuxt 视角）
- 浏览器/HTTP 缓存：通过响应头 `Cache-Control`, `ETag`, `Last-Modified` 控制；适合静态资源与不常变的页面。
- CDN/反向代理缓存：把页面缓存到边缘或代理层；命中后直接在边缘返回，最省服务器资源。
- Nitro 响应缓存（Server Response Cache）：Nuxt 3 服务器端对“页面响应”做缓存；命中时跳过 SSR 渲染链（包括 createRouter）。
- ISR（Incremental Static Regeneration）：增量静态再生成；在有效期内返回旧页，过期后后台再生成新页并替换。

## 三、什么时候适合缓存页面
- 公开、非个性化页面（首页、频道、帖子/商品详情）
- 个性化较弱，但可按维度拆分的页面（按语言/地区/设备）
- 不建议缓存：强个性化或包含敏感信息的页面（需要严格按用户区分或不缓存）

## 四、缓存键与 Vary（防止串扰的关键）
- 缓存键应包含影响页面内容的所有维度：
  - URL、查询参数
  - 语言/地区（lang、Accept-Language、cookie）
  - 设备类型（UA、自定义设备标识）
  - A/B 实验标记等
- Vary 告诉中间层如何区分缓存：如 `Vary: Accept-Language, User-Agent`。
- 设计原则：
  - 公共页：键=URL(+必要查询参数)
  - 半个性化页：键=URL+语言/设备等
  - 强个性化页：不缓存或键包含用户 ID（仅限私有缓存）

## 五、ASCII 时序图（命中与未命中）
```text
[Client] -> [CDN/Proxy] -> [Nitro] -> [Nuxt SSR]
  |           | 命中: 直接返回
  |           | 未命中: 继续到 Nitro
  |                          | 命中: Nitro 响应缓存直接返回
  |                          | 未命中: 进入 SSR 渲染(createRouter/渲染)
  |<------------------------- HTML 返回 -------------------------
```

## 六、Nuxt/Nitro 配置与示例

### 1) 路由级缓存（Nitro routeRules）
- 在 `nuxt.config.ts`：
```ts
export default defineNuxtConfig({
  nitro: {
    routeRules: {
      // 首页：缓存 300 秒（CDN 与 Nitro 都可识别）
      '/': { isr: 300 },
      // 频道页：缓存 120 秒，并根据语言区分（示例：设置响应头，配合 CDN Vary）
      '/category/**': {
        isr: 120,
        headers: { 'Vary': 'Accept-Language' }
      },
      // 详情页：可更长缓存或按需刷新
      '/posts/**': { isr: 600 }
    }
  }
})
```
- 说明：`isr: 300` 表示 300 秒内直接返回已生成的静态版本；过期后后台再生成。

### 2) 手动控制响应缓存（服务器端 Handler）
- 在 `server/api/foo.get.ts`：
```ts
export default defineEventHandler(async (event) => {
  // 设置缓存头
  setHeader(event, 'Cache-Control', 'public, max-age=60, s-maxage=300, stale-while-revalidate=600')
  // 可结合 getQuery(event) 设计缓存键(由 CDN/代理/客户端识别)
  return { ok: true, now: Date.now() }
})
```

### 3) 页面渲染的“个性化”与缓存
- 个性化因子放到缓存键里（语言/地区/设备），或把个性化部分迁到客户端渲染（首屏先返回公共内容，个性化区域用 CSR 注入）。
- 例如：首屏渲染公共信息，用户头像/用户名在客户端再请求。

## 七、示例：从 0 到 1 逐步加缓存
1) 第一步：不开缓存 → 每次都 SSR
2) 第二步：首页/频道加 ISR（`routeRules.isr`）
3) 第三步：为语言/设备加 Vary（`headers: { Vary: 'Accept-Language, User-Agent' }`）
4) 第四步：细分长尾详情页 TTL，或根据更新频率设置不同 isr 值
5) 第五步：对热点接口加 `Cache-Control`，配合 CDN 缓存 API 响应

## 八、排错与最佳实践
- 验证命中：
  - 观察响应头：`x-nitro-cache`, `age`, `cf-cache-status` 等（不同平台不同）。
  - 打开服务器日志：命中缓存时不应出现 SSR 渲染日志/耗时应显著降低。
- 常见问题：
  - 串内容：缓存键或 Vary 设计不全 → 把语言/设备/实验标记加入键。
  - 缓存不生效：代理层未遵守 Cache-Control 或未识别 isr/headers → 检查平台规则。
  - 数据过期：TTL 太长/缺少刷新策略 → 调整 isr、使用 webhook 触发 revalidate。
- 建议：
  - 重要公开页优先缓存；强个性化页谨慎缓存。
  - 分层缓存策略：CDN 静态长缓存 + Nitro 页缓存/ISR + API 层缓存。
  - 监控命中率与首字节时间（TTFB）、后端负载。

## 九、mm 思维导图（复制到思维导图工具）
```mm
<map version="1.0">
  <node TEXT="Nuxt3 页面缓存">
    <node TEXT="前置知识">
      <node TEXT="缓存层级/键/TTL/Vary"/>
    </node>
    <node TEXT="种类">
      <node TEXT="浏览器/HTTP"/>
      <node TEXT="CDN/Proxy"/>
      <node TEXT="Nitro 响应缓存"/>
      <node TEXT="ISR"/>
    </node>
    <node TEXT="适用场景">
      <node TEXT="公开页/半个性化页"/>
      <node TEXT="强个性化页不缓存或私有缓存"/>
    </node>
    <node TEXT="缓存键/Vary">
      <node TEXT="URL/查询/语言/设备/实验"/>
    </node>
    <node TEXT="示例步骤">
      <node TEXT="无缓存"/>
      <node TEXT="ISR"/>
      <node TEXT="Vary 细分"/>
      <node TEXT="TTL 策略"/>
    </node>
    <node TEXT="排错与实践">
      <node TEXT="命中验证"/>
      <node TEXT="串内容/不生效/过期"/>
      <node TEXT="分层缓存与监控"/>
    </node>
  </node>
</map>
```

—— 有需要我可以按你项目现有路由结构，标注“适合 ISR 的页面清单”和“Vary 维度建议”，并提交示例配置。
