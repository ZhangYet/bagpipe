+++
title = "debian 包的依赖问题"
author = ["Dantezy"]
description = "为 bpftrace 打包遇到的依赖问题以及解决方案。"
date = 2022-06-09
lastmod = 2022-06-10T15:22:37+08:00
tags = ["debian", "package"]
categories = ["code"]
draft = false
+++

## 背景 {#背景}

最近我要把 Ubuntu 社区的 bpftrace 包迁移到公司内部发版，所以我从社区将 bpftrace 的[源代码](https://salsa.debian.org/debian/bpftrace.git)[^fn:1]挪到公司内部的 gitlab 开始自己打包。

目前公司使用的主流 Linux 发行版本是 Ubuntu 20.04，所以我也是从 bpfttrace 0.9.4 版本着手编译[^fn:2]。


## 问题 {#问题}

bpftrace 源代码里面提供了 `build.sh` ，可以直接用 alpine 镜像构建可执行文件。同时它也提供了 ubuntu:bionic Dockerfile 。于是我首先想到按照 docker/Dockerfile.bionic 构建了一个新的 package 镜像。
这个镜像从 ubuntu:bionic 出发，安装了编译所需的依赖以及打包所需的 devscripts 等工具。

使用这个镜像可以顺利编译出 debian 包。但是在安装的时候，会因为 libbinutils 的依赖，无法成功安装。

从 Ubuntu packages 查询可知（当然用 apt 查也行）， libbinutils 在 Ubuntu 20.04 上的版本是 2.34-6ubuntu1，而我打出来的包要求的版本是：

```bash
dpkg-deb -I bpftrace_0.9.4-1_amd64.deb

...
Depends: libbcc, libbinutils (>= 2.30), libbinutils (<< 2.30.1), libc6 (>= 2.27), libclang1-9 (>= 1:9~svn359771-1~), libgcc1 (>= 1:3.0), libllvm9 (>= 1:9~svn298832-1~)
...
```

这里要求 libbinutils 的版本小于 2.30.1 场面有点尴尬。


## debian 包如何控制依赖 {#debian-包如何控制依赖}

bpftrace 源代码的 debian/control 给出的依赖项如下：

```nil
Depends: ${misc:Depends}, ${shlibs:Depends}
```

这是 [substvar](https://www.debian.org/doc/manuals/debmake-doc/ch05.en.html#substvar)，具体的值会在打包的过程中计算。其中 libbinutils 由 `${shlibs:Depends}` 给出，而 `${shlibs:Depends}` 是由 dh_shlibdeps&nbsp;[^fn:3]给出的。实际上 dh_shlibdeps 只是封装了 dpkg-shlibdeps。

```bash
dpkg-shlibdeps -Tdebian/bpftrace.substvars debian/bpftrace/usr/bin/bpftrace
```

这个命令从编译出来的 bpftrace 中扫描所有依赖的符号表，顺着这个符号表去找对应 library 文件。在 Ubuntu 20.04 环境下执行这条命令，会得到如下错误：

```text
dpkg-shlibdeps: error: cannot find library libbfd-2.30-system.so needed by debian/bpftrace/usr/bin/bpftrace (ELF format: 'elf64-x86-64' abi: '0201003e00000000'; RPATH: '')
dpkg-shlibdeps: error: cannot find library libopcodes-2.30-system.so needed by debian/bpftrace/usr/bin/bpftrace (ELF format: 'elf64-x86-64' abi: '0201003e00000000'; RPATH: '')
```

用 `dpkg -S` 查询，libbfd 和 libopcodes 由 libbinutils 提供的，这解释了 libbinutils (&lt;&lt; 2.30.1) 的来由。


## 标准答案 {#标准答案}

之所以 dh_shlibdeps 会找 2.30 版本的 libbfd 和 libopcodes 是因为我在 Ubuntu 18.04 镜像下编译，所以换成 Ubuntu 20.04 镜像。我打了一个 [docker image](https://hub.docker.com/repository/docker/dantezhang/ubuntu2004-packaging) 作为后续一系列打包工作的起点。

```nil
FROM ubuntu:focal

RUN sed -i 's/^# deb-src/deb-src/' /etc/apt/sources.list && \
    apt update && \
    DEBIAN_FRONTEND=noninteractive TZ=Asia/Singapore apt -y install devscripts build-essential
```

这个镜像做的事情很简单：添加 deb-src 因为 `apt build-dep` 需要，安装 devscripts 和 build-essential 。

真正进行打包工作的时候，我会从这个 image 出发，把源代码挂到容器中，执行

```nil
apt build-dep -y bpftrace
debuild -us -uc -b
```

这是 Debian 社区的标准流程，见 [Debian Packaging Tutorial](https://www.debian.org/doc/manuals/packaging-tutorial/packaging-tutorial.en.pdf)。


## 岔路 {#岔路}

我之前做过给 qemu 打包的工作，但是当时 qemu 被静态编译成一个单独的可执行文件 ，我没有用标准的打包流程去打包。所以这次我一开始也没有用社区的标准流程去打包。

为了解决 libbinutils 的依赖问题，我尝试过如下失败的解决方案：

1.  把编译的镜像从 Ubuntu 18.04 换成 Ubuntu 20.04，直接这样换编译会失败；
2.  把 libbinutils 2.34 手动编译到 Ubuntu 18.04 里面；

另外我还想到一个比较脏的解决方法：在 `debuild -us -uc -b` 打包之后，手动把 bpftrace.substvars 里面的 libbinutils (&lt;&lt; 2.30.1) 删掉，再执行

```bash
dh_shlibdeps
dh_installdeb
dh_gencontrol
dh_md5sums
dh_builddeb
```

总的来说，君子行不由径，没什么特殊需要的话，还是按照社区的标准流程走好。


## 附录 {#附录}

```nil
FROM ubuntu:bionic

ARG LLVM_VERSION
ENV LLVM_VERSION=$LLVM_VERSION

RUN apt-get update && apt-get install -y curl gnupg &&\
    llvmRepository="\n\
deb http://apt.llvm.org/bionic/ llvm-toolchain-bionic main\n\
deb-src http://apt.llvm.org/bionic/ llvm-toolchain-bionic main\n\
deb http://apt.llvm.org/bionic/ llvm-toolchain-bionic-${LLVM_VERSION} main\n\
deb-src http://apt.llvm.org/bionic/ llvm-toolchain-bionic-${LLVM_VERSION} main\n" &&\
    echo $llvmRepository >> /etc/apt/sources.list && \
    curl -L https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add - && \
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 4052245BD4284CDD && \
    apt-get install -y software-properties-common && \
    add-apt-repository -y ppa:team-xbmc/ppa && \
    echo "deb https://repo.iovisor.org/apt/bionic bionic main" | tee /etc/apt/sources.list.d/iovisor.list

RUN apt-get update && apt-get install -y \
      bison \
      binutils-dev \
      cmake \
      flex \
      g++ \
      git \
      libelf-dev \
      zlib1g-dev \
      libbcc \
      clang-${LLVM_VERSION} \
      libclang-${LLVM_VERSION}-dev \
      libclang-common-${LLVM_VERSION}-dev \
      libclang1-${LLVM_VERSION} \
      llvm-${LLVM_VERSION} \
      llvm-${LLVM_VERSION}-dev \
      llvm-${LLVM_VERSION}-runtime \
      libllvm${LLVM_VERSION} \
      systemtap-sdt-dev \
      python3 \
      debhelper \
      libgmock-dev \
      curl \
      devscripts && \
     mkdir /build/
```

<div class="src-block-caption">
  <span class="src-block-number">Code Snippet 1:</span>
  最初用来打包的 Dockerfile
</div>

[^fn:1]: Ubuntu 等发行版的社区会维护自己的代码版本，主要是在上游代码中添加编译和打包的配置（Ubuntu 和 Debian 社区会增加一个 deiban 文件夹）。
[^fn:2]: 见 [Ubuntu packages](https://packages.ubuntu.com/search?keywords=bpftrace) 的查询结果。
[^fn:3]: 当然 dh_shilbdeps 是 debuild 调用的。可以从 debuild 的日志看到。