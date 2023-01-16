+++
title = "qemu live update 简介"
author = ["Dantezy"]
description = "简单介绍一下 qemu 的 live-update 技术"
date = 2022-05-24
lastmod = 2023-01-16T14:13:51+08:00
tags = ["qemu", "virtualization", "live-update"]
categories = ["code"]
draft = true
+++

:EXPORT_HUGO_CUSTOM_FRONT_MATTER: :show_comments true


## live update patch {#live-update-patch}

这个 patch 是 Oracle 向社区提交的，直到我写这篇文章的时候（<span class="timestamp-wrapper"><span class="timestamp">&lt;2022-05-24 Tue 15:28&gt;</span></span>）还没有合并进 master 分支。

如果想要阅读其中的代码，可以在 [patchwork](https://patchwork.ozlabs.org/project/qemu-devel/list/?series=242677) 看所有提交，非常清楚。如果想把这个 patch 提前合并到自己的 qemu 分支。可以通过

```bash
wget https://patchew.org/QEMU/1640199934-455149-1-git-send-email-steven.sistare@oracle.com/mbox -O live-update.patch

git am --3way live-update.patch
```

合并进去[^fn:1]。


## 基本用法 {#基本用法}


## 代码分析 {#代码分析}

可以去 [patchew](https://patchew.org/QEMU/1640199934-455149-1-git-send-email-steven.sistare@oracle.com) 看这个 patch 的改动。


### memory: qemu_check_ram_volatile {#memory-qemu-check-ram-volatile}

实现了 `qemu_check_ram_volatile` 函数，这个函数会测试每个 `RAMBlock` 是否 volatile. 判断的标准是

> 1.  这个 RAMBlock 的 MemoryRegion 是 RAM；
> 2.  这个 MemoryRegion 不是 RAM device；
> 3.  这个 MemoryRegion 不是 ROM；
> 4.  这个 RAMBlock 的 fd 是 -1 或者这个 MemoryRegion 是 shared；

要搞清楚这个四个条件是什么意思，以及 `RAMBlock` 怎样初始化。

`qemu_ram_foreach_block` 这个函数应该是在 softmmu/physmem.c 中定义， `RAMBLOCK_FOREACH` 这个宏我没有看懂，因为它传入一个 `RAMBlock *` ，它怎么就能遍历所有 `RAMBlock` 呢？


### migration: fix populate_vfio_info {#migration-fix-populate-vfio-info}

我没有读懂这个 patch.


### migration: qemu file wrappers {#migration-qemu-file-wrappers}

这个 patch 定义了 `qemu_file_open` 和 `qemu_fd_open` 两个函数。这两个函数的区别其实就是一个用文件名打开文件，一个是用文件描述符打开。看后面的实现，是因为有一些东西是用文件描述符保存在环境变量里面的。

这个两个函数用了 `qio_channel_file_new_fd` 和 `qio_channel_file_new_path` 感觉就是因为 C 语言没有太多的语法糖，所以有很多宏的复杂实现。无论如何，要看一下 `QIOChannelFile` 的实现。


### migration: simplify savevm {#migration-simplify-savevm}

这就是个人风格问题的修改。


### vl: start on wakeup request {#vl-start-on-wakeup-request}

没看懂。


### cpr: reboot mode {#cpr-reboot-mode}

这个 patch 实现了 `qmp_cpr_save` 和 `qmp_cpr_load` 的一部分。大致的流程已经有了。


#### qmp_cpr_save {#qmp-cpr-save}

首先检查 vm 的运行状态，其实就是检查一个全局变量 `current_run_state` 。

然后调用 [qemu_check_ram_volatile](#memory-qemu-check-ram-volatile) 检查 ram 是否 volatile。还有三个我不太明白的检查。ram validate 的检查跟 qemu 的 memory-backend 有关。

通过检查之后，调用 [qemu_file_open](#migration-qemu-file-wrappers) 打开用来保存 vm 的文件 f。

如果能顺利打开文件，检查是否处于 RUN_STATE_SUSPENDED 状态，如果是，调用 `cpu_disable_ticks` 把虚拟机的 timer 停下来。

然后停下 vm，设置 cpr_state ，将 device_state 写入 f 中。如果保存的过程出错，那么要把 cpr_state 还原成 None，如果之前 vm 处于 RUNNING 状态，那么要调用 `vm_start` 把 vm 重新起起来。


#### qmp_cpr_load {#qmp-cpr-load}

[^fn:1]: qemu 社区用 email 进行管理（包括 PR 和 Code Reivew），如何想 qemu 社区提交 patch 可以参考[官方文档](https://www.qemu.org/docs/master/devel/submitting-a-patch.html)。我入行的时候
    github 已经很普及，所以其实我也不是很熟。年轻人应该多参与开源社区。