# ASPIRE RPI006 IOC : motor_control.py
# UPDATED: 03/08/25; AUTHOR: HAYDEN KLASSEN, Jacob Mattie
#  

#from epics import PV
from time import sleep
import lgpio
import atexit
import signal
import sys
#import busio
#import digitalio
#import board
#import adafruit_mcp3xxx.mcp3008 as MCP
#from adafruit_mcp3xxx.analog_in import AnalogIn


#Prior to runtime, install the lgpio library:
    #pip install lgpio
    #sudo apt update
    #sudo apt install lgpio

#***********************************************************************
#
#                  VARIABLES
#
#***********************************************************************

RDANG = 300
SETANG = 100
MAXANG = 305
MINANG = 99
FWSTEP = 0
BWSTEP = 0
FWSTEPINT = 0
BWSTEPINT = 0
ALERT = ""
STOP = 0

rotcounter = 0
stepDelayMilliseconds = 50
stepDelay = stepDelayMilliseconds/1000


coilPins = [("coilA1", 27), #list of tuples. Each entry is: (pinName, boardPinNumber)
            ("coilA2", 22), #the pinName string is for legibility only. Not used in code
            ("coilB1", 23), 
            ("coilB2", 24)]

# adcPins = [0,0,0,0]   #0 -- placeholder value
calibrationDevice = 0   #0 -- placeholder value

numCoils = len(coilPins)

startingState = [0]
h = None #chip handle; later used for lgpio


class Route:
    def __init__(self, start_ang, end_ang, dir_clockwise):
        self.start = start_ang
        self.end = end_ang
        if (dir_clockwise == True):
            self.clockwise = 1
        elif (dir_clockwise == False):
            self.clockwise = 0
        else:
            print("ERROR INVALID ARGS")
        self.priority = 0

        self.calc_details()

    def calc_details(self):
        if (self.clockwise == True):
            if (self.end > self.start):
                self.length = self.end - self.start
                self.rotations = 0
            else:
                self.length = (360 - self.start) + self.end
                self.rotations = 1
        else:
            if (self.end > self.start):
                self.length = self.start + (360 - self.end)
                self.rotations = -1
            else:
                self.length = self.start - self.end
                self.rotations = 0

    def intersection(self, start_ang, end_ang):
        if (self.rotations == 0):
            if (self.clockwise == True):
                if ((self.end >= start_ang) and (self.start <= start_ang)):
                    return True
            else:
                if ((self.end <= end_ang) and (self.start >= end_ang)):
                    return True
        else:
            if (self.clockwise == True):
                if (((self.start >= start_ang) and (self.start <= end_ang))
                    or ((self.start >= start_ang) and (start_ang > end_ang))
                    or (self.start <= start_ang)
                    or (self.end >= start_ang)
                    or (self.start <= end_ang)):
                    return True
            else:
                if (((self.end >= start_ang) and (self.end <= end_ang))
                    or ((self.end >= start_ang) and (start_ang > end_ang))
                    or (self.end <= start_ang)
                    or (self.start >= start_ang)
                    or (self.end <= end_ang)):
                    return True

#***********************************************************************
#
#                   FUNCTION DEFINITIONS
#
#***********************************************************************

def inSet(ang, start, end):
    if (start <= end):
        if (end >= ang >= start):
            return True
        else:
            return False
    else:
        if ((ang >= start) or (ang <= end)):
            return True
        else:
            return False
    
def doStep(clockwise):
    global RDANG, rotcounter, MINANG, MAXANG

    if (clockwise == True):
        premove = RDANG + 5
    elif (clockwise == False):
        premove = RDANG - 5
    else:
        print("ERR")

    if (premove >= 360):
        rotcounter += 1
    elif (premove < 0):
        rotcounter -= 1

    if inSet(premove % 360, MAXANG, MINANG):
        print("ERR")
    else:
        RDANG = premove % 360
    allCoilsStep(clockwise)

def initMotor(coilPins):
    for coil in coilPins:
        pinNumber = coil[1]
        lgpio.gpio_claim_output(h, pinNumber, 0)  # Claim as output, initial value 0 (LOW)

def allCoilsStep(directionForward=True):
        #Here we assume a start state of one energized element of coilPins: index 0
        currentState = [0]
        for i in range(4): #step 4 times, one for each coil. Thus we do not need to keep track of which coils are energized -- each step is a full coil circuit
            if directionForward == True:
                if len(currentState) == 1:
                    activatedPin = currentState[0]
                    addPinIndex = ((activatedPin+1) % numCoils) #reset to index 0 if at last element
                    addPin = coilPins[addPinIndex][1]
                    lgpio.gpio_write(h, addPin, 1) 

                    currentState.append(addPinIndex)

                elif len(currentState) == 2:
                    laggingPinIndex = currentState[0]
                    laggingPin = coilPins[laggingPinIndex][1]
                    lgpio.gpio_write(h, laggingPin, 0) 

                    currentState.remove(laggingPinIndex)

                else:
                    return "ERROR"
                
            else: #reverse
                if len(currentState) == 1:
                    activatedPin = currentState[0]
                    addPinIndex = ((activatedPin-1) % numCoils) #reset to index 0 if at last element
                    addPin = coilPins[addPinIndex][1]
                    lgpio.gpio_write(h, addPin, 1) 

                    currentState.insert(0, addPinIndex)

                elif len(currentState) == 2:
                    laggingPinIndex = currentState[-1]
                    laggingPin = coilPins[laggingPinIndex][1]
                    lgpio.gpio_write(h, laggingPin, 0) 

                    currentState.remove(laggingPinIndex)

                else:
                    return "ERROR"

def readADC(adcPinList): #this is a pain tbh. Not done.
    pass

def calibrate(calibrationDevice): #slowly rotates towards starting position, as defined by limitIndicatorPin -- Note: this contains internal configurations; e.g. potentiometer or limitSwitch calibration
    calibrationSensor = "potentiometer" #one of 'potentiometer', 'limitSwitch', or code your own
    potentiometerShutoff = 20 #assume a readValue of < 20 from the potentiometer is a flag for shutoff

    value = lgpio.gpio_read(h, calibrationDevice)

    if calibrationSensor == "limitSwitch":
        while not value:
            allCoilsStep(False) #this currently steps counterClockwise; limit switch should thus be on upper spoke
            value = lgpio.gpio_read(h, calibrationDevice)
            sleep(stepDelay)

    elif calibrationSensor == "potentiometer":
        while value > potentiometerShutoff: 
            allCoilsStep(False)
            value = lgpio.gpio_read(h, calibrationDevice)
            sleep(stepDelay)

    #elif calibrationSensor == "otherSensorType"
        #logic goes here

    return True

def findRoute(RDANG, SETANG):
    print(str(RDANG) + "->" + str(SETANG) + " in " + "[" + str(MINANG) + "," + str(MAXANG) + "]")
    # in restricted?
    #if not (MINANG <= SETANG <= MAXANG):
    #    print("No possible routes")
    #    return 0
    #print("Routes not restricted")

    # create routes
    route1 = Route(RDANG, SETANG, True)
    route2 = Route(RDANG, SETANG, False)
    print("Created routes")

    # prioritize shortest
    if (route2.length >= route1.length):
        route1.priority = 2
        route2.priority = 1
    else:
        route1.priority = 1
        route2.priority = 2
    print("Found fastest route: route1.priority=" + str(route1.priority) + ",route2.priority=" + str(route2.priority))

    # detailed testing
    for test_route in [route1, route2]:
        print("testing clockwise:" + str(test_route.clockwise))
        # validity: through restricted?
        if test_route.intersection(MAXANG, MINANG):
            test_route.priority = 0
            print("outside domain")
        # validity: too many rotations?
        if (abs(test_route.rotations + rotcounter) > 1):
            test_route.priority = 0
            print("too many rotations")
    print("Updated route priorities: route1.priority=" + str(route1.priority) + ",route2.priority=" + str(route2.priority))


    if (route1.priority >= route2.priority):
        if (route1.priority > 0):
            print("route1 selected")
            return route1
        else:
            return 0
    else:
        if (route2.priority > 0):
            print("route2 selected")
            return route2
        else:
            return 0
        
def doRoute(route: Route):
    global SETANG, RDANG
    if (route.rotations == 0):
        if ((route.clockwise == True)): 
            while (SETANG > RDANG):
                doStep(1)
                print(RDANG)
        else:
            while (RDANG > SETANG):
                doStep(0)
                print(RDANG)
    elif (route.rotations == 1):
            while (SETANG < RDANG):
                doStep(1)
                print(RDANG)
            while (SETANG > RDANG):
                doStep(1)
                print(RDANG)
    elif (route.rotations == -1):
            while (RDANG < SETANG):
                doStep(0)
                print(RDANG)
            while (RDANG > SETANG):
                doStep(0)
                print(RDANG)

#**********************************
#              Memory Handling

def cleanup():
    lgpio.gpiochip_close(h)

def signalHandler(_sig, _frame): #arguments unused but required feed by signal.signal
    cleanup()
    sys.exit()

atexit.register(cleanup) #call cleanup() on normal exit
signal.signal(signal.SIGINT, signalHandler) #Ctrl-C
signal.signal(signal.SIGTERM, signalHandler) #pkill, etc.
signal.signal(signal.SIGHUP, signalHandler) #controller session disconnect

#***********************************************************************
#
#                   MAIN LOOP
#
#***********************************************************************

def main():
    h = lgpio.gpiochip_open(0)

    lgpio.gpio_claim_input(h, calibrationDevice)
    initMotor(coilPins)
    calibrate(calibrationDevice) #moves motor to 0-position

    # main forever-loop, handles pv-pin controls
    while True:
        if (round(RDANG,0) != SETANG):
            print("starting, finding routes")
            route = findRoute(RDANG, SETANG)
            if (route != 0):
                doRoute(route)
            else:
                ALERT = "INVLD ANG"
                print(ALERT)
            break
    
    cleanup()
                


if __name__ == "__main__": #runs main() only if the file is called directly -- facilitates function exports
    main()