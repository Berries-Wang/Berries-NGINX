# NGINX 配置全景:参数长在请求流程的哪一步

> 源码根目录:`000.SOURCE_CODE/NGINX-1.30.2`。
> 本目录各篇(001-007)讲"单条参数怎么配";本篇把全部参数**钉到请求流程图与
> 架构图上**,回答"这条参数到底在哪个环节起作用"。阶段编号 [1]-[8] 全文通用。
> 机制与源码走读见 `../002.NGINX架构/000.NGINX架构图.md`(下称"架构笔记");
> 参数的默认值 / 源码行号 / 调优边界见各篇,本篇不重复展开。

## 目录导航

| 篇 | 主题 |
|---|---|
| [000](000.配置总览与解析机制.md) | 配置总览与解析机制 |
| [001](001.进程与events配置.md) | 进程与 events 配置 |
| [002](002.网络连接与内核联动配置.md) | 网络连接与内核联动 |
| [003](003.数据通路配置.md) | 数据通路 |
| [004](004.缓冲压缩与缓存配置.md) | 缓冲压缩与缓存 |
| [005](005.upstream配置.md) | upstream 配置 |
| [006](006.限流与日志配置.md) | 限流与日志 |
| [007](007.配置模板与变更方法论.md) | 配置模板与变更方法论 |
| 本篇 | 参数 × 流程落点全景图 |

一句话心智模型:**装配期参数决定"机器长什么样"(进程/socket/内存池,§1),
运行期参数决定"每个请求怎么流过这台机器"(§2-§5)**。
改装配期参数必须 reload 才换得掉 worker;排查运行期问题去流程图上找对应环节。

---

## 0. 八步流程缩略图:每一步归哪篇管

```
 客户端
    │
 ═══ 内核态:握手与排队,任何 nginx 进程不参与(002 篇)═══
    [1] 半连接队列  ← tcp_max_syn_backlog(sysctl)
    [2] 全连接队列  ← listen backlog= ↔ somaxconn,生效 = min(两者)
    [3] 连接分发    ← reuseport / EPOLLEXCLUSIVE(选哪个 worker)
 ═══ worker:单线程 + epoll 事件循环(001 篇容量主线)═════
    [4] accept 取槽 ← worker_connections / multi_accept / accept_mutex
    [5] 解析请求头  ← client_header_buffer_size 族(004 篇)
    [6] 11 阶段     ← limit_req / limit_conn(006)→ CONTENT 双车道(§3)
    [7] 过滤链+写出 ← gzip 族(004)+ 发送三开关(003,§4)
    [8] 收尾+日志   ← keepalive 两侧(002/005,§5)+ access_log(006)
 ═══ 装配期:master fork 之前的一切(§1)════════════════
```

---

## 1. 装配期:master 启动 / reload,参数各就各位

> 运行期 worker 不再读配置文件——所有指令在这一阶段变成进程结构里的字段。
> reload(HUP)= master 重走本图再换 worker(000 篇)。

```
 master 启动
   ├─ ① 解析 nginx.conf  ngx_conf_parse:逐条指令查表调 set 回调(000 篇)
   ├─ ② 逐层 merge       http → server → location 落值;nginx -t 到此为止(000 篇)
   ├─ ③ 建缓存目录与共享内存(slab,跨 worker 一致)
   │      limit_req_zone / limit_conn_zone(006 篇)
   │      upstream zone(005 篇)
   │      proxy_cache_path 的 keys_zone + 磁盘目录(004 篇)
   ├─ ④ 建 listen socket backlog= → listen(s, backlog),默认仅 511(002 篇)
   │      reuseport → 按 worker 数克隆 socket,每 worker 一份(002 篇)
   ├─ ⑤ fork             worker_processes N 个 worker(001 篇)
   │      每个 worker 内 ngx_worker_process_init:
   │        worker_rlimit_nofile → setrlimit(fd 天花板)
   │        worker_cpu_affinity  → 绑核(配网卡 RSS;容器慎用)
   │        worker_connections  → 预分配连接三数组(容量 = 数组大小)
   │        use epoll           → 各自建 epoll 实例(平台自动选择)
   │      proxy_cache_path → 另 fork cache manager / cache loader(004 篇)
   └─ ⑥ master 进入 sigsuspend 睡眠,数据通路全在 worker(架构笔记第 1 节)

 顺序的源码依据:ngx_cycle.c:284(parse)→ :354(目录)→ :491(共享内存)
              → :630(listen socket)→ :647(init modules)→ fork
```

装配期参数速记:worker_processes / worker_cpu_affinity / worker_rlimit_nofile /
worker_connections / use / listen backlog= / reuseport / limit_*_zone / zone /
proxy_cache_path——**它们不逐请求生效,改了必须 reload 才生效**(000 篇三段生命周期)。

---

## 2. 主图:一条请求的一生 × 参数落点

```
 客户端 ── SYN ──► nginx 主机
    │
 ═══════ 内核态:握手与排队,任何 nginx 进程都不参与 ═══════
    ▼
 [1] 半连接队列(SYN_RECV)
    │   ← tcp_max_syn_backlog(sysctl):半连接上限,抗 SYN 突发;
    │     它管的不是 accept 容量,别与 [2] 混谈(002 篇)
    ▼
 [2] 全连接队列(ACCEPT)
    │   ← listen 80 backlog=8192;(nginx 默认仅 511)
    │     + net.core.somaxconn(sysctl 默认 4096)
    │     生效上限 = min(两者)→ 只调 somaxconn 没用,两头一起动(002 篇)
    ▼
 [3] 连接分发:这个连接归哪个 worker?
    │   ← 默认:EPOLLEXCLUSIVE,内核只唤醒一个 worker(防惊群)
    │   ← listen ... reuseport:每 worker 专属 socket,内核四元组哈希分流,
    │     无锁、最均匀,高连接速率场景收益最大的单项(002 篇)
    ▼
 ═══════ worker 进程:单线程事件循环(架构笔记第 2 节)═══════
    ▼
 [4] accept():从预分配连接数组取 1 个槽位
    │   ← worker_connections(默认 512):每 worker 槽位总数(001 篇)
    │     静态:1 请求占 1 槽;反向代理:1 请求占 2 槽(client + upstream)
    │     槽满的日志特征:"worker_connections are not enough"
    │   ← multi_accept off / accept_mutex off:accept 的节奏,保持默认(001 篇)
    │   ← worker_rlimit_nofile:槽位背后的 fd 天花板;fd 耗尽时
    │     accept 返回 EMFILE,触发摘 listen 事件的兜底(架构笔记 7.2)
    ▼
 [5] 等首字节 → 解析请求行/头(状态机逐事件续传)
    │   ← client_header_buffer_size(默认 1k):初始缓冲(004 篇)
    │   ← large_client_header_buffers(默认 4 8k):按需增长上限,
    │     用满仍超长 → 400 / 414(004 篇)
    ▼
 [6] 11 阶段流水线(phase engine,架构笔记第 4 节)
    │   ← PREACCESS:limit_req(漏桶)/ limit_conn(并发数),
    │     状态在共享内存红黑树,所有 worker 同一个桶(006 篇)
    │   ← CONTENT:产出响应,双车道分叉 → §3
    ▼
 [7] 响应过滤链 + 写出
    │   ← gzip 族:header 链改头 + body 链压缩,烧的是 worker CPU(004 篇)
    │   ← sendfile / tcp_nopush / tcp_nodelay:写出方式 → §4
    ▼
 [8] 收尾:连接回收或复用
    │   ← 客户端侧 keepalive 族(002 篇)+ upstream 侧三参数(005 篇)→ §5
    │   ← LOG 阶段:access_log buffer=/flush=、error_log 级别(006 篇)
    ▼
 回到 epoll_wait,等这条连接(或新连接)的下一个事件
```

---

## 3. [6] CONTENT 双车道:静态文件 vs 反向代理

车道决定了哪些参数有用、哪些调了无感(003/005 篇):

```
 车道 A:静态文件(static 模块)
   open_file_cache max=10000 inactive=60s(+ valid / min_uses / errors)
     以路径为 key 缓存 fd + stat → 每请求 open+stat 系统调用归零(003 篇)
   sendfile on
     页缓存 → socket 零拷贝;只对本地文件的响应生效
   aio threads + directio
     大文件慢读挪进线程池(默认 32 线程),主循环永不阻塞(003 篇)

 车道 B:反向代理(proxy_pass → upstream)
   选 peer(round-robin / least_conn / ...,架构笔记第 6 节)
     ← zone:后端健康状态放共享内存,跨 worker 一致(≠连接池,005 篇)
   取后端连接:
     池中有空闲 → 直接复用        ← keepalive N(1.30 默认 32 local,005 篇)
     池空 → 非阻塞 connect 新建   ← ip_local_port_range / tcp_tw_reuse
                                    (sysctl,只管出站方向,002 篇)
   proxy_cache 命中?
     命中   → 磁盘缓存直接发,不连后端
              ← proxy_cache_path:keys_zone 共享内存索引 + 磁盘文件
                + master 另 fork 的 cache manager / loader(004 篇)
     未命中 → 收后端响应进 proxy_buffers,接入下游过滤链

 两车道在 [7] 汇合:
   车道 A 写出走 sendfile(零拷贝),车道 B 响应体在内存走 writev
   → 反向代理调 sendfile 无感;tcp_nopush 只伴 sendfile 出现(003 篇)
```

---

## 4. [7] 发送段:同一连接的三种发送形态

tcp_nopush(Cork 攒包)与 tcp_nodelay(关 Nagle)看似矛盾,实际作用时机不同,
可以同时 on(003 篇):

```
 t0 首个请求(小响应)
 │    tcp_nodelay on(默认已开)
 │    setsockopt(TCP_NODELAY):小包立即发,交互式 API 不被 Nagle
 │    攒出一个 RTT 级延迟
 ▼
 t1 开始发文件(静态大响应)
 │    tcp_nopush on + sendfile on
 │    setsockopt(TCP_CORK):响应头 + 文件首块攒成一个整包
 ▼
 t2 文件发送完毕
 │    拔塞放行(request.c:3438),之后 tcp_nodelay 接管后续小包
 ▼
 keepalive 复用期间的小响应:又回到 t0 的 NODELAY 形态
```

---

## 5. [8] 收尾段:两套 keepalive,各管一侧

连接寿命是对称的两套旋钮——入站侧管"客户端连接",出站侧管"后端连接":

| 入站侧:nginx ↔ 客户端(002 篇) | 出站侧:nginx ↔ 后端(005 篇) |
|---|---|
| keepalive_timeout 75s | keepalive N(1.30 默认 32 local) |
| keepalive_requests 1000 | keepalive_time 1h |
| keepalive_time 1h | keepalive_timeout 60s |
| keepalive_min_timeout(默认不设) | keepalive_requests 1000 |

```
 共同语义:省握手;代价:空闲连接一直占槽位和 fd
   入站侧:keepalive_timeout 必须短于前置 LB 的空闲超时,否则 LB 先踢出 RST
   出站侧:三个寿命参数要与后端自己的 keepalive 对齐,别 nginx 攒着、后端先踢
   出站侧收益:upstream keepalive 常是代理链路最大的单项(省握手 + 慢启动,
   还从根上消掉出站端口耗尽与 TIME_WAIT,002 篇联动表)
```

---

## 6. 观测变量也长在流程上

timing 日志(006 篇)的每个变量对应主图的一段,差分即可定位慢在哪段:

| 变量 | 覆盖区间 | 慢了指向 |
|---|---|---|
| $request_time | [4] → [8] 全程 | 与 $upstream_response_time 差分 |
| $upstream_connect_time | [6] 车道 B 的 connect | 出站端口耗尽 / 后端握手慢 |
| $upstream_header_time | [6] 到收到后端响应头 | 后端首字节 |
| $upstream_response_time | [6] 后端总耗时 | 后端慢,调 nginx 无用 |

```
 $request_time 高 + $upstream_response_time 低 → 慢在 nginx/客户端侧([4][5][7])
 $upstream_response_time 高                   → 慢在后端([6] 车道 B)
```

客户端侧的 curl -w 分层(TTFB / total)对应关系见 007 篇。

---

## 7. 参数 × 环节速查总表

| 环节 | 指令 / 参数 | 默认 | 一句话 | 详见 |
|---|---|---|---|---|
| 装配期⑤ | worker_processes | 1 | worker 数;auto = 核数,容器注意 cgroup | 001 篇 |
| 装配期⑤ | worker_cpu_affinity | 不绑 | 绑核配 RSS;容器慎用 | 001 篇 |
| 装配期⑤ | worker_rlimit_nofile | 不设 | worker 内 setrlimit,fd 天花板 | 001 篇 |
| 装配期⑤ | worker_connections | 512 | 每 worker 槽位;反向代理容量 ÷2 | 001 篇 |
| 装配期⑤ | use | 自动 | Linux 必是 epoll,写不写一样 | 001 篇 |
| 装配期⑤ | multi_accept | off | accept 节奏,保持 off | 001 篇 |
| 装配期⑤ | accept_mutex | off | EPOLLEXCLUSIVE 已接管惊群 | 001 篇 |
| 装配期④ | listen backlog= | 511 | 全连接队列,与 somaxconn 取 min | 002 篇 |
| 装配期④ | listen reuseport | off | 每 worker 专属 socket | 002 篇 |
| 装配期③ | limit_req_zone / limit_conn_zone | — | 共享内存漏桶 / 计数声明 | 006 篇 |
| 装配期③ | upstream zone | — | 后端状态共享内存(≠连接池) | 005 篇 |
| 装配期③④ | proxy_cache_path | — | keys_zone + 磁盘 + cache manager | 004 篇 |
| [1] | tcp_max_syn_backlog(sysctl) | — | 半连接队列,抗 SYN 突发 | 002 篇 |
| [2] | net.core.somaxconn(sysctl) | 4096 | 与 backlog 取 min 才生效 | 002 篇 |
| [3] | reuseport / EPOLLEXCLUSIVE | — | 连接分发策略,装配期已定 | 002 篇 |
| [4] | worker_connections(运行含义) | — | 槽位占用与 accept_disabled 防线 | 001 篇 / 架构 7.2 |
| [5] | client_header_buffer_size | 1k | 请求头初始缓冲 | 004 篇 |
| [5] | large_client_header_buffers | 4 8k | 请求头增长上限,超 → 400/414 | 004 篇 |
| [6] | limit_req(rate/burst/nodelay/delay) | 不限 | PREACCESS 漏桶 | 006 篇 |
| [6] | limit_conn | 不限 | PREACCESS 并发连接数 | 006 篇 |
| [6] 车道 A | open_file_cache 族 | off | 缓存 fd + stat | 003 篇 |
| [6] 车道 A | sendfile | off | 本地文件零拷贝 | 003 篇 |
| [6] 车道 A | aio threads / directio | off | 大文件读挪进线程池 | 003 篇 |
| [6] 车道 B | upstream keepalive N | 32 local | 后端连接池(每 worker 私有) | 005 篇 |
| [6] 车道 B | upstream keepalive_time / timeout / requests | 1h / 60s / 1000 | 后端连接寿命三参数 | 005 篇 |
| [6] 车道 B | proxy_cache 族(valid / key / no_cache) | — | 磁盘缓存按路由颗粒度控制 | 004 篇 |
| [6] 车道 B | ip_local_port_range / tcp_tw_reuse(sysctl) | — | 出站新建连接的端口与 TIME_WAIT | 002 篇 |
| [7] | gzip / comp_level / types / min_length / vary / proxied | off / 1 / 仅 html / 20 | 过滤链压缩,CPU 换带宽 | 004 篇 |
| [7] | tcp_nopush | off | Cork 攒包,伴 sendfile | 003 篇 |
| [7] | tcp_nodelay | on | 关 Nagle,默认已开 | 003 篇 |
| [8] | keepalive_timeout / requests / time / min_timeout | 75s / 1000 / 1h / 不设 | 客户端连接寿命四旋钮 | 002 篇 |
| [8] | access_log(buffer= / flush=) | 无缓冲 | 日志攒批落盘 | 006 篇 |
| [8] | error_log 级别 | error | 高频路径砍级别立竿见影 | 006 篇 |
| 全程 | fs.nr_open(sysctl) | 1048576 | nofile 的绝对天花板 | 001 篇 |

合并起来的完整配置模板与变更流程(备份 → 灰度 reload → 验证 → 回滚)
见 [007 篇](007.配置模板与变更方法论.md);参数间的联动陷阱
(worker_connections ↔ nofile、backlog ↔ somaxconn 等)见 007 篇第 4 节总表。

---

## 附录:一次反向代理请求的完整时序图

> §2 主图按**环节**拆解;本附录把同一条流程按**时间轴**重排成时序图:
> 四条生命线(客户端 / 内核 / worker / 后端),时间自上而下,
> 以覆盖参数最多的车道 B(反向代理)为例,阶段编号 [1]-[8] 与正文一致。

```
  ┌──────┐            ┌────────────────┐            ┌────────────────┐           ┌──────────────┐
  │客户端│            │内核(队列/epoll)│            │worker(事件循环)│           │后端(upstream)│
  └──┬───┘            └────────┬───────┘            └────────┬───────┘           └───────┬──────┘
     │                         │                             │                           │
     │ [1][2] SYN,三次握手     │                             │                           │
     ├─────────────────────────►                             │                           │
     │                         │ [1]半连接→[2]全连接         │                           │
     │                         │ ←tcp_max_syn_backlog        │                           │
     │                         │ ←min(backlog,somaxconn)     │                           │
     │                         │                             │                           │
     │                         │ [3] listen 可读             │                           │
     │                         │ EPOLLEXCLUSIVE / reuseport  │                           │
     │                         ├─────────────────────────────►                           │
     │                         │                             │ [4] accept() 取槽         │
     │                         │                             │ ←worker_connections       │
     │                         │                             │ ET 非阻塞,挂定时器        │
     │                         │                             │                           │
     │ [5] 请求行+头           │                             │                           │
     │                         │ 状态机逐事件续传            │                           │
     ├───────────────────────────────────────────────────────►                           │
     │                         │                             │ ←client_header_buffer_size│
     │                         │                             │ 超限→400/414              │
     │                         │                             │                           │
     │                         │                             │ [6] PREACCESS 限流        │
     │                         │                             │ limit_req/limit_conn      │
     │                         │                             │ NGX_BUSY→503              │
     │                         │                             │ [6] CONTENT 车道 B        │
     │                         │                             │ 选 peer(zone)             │
     │                         │                             │                           │
     │                         │                             │ keepalive 池空?           │
     │                         │                             ├───────────────────────────►
     │                         │                             │ $upstream_connect_time    │
     │                         │                             │                           │
     │                         │                             │ 请求头/体(边收边转)       │
     │                         │                             ├───────────────────────────►
     │                         │                             │                           │
     │                         │                             │ 响应头                    │
     │                         │                             ◄───────────────────────────┤
     │                         │                             │ $upstream_header_time     │
     │                         │                             │ 响应体                    │
     │                         │                             ◄───────────────────────────┤
     │                         │                             │ →proxy_buffers            │
     │                         │                             │ $upstream_response_time   │
     │                         │                             │                           │
     │                         │                             │ [7] 过滤链(gzip)          │
     │                         │ 响应(经内核 socket 缓冲)    │                           │
     ◄───────────────────────────────────────────────────────┤                           │
     │                         │ writev(代理)/sendfile(静态) │                           │
     │                         │ EAGAIN→挂写事件续发         │                           │
     │                         │ tcp_nodelay/nopush          │                           │
     │                         │                             │                           │
     │                         │                             │ [8] finalize              │
     │                         │                             │ keepalive 三判定          │
     │                         │                             │ timeout/requests/time     │
     │                         │                             │ 通过→挂空闲定时器         │
     │                         │                             │ 等下个请求(不占CPU,占槽)  │
     │                         │                             │ LOG 阶段:access_log 攒批  │
     │                         │                             │ ($request_time 终点)      │
     │                         │                             │ 后端连接回池(上限N)       │
     │                         │                             │ (1h/60s/1000)             │
     │                         │                             │                           │
     │ 分支一:连接复用         │                             │                           │
     │ 新请求(同连接)          │                             │                           │
     ├───────────────────────────────────────────────────────►                           │
     │                         │ → 回 [5](keepalive)         │                           │
     │                         │                             │                           │
     │ 分支二:定时器到点       │                             │                           │
     │                         │ FIN(四次挥手)               │                           │
     ◄───────────────────────────────────────────────────────┤                           │
     │                         │                             │ 关连接,释放槽位           │
     │                         │                             │                           │
```

读图说明:

- 时间自上而下;`│` 为生命线,横箭头是消息/系统调用的方向。客户端与 worker 之间的
  直线只示意方向,数据实际都经过内核 socket 缓冲;横线穿过内核生命线即为示意。
- `[n]` 与 §0-§7 的阶段编号一致;消息旁边的参数就是该环节的落点,完整对照见 §7 总表。
- 静态车道(§3 车道 A):没有 keepalive 池 / connect / 请求 / 响应这四段后端交互,
  [6] 直接 open_file_cache 取文件 → [7] sendfile 发出,其余步骤相同。
- keepalive 三判定(002 篇):timeout > 0、requests 未到上限、连接年龄 < time;
  后端连接回池后同样受 1h / 60s / 1000 三个寿命约束(005 篇)。
- 计时变量即图中的消息段(§6):connect 一段 = $upstream_connect_time,
  connect 到响应头 = $upstream_header_time,connect 到响应体收完 =
  $upstream_response_time;请求首字节到 LOG = $request_time。
