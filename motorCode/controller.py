"""
Raspberry pi as microcontroller for stepper motor
Created for the ASPIRE lab at Triumf


Written by Jacob Mattie, working under the guidance of Dr. Christopher Charles
July 28, 2025

j_mattie@live.ca
https://github.com/qimbet/triumf/tree/main/motorCode


--------------------------------------------------------------------------------

OVERVIEW:

The core of the function is in the ordered list coilPins.

The function step() increments the high-state output on the associated
pins in a way conducive to a unipolar stepper motor driver
i.e.
    pin1        ON      --- step 0
    pin1, pin2  ON      --- step 1
    pin2        ON      --- step 2
    pin2, pin3  ON      --- step 3
    ...                 
and so forth

The functions moveNumSteps and moveAngle dress up the step() function to 
make them more palatable, but ultimately do the same thing.

The order in which the motor windings are to be energized should be 
determined on a per-motor basis. This order can be set either in-code 
(by re-ordering coilPins) or through wiring.

The list coilPins is the program's ordering on outputs. 
Reorder, add/remove windings as needed.

"""

#requires installation of pigpio to control pins
#to start pin-control daemon on boot, run once: 
#   sudo systemctl enable pigpiod
#   sudo systemctl start pigpiod


#***********************************************************************
#
#                   VARIABLES & INITIALIZATION
#
#***********************************************************************

from time import sleep
import pigpio
import atexit
import signal
import sys

debug = False #prints process text if True; see d()
delayBetweenMotorSteps_milliseconds = 25 #set rotation speed
anglePerMotorStep = 0 #find

coilPins = [("coilA1", 27), #list of tuples. Each entry is: (pinName, boardPinNumber)
            ("coilA2", 22), #the pinName string is for legibility only. Not used in code
            ("coilB1", 23), 
            ("coilB2", 24)]



pi = None #used later for pigpio
numCoils = len(coilPins)

#***********************************************************************
#
#                   FUNCTION DEFINITIONS
#
#***********************************************************************

if True:
    def d(val): #debug function
        if debug == True:
            print(val)

    def milliSec(s):
        return (s/1000)

    def step(currentState, directionForward):
        #currentState is a list -- either one or two elements; describing the index values of which coilPins elements are energized

        if directionForward == True:
            if len(currentState) == 1:
                activatedPin = currentState[0]
                addPinIndex = ((activatedPin+1) % numCoils) #reset to index 0 if at last element
                addPin = coilPins[addPinIndex][1]
                pi.write(addPin, 1)

                currentState.append(addPinIndex)

            elif len(currentState) == 2:
                laggingPinIndex = currentState[0]
                laggingPin = coilPins[laggingPinIndex][1]
                pi.write(laggingPin, 0)

                currentState.remove(laggingPinIndex)

            else:
                return "ERROR"
            
        else: #reverse
            if len(currentState) == 1:
                activatedPin = currentState[0]
                addPinIndex = ((activatedPin-1) % numCoils) #reset to index 0 if at last element
                addPin = coilPins[addPinIndex][1]
                pi.write(addPin, 1)

                currentState.insert(0, addPinIndex)

            elif len(currentState) == 2:
                laggingPinIndex = currentState[1]
                laggingPin = coilPins[laggingPinIndex][1]
                pi.write(laggingPin, 0)

                currentState.remove(laggingPinIndex)

            else:
                return "ERROR"
        
        d(currentState)
        return currentState

    def moveNumSteps(steps, currentState, delayBetweenMotorSteps_milliseconds=0):
        directionForward = True
        if steps < 0:
            steps = steps * (-1)
            directionForward = False

        state = currentState

        for i in range(steps):
            state = step(state, directionForward)
            sleep(delayBetweenMotorSteps_milliseconds)

        return state

    def moveAngle(angle, currentState, anglePerStep=1.8, delayBetweenMotorSteps_milliseconds=0):
        #anglePerStep default is set based off typical stepper motor parameters
        #The ASPIRE motor setup uses an opaque gearbox -- anglePerStep is best found experimentally

        #feed a negative value into 'angle' to rotate counter-clockwise

        numStepsDecimal = angle/anglePerStep
        numStepsInteger = int(round(numStepsDecimal, 0))

        newState = moveNumSteps(numStepsInteger, currentState, delayBetweenMotorSteps_milliseconds)

        return newState


#**********************************
#              Pin Daemon Handling

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

#***********************************************************************
#
#                   MAIN LOOP
#
#***********************************************************************

def main():
    global pi
    pi = pigpio.pi() 
    if not pi.connected:
        print("Failed to connect to pigpio daemon")
        pi.stop()
        sys.exit(1)


    for coil in coilPins:
        pi.set_mode(coil[1], pigpio.OUTPUT)
        pass #pass: for debugging cases where pi.set_mode gets commented out 



    startingState = [0] #assuming element 0 of the coilPins list is to be energized during startup

    delayVal = milliSec(delayBetweenMotorSteps_milliseconds)

    steps = 0


    currentState = startingState
    for pin in startingState:
        pi.write(coilPins[pin][1], 1)
        pass #pass: for debugging cases where pi.set_mode gets commented out 

    while True:
        while True:
            stepsStr = input("""
            How many steps should the motor move? 
            
            The motor moves clockwise by default. 
            Enter a negative step number to rotate counterclockwise.
                
            >>  """) #should update for angle -- more intuitive on a GUI. Calibration needed.
            if stepsStr.isdigit():
                steps = int(round(float(stepsStr), 0))
                break
            else:
                print("That was not an integer.\n")
        
        currentState = moveNumSteps(steps, currentState, delayVal) #moveAngle(angle, currentState, anglePerMotorStep, delayVal)
        print(f"Motor moved {steps} steps.\n ")


#**********************************
#              Direct Calls

if __name__ == '__main__':
    main()

