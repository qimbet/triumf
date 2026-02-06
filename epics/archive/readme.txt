Different epics installers are separated by version. The installation script should be the same, but the relevant .deb files are different. 

Note that the libncurses-dev_6.3-2 file is not available for ubuntu 24.04, hence the redevelopment in Ubuntu 22.04

Functionality of install.sh is at time of writing identical for both releases. 


------------------------------------------------

To transfer files to VM:
sftp has been set up on Hermes:

	sudo systemctl enable sshd
	ip a
		Read ip address, connect on vm via:
		sftp jmattie@xxx.xxx.x.xxx #ip address
	sudo systemctl disable sshd

-----------------------------------------------
apt-get install --download-only [package] [p2] ...
Files will be cached in: /var/cache/apt/archives/


sudo apt install openssh-server vim make
