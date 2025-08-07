from .controller import moveAngle,  step, coilPins, initMotor, milliSec, startingState
import lgpio
# import spidev
import sys
import signal 
import atexit
import os
from time import sleep


#Prior to runtime, install the lgpio library:
    #pip install lgpio
    #sudo apt update
    #sudo apt install lgpio

#Prior to runtime, if using potentiometer for calibration:
    #this isn't fully coded yet, so not necessary. Keeping for posterity

    #pip install spidev

    #sudo raspi-config
    #   Interface Options --> SPI --> Enable
    #sudo reboot

#***********************************************************************
#
#                   VARIABLES
#
#***********************************************************************

#**********************************
#              Pin associations

# adcPins = [0, 0,0,0]   #0 -- placeholder value
calibrationDevice = 0   #pin number associated with calibration limit switch #0 -- placeholder value


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

delayBetweenMotorSteps_milliseconds = milliSec(10) #slow down motor during standard operation

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


def calibrate(calibrationDevice): #slowly rotates towards starting position, as defined by calibrationDevice
    calibrationSensor = "limitSwitch" #one of 'potentiometer', 'limitSwitch', or code your own

    state = startingState #initalize coils to element 0 of coilPins list

    value = lgpio.gpio_read(h, calibrationDevice)

    if calibrationSensor == "limitSwitch":
        while not value:
            state = step(state, False) #this currently steps counterClockwise; limit switch should thus be on upper spoke
            value = lgpio.gpio_read(h, calibrationDevice)
            sleep(stepDelay)
    elif calibrationSensor == "potentiometer":
        shutoffVal = 20 #assume a readValue of < 20 from the potentiometer is a flag for shutoff
        while value > shutoffVal:
            state = step(state, False)
            value = lgpio.gpio_read(h, calibrationDevice)
            sleep(stepDelay)
    #elif calibrationSensor == "otherSensorType"
        #logic goes here

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

def followCommands(commandsList, currentAngle, state=startingState):

    for command in commandsList:
        angle = command[0]
        holdTime = command[1]

        nextAngle = currentAngle + angle
        if (nextAngle > maxAngle) or (nextAngle < minAngle):
            print(f"ERROR: selected step {command} moves the motor to {nextAngle}.\nAllowable range is: [{minAngle}, {maxAngle}]")
            #should we rotate here? Go to furthest allowable angle, or hold at current state? 
        else:
            state = moveAngle(angle, state, delayBetweenMotorSteps_milliseconds)
            sleep(holdTime)

    print("Done!")

#***********************************************************************
#
#                   MAIN LOOP
#
#***********************************************************************

def main(commandsList=[]): #path is a list of tuples (angle, delay). This could be imported from a .txt file, hardcoded, or prompted
    global h
    h = lgpio.gpiochip_open(0)

    lgpio.gpio_claim_input(h, calibrationDevice)
    initMotor(coilPins)

    # spi = spidev.SpiDev()
    # spi.open(0, 0)
    # spi.max_speed_hz = 1350000

    calibrate(calibrationDevice) #moves motor to zero position

    currentAngle = 0
    state = startingState

    if commandsList == []:
        if os.path.exists(pathFileDir):
            commandsList = readPathFromFile(pathFileDir)
        followCommands(commandsList, currentAngle, state)

    elif type(commandsList) == int:
        followCommands([(commandsList, 0)])

    elif type(commandsList) == tuple:
        if len(commandsList) <= 2:
            if len(commandsList) == 1:
                newCommand = (commandsList[0], 0) #set holdTime to 0 if not provided
                followCommands([newCommand])
            elif len(commandsList) == 2: 
                followCommands([commandsList])
        else:
            print(f"Wrong number of arguments provided! The program accepts tuples: (angle, holdTime)")

    elif type(commandsList) == list:
        followCommands(commandsList, currentAngle, state)

    elif commandsList == "manual":
        while True:
            commandString = input("\nEnter an angle value for rotation: ")
            command = cleanCommand(commandString)
            commandsList = [(command, 0)] #set holdTime = 0 -- this is user-controlled
            followCommands(commandsList, currentAngle, state)

    #else:
        #insert other operating methods here -- can this be controlled from EPICS?
        #pass


    cleanup()

if __name__ == "__main__":
    main("manual")
