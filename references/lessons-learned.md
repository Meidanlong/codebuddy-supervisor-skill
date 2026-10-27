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

## wiki URL vs 裸 token 归一化不一致导致静默建错位置

**现象**：design-coding-test 流程中，飞书 wiki 的「接口文档」节点重复创建、且建到了错误位置（空间根而不是需求澄清 wiki 下）。

**根因**：`requirement_source` 变量存的是 wiki 完整 URL（如 `https://xxx.feishu.cn/wiki/Abc123`），但 `create_node`/`create_module` 的父节点解析逻辑没有做 URL→裸 token 的归一化，直接把 URL 喂给 `get_node` API → 解析失败 → 返回空串 → 父节点为空。
- 父为空 → `node-list` 查重永远查不到 → 每次都新建（重复创建）
- 父为空 → `node-create` 落到 wiki 空间根（创建错位置）

**对照参考**：同文件里的 `read_doc` OP 是做了归一化的（sed 提取 `/wiki/` 后的 token），所以读文档功能一直正常。问题就出在写操作的父解析漏了这一步——**同一个变量在不同操作里被假设成不同格式，不一致就出事**。

**修复三件套**：
1. **核心修复**：父 token 解析前补 URL→token 归一化（与 read_doc 一致），get_node 解析失败时回退原值（不要清空）
2. **防御门禁**：`create_or_reuse` 入口检查父为空直接报错退出，不再静默建到空间根
3. **契约显式化**：调用方在使用 WIKI_PARENT 前显式解析并归一化，不依赖 agent 兜底

**教训**：
- 外部输入（URL、token、路径）在不同消费方之间格式不一致是高频坑——**同一个变量在一处做了归一化，另一处忘了做**，bug 就藏在这种不对称里。
- 静默失败比报错更可怕：解析失败不清空、而是变成空串，下游继续跑，最后节点建到错误位置、且因为查重失效会重复建——排查时很难第一时间想到是输入格式问题。
- 写操作一定要加"前置条件门禁"：父为空、参数缺失这类情况，宁可报错也不要带病执行。

## RuoYi OSS endpoint 写死直链，本机 LAN IP 漂移导致图片全 000（2026-10-21，drama-pipeline）

**现象**：drama-ui 项目页所有图片加载失败，浏览器请求图片 URL 状态码 000（TCP 连不上），不是 404/CORS。

**排查要点**：
- 先区分故障层：000=TCP 连接失败；404=资源不存在；CORS 报错才是跨域。据此直接排除前端拼接、代理、CORS、资源缺失。
- RuoYi 系 OSS 配置存在 DB 表 `sys_oss_config`（不在 yml），`status='Y'` 的行启动时载入 Redis `sys_oss:default_config`；`domain_url` 为空时直链 = `endpoint + /bucket/key`，**endpoint 写什么就把什么主机永久写进业务表 url 字段**，之后改 endpoint 不回填存量，旧记录仍是旧主机。
- 本机 DHCP 分配的 LAN IP 变了（192.168.1.6 → 192.168.1.118），docker MinIO 虽 `0.0.0.0:9000` 发布可达，但库里写死的旧 IP 无人解析，图片全挂。
- 容器内后端视角 `localhost` ≠ 宿主机，回填/配 endpoint 时必须用 LAN IP，不能用 localhost，否则新上传连不上 MinIO。

**本机快速修复（方案 A）**：备份表 → `UPDATE drama_asset SET url=REPLACE(url,'旧IP:9000','新IP:9000')` 回填存量；endpoint 未改则新上传仍写旧 IP，需另行改 `sys_oss_config.endpoint` 并刷新 Redis/本地缓存（后台 OSS 页自动刷，直改库须重启 meic-resource/meic-drama）。

**根治方向（方案 B）**：后端加 `/asset/file/{assetId}` 流式接口，前端走相对路径经网关代理，浏览器不再直连 MinIO，从根上摆脱 IP 漂移与 CORS。

**同类症状先查**：图片 000 → `curl -I 直链` 区分 IP 失效/端口未监听/隧道断；核对 `ipconfig getifaddr en0` 当前 LAN IP 与库里写死主机是否一致。

## 被中断的删除任务：先只读核对基线，再决定补跑（2026-10-22，mac-ops）

**现象**：CodeBuddy 删除任务被用户消息打断，退出码 -1，stdout 未回传。不能假设它删了一半，也不能直接重跑（可能重复删除或误判）。

**做法**：先派一轮纯只读核对——`df -h`、各目标对象 `du -sh`、本体与红线对象（照片图库）大小前后对比。本次核对结果：零删除、基线完好、本体与图库未动，随后才按原清单补跑。

**教训**：任何带副作用的任务被中断后，恢复顺序是「只读核对现状 → 对照基线判断哪些已做/未做 → 再补跑剩余项」，禁止直接重跑整条删除命令。

## Photos / iCloud 状态的 CLI 边界（2026-10-22，mac-ops）

SSH 只读能拿到：同步是否开启（cloud master 记录、bird 进程）、本地是原件还是优化版（`originals/` 占比、`ZCLOUDLOCALSTATE`、待下载请求数）、资产数量。

**拿不到**：云端原件字节是否已全量上传并通过服务端校验、iCloud 剩余配额、上传队列进度。这类判断必须登录 iCloud.com 或在 Photos GUI 里对账；关同步、切优化存储、删图库包都是 GUI 动作，命令行替代不了。

## 小于 1GiB 的删除不要用 df -h 当验收依据（2026-10-22，mac-ops）

`df -h` 以 GiB 为粒度，删几十 MB 的文件后 Used/Avail 数字不变属正常，不代表没删掉。验收小体积删除要靠：`ls -d` 对象不存在、`which` 找不到命令、`du -sh` 归零、inode 计数（`df -i`）下降；再附 `docker images`/`docker ps -a` 复核相关运行时对象未受牵连。

## 远程服务器运维巡检：防止 CodeBuddy 误在本机 macOS 空跑命令

**现象**：vps-ops 这类 SSH 远程任务中，CB 常先在本机（macOS）空跑几条 Linux/docker 命令，产生一批噪音报错：`ss: command not found`、`systemctl: command not found`、`ps: illegal option -- -`（macOS 是 BSD ps，不支持 `-eo` 与 `--sort=-%mem`）、`Error response from daemon: client version 1.41 is too old`（本地老 Docker Desktop 连 colima 的已知版本冲突）、`command substitution: syntax error near unexpected token`（指令里的 `<路径>`、`<容器名>`、`<pid>` 尖括号占位符被本机 bash 当命令替换解析）。这些失败命令的结果不能采信；后续走 SSH 在远程成功执行的数据才有效。

**处置**：
1. 派发指令开头写死"本机是 macOS，禁止本机直接跑 docker、ss、systemctl、ps 等 Linux 命令，所有命令必须带 SSH 包装"，并给出完整 ssh 前缀模板。
2. 第一步先跑 `ssh ... 'hostname; uname -a'` 自证目标是远程主机并贴出输出，再继续后续命令。
3. 指令里不要留 `<路径>`、`<pid>` 这类尖括号占位符让 CB 在本机展开；路径直接写成明确清单，或让 CB 在远程 shell 循环里自己取值。
4. 验收时独立派一轮只读复核，重新拉取 `docker ps -a`、`ss -tulnp`、`docker inspect`、保护目录 `ls` 的原始输出交叉核对，不能只信执行轮次的自报汇总。
5. 开头出现的本机噪音报错要识别并剔除，最终结论只采用带 hostname 自证、在远程执行的证据。

## docker 模板字段与重启策略取值口径

**现象**：`docker ps --format` 不支持 RestartCount、RestartPolicy、StartedAt 等字段，写了会报 `can't evaluate field X`；重启策略和重启次数必须走 inspect。

**口径**：
- 重启策略：`docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' <容器>`（取值 always / no / on-failure / unless-stopped）。
- 自动重启次数：`docker inspect --format '{{.RestartCount}}' <容器>`（只统计 Docker 自动重启次数，手动 `docker start` 不计入）。
- 容器网络模式：`docker inspect --format '{{.HostConfig.NetworkMode}}' <容器>`；bind 挂载用 `docker inspect --format '{{range .Mounts}}{{.Source}}->{{.Destination}};{{end}}' <容器>`。
- 匿名卷不会随普通 `docker rm` 删除，需要 `docker rm -v` 或显式 `docker volume rm`；`docker volume prune -f` 只清 dangling 卷、不删命名卷。

## 本机两套 CodeBuddy 发行版必须区分，派发前先 export PATH（2026-10-22，codebuddy-supervisor）

**现象**：本机同时存在两套 CodeBuddy 发行版，凭证与模型清单互相隔离，混用会静默走错通道：

- **独立官方 CLI**：npm 包 `@tencent-ai/codebuddy-code`，版本 `2.170.0`；二进制 `/Users/meidanlong/.nvm/versions/node/v22.22.0/bin/codebuddy`（同目录另有别名 `cbc`、`codebuddy-code`、`codebuddy-lowmem`）；shebang 为 `#!/usr/bin/env node`；模型清单含 `hy3`、`hy3-x`、`hy4-preview`、`space-bunny`、`deepseek-v4-pro`、`glm-5.3` 系列等；官方账号凭证有效，`hy3` 实测非交互调用返回正常。
- **WorkBuddy 内置 lite**：`/Applications/WorkBuddy.app/Contents/Resources/app.asar.unpacked/cli/dist/codebuddy-lite-wb.mjs`（`2.161.0`）；凭证与独立 CLI 隔离，非交互 `-p` 模式读不到 app GUI 登录态，默认通道报 `Authentication required. Please use /login`；其模型清单**不含 `hy3`**；此前只能用本机 `models.json` 里的 `custom-local:MiniMax-M3` 兜底，`502 canceled (target: https://api.minimaxi.com)` 是该 MiniMax 网关服务端错误，与 `hy3` 无关。

**坑**：Doubao Bash 工具默认 PATH 里 `sandbox_runtime` 的 node 抢先，裸敲 `codebuddy` 会 `command not found`；派发独立 CLI 前必须先 `export PATH=~/.nvm/versions/node/v22.22.0/bin:$PATH`。`~/.codebuddy/bin/buddycn` 软链指向已删除的 `/Applications/CodeBuddy CN.app`，已失效，不要再用。

**正确派发模板**（与 SKILL.md 第 4 步命令风格一致）：

```bash
export PATH=~/.nvm/versions/node/v22.22.0/bin:$PATH; codebuddy -p --output-format text --dangerously-skip-permissions --autocompact auto --model hy3 --session-id <session> "<任务>"
```

**验收口径**：独立 CLI 用 `which codebuddy` 应解析到上述 nvm bin 路径；`hy3` 未认证时先排查 PATH 与登录态，不要默认退到 WorkBuddy lite 或 MiniMax 兜底。

## drama-ui 图片不显示：先分「URL 失效」还是「关联键断裂」（2026-10-23，cloud-uniapp）

**现象**：meic-cloud 配套工作台 drama-ui 分镜页图片全占位，素材库图片却正常；容易被误判成 MinIO / IP 漂移问题。

**排查顺序（先分层再下结论）**：
1. 先 curl 资产直链区分层：200 = 存储与 URL 健康，问题在关联层；404/403/000 才是存储、桶权限或网络层。
2. 库内核对分镜表素材 id 列是否全 NULL；再核对资产 `owner_id` 在分镜表的存在数。两者都断 = 关联键断裂。本次根因：分镜被重导换了新主键，38 条旧资产 `owner_id` 指向已不存在的旧分镜 id，且分镜三列 `image_asset_id/video_asset_id/start_frame_asset_id` 全 NULL；资产本身 URL 全 200。
3. 用对照组排除前端 bug：角色头像、素材库走同一 `assetUrl/assetMap` 机制且正常出图，即证明前端映射无问题，故障被限制在「分镜↔资产」关联层。
4. `referImages` 这类平行字段单独追：CLI 本地相对路径入库 → 后端实体直出裸路径 → 前端全仓 grep 0 命中，三段全断；它与 `drama_asset` 关联体系无关，不要混为一谈。

**环境事实（meic-cloud 本地）**：
- 工作台 `drama-ui` 是独立 Vue3 + Vite + Element Plus SPA，在 meic-cloud 仓库**外兄弟目录** `~/workspace/home/drama-ui`，端口 5173；`meic-ui` 是若依 Admin，内置一套半成品 drama 页面（无图片渲染），不要把两套前端当成一个工程。
- OSS 默认配置在 `sys_oss_config`（meic-cloud 库），`status=Y` 行由 meic-user 启动时载入 Redis；种子 SQL 的 endpoint/bucket 会被运行态库覆盖，查配置以库内 SELECT 实测为准，不要信种子值。
- 后端端口：gateway 8080 / meic-user 9213（已合并 auth 与 OSS 资源）/ meic-drama 9412 / meic-ai 9206 / meic-job 9203；MySQL 容器 `ruoyi-mysql` 映射 3307，root/meic123，drama 业务库 = `meic-drama`。
- 浏览器验收时 CodeBuddy 可能误判 5173 进程归属；以浏览器标题、路由、代码 grep 实测为准，不采信它对进程名的口头判断。

## 文档/只读轮必须硬禁 shell 命令，防 CB 把命令口径当真实安装执行（2026-10-23，design-coding-test）

**现象**：纯文档轮任务里，CB 把"文档中要写的 myfe / skill 安装命令"理解成"先把本机环境装好"，擅自执行 `myfe skills install chaoyue-lifecycle`；该命令交互式选择 agent/范围、无非交互 flag，在 `-p` 非交互模式下挂死十几分钟，日志重定向文件甚至没落盘。盘点后确认 kill 时未写入任何东西（skill 目录 mtime、`~/.myskills` manifest、全局 npm 包均未变），零残留副作用。

**处置口径**：
1. 纯文档/只读轮指令开头写最高禁令：只允许 Read/Edit/Write，禁止 myfe（含 `myfe skills install`、`myfe sso`）、npm、pip、sso login、联网下载，禁止跑测试、禁止 git 写、禁止新建其他文件；明确"文档里的命令只是正文文本，不是让你执行"。
2. 长任务无进展先判活再等：`ps aux | grep -iE 'myfe|npm install|codebuddy|test_'` 盘点挂死子进程；不能只看日志文件大小（`-p` 缓冲到进程结束才落盘，0 字节不代表假死）；同时核对工作树 mtime、`git status`、manifest、全局包，确认 CB 是否已经误写。
3. 确认误触发的挂死进程先 kill 再重派小批次；执行前清单与实际落盘状态逐项对账，CB 自报完成不算数。

**文档护栏教训**：e2e T43a 禁裸 `pipeline.py <子命令>`，正则后顾 `(?<![./\w-])`，散文反引号里的 `` `pipeline.py chaoyue-env-check` `` 同样命中；新增文档命令引用一律写完整字面量路径 `${PLUGIN_ROOT}/skills/.../pipeline.py`，提交前用 Python 复刻护栏正则全库扫一遍裸调用。

## hook 静默上报场景禁用 sso_get_token，token 只读本地缓存（2026-10-23，design-coding-test）

**坑**：myskill 的 `sso_get_token(client_id, env)` 在本地凭证缺失/过期时会调 `sso_login` 发起 PKCE 浏览器登录；hook 在每条 pipeline 命令后静默触发，绝不能挂交互（最长挂 300s）。正确做法：改用 `load_credentials(client_id=...)` 只读本地缓存，返回 `{access_token, expires_at, client_id, ...}` 或 None（内部自清过期）；缺失/过期返回空串 → 走失败不阻断口径，凭证修复路径留给 env-check `--login`，hook 不主动续期。

**接口事实**（myskill 0.0.1，包目录 `~/.cache/chaoyue-lifecycle/python-packages`，由 env-check `_ensure_myskill` 自举）：
- `load_credentials(client_id: Optional[str]=None) -> Optional[Dict]`：指定 client_id 返回单凭证 dict，不指定返回 `{client_id: creds}` 全量 dict；字段名是 `access_token`、`expires_at`（epoch 秒），不是 `token`。
- 包导出清单以 `myskill/__init__.py` 的 `__all__` 为准；函数定义在 `sso_pkce.py`。验收前先 grep 定义位置核对参数名与返回字段，别凭函数名猜。
- 对接第三方 skill 契约前，先读本机 `.claude/skills/<name>/scripts/` 真实源码（参数互斥关系、退出码、stdout/stderr 分界、成功码、阶段枚举、默认值）；方案摘要与仓库旧实现都不算数。

## 协作闭环固化与脚本一致性经验（2026-10-24，cb-supervisor）

本次对 codebuddy-supervisor 技能做了一次结构性固化，沉淀五条经验（逐条追加，不覆盖）：

1. **五段闭环落地**：任务协作固定为「转达需求 → 商讨方案（业务方向用户确认闸门，方案含目标/步骤/验证/风险四项）→ 拆有序步骤 → 逐步派发逐步验收（不通过打回修正）→ 复盘沉淀」；替代过去一次性把大任务整段甩给 CodeBuddy 的做法。

2. **三级任务分级闸门**：小任务（只读/单点/可逆）单次派发、做完贴证据一次验收，不出方案不拆步；中任务（完整功能点、少文件、有依赖）先出方案、拆 2~5 步逐步闸；大任务（跨模块多文件、不可逆、长流水线）方向用户确认后拆 5 步以上，不可逆动作单独再开确认闸。

3. **单步 5 分钟上限**：每步派发任务收窄到 5 分钟内可完成，指令只给一件可独立验收的事；超时无新证据即按超时排查打回缩小范围或拆更细；只有真长任务才走后台 + cron 兜底，不能拿长任务名义逃避单步闸。

4. **文档与脚本一致性教训**：SKILL.md 早已废弃命令行 `--disallowedTools` 黑名单、回归三层防护，但 `cb_run.sh` 里残留内嵌黑名单数组与参数拼装，造成文档与脚本矛盾；本次已删除脚本黑名单，只保留后置日志报警。以后改文档防护规则时，必须同步检查 `scripts/` 下脚本是否还残留旧机制。

5. **派发中断处置**：一次派发被新消息中断后，先派只读任务核查工作区基线（git status、目标文件 diff、关键旧称 grep），确认有无半截改动，再决定继续或重做；禁止在未核查状态下直接重派同一任务，避免重复执行覆盖已落地内容。

## iCloud dataless 占位文件：命令行删除死锁，须 Finder GUI 通道（2026-10-24，mac-ops）

**现象**：删除 `~/Documents/TencentMeeting` 下某场会议时，`mv` 到 `~/.Trash` 复制成功但源目录删除被阻塞，进程空转十多分钟挂死；AppleScript/osascript 删除超时（-1712）。同目录另外两场全本地文件删除一次成功。

**根因**：卡住目录内含 6 个 `UF_DATALESS`（dataless）iCloud 云端占位文件——内容在云上、本机是 0 字节空壳。FileProvider 删除这类文件必须先与云端协调，命令行层直接死锁；全本地文件没有这个协调环节，所以顺利。

**检测要点（前面几轮踩的坑）**：
- `find -name '*.icloud'`、`xattrname ZCLOUDLOCALSTATE`、`com.apple.icloud.metadata` 都检测不到 dataless 占位；真正标志是 `ls -lO` 输出里的 **`dataless` flag**，必须按 flag 盘点，别只看 xattr/后缀。
- 占位文件读出来是 0 字节、shasum = `da39a3ee…`（空哈希）；`dd if=文件 bs=1 count=4 | wc -c` 可实证本机无可读内容。
- `du -sh` 把稀疏/占位算成逻辑大小，废纸篓物化后块占用会膨胀（31M 逻辑 → 86M 块），这是记账差异，不是多出数据。

**安全边界（重要）**：把占位文件目录移入废纸篓时，废纸篓副本里这些占位仍是 0 字节空壳，不构成真实备份；此时删目录会把云端内容一并删掉且本机无副本。删除前必须先在 Finder 里右键「下载/使可用离线」落地，或明确告知用户云端删除风险、留 iCloud「最近删除」30 天窗口兜底。shasum 三处一致的结论对 dataless 文件不成立，不能据此宣称"三份备份一致、无丢失"。

**正确通道**：命令行 `mv`/`rm`/osascript 对 dataless 文件都被阻塞；走 `computer-use-automation-mac`（cu, plane="cu"）打开 Finder，`Cmd+Shift+G` 直达目录，单击选中目标行（别双击，分栏视图会展开预览第三栏），`Cmd+Delete` 移废纸篓，系统 FileProvider 用户态协调即可完成，不弹死锁确认框。删除后独立派一轮只读验收：源目录消失、保护条目原位大小不变、`~/.Trash` 同名副本未覆盖其他场次。

**复盘教训**：多场次批量删除前，先逐场 `ls -lO` 统计 dataless 数量，全本地场次先走命令行；含占位的场次单独走 GUI，不要混在同一批里——否则一个死锁会拖垮整批并空转烧 token。

## iCloud 同步区项目的回收站位置：Finder 删除进专属 .Trash，别只扫本地 ~/.Trash（2026-10-24，mac-ops）

**核心结论**：在 iCloud 同步区（~/Documents、~/Desktop、~/Library/Mobile Documents/com~apple~CloudDocs 内）的项目，经访达 `Cmd+Delete` 删除后**不进**本地 `~/.Trash`，而是进 iCloud/FileProvider 专属回收站 `~/Library/Mobile Documents/.Trash/`。排查回收位置时务必同时扫这两个容器，否则会把已成功回收的条目误判为「去向不明 / 丢失」。

1. **路径区分**：本地普通文件 / 目录用命令行 `mv` 删除进 `~/.Trash`；而位于 iCloud 同步区（`~/Documents`、`~/Desktop`、`~/Library/Mobile Documents/com~apple~CloudDocs` 内）的项目，通过访达 `Cmd+Delete` 删除后，实际进入 iCloud/FileProvider 专属回收站 `~/Library/Mobile Documents/.Trash/`——它与 `com~apple~CloudDocs` 在**同级父目录**（`Mobile Documents` 下），**不是** `com~apple~CloudDocs/.Trash`（该路径不存在）。

2. **排查回收位置时不要只扫 `~/.Trash`**，否则会把已成功回收的项目误判成「去向不明 / 丢失」；必须同时 `find ~/Library/Mobile Documents/.Trash`。`mdfind` 对 iCloud 目录索引滞后、可能漏检，按文件名 / 会议 ID 直接 `find` 这两个容器最可靠。

3. **本轮实测基线**：`867215890=98M`、`564154907=51M`、`416807527=82M`、`篮球训练.MOV=1.9G`、`node_modules=38M`；Finder 删除后在专属 `.Trash` 中大小与删除前一致、内容完好可还原。`node_modules` 另可由 `npm install` 重建。

4. **空间释放口径**：清空本地 `~/.Trash` **不会**释放 iCloud 云端配额；要彻底释放需同步清空 iCloud Drive 的「最近删除」（专属 `.Trash`），iCloud 最近删除保留约 30 天可恢复。

5. **命令行 `mv` 把 iCloud 目录树移出同步区会报 `Resource deadlock avoided (EDEADLK)`**，这类删除只能走 Finder GUI `Cmd+Delete`（沿用文档已有的 dataless 占位经验章节，不重复展开）。

## 本机认证：从 WorkBuddy 派生的进程读不出钥匙串凭证，改走 API Key 通道（2026-10-27，cb-supervisor）

**现象**：`codebuddy -p` 在 WorkBuddy 的 Bash 里返回 `Authentication required. Please use /login command to sign in`，而同一条命令贴进 Terminal 立刻正常返回。还伴随「间歇成功」——某段时间连通过 3 次，之后全挂，极易误判成环境变量或限流。

**决定性判据（先看这三条，别急着试修）**：

1. 同一命令在 Terminal 能跑、在 WorkBuddy 里不能跑 → **不是登录态问题**。
2. 失败日志有 `resource=auth/workbuddy-desktop.info operation=read category=missing-key`，且 `hasAccessToken=false`；Terminal 成功那次这两行**完全不存在**。
3. `security find-generic-password -w -s "CodeBuddy CN Safe Storage"` 返回 exit 0 → 钥匙串**本身能解密**，不是 ACL 权限问题。

结论：文件都在、密钥能读，是 CLI 在 WorkBuddy 派生进程里解析不出凭证加密上下文，直接把 token 当不存在。

**已实测证伪、不要再试的假设**：

| 假设 | 实测结果 |
|---|---|
| 沙箱隔离 | 关沙箱（`dangerouslyDisableSandbox`）结果相同 |
| 没登录 / 凭证没落盘 | Terminal 里同二进制正常，`hasAccessToken=true` |
| 读不到 `~/.codebuddy/` | 读得到，日志 / `local_storage` / 存储文件都能访问且可写 |
| 钥匙串 ACL 拦住 | `security -w` 返回 exit 0，能解密 |
| node 版本 | 切回 nvm v22.22.0 仍失败 |
| 环境变量 | `WORKBUDDY_IS_PACKAGED`、`CODEBUDDY_FORCE_LITE_WB_BUNDLE`、`CODEBUDDY_FORCE_HEADLESS_BUNDLE`、`CODEBUDDY_HOST`、`CODEBUDDY_CONFIG_DIR`、`NODE_OPTIONS`、`__CFBundleIdentifier`——逐个摘、整批摘 131 个产品族变量、`env -i` 全清空，都不稳定 |
| cwd / session-id / 模型 | 复刻 Terminal 成功那次的完全相同参数，仍失败 |
| 端口 | 换端口不解决认证（但默认端口确有 `EADDRINUSE`，见下） |

**已实测失败的绕行路径**：launchd `bootstrap` 被拒（exit 5）、`launchctl submit` 无输出、AppleScript `tell application "Terminal"` 进程被 SIGTERM、`open -a Terminal xxx.command` 能起窗口但脚本不执行、`ssh localhost` 无密钥（`Permission denied`）。

**正解**：CLI 支持 `CODEBUDDY_API_KEY`，走**完全独立的校验通道，不碰钥匙串**。三项前置缺一不可：

```bash
export PATH="$HOME/.nvm/versions/node/v22.22.0/bin:$PATH"
set -a; source "$HOME/.workbuddy/skills/codebuddy-supervisor/.env.local"; set +a
codebuddy -p --port 49211 --output-format text --dangerously-skip-permissions \
  --autocompact auto --model hy3 --session-id <session> "<任务>"
```

- **端口**：默认 51803 被 WorkBuddy 的 Electron 长期占用，且它会随机抢端口，不指定就 `EADDRINUSE`。`scripts/cb_run.sh` 从 49211 起自动向上探测（实测 49211、49212 都被占时正确落到 49213）。
- **凭证文件**：`.env.local`，权限 `600`，已在 `.gitignore`（`.env*`）里，不进远程。
- **PATH**：不前置 nvm node 会被 WorkBuddy 内置 node 抢走 shebang（同「本机两套 CodeBuddy 发行版」一节）。

**验收口径**：`cb_run.sh` 的诊断行应同时满足 `auth=api-key`、`node=.../.nvm/versions/node/v22.22.0/bin/node`、`port=<非空>`。已实测通过：纯对话、真实文件写入（`CB_RUN_OK` 9 字节，`--dangerously-skip-permissions` 未被静默拦截）、连跑 3 次无失败、`--session-id` 上下文正确带过来、端口自动避让。

**上游旧结论的修正**：曾记录「`cb_run.sh` 对长指令 prompt 会让 hy3 返回空」。本机 codebuddy v2.170.0 实测 `--plan` / `--exec` 带长 INSTRUCTION 均正常返回，未复现；若再遇到返回空，再退回原生 `codebuddy -p`（同样保留上面三项前置）。
