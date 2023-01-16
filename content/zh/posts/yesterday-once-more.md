+++
title = "博客迁移日记"
author = ["Dantezy"]
description = "简单讲述一下博客迁移的过程。"
date = 2022-05-19
lastmod = 2023-01-17T02:35:13+08:00
tags = ["log"]
categories = ["log"]
draft = false
+++

## 缘起 {#缘起}

我的[博客](https://zhangyet.github.io/)原来用 git-page 部署。 因为去年我转岗到了新加坡，所以我有了方便的支付手段，于是我买了虚拟机和域名，把博客迁移到现在的域名上。

选择 [hugo](https://gohugo.io/) 生成网页是受[《博客从 hexo 迁移到 hugo》](https://zilongshanren.com/post/move-from-hexo-to-hugo/)影响，主要因为 [ox-hugo](https://ox-hugo.scripter.co/) 可以让我用 org-mode 写博客。博客的主题是 [eureka](https://github.com/wangchucheng/hugo-eureka)，选这个主题的原因一是它比较简洁，二是因为它的名字[^fn:1]。


## 进度 {#进度}

<span class="timestamp-wrapper"><span class="timestamp">[2022-03-18 Fri] </span></span> 在 DigitalOcean 上购买了服务器。

<span class="timestamp-wrapper"><span class="timestamp">[2022-03-19 Sat] </span></span> 决定使用 Hugo，原因如上。

<span class="timestamp-wrapper"><span class="timestamp">[2022-03-20 Sun] </span></span> 买了域名。

<span class="timestamp-wrapper"><span class="timestamp">[2022-03-21 Mon] </span></span> 请教 [wzyboy](https://wzyboy.im/) 如何部署博客，采用 nginx + 静态生成网页的方案。

<span class="timestamp-wrapper"><span class="timestamp">[2022-04-03 Sun] </span></span> 装了 ox-hugo 学习用 org-mode 写博客。

<span class="timestamp-wrapper"><span class="timestamp">[2022-05-14 Sat] </span></span> 更新个人简介。

<span class="timestamp-wrapper"><span class="timestamp">[2022-05-19 Thu] </span></span> 写这篇迁移日记

<span class="timestamp-wrapper"><span class="timestamp">[2022-05-22 Sun] </span></span> 用 [Let's Encrypt](https://letsencrypt.org/) 开启了 https 支持。

<span class="timestamp-wrapper"><span class="timestamp">[2023-01-16 Mon] </span></span> 配置了评论系统，用的是 valine。

<span class="timestamp-wrapper"><span class="timestamp">[2023-01-17 Tue] </span></span> 改用 utterances 作为评论系统，因为 valine 评论发不出去。


## 旧文存档 {#旧文存档}

古人云：「愧其少作」。我本来想把过去的一些旧文迁移过来，但是翻了一下以前的文章，着实没有太多好的。所以在这里列一下就算了。当然有少数文章我写的时候还是动了脑子的，所以可能会修改一下，重新在这里发布。

1.  [《日月忽其不奄兮，春与秋其代序》](https://zhangyet.github.io/archivers/summary2021) 这是我2021年的年度总结。
2.  [《脱口秀狂想》](https://zhangyet.github.io/archivers/talkshow)算是比较严肃的脱口秀评论。
3.  [《我的减肥之道》](https://zhangyet.github.io/archivers/my-way-to-weight-loss)我减肥是成功了，虽然维持体重比较麻烦，但我最近(<span class="timestamp-wrapper"><span class="timestamp">&lt;2022-05-19 Thu 16:19&gt;</span></span>)在一本书（《饮食的迷思》），可能我会更新一下里面的观点。
4.  [《鹰翔地海》](https://zhangyet.github.io/archivers/a-wizard-of-earthsea)《地海巫师》的读后感，想法很多但是我没有整理好，这本书我一读再读，之后应该会重新写。
5.  [《论996与内卷》](https://zhangyet.github.io/archivers/on-996-and-involution)这篇写得比较用心，不过没有聚焦在一个中心论点上，所以显得有点凌乱。
6.  [《开往无锡的列车》](https://zhangyet.github.io/archivers/the-train-to-wuxi)、[《无锡游记》](https://zhangyet.github.io/archivers/wuxi)和[《上海游记》](https://zhangyet.github.io/archivers/shanghai)这三篇游记是我2020年五一假期时候写的，现在想想，旅行的意义可能就在回忆。
7.  [《如果你想了解贫穷，不妨读一下乔治·奥威尔》](https://zhangyet.github.io/archivers/down-and-out-in-Paris-and-London)奥威尔《巴黎伦敦落魄记》的读书笔记。如果我重读这本书，应该会更新。
8.  [《&lt;武装的先知&gt;：托洛茨基》](https://zhangyet.github.io/archivers/the-prohet-armed)这本书对我的影响还挺大的，读完这本书之后我基本不自称「XX主义者[^fn:2]」。因为XX主义包含的东西太多了。
9.  [The Darkest Night](https://zhangyet.github.io/archivers/blackest-night) 记录了2020年初失业到找到新工作稳定下来的感想。
10. [《女巫、工业与现代化》](https://zhangyet.github.io/archivers/release-the-witch)这是我为《放开那个女巫》写的书评，里面有我对网络小说比较认真的评论。
11. [《爱情童话一则》](https://zhangyet.github.io/archivers/fairy-tale)比较好玩的小小说。
12. [《quickfixgo 源代码剖析》](https://zhangyet.github.io/archivers/quickfixgo) 、[《写一个 FIX 模拟器》](https://zhangyet.github.io/archivers/fix_simulator)这两篇技术博客其实写得不好，但我收录在这里，纪念一下倒闭的前公司。
13. [《kamui: bookdown vscode 插件》](https://zhangyet.github.io/archivers/kamui)2019年从北京回来，有一个月时间都在休假，期间翻译了一本书，为了组织翻译，写了个 vscode 小插件，不过已经弃坑（毕竟谁会在 vs code 里面用 bookdown 啊）。

写了这么久，重新选也只有13项写得还行的博客想来我真是做人失败[^fn:3]。


## 规划 {#规划}

简单划分一下以后博客的分类：

1.  log 这种就类似日记，或者说随笔、杂文，某种意义上来说就是其他。
2.  reading 读书笔记。
3.  code 代码相关，包括源代码阅读和某些有价值写一下的 debug 过程。
4.  game 游戏相关。
5.  anime 动画相关。

不排除以后会增加新的分类，眼下就先这样吧。

[^fn:1]: 这是阿基米德的故事：<https://en.wikipedia.org/wiki/Eureka_(word)>
[^fn:2]: 这个「XX主义」包括 共产主义、自由主义和女权主义。
[^fn:3]: 这是欲星移的梗。