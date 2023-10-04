+++
title = "ebpf 札记(3): 一个跟踪 kernel I/O request 生命周期的脚本"
author = ["Dantezy"]
description = "ebpf 札记第三篇。跟踪 kernel I/O request 的生命周期。"
date = 2023-10-04
lastmod = 2023-10-04T11:17:34+08:00
tags = ["ebpf", "kernel"]
categories = ["code"]
draft = false
+++

上周睡眠一直有问题，没有继续看 samples 里面的代码。写点别的来充数。

现在在追踪 kernel I/O request ，一个 request 被创建出来之后，会在多个函数中传递，直到被释放。
这个过程中它被那些内核函数调用？这是一个复杂的问题。幸好很多处理 request 的函数都是以 `struct request*` 作为入参，
这给我们一个跟踪 request 的思路。

同样的思路我还用来跟踪 nginx 里面的运行过程。

```shell
#!/usr/bin/env bpftrace

kretprobe:blk_mq_alloc_request
{
  if (@req == 0) {
    @req = retval;
    printf("%llu, %d,  %s\n", (struct request *)@req, pid, probe);
    printf("comm: %s, kstack: \n%s\n", comm, kstack);
  }
  if (retval == @req) {
    printf("duplicated req: %d, %llu\n", pid, @req);
  }
}

kprobe:blk_*
{
  if (@req != 0) {
    if (arg1 == @req || arg0 == @req) {
      $rid = arg0;
      if (arg1 == @req) {
	$rid = arg1
      }
      printf("%llu, %s\n", (struct request *)$rid, probe);
    }
  }
}

kprobe:blk_mq_get_driver_tag, k:blk_mq_start_request, k:blk_add_timer, k:blk_mq_complete_request,
     k:blk_update_request, k:blk_stat_add, k:blk_account_io_done, k:blk_put_request, k:blk_mq_free_request
{
  if (@req != 0) {
    if (arg1 == @req || arg0 == @req) {
      print("%llu, %s\n%s\n", @req, probe, kstack);
    }
  }
}

kprobe:blk_mq_free_request
{
  @req = 0;
}
```

现在 bpftrace 的 kprobe section 不支持更复杂的匹配方式，倒是挺遗憾的。我想
「匹配所有 blk\_ 开头的 kprobe 但是 blk_mq_free_request 除外」，但是没有找到方法实现。

TODO:

1.  为什么 `blk_mq_alloc_request` 会重入？