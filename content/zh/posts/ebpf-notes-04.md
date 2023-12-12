+++
title = "ebpf 札记(4): 用 ebpf 侦测函数内部的状态"
author = ["Dantezy"]
description = "ebpf 札记第四篇。这个系列停更了好久啊。讨论一下如何用 ebpf 侦测函数内部的状态。"
date = 2023-12-12
lastmod = 2023-12-12T23:23:33+08:00
tags = ["ebpf", "kernel"]
categories = ["code"]
draft = false
+++

## Introduction {#introduction}

为了行文方便，probe 这个词我就翻译为侦测了。

使用 ebpf 可以很方便地获取被侦测函数的入参（当然大于6个的时候还是有麻烦）和返回值。但如果我们需要获知函数内部的状态呢？

如果我们需要知道函数内部的临时变量，还有函数调用别的函数时候的入参，ebpf 还是可以做到的。主要思路如下：

1.  ebpf 可以挂载到函数的某个 offset;
2.  ebpf 可以读到寄存器；
3.  如果我们知道函数某个 offset 的时候，变量保存在哪个寄存器或者在栈的某个位置，那么我们可以通过寄存器拿到变量的值；

下面通过一个具体的例子来说明如何侦测函数内部状态。


## Example {#example}

```c
#include <stdio.h>
#include <unistd.h>
#include <string.h>

struct exp_s {
  int num;
  char name[35];
};

void accept_exp(struct exp_s *t) {
  char name[35];
  int a;
  memcpy(name, t->name, 35);
  printf("num: %d, name %s\n", t->num, name);
  a = t->num;
  printf("a: %d\n", a);
}

int main() {
  struct exp_s s = {
    .num = 1,
    .name = "keqing",
  };

  while(1) {
    s.num ++;
    accept_exp(&s);
    sleep(5);
  }

  return 0;
}
```

假设我想知道变量 `name` 和 `a` 在函数 `accept_exp` 中的值（当然实际上 `name` 在这里是一个地址，但为了行文简便我就这么说了），
那么我可以这样做：

首先，disas `accept_exp` 函数。

```bash
gdb -batch -ex 'disas accept_exp' exp
Dump of assembler code for function accept_exp:
   0x0000000000001189 <+0>:     endbr64
   0x000000000000118d <+4>:     push   %rbp
   0x000000000000118e <+5>:     mov    %rsp,%rbp
   0x0000000000001191 <+8>:     push   %rbx
   0x0000000000001192 <+9>:     sub    $0x58,%rsp
   0x0000000000001196 <+13>:    mov    %rdi,-0x58(%rbp)
   0x000000000000119a <+17>:    mov    %fs:0x28,%rax
   0x00000000000011a3 <+26>:    mov    %rax,-0x18(%rbp)
   0x00000000000011a7 <+30>:    xor    %eax,%eax
   0x00000000000011a9 <+32>:    mov    -0x58(%rbp),%rax
   0x00000000000011ad <+36>:    add    $0x4,%rax
   0x00000000000011b1 <+40>:    mov    (%rax),%rcx
   0x00000000000011b4 <+43>:    mov    0x8(%rax),%rbx
   0x00000000000011b8 <+47>:    mov    %rcx,-0x40(%rbp)
   0x00000000000011bc <+51>:    mov    %rbx,-0x38(%rbp)
   0x00000000000011c0 <+55>:    mov    0x10(%rax),%rcx
   0x00000000000011c4 <+59>:    mov    0x18(%rax),%rbx
   0x00000000000011c8 <+63>:    mov    %rcx,-0x30(%rbp)
   0x00000000000011cc <+67>:    mov    %rbx,-0x28(%rbp)
   0x00000000000011d0 <+71>:    movzwl 0x20(%rax),%edx
   0x00000000000011d4 <+75>:    mov    %dx,-0x20(%rbp)
   0x00000000000011d8 <+79>:    movzbl 0x22(%rax),%eax
   0x00000000000011dc <+83>:    mov    %al,-0x1e(%rbp)
   0x00000000000011df <+86>:    mov    -0x58(%rbp),%rax
   0x00000000000011e3 <+90>:    mov    (%rax),%eax
   0x00000000000011e5 <+92>:    lea    -0x40(%rbp),%rdx
   0x00000000000011e9 <+96>:    mov    %eax,%esi
   0x00000000000011eb <+98>:    lea    0xe12(%rip),%rdi        # 0x2004
   0x00000000000011f2 <+105>:   mov    $0x0,%eax
   0x00000000000011f7 <+110>:   callq  0x1080 <printf@plt>
   0x00000000000011fc <+115>:   mov    -0x58(%rbp),%rax
   0x0000000000001200 <+119>:   mov    (%rax),%eax
   0x0000000000001202 <+121>:   mov    %eax,-0x44(%rbp)
   0x0000000000001205 <+124>:   mov    -0x44(%rbp),%eax
   0x0000000000001208 <+127>:   mov    %eax,%esi
   0x000000000000120a <+129>:   lea    0xe05(%rip),%rdi        # 0x2016
   0x0000000000001211 <+136>:   mov    $0x0,%eax
   0x0000000000001216 <+141>:   callq  0x1080 <printf@plt>
   0x000000000000121b <+146>:   nop
   0x000000000000121c <+147>:   mov    -0x18(%rbp),%rax
   0x0000000000001220 <+151>:   xor    %fs:0x28,%rax
   0x0000000000001229 <+160>:   je     0x1230 <accept_exp+167>
   0x000000000000122b <+162>:   callq  0x1070 <__stack_chk_fail@plt>
   0x0000000000001230 <+167>:   add    $0x58,%rsp
   0x0000000000001234 <+171>:   pop    %rbx
   0x0000000000001235 <+172>:   pop    %rbp
   0x0000000000001236 <+173>:   retq
End of assembler dump.
```

可以看到 `0x00000000000011f7 <+110>:   callq  0x1080 <printf@plt>` 在这里， `name` 会作为第三个参数传入 `printf` 里面。
所以我们可以知道，需要看 `%rdx` 寄存器[^fn:1]。至于 `a` 可以从 `0x0000000000001216 <+141>:   callq  0x1080 <printf@plt>`
往上找，看到它在栈里的位置 `-0x44(%rbp)` ，我们读这个位置就好。

```bpftrace
#!/usr/bin/env bpftrace

uprobe:./exp:accept_exp+110
{
  $di = reg("di");
  $char_di = (uint8 *)$di;
  $dx = reg("dx");
  $char_dx = (uint8 *)$dx;
  if ($di > 0) {
    printf("di: %lu, pointer: %lu, str: %s\n", $di, $char_di, str($char_di));
    printf("dx: %lu, pointer: %lu, str: %s\n", $dx, $char_dx, str($char_dx));
  } else {
    print("no ax value get");
  }
}

uprobe:./exp:accept_exp+141
{
  $bp = reg("bp");
  $local_va = $bp - 0x44;
  $si = reg("si");
  printf("local_va: %d/%d, si: %d\n",$local_va, *($local_va), $si);
}
```

这样我们可以知道 `name` 的内容和 `a` 的值了。


## Epilogue {#epilogue}

当然这个例子很取巧，主要是这两个变量的位置我都很清楚，更复杂的函数需要花费更多时间去理解汇编代码[^fn:2]。

[^fn:1]: 注意 bpftrace 支持的 x86 寄存器名字不是常规的 eax, rdx 等，而是 ax, dx 这样的。见[源码](https://github.com/iovisor/bpftrace/blob/45617cd40d5314cd98fa74560d8c980e4a417463/src/arch/x86_64.cpp)。
[^fn:2]: 学习 x86_64 汇编算是今年最有效的投入了，[x86-64 Assembly Language Programming with Ubuntu](http://www.egr.unlv.edu/~ed/x86.html) 这本书可以算我年度之书。