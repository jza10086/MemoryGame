# M01 方向密码　A　依赖 G02

来源：2026-11-07 架构审查及其最后实施记录。整理日期：2026-11-14。下列待办保留原状态；实施前核对本包源码与工作区，不以历史检查代替本次验收。

[共享 G01–G03 任务](../../../protocols/godot_party_default_protocol/doc/godot_party_default_protocol_development.md) · [包说明](gp_direction_code_guide.md)


包：`gp_direction_code`。定位：[direction_password.gd](../direction_password.gd) 的 `_ready()`、`_unhandled_key_input()`、`activate_primary()`、`enter_direction()`。

- [x] 从父节点探测改为显式注入；正式方向、撤销、确认动作使用 PartyInput，按钮和键盘共用阶段/菜单门控。当前只有本地键码匹配，没有正式输入上下文。
- [ ] 保留两排八个答案槽和六行成绩，补齐仍散落的阶段/反馈文字模板；预览继续使用已有 DEFAULT_TEXT。
- [ ] 规则、六轮流程和计分留在现有 `direction_password_rules.gd`/玩法中，不为了 312 行脚本再拆控制器。

验证：六轮、撤销/超时、菜单遮挡和唯一提交；改输入后检查自定义绑定。无需重建静态题面。

## 人工验收待办

保留自 2026-11-05 场景审查，后续记录未明确关闭的人工事项：大厅完整流程及人工操作待验收。
