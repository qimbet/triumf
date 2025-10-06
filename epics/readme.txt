Different epics installers are separated by version. The installation script should be the same, but the relevant .deb files are different. 

Note that the libncurses-dev_6.3-2 file is not available for ubuntu 24.04, hence the redevelopment in Ubuntu 22.04

Functionality of install.sh is at time of writing identical for both releases. 


------------------------------------------------


To set up sftp on the virtual machine, run: 

sudo apt update
sudo apt install openssh-server vim
sudo passwd ubuntu
sudo mkdir epics
sudo vim /etc/ssh/sshd_config
	Match Group sftpusers
		ForceCommand internal-sftp -d /home/ubuntu/epics
		PasswordAuthentication yes

sudo systemctl enable ssh

------------------------------------------------
apt-get install --download only [package] [p2] ...
Files will be cached in: /var/cache/apt/archives/



------- needed .deb files: ----------

build-essential
git
iperf3
nmap
openssh-server
vim 
libreadline-gplv2-dev
libgif-dev
libmotif
libxmu-dev
libxmu-headers
libxt-dev
libxtst-dev
xfonts-100dpi
xfonts-75dpi
x11proto-print-dev
autoconf
libtool
sshpass
