# Lessons Learned

踩过的坑、验证过的做法，逐条追加，不覆盖。

## 怎么查 CodeBuddy 模型价格（模型目录 + 倍率）

**结论：不要硬记价格。** 价格/倍率随官方调整，一律以本机账号级缓存文件实时拉取为准。

### 数据源 1（首选）：账号级缓存 `~/.codebuddy/local_storage/entry_*.info`

- 目录：`~/.codebuddy/local_storage/`
- 每个 `entry_<hash>.info` 是一个 JSON 数组，形如 `[{"userId":..., "data":{...}, "ts":...}]`
- 模型目录在 `data.models[]`，是**当前账号**能用的完整模型清单（含账号专属/未公开模型）
- 挑最新文件即可：`ls -t ~/.codebuddy/local_storage/entry_*.info | head -1`，再按体积/修改时间选（模型目录条目通常较大）

每个模型的字段：

| 字段 | 含义 |
|---|---|
| `id` | 模型标识（如 `space-bunny`、`deepseek-v4-pro`） |
| `name` | 展示名 |
| `credits` | **相对倍率**（如 `x0.08 credits`），用来算价格 |
| `reasoning` | 推理配置（`effort`/`supportedEfforts`/`summary`/`canDisableThinking`） |
| `supportsImages` | 是否支持图片输入 |
| `maxInputTokens` / `maxOutputTokens` / `maxAllowedSize` | 上下文与输出上限 |
| `tags` | 标签（部分模型有） |
| `descriptionEn` / `descriptionZh` | 官方描述 |
| `vendor` | 供应商**代码**（`e`/`f`/`j`/`i`/`v`/`tencent`），不是公司名 |
| `relatedModels` | lite / reasoning / builtin-lite 的关联模型 |

快速提取某模型的完整条目：

```bash
python3 - <<'PY'
import json, glob, os
f = max(glob.glob(os.path.expanduser('~/.codebuddy/local_storage/entry_*.info')), key=os.path.getmtime)
d = json.load(open(f))
for m in d[0]['data']['models']:
    if m.get('id') == 'space-bunny':
        print(json.dumps(m, ensure_ascii=False, indent=2))
PY
```

### 数据源 2（补充）：npm 包内 `product*.json`

- 路径：`~/.nvm/versions/node/v22.22.0/lib/node_modules/@tencent-ai/codebuddy-code/`
  - 注意：包名是 **`codebuddy-code`**，不是 `codebuddy`
- 文件：`product.json` / `product.cloudhosted.json` / `product.internal.json` / `product.ioa.json` / `product.selfhosted.json`
- 这些是**内置默认模型目录**（fallback），也有 `credits` / `vendor` 字段，可作为兜底
- **局限**：不含账号专属/未公开模型（例如 `space-bunny` 只在 `entry_*.info` 里有，product*.json 里查不到）

### 查不到的地方（别浪费时间）

- **官方定价页**（`copilot.tencent.com/pricing`）和**文档站**（`codebuddy.ai/docs`）都是 SPA，`curl` 抓不到每模型价格，只会拿到空壳 HTML
- `vendor` 是内部代码，包内没有代码→公司名的对照表，别硬猜

### 原则

1. **以 `entry_*.info` 实时拉取为准**，不写死价格/倍率。
2. 倍率是相对值（`x0.08 credits` 这类），要和套餐积分一起算才能换算成钱。
3. 需要跨账号/新装环境验证时，先看 `entry_*.info`，再用 `product*.json` 兜底。

## 模型失效时的处理

当 CodeBuddy 报告某个已配置模型被撤销、不可用、或不在模型列表里时（注意：限流/限额/超时不算，那是临时问题，切兜底即可），执行以下步骤：

1. 重新读取 `~/.codebuddy/local_storage/entry_*.info` 缓存文件，拉取最新模型目录
2. 把完整模型表（模型名/倍率/推理/图像/上下文）按倍率排序打屏给用户
3. 让用户重新选主力/编码/兜底三档模型
4. 不要自己拍板换模型，等用户决定
5. 更新 `SKILL.md` 和 `models.md` 里的模型配置

## 减少 CodeBuddy 内部轮次（工具调用 = 模型请求）

**结论：CodeBuddy 的 agent 循环里，每次工具调用都会触发一轮新的模型请求。336 次请求分布在 26 个会话，平均 13 轮/任务，峰值 61 轮。大部分轮次消耗在 ls/grep/cat 探索目录上。优化方式：指令给具体文件路径、用 Read/Grep 工具代替 Bash、一次性列全需求。**

推论：轮次是成本的主要来源。减少轮次的三条杠杆——① 指令里直接给文件路径，别让它自己找；② 用 Read/Grep/Glob 结构化工具而不是 Bash 的 cat/grep/ls，避免解析失败触发重试；③ 只读扫描任务一次把需求列全，不要分多轮追问。

## 删除 / 改配置类任务的通用教训（先列清单 → 审核 → 执行）

一次本机维护中曾因**未先列精确清单就直接执行删除**，误删了仍需要的内容，事后只能从备份/回收站抢救。教训沉淀为固定流程，已固化为 SKILL.md 的「删除 / 卸载 / 改配置类任务：三步审核法」：

1. **列清单**：把要删/卸/改的对象精确到路径与命令，标注是否可恢复、影响范围。
2. **交审核**：把清单交给用户逐条确认，不替用户拍板、不缩小范围。
3. **确认后执行**：用户明确同意才动手，且优先用可回收方式（先回收站 / 备份，而非 `rm -rf`）。

所有不可逆 / 高风险操作一律先走这三步，不图快、不绕过。

## 监督模式下的通用坑

- **不亲自下场**：监督方的价值在「问清 + 审方案 + 验收」，不在自己跑命令；自己动手既浪费 token 又容易漏掉审核这一环。
- **验收必须贴证据**：CodeBuddy 自报「完成」不算数，要它把文件片段 / 命令输出 / 测试结果打屏核对。
- **不可逆操作先确认意图**：push 到共享 / 受保护分支、force push、生产写操作，先与用户确认再执行，不绕过、不拆命令或换脚本规避系统安全策略。
- **只读轻活也要先出方案**：哪怕只是查状态，也先让 CodeBuddy 给一句「目标 + 只读检查清单」过目，不悄无声息直接跑。
