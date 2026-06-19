First, run: 
	sudo epics_installer.sh

This installs epics, edm, and configures your system paths.
I do encourage you to take a look through the code out of principle. Be wary of giving unverified code sudo access!

After the installation is done, refresh your terminal session with one of:
source ~/.bashrc

OR

close & reopen a terminal window.

-----------------------------------------------
To use EDM:
Enter into commandline: 
    edm

-----------------------------------------------

Creating, reading PVs from epics commandline

in a program directory (e.g. /opt/epics/test/db/)
create a .db file; test.db

.db file contents:
==============================================

record(ai, "TEST:PV1") {
	field(DESC, "Test Analog Input")
	field(SCAN, "1 second")
	field(PREC, "2")
}
record(ao, "TEST:PV2") {
	field(DESC, "Test Analog Output")
}

==============================================

ai = analog input
ao = analog output
variable names; TEST:PV1, TEST:PV2 must be unique


==============================================
==============================================
To start an ioc:

commandline:
$EPICS_BASE/bin/$EPICS_HOST_ARCH/softIoc -d test.db

where {test.db} is the path to the .db file created above
e.g. /epics/test/db/test.db


==============================================
==============================================
To query PVs:

Open a new terminal window. 
Use caget/caput to get/put PV values. 

Try: 

caget TEST:PV1 		#queries value saved in TEST:PV1

caput TEST:PV2 42 	#sets value of TEST:PV2
caget TEST:PV2 		#queries value saved in TEST:PV2 -- should be 42	

