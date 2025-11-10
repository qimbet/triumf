to check system memory: 
free -h

Quick note -- 
debFiles are installed manually from web sources. 
debInstalls come from the apt package manager, with argument --download-only

list of target packages for epics: 

vim 
make
build−essential 
git 
iperf3 
nmap 
openssh−server 
libreadline−gplv2−dev 
libgif−dev 
libmotif−dev 
libxmu−dev 
libxmu−headers 
libxt−dev 
libxtst−dev 
xfonts−100dpi 
xfonts−75dpi 
x11proto−print−dev 
autoconf
libtool 
sshpass

apt install --download-only build−essential git iperf3 nmap openssh−server vim libreadline−gplv2−dev libgif−dev libmotif−dev libxmu−dev libxmu−headers libxt−dev libxtst−dev xfonts−100dpi xfonts−75dpi x11proto−print−dev autoconf libtool sshpass make

Installs files to the apt cache at: 
/var/cache/apt/archives

