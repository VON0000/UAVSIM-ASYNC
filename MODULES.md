# 项目模块说明

本文档描述当前异步多无人机仿真器骨架中每个模块的职责、主要 API、运行时数据流、解耦边界和后续扩展点。文档以当前代码为准。

## 总体分层

项目是一个 OCaml 事件驱动异步多无人机仿真器骨架，不使用 dune，通过 `Makefile + ocamlfind ocamlopt` 构建。

代码按职责分成五层：

1. 基础类型与工具：`Vec3`、`Random_utils`、`Types`、`Config`
2. 可替换模块接口：`Airspace_model`、`Conflict_model`、`Motion_model`、`Planner_adapter`、`Evaluation_model`
3. 模式实现：`Layered_*` 与 `Continuous3d_*`
4. 通用仿真基础设施：`World`、`Comm_model`、`Event_queue`、`Neighbor_cache`、`Planner_scheduler`、`Logger`、`Scenario`
5. 可执行程序与外围文件：`Run_async`、`Run_batch`、`Export_rviz_log`、`Makefile`、scenarios、scripts

最重要的工程边界：

- planner 只能看到 `Types.self_state`、`Types.neighbor_observation list` 和上一条 `Types.planner_command option`。
- planner adapter 的接口里没有 `Types.uav_state array`，因此不能直接读 world 真值快照。
- mode 相关行为通过 `Mode_registry.mode_bundle` 中的 first-class modules 分发。
- `Scenario`、`Logger`、`World` 等通用模块不通过字符串分支理解具体 mode。
- `Evaluation_model.on_step` 不自己判断冲突，而是由主循环传入当前 mode 的 `pair_distance` 和 `is_conflict`。

## 基础类型与工具模块

### `src/vec3.ml`

`Vec3` 是三维向量基础模块。

职责：

- 定义三维向量类型 `t = { x : float; y : float; z : float }`
- 提供显式命名的向量运算
- 为状态、运动模型、冲突检测、通信外推、日志指标提供统一向量表示

主要 API：

- `zero`：零向量
- `make x y z`：构造向量
- `add a b`：向量加法
- `sub a b`：向量减法
- `scale k v`：标量乘向量
- `dot a b`：点积
- `norm_sq v`：模长平方
- `norm v`：3D 模长
- `norm_xy v`：只看 x/y 的水平模长
- `distance a b`：3D 欧氏距离
- `distance_xy a b`：水平距离
- `normalize v`：单位化；接近零向量时返回 `zero`
- `lerp a b t`：线性插值

设计说明：

- 当前版本没有 `+|`、`-|`、`*|` 这类运算符别名，项目统一使用 `add/sub/scale`。
- layered 模式也使用 `Vec3.t` 存 world 真值位置；其中 `z` 表示当前层高度或换层过程中的中间高度。

### `src/random_utils.ml`

`Random_utils` 是仿真随机性的唯一入口。

职责：

- 用 `Random.State.t` 封装带 seed 的随机数状态
- 保证通信 delay、丢包、planner jitter 等随机过程可复现
- 避免业务模块直接调用全局 `Random.float`

主要 API：

- `type t = Random.State.t`
- `make seed`：创建随机状态
- `uniform rng low high`：区间 `[low, high)` 上的均匀采样
- `uniform_01 rng`：区间 `[0, 1)` 上的均匀采样
- `bernoulli rng p`：概率为 `p` 的布尔采样
- `normal rng mean std`：Box-Muller 正态采样
- `int_below rng n`：整数采样

当前使用位置：

- `Comm_model` 用于通信延迟和丢包
- `Planner_scheduler` 用于初始错峰和 planner 周期 jitter

### `src/types.ml`

`Types` 是全项目共享数据结构模块。

职责：

- 定义 world、comm、planner、logger、evaluator 之间传递的数据结构
- 统一表达 layered 和 continuous3d 两类 mode 的状态
- 明确真值状态与 planner 可见状态的边界

主要类型：

- `v2`：二维向量；为 layered 算法 adapter 保留
- `uav_type_params`：无人机类型参数，包括速度、加速度、jerk、yaw、爬升率、半径等
- `transition_state`：layered 换层状态机，取值为 `LevelStable` 或 `LevelChanging _`
- `layered_state`：layered 专属状态，包含 `current_level` 和 `transition`
- `mode_state`：模式状态，取值为 `Layered of layered_state` 或 `Continuous3D`
- `uav_state`：world 内部真值状态，包含 `active/reached/stalled`
- `self_state`：planner 可见的自身状态，不包含 world 管理字段
- `neighbor_msg`：通信发送时刻的邻机快照，包含 `sent_time` 和 `receive_time`
- `neighbor_observation`：`Neighbor_cache` 外推后的 planner 可见邻机观察
- `planner_command`：planner 输出命令
- `sim_config`：仿真配置

关键边界：

- `uav_state` 是 world 真值；planner adapter 签名拿不到它的数组。
- `self_state` 是从 `uav_state` 裁剪出来的 planner 输入。
- `neighbor_msg` 是通信消息，不等于实时真值。
- `neighbor_observation` 是根据消息和当前时间一阶外推后的估计状态。
- `Types` 当前只定义类型，不实现 mode 行为函数；例如日志层字段由 `Airspace_model.log_layer_fields` 负责。

### `src/config.ml`

`Config` 提供默认仿真配置和日志路径派生函数。

职责：

- 定义 `default_config`
- 根据 `--out-dir` 生成 `state.csv`、`events.csv`、`summary.csv` 路径

主要 API：

- `default_config : Types.sim_config`
- `with_output_dir cfg out_dir`

当前默认值要点：

- `world_dt = 0.05`
- `max_time = 20.0`
- `planner_period = 0.5`
- `planner_jitter = 0.05`
- `broadcast_rate = 5.0`
- `packet_loss = 0.0`
- `comm_range = infinity`
- `stale_timeout = 2.0`
- `layer_spacing = 5.0`
- `layer_count = 5`
- `climb_steps = 20`
- `safety_radius = 1.5`

## 可替换模块接口

这些模块只定义 `module type`。具体实现由 `Layered_*` 和 `Continuous3d_*` 提供，并在 `Mode_registry` 中打包。

### `src/airspace_model.ml`

定义 `AIRSPACE_MODEL`。

职责：

- 抽象空域结构
- 将“占用层、层高转换、初始 mode_state、日志层字段”等 mode-aware 逻辑从通用模块中移出

接口：

- `name`
- `occupied_layers : Types.uav_state -> int list`
- `z_of_level : Types.sim_config -> int -> float`
- `level_of_z : Types.sim_config -> float -> int`
- `initial_level_of_goal : Types.sim_config -> goal:Vec3.t -> start:Vec3.t -> int`
- `initial_mode_state : Types.sim_config -> initial_level:int -> Types.mode_state`
- `log_layer_fields : Types.uav_state -> int * int * int * int`

使用位置：

- `Scenario.to_initial_states` 通过 `initial_mode_state` 构造初始 `mode_state`
- `Logger.write_state_row` 通过 `log_layer_fields` 写 state CSV 的层字段
- layered conflict 会调用 layered airspace 的占用层逻辑

### `src/conflict_model.ml`

定义 `CONFLICT_MODEL`。

职责：

- 抽象真值层面的冲突判定
- 统一提供 pair 距离，避免 evaluator 重复实现距离/冲突逻辑

接口：

- `name`
- `is_conflict ~cfg a b`
- `pair_distance ~cfg a b`

使用位置：

- `Run_async` 从当前 bundle 拆出 conflict 模块
- 主循环将 `pair_distance` 和 `is_conflict` partial apply 后传给 `Evaluation_model.on_step`

### `src/motion_model.ml`

定义 `MOTION_MODEL`。

职责：

- 抽象 mode-specific 状态积分
- 使用 planner command 推进 `uav_state`
- 判断是否到达目标

接口：

- `name`
- `step ~cfg ~dt ~cmd state`
- `reached ~cfg state`

使用位置：

- `World.step` 通过 `bundle.motion` 调用当前 mode 的 motion 实现。

### `src/planner_adapter.ml`

定义 `PLANNER_ADAPTER`。

职责：

- 抽象 planner 接入点
- 保证 planner 只使用受控输入

接口：

- `name`
- `plan_once ~cfg ~now ~self ~neighbors ~last_command`

关键约束：

- `plan_once` 不接收 world 真值数组。
- 后续 ORCA/Maneuver 真实算法应在 adapter 内把 `self_state` 和 `neighbor_observation list` 转换为算法内部输入。

### `src/evaluation_model.ml`

定义 `EVALUATION_MODEL`。

职责：

- 抽象指标累计逻辑
- 支持不同 mode 输出不同 summary 字段
- 通过参数接收当前 mode 的冲突/距离函数

接口：

- `type accumulator`
- `empty cfg`
- `on_planning acc ~cmd`
- `on_step acc ~now ~states ~pair_distance ~is_conflict`
- `on_comm_event acc event`
- `summary_row acc ~cfg`

设计说明：

- `on_step` 仍然读取真值状态数组，但它只用于评估，不参与 planner 决策。
- `on_step` 不直接依赖 `Layered_conflict` 或 `Continuous3d_conflict`。

## Mode Registry

### `src/mode_registry.ml`

`Mode_registry` 将某个运行模式需要的五类模块打包成一个 bundle。

职责：

- 定义 `mode_bundle`
- 注册 `layered`
- 注册 `continuous3d`
- 通过 `by_name` 支持 CLI 运行时选择 mode

核心类型：

```ocaml
type mode_bundle = {
  mode_name : string;
  airspace : (module Airspace_model.AIRSPACE_MODEL);
  conflict : (module Conflict_model.CONFLICT_MODEL);
  motion : (module Motion_model.MOTION_MODEL);
  planner : (module Planner_adapter.PLANNER_ADAPTER);
  evaluator : (module Evaluation_model.EVALUATION_MODEL);
}
```

当前注册：

- `layered`：`Layered_airspace`、`Layered_conflict`、`Layered_motion`、`Layered_planner_adapter`、`Layered_evaluation`
- `continuous3d`：`Continuous3d_airspace`、`Continuous3d_conflict`、`Continuous3d_motion`、`Continuous3d_planner_adapter`、`Continuous3d_evaluation`

运行时使用：

- `Run_async` 用 `by_name cli.mode` 选择 bundle。
- `World` 保存并调用 `bundle.motion`。
- `Run_async` 调用 `bundle.planner`、`bundle.conflict`、`bundle.evaluator`。
- `Logger` 保存 bundle，并通过 `bundle.airspace` 写层相关日志字段。

## Layered 模式模块

### `src/layered_airspace.ml`

`Layered_airspace` 是 layered 模式的空域实现。

职责：

- 根据 `uav_state.mode_state` 返回当前占用层
- 实现层号和高度之间的转换
- 根据 scenario 初始层构造 layered 初始 `mode_state`
- 提供 state CSV 中的层字段

主要行为：

- 稳定飞行：`occupied_layers` 返回 `[current_level]`
- 换层中：`occupied_layers` 返回 `[from_level; target_level]`
- `initial_mode_state _ ~initial_level` 返回 `Types.Layered { current_level = initial_level; transition = LevelStable }`
- `log_layer_fields` 返回 `(level, from_level, target_level, is_changing)`
- 若 layered airspace 收到 `Continuous3D` 状态，会 `failwith`，表示 mode 使用错误

### `src/layered_conflict.ml`

`Layered_conflict` 是 layered 模式的真值冲突模型。

职责：

- 判断两架无人机在 layered 空域里是否冲突
- 提供水平距离作为 pair distance

冲突规则：

- 两架无人机占用层集合有交集
- 且水平距离 `Vec3.distance_xy a.pos b.pos < cfg.safety_radius`

注意：

- 换层中无人机会双层占用，因此可能和 source/target 两层中的任意邻机冲突。

### `src/layered_motion.ml`

`Layered_motion` 是 layered 模式的状态推进模块。

职责：

- 使用 `cmd.target_vel.x/y` 推进水平位置
- 管理 `LevelStable` 和 `LevelChanging` 状态机
- 根据水平距离判断是否到达 goal

当前简化：

- 水平运动为一阶积分
- `target_vel` 的 xy 速度会被限制在 `uav_type.vmax`
- `z` 在换层期间用线性插值推进
- 加速度、jerk、yaw/yaw_rate 未实现真实动力学
- `active = false` 的状态不再推进

换层逻辑：

- 当前处于 `LevelStable` 且 `cmd.start_level_change = true` 且 `cmd.target_level = Some target` 时开始换层
- 换层持续 `cfg.climb_steps`
- 换层完成后进入 `LevelStable`，`current_level = target_level`

### `src/layered_planner_adapter.ml`

`Layered_planner_adapter` 是 layered 模式 stub planner。

职责：

- 作为后续 layered ORCA/Maneuver 的接入点
- 当前只输出朝 goal 水平方向直飞的命令

当前行为：

- 从 `self.mode_state` 读取当前层
- 若收到 `Continuous3D` mode_state，则 `failwith`
- 只使用 goal 与当前位置的水平差
- 输出速度不超过 `self.uav_type.vmax`
- `target_level = Some current_level`
- `start_level_change = false`
- 不避障，不主动换层

后续扩展：

- 将 `neighbor_observation list` 转换为 layered ORCA/Maneuver 所需的 points/speeds/levels snapshot
- 接入后续抽出的 `resolstage_move_once_3d` 核心函数

### `src/layered_evaluation.ml`

`Layered_evaluation` 是 layered 模式的评估累计模块。

职责：

- 累计通用指标
- 累计 layered 专属指标
- 输出 layered summary CSV 字段

当前通用指标：

- `success`
- `collision_pair_step_count`
- `min_distance`
- `flight_time`
- `path_length`
- `avg_speed`
- `planning_count`
- `compute_time_ms`
- `packet_delivery_ratio`

当前 layered 专属指标：

- `layer_change_count`
- `failed_layer_change_count`
- `dual_layer_conflict_count`
- `time_in_transition`
- `return_to_original_layer_ratio`

实现细节：

- 路径长度用连续 tick 间的 3D 位移累计。
- `min_distance` 由主循环传入的 `pair_distance` 计算。
- 冲突计数由主循环传入的 `is_conflict` 计算。
- `collision_pair_step_count` 表示“每个仿真 step 中冲突 pair 的累计次数”，不是唯一碰撞事件数。
- `dual_layer_conflict_count` 仍通过 `Layered_airspace.occupied_layers` 判断是否有换层中的冲突 pair。

## Continuous3D 模式模块

### `src/continuous3d_airspace.ml`

`Continuous3d_airspace` 是 continuous3d 模式的空域实现。

职责：

- 满足 `AIRSPACE_MODEL` 接口
- 表示 continuous3d 没有离散层占用
- 构造 continuous3d 初始 mode state
- 提供 state CSV 的层字段占位值

主要行为：

- `occupied_layers` 始终返回 `[]`
- `initial_mode_state _ ~initial_level:_` 返回 `Types.Continuous3D`
- `log_layer_fields _` 返回 `(-1, -1, -1, 0)`
- `z_of_level` / `level_of_z` 仅用于接口兼容
- `initial_level_of_goal` 返回 `0`

### `src/continuous3d_conflict.ml`

`Continuous3d_conflict` 是 continuous3d 模式的真值冲突模型。

职责：

- 判断两机 3D 欧氏距离是否低于安全半径
- 提供 3D pair distance

冲突规则：

- `Vec3.distance a.pos b.pos < cfg.safety_radius`

### `src/continuous3d_motion.ml`

`Continuous3d_motion` 是 continuous3d 模式的状态推进模块。

职责：

- 使用 `cmd.target_vel` 推进 xyz
- 根据 3D 距离判断是否到达 goal

当前简化：

- 一阶积分
- `target_vel` 会被限制在 `uav_type.vmax`
- 不建模 jerk、acc、yaw/yaw_rate
- `active = false` 的状态不再推进

### `src/continuous3d_planner_adapter.ml`

`Continuous3d_planner_adapter` 是 continuous3d 模式 stub planner。

职责：

- 作为后续 3D ORCA 的接入点
- 当前只输出朝 3D goal 的直飞速度

当前行为：

- `target_vel = vmax * unit(goal - pos)`
- `target_level = None`
- `start_level_change = false`
- 不避障

后续扩展：

- 将 `neighbor_observation list` 转换为 3D ORCA obstacle list
- 接入后续抽出的 `Avoid.solve_desired_velocity`

### `src/continuous3d_evaluation.ml`

`Continuous3d_evaluation` 是 continuous3d 模式的评估累计模块。

职责：

- 累计通用指标
- 输出 continuous3d 专属 summary 字段

当前通用指标：

- `success`
- `collision_pair_step_count`
- `min_distance`
- `flight_time`
- `path_length`
- `avg_speed`
- `planning_count`
- `compute_time_ms`
- `packet_delivery_ratio`

当前 3D 专属指标：

- `vertical_maneuver_distance`
- `altitude_deviation`
- `path_smoothness_3d`
- `vz_violations`
- `min_3d_separation`

实现细节：

- `vertical_maneuver_distance` 累计连续 tick 间的 z 变化绝对值。
- `min_distance` 和 `collision_pair_step_count` 使用主循环传入的当前 conflict 模型函数。
- `altitude_deviation`、`path_smoothness_3d`、`vz_violations` 当前是骨架占位值。

## 通用仿真基础设施模块

### `src/event_queue.mli` / `src/event_queue.ml`

`Event_queue` 是通信消息延迟投递队列。

职责：

- 保存已经发送但尚未到达的 `Types.neighbor_msg`
- 根据当前仿真时间弹出已到达消息

主要 API：

- `create : unit -> t`
- `push : t -> Types.neighbor_msg -> unit`
- `pop_ready : t -> now:float -> Types.neighbor_msg list`

实现方式：

- 当前使用 list 存储消息
- `pop_ready` 用 `List.partition` 分离 `receive_time <= now` 的消息
- ready 消息按 `receive_time` 排序后返回

设计说明：

- 骨架阶段足够简单；大规模仿真可替换为优先队列。

### `src/neighbor_cache.mli` / `src/neighbor_cache.ml`

`Neighbor_cache` 是每架无人机自己的邻机缓存。

职责：

- 维护 `sender_id -> latest neighbor_msg`
- 接收 `Event_queue` 投递的消息
- 对消息中的位置做一阶外推
- 生成 planner 可见的 `neighbor_observation list`

主要 API：

- `create : unit -> t`
- `ingest : t -> Types.neighbor_msg -> unit`
- `get_valid_neighbors : t -> now:float -> cfg:Types.sim_config -> self_id:int -> Types.neighbor_observation list`

外推规则：

- `age = max 0.0 (now - msg.sent_time)`
- `pos = msg.pos + age * msg.vel`
- `effective_radius = msg.radius + cfg.k_delay_radius * age`
- `is_stale = age > cfg.stale_timeout`

关键边界：

- 不访问 world 真值。
- stale 观察不被过滤，而是带 `is_stale = true` 返回给 planner。
- `ingest` 只保留同一 sender 的最新消息。

### `src/comm_model.mli` / `src/comm_model.ml`

`Comm_model` 是通信广播模型。

职责：

- 为每架无人机维护下一次广播时间
- 生成带延迟的 `neighbor_msg`
- 根据通信范围和丢包率决定消息是否丢弃
- 通过 callback 把发送/丢包事件交给主循环记录

主要 API：

- `create ~cfg ~n_uavs ~rng`
- `maybe_broadcast t ~now ~true_states ~on_send ~on_drop`

当前通信逻辑：

- 每架 active UAV 到达 `next_broadcast` 后向其它 UAV 广播。
- 若接收者超出 `cfg.comm_range` 或 `packet_loss` 命中，则调用 `on_drop`。
- 否则构造 `neighbor_msg`，其中 `receive_time = now + delay`。
- `delay = max 0 (delay_mean + uniform(-delay_jitter, delay_jitter))`。
- 成功发送的消息由返回值交给主循环 push 到 `Event_queue`。

### `src/planner_scheduler.mli` / `src/planner_scheduler.ml`

`Planner_scheduler` 是异步 planner 调度器。

职责：

- 为每架无人机维护下一次 planner 触发时间
- 支持随机初始错峰
- 支持 planner period jitter

主要 API：

- `create ~cfg ~n_uavs ~rng`
- `due_uavs t ~now`
- `schedule_next t ~uav_id ~now`

当前行为：

- 初始化时每架机在 `[0, cfg.planner_period]` 内随机获得首次触发时间。
- 每次规划后，下一次触发为 `now + planner_period + jitter`。
- jitter 后的周期下限为 `cfg.world_dt`。

### `src/world.mli` / `src/world.ml`

`World` 是真值状态容器。

职责：

- 持有所有 `Types.uav_state`
- 保存每架无人机最近一次 planner command
- 调用当前 mode 的 motion model 推进状态
- 对 planner 提供受控的自身状态快照

主要 API：

- `create ~cfg ~bundle ~initial`
- `step t ~now ~dt`
- `set_command t cmd`
- `get_self_state t ~uav_id ~now`
- `all_states_for_evaluator t`
- `n_uavs t`
- `all_finished t`

关键边界：

- `get_self_state` 返回 `Types.self_state`，不是 `Types.uav_state`。
- `all_states_for_evaluator` 返回数组副本，只供 evaluator/logger 使用。
- `World.step` 不知道具体 mode，只调用 `bundle.motion`。

当前简化：

- 无命令时使用当前速度构造 hold command。
- command 在 `World.set_command` 后由后续 world step 消费。

### `src/logger.mli` / `src/logger.ml`

`Logger` 是 CSV 输出模块。

职责：

- 写 `state.csv`
- 写 `events.csv`
- 写 `summary.csv`
- 创建输出目录
- 通过当前 airspace model 写层相关日志字段

主要 API：

- `create ~cfg ~bundle`
- `close`
- `write_state_row`
- `write_event`
- `write_summary`

内部状态：

- `state : out_channel`
- `events : out_channel`
- `summary : out_channel`
- `bundle : Mode_registry.mode_bundle`

`state.csv` 字段：

```text
time,uav_id,x,y,z,vx,vy,vz,yaw,level,from_level,target_level,is_changing,reached,active
```

`events.csv` 字段：

```text
time,event,uav_id,other_id,value1,value2,desc
```

设计说明：

- `write_state_row` 调用 `bundle.airspace` 中的 `log_layer_fields`，不直接 pattern-match `Layered` 或 `Continuous3D`。
- planner adapter 内部不写文件；事件由主循环统一记录。

### `src/scenario.mli` / `src/scenario.ml`

`Scenario` 是极简文本场景加载与初始状态构造模块。

职责：

- 读取 scenario 文本文件
- 解析 UAV 初始位置、目标、类型、初始层
- 转换为 `Types.uav_state array`

主要类型：

- `uav_spec`
- `t = { name; uavs }`

主要 API：

- `load_file path`
- `to_initial_states ~bundle ~cfg scenario`

当前文本格式：

```text
name head_on_2
uav 0 start 0 0 0 goal 20 0 0 type default level 0
```

当前默认 UAV 参数：

- `type_name = "default"`
- `vmax = 2.0`
- `amax_xy = 3.0`
- `az_up_max = 2.0`
- `az_down_max = 2.0`
- `jerk_max = 5.0`
- `yaw_rate_max = 1.5`
- `yaw_acc_max = 3.0`
- `climb_rate_max = 2.0`
- `radius = 0.5`

关键边界：

- `Scenario` 不根据 `bundle.mode_name` 做字符串分支。
- 初始 `mode_state` 由 `bundle.airspace` 的 `initial_mode_state cfg ~initial_level` 构造。
- continuous3d 是否忽略 `level`、layered 如何使用 `level`，都由具体 airspace model 决定。

## 可执行程序

### `bin/run_async.ml`

`Run_async` 是主仿真程序。

职责：

- 解析命令行
- 根据 `--mode` 选择 `Mode_registry.mode_bundle`
- 加载 scenario 并构造初始 world
- 创建通信模型、事件队列、邻机缓存、planner 调度器、logger、evaluator
- 执行异步仿真主循环
- 写 summary 并关闭日志

命令行参数：

- `--mode layered|continuous3d`
- `--scenario <path>`
- `--seed <int>`
- `--out-dir <path>`

主循环顺序：

1. `World.step`
2. `Comm_model.maybe_broadcast`
3. 成功发送的消息进入 `Event_queue`
4. `Event_queue.pop_ready` 投递到接收者的 `Neighbor_cache`
5. `Planner_scheduler.due_uavs` 找到需要规划的 UAV
6. 对每个 due UAV，读取 `World.get_self_state` 和 `Neighbor_cache.get_valid_neighbors`
7. 调用当前 mode 的 `Planner_adapter.plan_once`
8. `World.set_command` 保存新命令
9. 调用 `Evaluation_model.on_step`
10. 调用 `Logger.write_state_row`
11. 时间增加 `cfg.world_dt`

当前主循环中的模块拆包：

- `P = bundle.planner`
- `E = bundle.evaluator`
- `C = bundle.conflict`

其中 `C.pair_distance ~cfg` 和 `C.is_conflict ~cfg` 会作为函数传入 `E.on_step`。

### `bin/run_batch.ml`

`Run_batch` 是批量实验入口占位文件。

当前行为：

- 打印占位说明

后续用途：

- 支持 scenario × seed × method 的实验矩阵
- 批量调用 `run_async`
- 汇总多个 summary 文件

### `bin/export_rviz_log.ml`

`Export_rviz_log` 是 RViz 导出入口占位文件。

当前行为：

- 打印占位说明

后续用途：

- 将 CSV trace 转换成 RViz replay 或其它可视化格式

## 构建与外围文件

### `Makefile`

`Makefile` 是构建入口。

职责：

- 使用 `ocamlfind ocamlopt`
- 显式列出编译顺序
- 编译 `_build/run_async`
- 编译 `_build/run_batch`
- 编译 `_build/export_rviz_log`

依赖包：

- `unix`
- `str`

主要目标：

- `make`
- `make clean`

注意：

- 不使用 dune。
- 不使用 ocamldep 自动生成依赖。
- `.mli` 文件在对应 `.ml` 编译前按依赖顺序生成 `.cmi`，保证 `make clean && make` 可直接通过。

### `README.md`

项目快速说明文档。

职责：

- 简要说明项目目标
- 给出 build 命令
- 给出 layered 和 continuous3d 的运行示例
- 说明 scenario 格式
- 标记 planner adapter 的 TODO

### `scenarios/head_on_2.txt`

两机对头场景。

用途：

- 最小 smoke test 场景
- stub planner 下两机直线相向飞行，预期发生冲突

内容：

- UAV 0 从 `(0,0,0)` 飞向 `(20,0,0)`
- UAV 1 从 `(20,0,0)` 飞向 `(0,0,0)`
- 初始 level 均为 `0`

### `scenarios/crossing_4.txt`

四机交叉场景。

用途：

- 比两机对头更复杂的基础场景
- 可用于后续测试通信、缓存、planner adapter 和 evaluator 行为

内容：

- 两架东西向对穿
- 两架南北向对穿
- 初始 level 均为 `0`

### `scripts/summarize.py`

实验结果汇总脚本占位文件。

当前状态：

- 仅保留占位注释

后续用途：

- 汇总多个 `summary.csv`
- 输出批量实验表格

### `scripts/plot_metrics.py`

绘图脚本占位文件。

当前状态：

- 仅保留占位注释

后续用途：

- 绘制距离、冲突数、通信指标、轨迹等图表

## 运行时数据流

一次仿真 tick 的核心数据流：

1. `World.step` 用上一条 planner command 推进真值 `uav_state`
2. `Comm_model` 根据真值状态构造发送时刻的 `neighbor_msg`
3. `Event_queue` 根据 `receive_time` 延迟投递消息
4. `Neighbor_cache` 保存最新消息，并在 planner 触发时外推为 `neighbor_observation`
5. `Planner_adapter.plan_once` 只基于 `self_state`、`neighbor_observation list` 和 `last_command` 输出命令
6. `World.set_command` 保存命令，后续 world step 生效
7. `Evaluation_model.on_step` 使用真值副本和当前 conflict 函数累计指标
8. `Logger` 写出 state/event/summary CSV

## 后续接入真实算法的位置

### 接入 Continuous 3D ORCA

目标文件：

- `src/continuous3d_planner_adapter.ml`

建议工作：

- 将 `self_state` 转换为 3D ORCA 所需 state
- 将 `neighbor_observation list` 转换为 obstacle list
- 保留 neighbor 的 `age` 和 `effective_radius`
- 调用后续抽出的 `Avoid.solve_desired_velocity`
- 将结果转换为 `planner_command`

### 接入 Layered ORCA/Maneuver

目标文件：

- `src/layered_planner_adapter.ml`

建议工作：

- 从 `self_state.mode_state` 获取当前层与换层状态
- 从 `neighbor_observation list` 构造 points/speeds/levels snapshot
- 将 stale、delay、effective_radius 纳入 adapter 输入
- 调用后续抽出的 layered ORCA/Maneuver 核心
- 将结果转换为 `target_vel`、`target_level`、`start_level_change`

## 当前已知骨架限制

- planner 是 stub，不避障。
- motion model 是一阶积分，不是真实动力学。
- evaluator 中部分高级指标仍是占位值。
- `collision_pair_step_count` 是逐 tick、逐 pair 累计，不是唯一碰撞事件计数。
- `Event_queue` 是 list 实现，大规模仿真时应替换为优先队列。
- `Scenario` 只支持极简文本格式和默认 UAV 类型。
- `run_batch`、`export_rviz_log` 和 Python scripts 仍是占位。
