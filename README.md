# Doubao Supervises CodeBuddy

让豆包作为监督者指挥 CodeBuddy CLI 执行编码任务，节省豆包 token。

## 角色分工

| 角色 | 职责 |
|---|---|
| 豆包（监督者） | 接需求 / 问清楚 / 审方案 / 验结果 |
| CodeBuddy（执行者） | 写代码 / 改文件 / 跑命令 / 跑测试 |

豆包负责"想清楚"和"把关"，CodeBuddy 负责"动手做"。豆包只做需求澄清、方案评审和结果验收，把实际的读写文件、执行命令、跑测试等重活交给 CodeBuddy，从而把昂贵的豆包 token 省下来。

## 核心协作原则

- **三层协作（你 → 我 → CodeBuddy）**：你提需求与拍板，豆包只做澄清 / 审方案 / 验收，CodeBuddy 负责动手。
- **所有任务先出方案再执行**：不论只读还是有副作用，都先让 CodeBuddy 给出方案，确认后再动手。
- **删除 / 卸载 / 改配置走三步审核法**：列清单 → 交你审核 → 确认后执行，不可逆操作不绕过。
- **经验反馈闭环**：每次任务后把踩坑与有效做法沉淀进 `references/lessons-learned.md`，下次执行前先查。
- **执行超期主动排查根因**：CodeBuddy 长时间无进展时，豆包主动诊断（空转 / 卡凭证 / 超能力 / 沙箱网络）并修正再继续，不干等。

## 模型配置

CodeBuddy CLI 支持灵活配置底层模型，按成本与场景选择。三档制：

- **默认（只读轻活）`hy3`**：免费（x0.00，限时免费，每日有调用上限）。查状态、读日志、看 git log 这类简单只读任务，默认就用它。
- **编码干活 `space-bunny`**：x0.08，极快、强制推理、1M 上下文、支持看图。写代码、改文件、跑测试这类正经编码任务，切到它。
- **兜底 `glm-5.3-flash`**：x0.06。只有 `hy3` 撞到每日限额、不可用时，才切过来顶上。
- **不用旗舰模型**（`deepseek-v4-pro` / `kimi-k3-2` / `glm-5.3`），除非用户显式点名。

其他接入方式：

- **本地模型**
  - Ollama / vLLM：本地部署、零 API 成本，适合隐私敏感或离线场景。
- **第三方 API**
  - MiniMax / 智谱（GLM）/ Moonshot（Kimi）：通过自定义端点接入，按各家官方 API 计费。

详细档位与倍率见 [`references/models.md`](references/models.md)。

## 快速开始

1. **安装 CodeBuddy**：安装 CodeBuddy CLI 并完成登录。
2. **放置技能**：把 `SKILL.md`（连同 `scripts/`、`references/`）放到豆包的 skills 目录。
3. **跟豆包说任务**：用自然语言把要做的事告诉豆包。
4. **豆包派给 CodeBuddy**：豆包澄清需求、拆解任务后，通过 CodeBuddy CLI 派发执行。
5. **豆包验收**：CodeBuddy 完成后，豆包检查改动与测试结果，确认是否达标。

## 目录结构

```
doubao-supervises-codebuddy/
├── SKILL.md              # 豆包侧技能定义（含三层协作 / 三步审核法 / 经验闭环）
├── README.md             # 本文件
├── scripts/
│   ├── cb_run.sh         # 调用 CodeBuddy CLI 的封装脚本
│   └── fetch_pricing.sh  # 抓取官方定价页、抽取价格关键词
└── references/
    ├── models.md         # 模型档位与成本参考（不写死价格）
    └── lessons-learned.md# 踩坑与验证过的做法（持续沉淀）
```

## License

MIT
