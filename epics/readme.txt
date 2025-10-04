Different epics installers are separated by version. The installation script should be the same, but the relevant .deb files are different. 

Note that the libncurses-dev_6.3-2 file is not available for ubuntu 24.04, hence the redevelopment in Ubuntu 22.04

Functionality of install.sh is at time of writing identical for both releases. 


------------------------------------------------


To set up sftp on the virtual machine, run: 

sudo apt install openssh vim
sudo passwd ubuntu
sudo vim /etc/ssh/sshd_config
	PasswordAuthentication yes
	Subsystem sfpt internal-sftp #this line may/may not be necessary


sudo systemctl enable ssh

------------------------------------------------
Dependency Tree:

libreadline-gplv2
> libreadline5
> libtinfo6.3-2
>> libncurses-dev6.3-2

