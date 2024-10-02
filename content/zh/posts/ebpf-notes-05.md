+++
title = "ebpf 札记(5): bpftrace cgroup_path 无法用作 map key"
author = ["Dantezy"]
description = "ebpf 札记第五篇。从 bpftrace 社区的一个 issue 开始，讨论 bpftrace cgroup_path 无法用作 map key 的原因。"
date = 2024-10-01
lastmod = 2024-10-02T18:27:58+08:00
tags = ["ebpf", "kernel"]
categories = ["code"]
draft = false
+++

## 背景 {#背景}

bpftrace 的函数 `cgroup_path` 接受 cgroup id ，返回一个表示 cgroup path 的字符串。
我们很容易觉得它应该可以用做 bpftrace 里面的 map key ，所以不久前社区有一个 [issue](https://github.com/bpftrace/bpftrace/issues/3421)
要求支持 `cgroup_path` 作为 map key。


## 结论 {#结论}

为这个 issue 提了一个 [PR](https://github.com/bpftrace/bpftrace/pull/3438) 之后，我发现这个实现有一个无法解决的问题：

```shell
bpftrace -e 'BEGIN { @[cgroup_path(13)]=42; @debug_var=@[cgroup_path(13)]; }'
```

考虑这样一个脚本，最后退出运行的时候，我们会发现虽然这个匿名的 map (`@`) 会有值，
key 是对应13的 cgroup path，值是42，但是 `@debug_var` 会是0。

因为无法解决问题，所以最后这个 issue 被关闭了，目前 bpftrace `cgroup_path`
无法成为 map key。


## 原因 {#原因}

使用 bpftrace emit-elf[^fn:1] 功能，我们可以得到 bpftrace script 对应的 elf 文件：

```shell
bpftrace -e 'BEGIN { @[cgroup_path(13)]=42; @debug_var=@[cgroup_path(13)]; }' --emit-elf cgroup_elf
```

使用 `llvm-objdump -S cgroup_elf` 我们有：

```asm
cgroup_elf:	file format elf64-bpf

Disassembly of section s_BEGIN_1:

0000000000000000 <BEGIN_1>:
       0:	b7 07 00 00 0d 00 00 00	r7 = 0xd
       1:	7b 7a d8 ff 00 00 00 00	*(u64 *)(r10 - 0x28) = r7
       2:	b7 06 00 00 00 00 00 00	r6 = 0x0
       3:	7b 6a d0 ff 00 00 00 00	*(u64 *)(r10 - 0x30) = r6
       4:	b7 01 00 00 2a 00 00 00	r1 = 0x2a
       5:	7b 1a e0 ff 00 00 00 00	*(u64 *)(r10 - 0x20) = r1
       6:	bf a2 00 00 00 00 00 00	r2 = r10
       7:	07 02 00 00 d0 ff ff ff	r2 += -0x30
       8:	bf a3 00 00 00 00 00 00	r3 = r10
       9:	07 03 00 00 e0 ff ff ff	r3 += -0x20
      10:	18 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00	r1 = 0x0 ll
      12:	b7 04 00 00 00 00 00 00	r4 = 0x0
      13:	85 00 00 00 02 00 00 00	call 0x2
      14:	7b 7a e8 ff 00 00 00 00	*(u64 *)(r10 - 0x18) = r7
      15:	b7 01 00 00 01 00 00 00	r1 = 0x1
      16:	7b 1a e0 ff 00 00 00 00	*(u64 *)(r10 - 0x20) = r1
      17:	bf a2 00 00 00 00 00 00	r2 = r10
      18:	07 02 00 00 e0 ff ff ff	r2 += -0x20
      19:	18 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00	r1 = 0x0 ll
      21:	85 00 00 00 01 00 00 00	call 0x1
      22:	b7 01 00 00 00 00 00 00	r1 = 0x0
      23:	15 00 01 00 00 00 00 00	if r0 == 0x0 goto +0x1 <LBB0_2>
      24:	79 01 00 00 00 00 00 00	r1 = *(u64 *)(r0 + 0x0)

00000000000000c8 <LBB0_2>:
      25:	7b 6a f0 ff 00 00 00 00	*(u64 *)(r10 - 0x10) = r6
      26:	7b 1a f8 ff 00 00 00 00	*(u64 *)(r10 - 0x8) = r1
      27:	bf a2 00 00 00 00 00 00	r2 = r10
      28:	07 02 00 00 f0 ff ff ff	r2 += -0x10
      29:	bf a3 00 00 00 00 00 00	r3 = r10
      30:	07 03 00 00 f8 ff ff ff	r3 += -0x8
      31:	18 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00	r1 = 0x0 ll
      33:	b7 04 00 00 00 00 00 00	r4 = 0x0
      34:	85 00 00 00 02 00 00 00	call 0x2
      35:	b7 00 00 00 00 00 00 00	r0 = 0x0
      36:	95 00 00 00 00 00 00 00	exit
```

13行 `call 0x2` 调用 `bpf_map_update_elem`, 21行 `call 0x1` 调用 `bpf_map_lookup_elem` ,
从这两行回去看 key 的构造，可以发现，在2-5行，代码用了两个 u64 来存 `bpf_map_update_elem`
的 key &lt;13, 0&gt; (13 是我们传入的 cgroup id, 0 是 cgroup_path_id 后文我们会讨论)。
在14-16行，我们看到 `bpf_map_lookup_elem` 使用的 key 是 &lt;13, 1&gt; ， \*因为 update 和 lookup
的时候使用了不同的 key，所以在 map 中使用 `cgroup_path` 作为 key 无法达成我们预期的结果\*。


## `cgroup_path` 的实现 {#cgroup-path-的实现}

`cgroup_path` 在 bpftrace 里面其实是一个函数：
\`\`\`shell
cgroup_path(int cgroupid, string filter)
\`\`\`
在生成 IR 过程中，bpftrace 每次遇到 "cgroup_path" 都会创建一个 `CgroupPath` 实例。

```c++
 struct CgroupPath {
  uint64_t cgroup_path_id;
  uint64_t cgroup_id;

  std::vector<llvm::Type*> asLLVMType(ast::IRBuilderBPF& b);
} __attribute__((packed));
```

`cgroup_path_id` 和 `cgroup_id` 是上文提及的两个 u64 变量。

`cgroup_path_id` 其实是一个自增的变量，因为在后面 resource analyse 阶段，
bpftrace 会把 `string filter` （默认的 filter 是"\*"）保存到 `cgroup_path_args` 这个向量里面，
这样我们可以用 `cgroup_path_id` 作为索引找到对应的 filter。

在使用 `cgroup_path` 作为 map key 的情况下，bpf map 里面保存的是 &lt;cgroup_id, cgroup_path_id&gt;
但是 cgroup_path_id 每次都会变动，导致 update 跟 lookup 的 key 不一样。

我尝试绕开这个问题，发现完全绕不开：

1.  去掉 `cgroup_path_id`: 我们完全可能出现同一个 cgroup_id 使用不同 filter 的情况。
2.  直接把 filter 存进来：抛开性能不说，要在 bpf prog 里面存一个字符串，还是只能存一个地址，
    最后还是每个 key 都会变。
3.  在 map 里面只使用 cgroup_id 作为key, 到 output 的时候才去把 cgroup_path_id 联回来。
    老实说，这是最有可能的一种方案，但是 output 的时候，bpftrace 只能读到 key 的数据，
    如果 key 用 cgroup_id 的值，那根本拿不到整个 `CgroupPath` 的信息，如果存 cgroup_id
    的地址——这回到情况2。
4.  在 IR 阶段，把 cgroup_id 和 filter 相同的 `cgroup_path` 对应成同一个 `CgroupPath`,
    你还别说，这个还真的可能可以实现！但我是在写这篇博客的时候想到的，等老衲回去试一试。


## 总结 {#总结}

最后考虑到开发成本和收益，我关掉了这个 PR，但是写完这篇博客之后就有点不同了，没准可以再试一发。

[^fn:1]: 当然也可以使用 `--emit-llvm` 生成 bpftrace clang IR 来分析，
    不过既然这个系列是 ebpf 札记，所以我还是选择分析 bpf 汇编。