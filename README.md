# SSDM

22:08 2017-12-17
为应对服务器重启而增加了ssdm.sh -o save 设置，跟iptables 一样只显示保存的命令，并不做实际的磁盘储存，可以用重定向到文件。

07:30 2017-11-30

# 实验平台

Ubuntu 14.04


#===================================================

原理

每当用户从Shadowsocks 服务器上获取数据时，服务器的iptables 会在OUTPUT 链上记录下经过了多少流量。
为了精确区分这些流量走的分别是哪些端口，需要在iptables 上建立相应的规则，例如：

假设Server 的IP 是104.207.135.28，开放的端口为9004，iptables 默认是filter 表，所以-t filter 可省略

# 在入口以目标地址为104.207.135.28 及目标端口为9004 的流量放行
sudo iptables -A INPUT -d 104.207.135.28 -p tcp --dport 9004 -j ACCEPT

# 在出口以源地址为104.207.135.28 及源端口为9004 的流量放行
sudo iptables -A OUTPUT -s 104.207.135.28 -p tcp --sport 9004 -j ACCEPT

# 设置规则后利用后台进程每隔1 秒查看一下流量情况
sudo iptables -nvxwL --line-numbers
# 参数说明
-n  不做反向解析，DOMAIN-->IP 是正向解析，IP-->DOMAIN 是反向解析，仅以IP 显示，不显示域名。
-v  详细信息，加上-x 参数可使第三字段bytes 显示单位为byte，否则其将自动转为B/M/G 等。
-x  参看-v
-w  等待同步锁，可能有多个进程调用了iptables 来查看，别人用完了本程序就可以看了。
-L  查看某条链上的规则，默认全部，OUTPUT/INPUT/FORWARD。

# 发现端口流量有超出允许范围则修改规则关闭通道，入口出口均关闭
sudo iptables -A INPUT -d 104.207.135.28 -p tcp --dport 9005 -j DROP
sudo iptables -A OUTPUT -s 104.207.135.28 -p tcp --sport 9005 -j DROP

以上就是本脚本背后的基本流程，如果用本脚本开放或关闭某一端口，它会先清理与该端口相关的旧规则和后台进程。
sudo iptables -D OUTPUT -s 104.207.135.28 -p tcp --sport 9004 -j ACCEPT
sudo iptables -D OUTPUT -s 104.207.135.28 -p tcp --sport 9004 -j DROP
sudo iptables -D INPUT -d 104.207.135.28 -p tcp --dport 9004 -j ACCEPT
sudo iptables -D INPUT -d 104.207.135.28 -p tcp --dport 9004 -j DROP)

值得注意的是删除规则时，必须和添加规则时的参数绝对一模一样。


#===================================================

用例

root@vultr:/opt/ss# ./ssdm.sh -h
   Usage:
   ssdm.sh {-v} {-h} {-l} {-i} {-o allow|forbid|clean(all)|view [-s Server_IPAddress] -p PORT -c numG|M} [-x SUDOPSWD]

   Options:
   -h Help 帮助
   -l List daemon processes 列出所有的后台监控进程
   -i List IPs and iptables of server 列出服务器所有IP
   -o Operate types
      allow      : Allow limited data through a port 允许某端口流经的流量
      forbid     : Forbid any data through a port 禁止某端口通过流量
      clean(all) : Clean iptables and daemon process by conditions or clean them all 清除某端口的设置(允许或禁止)，cleanall 表全部清除
      view       : View current status 查看当前的状态，规则列表及流量使用率
   -s Server IP address 指定服务器IP，可选，默认ifconfig 的第一块网卡地址
   -p Server port 指定服务器端口
   -c Data capacity 指定允许的流量
   -x Password of sudo 指定sudo 的密码，设置iptables 用
   -v Show Version 查看本脚本版本


以服务器端口9004 为例

# 开放本机9004，以104.207.135.28 作为通信地址，流量限制30GB
./ssdm.sh -o allow -s 104.207.135.28 -p 9004 -c 30GB
# -s 参数是可选的，默认用ifconfig 中显示的第一个地址，./ssdm.sh -i 可查看服务器所以IP



#===================================================

测试

将ssdm.sh 加入环境变量的/usr/bin 里
sudo ln -s /opt/ss/ssdm.sh /usr/bin/ssdm.sh
注意软连接一定要给原脚本名字一样，否则无法运行(脚本内有检测)

设置放行规则
ssdm.sh -o allow -p 9004 -c 200m

创建存放测试文件的文件夹
cd && mkdir temp && cd temp

# 创建指定大小的文件(300M，1.5G)，注意bs 小反而速度快
dd if=/dev/zero of=300MB.file bs=100M count=3
# 推荐这样做，bs 小，count 大，创建时间更短
dd if=/dev/zero of=300MB.file bs=1M count=300
dd if=/dev/zero of=1.5GB.file bs=1M count=1536


启动Python HTTP 简单服务
# Python2(推荐)
python -m SimpleHTTPServer 9004
# Python3
python3 -m http.server 9004


浏览器访问
http://104.207.135.28:9004
下载300MB.file 文件，在下载到200MB 左右的时候iptables 规则应该会被后台的ssdm.sh 改变导致下载不完成。

清理规则及后台进程
ssdm.sh -o cleanall



#===================================================
