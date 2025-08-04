from .controller import moveAngle,  step, coilPins, initMotor, milliSec, startingState, delayBetweenMotorSteps_milliseconds
import lgpio
import sys
import signal 
import atexit
import os
from time import sleep

#Prior to runtime, install the lgpio library:
    #pip install lgpio
    #sudo apt update
    #sudo apt install lgpio

#***********************************************************************
#
#                   VARIABLES
#
#***********************************************************************

#**********************************
#              Pin associations

calibrationSwitch = 0 #pin number associated with calibration limit switch

h = None #lgpio handle; initalized later


#**********************************
#              Operating Variables

maxAngle = 270
minAngle = 0
startAngle = 0

pathFileDir = r"/absolute/path/to/commandFile/file.txt" #this contains a text file -- each row a tuple; "angle, delay". First row is a header and is ignored

angleBetweenSamples = 20 #degrees


#**********************************
#              Timing

stepDelayMilliseconds = 50
stepDelay = milliSec(stepDelayMilliseconds) #delay 50ms between each step -- slow during calibration

stateDelaySeconds = 60*5 #how many seconds should the motor hold its position before rotating to the next sample?




#***********************************************************************
#
#                   FUNCTION DEFINITIONS
#
#***********************************************************************

if True: #shutdown cleanups 
    def cleanup():
        global pi
        if pi is not None:
            pi.stop()

    def signalHandler(_sig, _frame): #arguments unused but required feed by signal.signal
        cleanup()
        sys.exit()

    atexit.register(cleanup) #call cleanup() on normal exit
    signal.signal(signal.SIGINT, signalHandler) #Ctrl-C
    signal.signal(signal.SIGTERM, signalHandler) #pkill, etc.
    signal.signal(signal.SIGHUP, signalHandler) #controller session disconnect


def calibrate(limitIndicatorPin): #slowly rotates towards starting position, as defined by limitIndicatorPin
    #input a list of pins associated with boundary-detection sensors
    state = startingState #initalize coils to element 0 of coilPins list

    value = 0
    while not value:
        state = step(state, False) #this currently steps counterClockwise; limit switch should thus be on upper spoke
        value = lgpio.gpio_read(h, calibrationSwitch)
        sleep(stepDelay)

    return True

def cleanCommand(commandString, count=0):
    numericParts = []

    lineParts = commandString.split(",")

    for part in lineParts:
        part = part.strip()
        if not float(part):
            if count:
                print(f"Error: \nLine {count} of command file is not numeric.\n\nProper format for each row is two comma-separated numbers -- angle(degrees), delay(seconds)\nEnter a negative angle to rotate counterclockwise.")
            else:
                print(f"Error: \nLine {commandString} is not numeric.\n\nProper format is two comma-separated numbers -- angle(degrees), delay(seconds)\nEnter a negative angle to rotate counterclockwise.")
            return False #Do not continue if the input file is incorrect

        val = float(part) 
        numericParts.append(val)
        numericPartsTuple = tuple(numericParts)
    return numericPartsTuple

def readPathFromFile(fileDir):
    lines = []
    with open(fileDir, "r") as f:
        next(f)
        count = 1
        for line in f:
            count += 1

            numericPartsTuple = cleanCommand(line, count)

            lines.append(numericPartsTuple)

    return lines

def followCommands(commandsList):

    for command in commandsList:
        angle = command[0]
        holdTime = command[1]

        nextAngle = currentAngle + angle
        if (nextAngle > maxAngle) or (nextAngle < minAngle):
            print(f"ERROR: selected step {command} moves the motor to {nextAngle}.\nAllowable range is: [{minAngle}, {maxAngle}]")
            #should we rotate here? Go to furthest allowable angle, or hold at current state? 
        else:
            state = moveAngle(angle, state)
            sleep(holdTime)

    print("Done!")

#***********************************************************************
#
#                   MAIN LOOP
#
#***********************************************************************

def main(commandsList=[]): #path is a list of tuples (angle, delay). This could be imported from a .txt file, hardcoded, or prompted
    h = lgpio.gpiochip_open(0)

    lgpio.gpio_claim_input(h, calibrationSwitch)
    initMotor(coilPins)

    calibrate(calibrationSwitch) #moves motor to zero position

    currentAngle = 0
    state = startingState

    if commandsList == []:
        if os.path.exists(pathFileDir):
            commandsList = readPathFromFile(pathFileDir)
        followCommands(commandsList)

    elif commandsList == "manual":
        while True:
            commandString = input("Enter an angle value for rotation: ")
            command = cleanCommand(commandString)
            followCommands(command)

    #else:
        #insert other operating methods here -- can this be controlled from EPICS?
        #pass


    cleanup()

if __name__ == "__main__":
    main()
