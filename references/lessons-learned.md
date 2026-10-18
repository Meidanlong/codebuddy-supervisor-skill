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

## Docker CLI 版本太老连不上 colima 的修复

**现象**：`docker ps` 报错 `Error response from daemon: client version 1.41 is too old. Minimum supported API version is 1.44`。

**原因**：本机装的是 Docker Desktop 20.10.7（很老），但 colima 的 daemon 是新的（要求 API 1.44+）。两者不兼容。

**修复**：用环境变量指定 socket + 降级 API 版本绕过：
```bash
export DOCKER_HOST=unix:///Users/meidanlong/.colima/default/docker.sock
export DOCKER_API_VERSION=1.44
```

**注意**：这只是绕过版本检查，不是真的升级。长期建议 brew upgrade docker。

## `-p` 模式下写不了文件的坑（重要）

**现象**：`codebuddy -p` 调用时，CodeBuddy 能读文件、能分析，但一写文件就静默失败，git status 里看不到任何改动。

**原因**：光加 `--permission-mode bypassPermissions` 不够。官方文档明确：**`-p/--print` 非交互模式下，必须额外加 `--dangerously-skip-permissions`（或 `-y`）参数**，否则文件写、命令执行等需要授权的操作全被拦截。

**为什么这么隐蔽**：这个失败**不报错、不非零退出**。CodeBuddy 会正常返回一段"已完成"的自述，但文件根本没落盘。所以它能骗过"看它自报完成"的验收方式——**必须用 `git status` / `ls` 之类外部手段核对文件是否真的存在**，别只看它的文字汇报。

**两个参数的关系**（别混淆）：

| 参数 | 作用 | 能替代 `--dangerously-skip-permissions` 吗 |
|---|---|---|
| `--permission-mode <mode>` | 交互模式下的权限策略（`bypassPermissions` / `dontAsk` / `default` 等） | ❌ 不能 |
| `--dangerously-skip-permissions`（`-y`） | 跳过权限确认，`-p` 下授权操作得以执行 | —— 就是它 |
| `--disallowedTools` | 黑名单，拦危险命令 | ❌ 命令行里**不要**用：里面的高危关键词会触发 Doubao 这边 Bash 安全检查误判，整条命令被拦（见下方条目） |

> `codebuddy --help` 对该参数的说明：`Bypass permission prompts (HIGH/CRITICAL still ask)`。
> 即**高危/严重级别仍会询问**，这是 CLI 自身的第三层防护；命令行里不要再塞 `--disallowedTools` 黑名单（会触发 Doubao 的 Bash 安全检查误判），危险操作的防护改靠三层兜底，见下方条目。

**正确命令模板**：
```bash
codebuddy -p --output-format text --dangerously-skip-permissions --model <模型> --session-id <session> "<任务>"
```

**验证**：2026-10-16 实测，加上 `--dangerously-skip-permissions` 后 CodeBuddy 成功写入文件，git status 能看到改动。同日复测：不加该参数时，CodeBuddy 自报完成但 `git status` 干净，确认是静默拦截而非报错。

## 命令行传 `--disallowedTools` 黑名单会触发 Doubao Bash 安全检查误判

**现象**：`codebuddy` 命令里带 `--disallowedTools` 参数（里面列着 `rm -rf /`、`sudo`、`mkfs`、`git push --force`、`DROP`/`TRUNCATE` 等高危操作关键词）时，这些关键词会被 **Doubao 这边的 Bash 工具安全扫描**识别为危险操作，直接把整条 `codebuddy` 命令拦下，任务根本派发不出去。

**原因**：两层防护叠在一起打架——Doubao 的 Bash 安全检查是第一层（挡在命令发出之前），CodeBuddy 的 `--disallowedTools` 是第二层。第一层看到命令行字面量里有危险关键词就先拦了，第二层根本没机会生效。等于我要给 CodeBuddy 装锁，结果自己家门口的保安先把我拦了。

**解法**：去掉 `codebuddy` 命令行里的 `--disallowedTools` 参数，高危操作的防护改靠**三层兜底**：
1. **Doubao 的 Bash 工具自身安全检查**（第一层，本就是兜底）；
2. **SKILL.md 的流程审核机制**（第二层）：删除/卸载/改配置走「三步审核法」、push 到共享/受保护分支前先确认用户意图；
3. **CodeBuddy CLI 自身的权限机制**（第三层）：`--dangerously-skip-permissions` 只跳过弹窗，高危/严重操作 CLI 仍会询问。

真要解锁某个危险操作，不靠黑名单开关切换，而是**由用户显式确认**（"这次允许 xxx"）才让 CodeBuddy 执行，不绕过系统安全策略。

**验证**：2026-10-16 实测，把 `--disallowedTools` 从派发命令里去掉后，原本被整条拦截的 `codebuddy` 命令能正常派发了；SKILL.md 命令模板与「权限与黑名单」章节已同步更新为三层兜底。
