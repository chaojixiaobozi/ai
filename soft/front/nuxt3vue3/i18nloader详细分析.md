# i18n.loader 插件详细分析

目标：解释 `plugins/i18n.loader.ts` 的执行流程、在 SSR/CSR 中的行为差异、是否全局共享、潜在问题与优化建议。

## 1. 代码职责与要点
- 初始化语言：从 URL `?lang` 或 `lang` Cookie 推导语言；若都没有，保留默认语言。
- 懒加载词典：若不是 `en` 且本地还未有该语言消息，则向后端接口拉取字典，处理后注入到 i18n。
- 客户端保障：在客户端环境确保 `i18n.setLocale(locale)` 生效。
- 语言切换监听：当 `i18n.locale` 变化时，再懒加载目标语言并设置。

核心函数：
- `initializeLanguage(i18n, route, langCookie)`：根据 URL/Cookie 校验并设置语言。
- `loadLanguagePack(locale, config, deviceInfoCookie, i18n)`：POST 获取字典，`processDictionaryData` 归一化，然后 `i18n.setLocaleMessage(locale, processedData)`。

## 2. 请求处理时序（SSR 首屏）
```text
Nitro(SSR) 处理请求
  -> 读取 URL & Cookie -> initializeLanguage()
  -> 若 locale !== 'en' 且本地无消息: loadLanguagePack(locale)
       - $fetch POST /v1/api/user/getDictionaryMap
       - processDictionaryData()
       - i18n.setLocaleMessage(locale, data)
  -> 返回 HTML（可内联初始状态）
Client 端接管
  -> if (import.meta.client) i18n.setLocale(locale)
  -> 监听 i18n.locale 变更并按需再次加载
```

## 3. 导航时序（CSR 语言切换）
```text
用户触发语言切换 -> i18n.locale = newLocale
  -> watch(i18n.locale) 触发
    -> loadLanguagePack(newLocale)（若未缓存）
    -> i18n.setLocale(newLocale)
```

## 4. mm 流程图（复制到思维导图工具）
```mm
<map version="1.0">
  <node TEXT="i18n.loader 流程">
    <node TEXT="SSR 首屏">
      <node TEXT="URL/Cookie 推导语言"/>
      <node TEXT="按需加载字典"/>
      <node TEXT="setLocaleMessage"/>
    </node>
    <node TEXT="客户端">
      <node TEXT="保证 setLocale"/>
      <node TEXT="watch 语言切换 -> 懒加载"/>
    </node>
  </node>
</map>
```

## 5. 是否“全局共享”？
- i18n 实例是“每个应用实例独立”的：
  - SSR：Nuxt 3 每个请求都会创建新的 app 与 i18n 实例；`setLocaleMessage` 注入到本次请求的实例中，仅对本请求可见，不会自动复用到其他请求。
  - CSR：浏览器中是单实例，`setLocaleMessage` 后对后续导航有效。
- 结论：
  - 服务器端“不会跨请求共享”。A 请求加载的语言包，不会自动供 B 请求使用。
  - 若要“跨请求”复用，应使用“结果缓存”（如将字典放 CDN/内存缓存/边缘缓存），让每个请求都能快速拿到相同 JSON，再各自 `setLocaleMessage`。

## 6. 潜在问题与风险
- 首屏阻塞：SSR 时若非 `en`，会进行一次远程 POST，增加 TTFB。
- 缺少缓存：目前没有应用内缓存（Memory/LRU/边缘），高并发下重复请求同一字典。
- 键一致性：`getLanguageFormat(locale)` 与 `locales` 列表需严格一致，否则加载错误语言。
- 客户端二次 setLocale：SSR 已是目标语言，CSR 再 `setLocale(locale)` 一次，虽影响不大，但可优化判断。
- 语言种类过多：与路由扩张叠加放大初始化成本（虽与本插件不直接相关）。

## 7. 优化建议
- 7.1 结果缓存
  - 服务端：在 `loadLanguagePack` 前加内存缓存（LRU，带 TTL）或通过 Nitro storage/Redis；
  - 边缘/CDN：将字典静态化到 CDN，直接 GET；
  - 客户端：sessionStorage/localStorage 缓存，避免重复拉取。
- 7.2 降低首屏阻塞
  - 非关键语言首屏先用英文或骨架，待客户端再切换；
  - 或 SSR 仅加载主要语言，长尾语言在 CSR 切换时加载。
- 7.3 健壮性
  - 对 `result?.data` 判空与结构校验；
  - try/catch 已有，但可在失败时回退至英文并上报。
- 7.4 冗余设置优化
  - 在客户端仅当 `i18n.locale.value !== locale` 时才调用 `i18n.setLocale(locale)`。

## 8. 小示例：服务端 LRU 缓存（伪代码）
```ts
// plugins/i18n.loader.ts（示意）
const langCache = new Map<string, { at: number, data: any }>()
const TTL = 5 * 60 * 1000

async function fetchLang(locale, config, deviceInfoCookie) {
  const now = Date.now()
  const key = locale
  const hit = langCache.get(key)
  if (hit && now - hit.at < TTL) return hit.data

  const result = await $fetch(/* 同上 */)
  const processed = processDictionaryData(result?.data, getLanguageFormat(locale))
  langCache.set(key, { at: now, data: processed })
  return processed
}

async function loadLanguagePack(locale, config, deviceInfoCookie, i18n) {
  const localeMessage = i18n.getLocaleMessage(locale)
  if (locale === 'en' || (localeMessage && Object.keys(localeMessage).length)) return
  try {
    const data = await fetchLang(locale, config, deviceInfoCookie)
    i18n.setLocaleMessage(locale, data)
  } catch (e) { /* fallback 到 en 并上报 */ }
}
```

## 9. QA
- Q: i18n 是全局吗？
  - A: 在浏览器端（单页面应用）是单实例；在服务器端（SSR）是“每请求一个实例”，不会跨请求共享。
- Q: `setLocaleMessage` 是否所有请求共用？
  - A: 不是。它只写入当前应用实例的内存。若需要跨请求复用，使用缓存/静态化语言包。
- Q: 需要每次都重新加载吗？
  - A: 在 SSR 层面，是的（除非你做了结果缓存）；在客户端，切换过一次语言后可复用内存/本地缓存。

---
以上分析能帮助你判断：是否要在服务端加 LRU/边缘缓存，或将语言包静态化，从根源降低首屏等待与后端压力。
