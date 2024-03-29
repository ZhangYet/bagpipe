+++
title = "Summerize network throughput by ebpf"
author = ["Dantezy"]
description = "Use ebpf to summerize network throughput on ipv6."
date = 2022-01-18
lastmod = 2023-01-25T18:05:30+08:00
tags = ["ebpf", "kernel", "ipv6"]
categories = ["code"]
draft = false
+++

## TL;DR {#tl-dr}

1.  use `bpf_probe_read_kernel()` to read structs in the kernel.
2.  in a sense, debuging it to printing. Writing a bcc script to test your ebpf_exporter script is a good debugging method.


## The problem {#the-problem}

We have servers in different zones, which have different subnets. We want to use [ebpf_exporter](https://github.com/cloudflare/ebpf_exporter)[^fn:1] to monitor network throughput from subnet1 to subnet2.
So I have to write some [bcc](https://github.com/iovisor/bcc) scripts.

Some tcp throughput is sent from subnet1 to subnet2 using ipv6. But the servers don't have real ipv6 addresses, they have ipv4 addresses embedded in ipv6[^fn:2].

```text
::ffff:192.168.9.255
```

<div class="src-block-caption">
  <span class="src-block-number">Code Snippet 1:</span>
  A manual exmaple of an ipv4 address embedded in ipv6
</div>

I have two missions:

1.  filter and summerise the throughput by subnets.
2.  get the ipv4 address from the ipv6 then filter and summerise by subnets.


## Development phase {#development-phase}


### Copy and paste phase {#copy-and-paste-phase}

epbf itself is very simple[^fn:3]. Using it is difficult. The difficulty is that you have know about the probe in the kernel.
The main problem is where to probe.

The [bcc/tools](https://github.com/iovisor/bcc/tree/master/tools) is a good example to learn(ok, it's copy-and-paste).

[tcpsubnet](https://github.com/iovisor/bcc/blob/master/tools/tcpsubnet.py) and [tcptop](https://github.com/iovisor/bcc/blob/master/tools/tcptop.py) are the most useful examples. From these two scripts, I know that:

1.  we need to attach kprobes to `tcp_sendmsg` and `tcp_cleanup_rbuf`.
2.  we can get the ip info from `struct sock`.

The ipv4 mission is simple.

```yaml
programs:
  - name: container-tcptop-by-subnet
    metrics:
      counters:
	- name: ipv4_send_bytes_by_subnet
	  help: Summarize TCP send throughput by subnet.
	  table: ipv4_send_bytes
	  labels:
	    - name: subnet
	      size: 32
	      decoders:
		- name: string
	- name: ipv4_recv_bytes_by_subnet
	  help: Summarize TCP recv throughput by subnet.
	  table: ipv4_recv_bytes
	  labels:
	    - name: subnet
	      size: 32
	      decoders:
		- name: string
    kprobes:
      tcp_sendmsg: tcp_sendmsg
      tcp_cleanup_rbuf: tcp_cleanup_rbuf
    code: |
      #include <linux/nsproxy.h>
      #include <linux/mount.h>
      #include <linux/ns_common.h>
      #include <uapi/linux/ptrace.h>
      #include <net/sock.h>
      #include <bcc/proto.h>
      #define CONTAINER_ID_LEN 128
      #define TARGET_IP_SUBNET 0xA90A // 10.169.0.0/16
      #define TARGET_MASK  0xFFFF // 16
      #define TARGET_IP_SUBNET_TAG "10.169.0.0/16"
      struct subnet_key {
	  char subnet[32];
      };
      BPF_HASH(ipv4_send_bytes, struct subnet_key);
      BPF_HASH(ipv4_recv_bytes, struct subnet_key);

      int tcp_sendmsg(struct pt_regs *ctx, struct sock *sk,
	  struct msghdr *msg, size_t size)
      {
	  u32 pid = bpf_get_current_pid_tgid() >> 32;
	  u16 family = sk->__sk_common.skc_family;

	  if (family == AF_INET) {
	      u32 dst = sk->__sk_common.skc_daddr;
	      if ((TARGET_IP_SUBNET & TARGET_MASK) == (dst & TARGET_MASK)) {
		struct subnet_key skey = {.subnet = TARGET_IP_SUBNET_TAG};
		ipv4_send_bytes.increment(skey, size);
	      }
	  }
	  // else drop
	  return 0;
      }

      int tcp_cleanup_rbuf(struct pt_regs *ctx, struct sock *sk, int copied)
      {
	  u32 pid = bpf_get_current_pid_tgid() >> 32;
	  u16 family = sk->__sk_common.skc_family;
	  u64 *val, zero = 0;
	  if (copied <= 0)
	      return 0;
	  if (family == AF_INET) {
	      u32 src = sk->__sk_common.skc_addr;
	      if ((TARGET_IP_SUBNET & TARGET_MASK) == (src & TARGET_MASK)) {
		struct subnet_key skey = {.subnet = TARGET_IP_SUBNET_TAG};
		ipv4_recv_bytes.increment(skey, copied);
	      }
	  }
	  // else drop
	  return 0;
      }

```

Following this idea, I wrote the code for the ipv6 part.

```c
if (family == AF_INET6) {
  u8 remote_ip[2];
  remote_ip[0] = sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8[12];
  if ((remote_ip[0] & MASK0_FOR_IPV6) != SUBNET0) {
    return 0;
  }
  remote_ip[1] = sk->__sk_common.skc_v6_rcv_saddr.in6_u.u6_addr8[13];
  if ((remote_ip[1] & MASK1_FOR_IPV6) != SUBNET1) {
    return 0;
  }
  struct subnet_key skey = {.subnet = TARGET_IP_SUBNET_TAG};
  ipv6_send_bytes.increment(skey, size);
}
```

But when I tested, I didn't get any data for ipv6 throughput. But when I deleted the if part, the test server did have ipv6 throughput.

What happened?


### Write a bpftrace script {#write-a-bpftrace-script}

Since we cannot use [bpf_trace_printk()](https://github.com/iovisor/bcc/blob/master/docs/reference_guide.md#1-bpf_trace_printk) in ebpf_exporter, I don't know what happened in the if statement `if ((remote_ip[0] & MASK0_FOR_IPV6) != SUBNET0)`.
I decided to write a bpftrace script to test this.

```nil
#!/usr/bin/env bpftrace

#include <net/sock.h>
#include <net/sock.h>

kprobe:tcp_sendmsg
{
  $sk = (struct sock *)arg0;
  $dst = $sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8;

  $fm = $sk->__sk_common.skc_family;
  if ( $1 > 0 ) {
    if ( pid != $1 ) {
      return;
    }
  }

  if ( $fm == AF_INET6) {
    if (( ($dst[12] & 255) == 192 ) && ( ($dst[13] & 255) == 168 )) {
	printf("dst12: %d, dst13: %d\n", $dst[12] & 255, $dst[13] & 255);
	printf("pid %d, dst: %d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d \n", pid,
	   $dst[0],$dst[1],$dst[2],$dst[3],$dst[4],$dst[5],$dst[6],$dst[7],
	   $dst[8],$dst[9],$dst[10],$dst[11],$dst[12],$dst[13],$dst[14],$dst[15]);
      }
  }
}

kprobe:tcp_cleanup_rbuf
{
  $sk = (struct sock *)arg0;
  $dst = $sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8;

  $fm = $sk->__sk_common.skc_family;
  if ( $1 > 0 ) {
    if ( pid != $1 ) {
      return;
    }
  }

  if ( $fm == AF_INET6 ) {
    if (( ($dst[12] & 255) == 192 ) && ( ($dst[13] & 255) == 168 )) {
	printf("dst12: %d, dst13: %d\n", $dst[12] & 255, $dst[13] & 255);
	printf("pid %d, dst: %d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d \n", pid,
	   $dst[0],$dst[1],$dst[2],$dst[3],$dst[4],$dst[5],$dst[6],$dst[7],
	   $dst[8],$dst[9],$dst[10],$dst[11],$dst[12],$dst[13],$dst[14],$dst[15]);
    }
  }
}

```

To my suprise, this script showed a normal ipv6 address!


### Debug {#debug}

Why did bpftrace and ebpf_exporter give different results using the same logic?
I don't know why. But it occurred to me that even though `bpf_trace_printk()` is of no use in ebpf_exporter,
why not write a bcc script to check the result?

```python
#!/usr/bin/python
from bcc import BPF

src = '''
#include <net/sock.h>
int kprobe__tcp_sendmsg(struct pt_regs *ctx, struct sock *sk,
	  struct msghdr *msg, size_t size)
{
    u16 family = sk->__sk_common.skc_family;
    if (family == AF_INET6) {
	bpf_trace_printk("Debug %d \\n", sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8[0]);
	bpf_trace_printk("Debug %d \\n", sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8[1]);
	bpf_trace_printk("Debug %d \\n", sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8[2]);
	bpf_trace_printk("Debug %d \\n", sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8[3]);
	bpf_trace_printk("Debug %d \\n", sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8[4]);
	bpf_trace_printk("Debug %d \\n", sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8[5]);
	bpf_trace_printk("Debug %d \\n", sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8[6]);
	bpf_trace_printk("Debug %d \\n", sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8[7]);
	bpf_trace_printk("Debug %d \\n", sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8[8]);
	bpf_trace_printk("Debug %d \\n", sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8[9]);
	bpf_trace_printk("Debug %d \\n", sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8[10]);
	bpf_trace_printk("Debug %d \\n", sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8[11]);
	bpf_trace_printk("Debug %d \\n", sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8[12]);
	bpf_trace_printk("Debug %d \\n", sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8[13]);
	bpf_trace_printk("Debug %d \\n", sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8[14]);
	bpf_trace_printk("Debug %d \\n", sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8[15]);

	bpf_trace_printk("rcvDebug %d \\n", sk->__sk_common.skc_v6_rcv_saddr.in6_u.u6_addr8[0]);
	bpf_trace_printk("rcvDebug %d \\n", sk->__sk_common.skc_v6_rcv_saddr.in6_u.u6_addr8[1]);
	bpf_trace_printk("rcvDebug %d \\n", sk->__sk_common.skc_v6_rcv_saddr.in6_u.u6_addr8[2]);
	bpf_trace_printk("rcvDebug %d \\n", sk->__sk_common.skc_v6_rcv_saddr.in6_u.u6_addr8[3]);
	bpf_trace_printk("rcvDebug %d \\n", sk->__sk_common.skc_v6_rcv_saddr.in6_u.u6_addr8[4]);
	bpf_trace_printk("rcvDebug %d \\n", sk->__sk_common.skc_v6_rcv_saddr.in6_u.u6_addr8[5]);
	bpf_trace_printk("rcvDebug %d \\n", sk->__sk_common.skc_v6_rcv_saddr.in6_u.u6_addr8[6]);
	bpf_trace_printk("rcvDebug %d \\n", sk->__sk_common.skc_v6_rcv_saddr.in6_u.u6_addr8[7]);
	bpf_trace_printk("rcvDebug %d \\n", sk->__sk_common.skc_v6_rcv_saddr.in6_u.u6_addr8[8]);
	bpf_trace_printk("rcvDebug %d \\n", sk->__sk_common.skc_v6_rcv_saddr.in6_u.u6_addr8[9]);
	bpf_trace_printk("rcvDebug %d \\n", sk->__sk_common.skc_v6_rcv_saddr.in6_u.u6_addr8[10]);
	bpf_trace_printk("rcvDebug %d \\n", sk->__sk_common.skc_v6_rcv_saddr.in6_u.u6_addr8[11]);
	bpf_trace_printk("rcvDebug %d \\n", sk->__sk_common.skc_v6_rcv_saddr.in6_u.u6_addr8[12]);
	bpf_trace_printk("rcvDebug %d \\n", sk->__sk_common.skc_v6_rcv_saddr.in6_u.u6_addr8[13]);
	bpf_trace_printk("rcvDebug %u \\n", sk->__sk_common.skc_v6_rcv_saddr.in6_u.u6_addr8[14]);
	bpf_trace_printk("rcvDebug %u \\n", sk->__sk_common.skc_v6_rcv_saddr.in6_u.u6_addr8[15]);

    }
    return 0;
}
'''
# This may not work for 4.17 on x64, you need replace kprobe__sys_clone with kprobe____x64_sys_clone
BPF(text=src).trace_print()

```

Use `nc -6 -l ::1 10096` to set a server and `nc -6 localhost 10096` to connect the server and send data over ipv6. What I got is shown as below:

```shell
b'              nc-401206  [003] .... 33610.016579: 0: Debug 0'
b'              nc-401206  [003] .... 33610.016614: 0: Debug 0'
b'              nc-401206  [003] .... 33610.016614: 0: Debug 0'
b'              nc-401206  [003] .... 33610.016615: 0: Debug 133'
b'              nc-401206  [003] .... 33610.016615: 0: Debug 255'
b'              nc-401206  [003] .... 33610.016615: 0: Debug 0'
b'              nc-401206  [003] .... 33610.016616: 0: Debug 152'
b'              nc-401206  [003] .... 33610.016616: 0: Debug 0'
b'              nc-401206  [003] .... 33610.016616: 0: Debug 176'
b'              nc-401206  [003] .... 33610.016617: 0: Debug 0'
b'              nc-401206  [003] .... 33610.016618: 0: Debug 208'
b'              nc-401206  [003] .... 33610.016618: 0: Debug 0'
b'              nc-401206  [003] .... 33610.016618: 0: Debug 0'
b'              nc-401206  [003] .... 33610.016618: 0: Debug 4'
b'              nc-401206  [003] .... 33610.016619: 0: Debug 0'
b'              nc-401206  [003] .... 33610.016619: 0: Debug 0'
b'              nc-401206  [003] .... 33610.016619: 0: rcvDebug 0'
b'              nc-401206  [003] .... 33610.016620: 0: rcvDebug 0'
b'              nc-401206  [003] .... 33610.016620: 0: rcvDebug 133'
b'              nc-401206  [003] .... 33610.016621: 0: rcvDebug 255'
b'              nc-401206  [003] .... 33610.016621: 0: rcvDebug 0'
b'              nc-401206  [003] .... 33610.016621: 0: rcvDebug 152'
b'              nc-401206  [003] .... 33610.016622: 0: rcvDebug 0'
b'              nc-401206  [003] .... 33610.016622: 0: rcvDebug 176'
b'              nc-401206  [003] .... 33610.016622: 0: rcvDebug 0'
b'              nc-401206  [003] .... 33610.016623: 0: rcvDebug 208'
b'              nc-401206  [003] .... 33610.016623: 0: rcvDebug 0'
b'              nc-401206  [003] .... 33610.016623: 0: rcvDebug 0'
b'              nc-401206  [003] .... 33610.016624: 0: rcvDebug 4'
b'              nc-401206  [003] .... 33610.016624: 0: rcvDebug 0'
b'              nc-401206  [003] .... 33610.016624: 0: rcvDebug 0'
b'              nc-401206  [003] .... 33610.016625: 0: rcvDebug 0'
```

Wait, what is that? I suppose to get something that stands for ::1! After looking at this output, I understood that my problem was not in the if statement, but
in `remote_ip[0] = sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8[12];` ! Check the struct of `__sk_common` in kernel source code:

```c
  struct sock_common {
	/* skc_daddr and skc_rcv_saddr must be grouped on a 8 bytes aligned
	 * address on 64bit arches : cf INET_MATCH()
	 */
	union {
		__addrpair	skc_addrpair;
		struct {
			__be32	skc_daddr;
			__be32	skc_rcv_saddr;
		};
	};
    // ...

#if IS_ENABLED(CONFIG_IPV6)
	struct in6_addr		skc_v6_daddr;
	struct in6_addr		skc_v6_rcv_saddr;
    // ...
    }
```

The `skc_daddr` is a value but `skc_v6_dadder` is a struct. We should use [bpf_probe_read_kernel()](https://github.com/iovisor/bcc/blob/master/docs/reference_guide.md#1-bpf_probe_read_kernel) to read it. So the final solution is as follows:

```c
if (family == AF_INET6) {
  u8 ip1, ip2, ipv6[16];
  bpf_probe_read_kernel(&ipv6, sizeof(ipv6),
			sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8);
  ip1 = ipv6[12], ip2 = ipv6[13];
  if ((ip1 == SUBNET0) && (ip2 == SUBNET1)) {
	struct subnet_key skey = {.subnet = TARGET_IP_V6_SUBNET_TAG, .pid = pid};
	u64 *val, zero = 0, s = (u64)size;
	val = ipv6_send_bytes.lookup_or_try_init(&skey, &zero);
	if (val) {
	  (*val) += s;
	}
  }
}
```

Test passed.

[^fn:1]: The ebpf_exporter 2.0 has been migrated from BCC to libbpf, see [the release note of ebpf_exporter 2.0](https://github.com/cloudflare/ebpf_exporter/releases/tag/v2.0.0).
[^fn:2]: I don't know why.
[^fn:3]: See [the man page of bpf()](https://man7.org/linux/man-pages/man2/bpf.2.html), only six commands for the `bpf()` syscall. I'm going to write another blog to analyse the source code of `bpf()`.